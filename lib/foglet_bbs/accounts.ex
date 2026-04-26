defmodule Foglet.Accounts do
  @moduledoc """
  User accounts, SSH keys, and token generation.

  Public API consumed by:
    * Phase 1 Mix tasks (`mix foglet.user.*`)
    * Phase 3 SSH auth (`authenticate_by_password/2`, `get_user_by_public_key/1`)
    * Email and operator delivery paths persist token rows and return
      raw delivery tokens to the caller-owned delivery channel.

  Design notes:
    * Hand-rolled per CONTEXT D-07 — not `mix phx.gen.auth` output.
    * `:password` is a virtual field on User; never persisted.
    * `user_tokens` stores SHA256 hashes; raw token returned to caller.
    * Account deletion preserves the user row (sets `deleted_at`) so
      foreign keys remain valid. Post rewrites to the tombstone user
      are layered in when `posts` exists (Phase 2+).
  """

  import Ecto.Query, warn: false

  alias Foglet.QueryHelpers

  alias Foglet.Accounts.{Email, Invite, SSHKey, User, UserToken}
  alias Foglet.{Config, Mailer}
  alias Foglet.Posts.Post
  alias FogletBbs.Repo

  @tombstone_user_id "00000000-0000-0000-0000-000000000001"

  @type invite_status :: %{
          code: String.t(),
          issuer_id: Ecto.UUID.t(),
          inserted_at: DateTime.t(),
          consumed_at: DateTime.t() | nil,
          consumed_by_user_id: Ecto.UUID.t() | nil,
          revoked_at: DateTime.t() | nil,
          status: :available | :consumed | :revoked
        }

  @type status_transition_delivery ::
          :not_applicable | :skipped_no_email | :attempted | {:failed, term()}

  @type status_transition_result :: %{
          user: User.t(),
          from: atom(),
          to: atom(),
          delivery: status_transition_delivery()
        }

  @doc "UUID of the tombstone user. Post-anonymization (Phase 2+) rewrites authorship to this id."
  @spec tombstone_user_id() :: String.t()
  def tombstone_user_id, do: @tombstone_user_id

  # ---------- Users ----------

  @doc """
  Create a new user account and subscribe to default boards (D-06).

  Calls `Foglet.Boards.subscribe_to_defaults/1` after a successful insert.
  The subscription call is made post-commit (not inside Multi) so a subscription
  failure does not roll back user creation.
  """
  @spec register_user(map()) :: {:ok, User.t()} | {:error, Ecto.Changeset.t()}
  def register_user(attrs) do
    case Foglet.Config.registration_mode() do
      "invite_only" -> register_invite_only_user(attrs)
      "sysop_approved" -> register_pending_user(attrs)
      _open -> register_open_user(attrs)
    end
  end

  defp register_open_user(attrs) do
    result =
      %User{}
      |> User.registration_changeset(attrs)
      |> Repo.insert()

    case result do
      {:ok, user} ->
        # D-06: subscribe to default boards after successful registration.
        Foglet.Boards.subscribe_to_defaults(user.id)
        {:ok, user}

      error ->
        error
    end
  end

  defp register_invite_only_user(attrs) do
    attrs = Map.new(attrs)
    invite_code = attrs[:invite_code] || attrs["invite_code"]
    user_changeset = User.registration_changeset(%User{}, attrs)

    cond do
      blank_invite_code?(invite_code) ->
        {:error, invite_code_error(user_changeset)}

      not user_changeset.valid? ->
        {:error, user_changeset}

      true ->
        invite_code
        |> redeem_invite_registration(user_changeset)
        |> handle_invite_registration_result(user_changeset)
    end
  end

  defp blank_invite_code?(nil), do: true
  defp blank_invite_code?(code), do: String.trim(to_string(code)) == ""

  defp redeem_invite_registration(invite_code, user_changeset) do
    code = String.trim(to_string(invite_code))

    Repo.transact(fn ->
      case Repo.insert(user_changeset) do
        {:ok, user} -> consume_invite_for_user(Repo, code, user)
        {:error, changeset} -> {:error, changeset}
      end
    end)
  end

  defp handle_invite_registration_result({:ok, user}, _user_changeset) do
    # D-06: subscribe to default boards after successful registration.
    Foglet.Boards.subscribe_to_defaults(user.id)
    {:ok, user}
  end

  defp handle_invite_registration_result({:error, :invalid_invite_code}, user_changeset) do
    {:error, invite_code_error(user_changeset)}
  end

  defp handle_invite_registration_result({:error, %Ecto.Changeset{} = changeset}, _user_changeset) do
    {:error, changeset}
  end

  defp consume_invite_for_user(repo, code, %User{} = user) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    query =
      from i in Invite,
        where: i.code == ^code and is_nil(i.consumed_at) and is_nil(i.revoked_at)

    case repo.update_all(query,
           set: [consumed_at: now, consumed_by_user_id: user.id, updated_at: now]
         ) do
      {1, _rows} -> {:ok, user}
      {0, _rows} -> {:error, :invalid_invite_code}
    end
  end

  defp invite_code_error(changeset) do
    Ecto.Changeset.add_error(changeset, :invite_code, "is invalid or unavailable")
  end

  defp normalize_status(status) when status in [:active, :rejected, :suspended], do: {:ok, status}

  defp normalize_status(status) when is_binary(status) do
    status
    |> String.trim()
    |> String.downcase()
    |> String.to_existing_atom()
    |> normalize_status()
  rescue
    ArgumentError -> {:error, :invalid_status}
  end

  defp normalize_status(_status), do: {:error, :invalid_status}

  defp fetch_status_target(%User{id: id}), do: fetch_status_target(id)

  defp fetch_status_target(identifier) when is_binary(identifier) do
    user =
      case Ecto.UUID.cast(identifier) do
        {:ok, id} -> Repo.get(User, id)
        :error -> Repo.get_by(User, handle: identifier)
      end

    case user do
      %User{} = user -> {:ok, user}
      nil -> {:error, :not_found}
    end
  end

  defp fetch_status_target(_target), do: {:error, :not_found}

  defp ensure_not_deleted(%User{deleted_at: nil}), do: :ok
  defp ensure_not_deleted(%User{}), do: {:error, :deleted}

  defp ensure_not_self(%User{id: id}, %User{id: id}), do: {:error, :invalid_transition}
  defp ensure_not_self(_actor, _user), do: :ok

  defp permit_status_transition(:pending, :active), do: :ok
  defp permit_status_transition(:pending, :rejected), do: :ok
  defp permit_status_transition(:active, :suspended), do: :ok
  defp permit_status_transition(:suspended, :active), do: :ok
  defp permit_status_transition(_from, _to), do: {:error, :invalid_transition}

  @doc """
  Create a new user account in `:pending` status (sysop-approved registration mode, D-05).
  Same validation as `register_user/1`; differs only in the persisted status value.
  Login is blocked for pending users in Phase 3's login flow.
  """
  @spec register_pending_user(map()) :: {:ok, User.t()} | {:error, Ecto.Changeset.t()}
  def register_pending_user(attrs) do
    result =
      %User{status: :pending}
      |> User.registration_changeset(attrs)
      |> Repo.insert()

    case result do
      {:ok, %User{} = user} ->
        notify_sysops_pending_registration(user)
        {:ok, user}

      error ->
        error
    end
  end

  @spec get_user(String.t()) :: User.t() | nil
  def get_user(id), do: Repo.get(User, id)

  @spec get_user!(String.t()) :: User.t()
  def get_user!(id), do: Repo.get!(User, id)

  @spec get_user_by_handle(String.t()) :: User.t() | nil
  def get_user_by_handle(handle) when is_binary(handle) do
    Repo.get_by(User, handle: handle)
  end

  @spec get_user_by_email(String.t()) :: User.t() | nil
  def get_user_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: email)
  end

  @doc """
  Verify handle + password. Always runs an Argon2 hash comparison
  (even on unknown handle) to prevent timing-based user enumeration.
  Rejects deleted users.
  """
  @spec authenticate_by_password(String.t(), String.t()) ::
          {:ok, User.t()} | {:error, :invalid_credentials}
  def authenticate_by_password(handle, password)
      when is_binary(handle) and is_binary(password) do
    user = get_user_by_handle(handle)

    cond do
      user && is_nil(user.deleted_at) && Argon2.verify_pass(password, user.password_hash) ->
        {:ok, user}

      user ->
        # real user, wrong password (or deleted)
        {:error, :invalid_credentials}

      true ->
        # unknown handle — still burn a hash to equalize timing
        Argon2.no_user_verify()
        {:error, :invalid_credentials}
    end
  end

  @doc "Apply role change (sysop pathway — used by `mix foglet.user.promote`)."
  @spec update_role(User.t(), atom() | String.t()) ::
          {:ok, User.t()} | {:error, Ecto.Changeset.t()}
  def update_role(%User{} = user, role) do
    user
    |> User.role_changeset(%{role: role})
    |> Repo.update()
  end

  @doc """
  Transition a user's account status through the locked sysop graph.

  The actor is authorized before target lookup or mutation so unauthorized
  callers cannot use this boundary to probe account existence.
  """
  @spec transition_user_status(User.t() | nil, User.t() | String.t(), atom() | String.t()) ::
          {:ok, status_transition_result()}
          | {:error, :forbidden | :not_found | :deleted | :invalid_transition | :invalid_status}
  def transition_user_status(actor, target, target_status) do
    with :ok <- Bodyguard.permit(Foglet.Authorization, :manage_user_status, actor, :site),
         {:ok, status} <- normalize_status(target_status),
         {:ok, user} <- fetch_status_target(target),
         :ok <- ensure_not_self(actor, user),
         :ok <- ensure_not_deleted(user),
         :ok <- permit_status_transition(user.status, status),
         {:ok, updated} <- user |> User.status_changeset(%{status: status}) |> Repo.update() do
      delivery = deliver_status_transition_notification(updated, user.status, status)

      {:ok,
       %{
         user: updated,
         from: user.status,
         to: status,
         delivery: delivery
       }}
    else
      {:error, reason}
      when reason in [:forbidden, :not_found, :deleted, :invalid_transition, :invalid_status] ->
        {:error, reason}

      {:error, %Ecto.Changeset{}} ->
        {:error, :invalid_status}
    end
  end

  @doc "List non-deleted users grouped by status for sysop status administration."
  @spec list_user_status_admin_targets(User.t() | nil) ::
          {:ok,
           %{
             pending: [User.t()],
             active: [User.t()],
             suspended: [User.t()],
             rejected: [User.t()]
           }}
          | {:error, :forbidden}
  def list_user_status_admin_targets(actor) do
    case Bodyguard.permit(Foglet.Authorization, :manage_user_status, actor, :site) do
      :ok ->
        users =
          from(u in User, order_by: [asc: u.inserted_at])
          |> QueryHelpers.not_deleted()
          |> Repo.all()

        grouped = Enum.group_by(users, & &1.status)

        {:ok,
         %{
           pending: Map.get(grouped, :pending, []),
           active: Map.get(grouped, :active, []),
           suspended: Map.get(grouped, :suspended, []),
           rejected: Map.get(grouped, :rejected, [])
         }}

      {:error, :forbidden} ->
        {:error, :forbidden}
    end
  end

  @spec update_profile(User.t(), map()) :: {:ok, User.t()} | {:error, Ecto.Changeset.t()}
  def update_profile(%User{} = user, attrs) do
    user
    |> User.profile_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Reset a user's password. After update, deletes any outstanding
  reset_password tokens for that user so a used token can't be replayed.
  """
  @spec reset_user_password(User.t(), map()) ::
          {:ok, User.t()} | {:error, Ecto.Changeset.t()}
  def reset_user_password(%User{} = user, attrs) do
    Repo.transact(fn ->
      with {:ok, updated} <- user |> User.password_changeset(attrs) |> Repo.update() do
        Repo.delete_all(UserToken.by_user_and_contexts_query(user, ["reset_password"]))
        {:ok, updated}
      end
    end)
  end

  @spec confirm_user(User.t()) :: {:ok, User.t()} | {:error, Ecto.Changeset.t()}
  def confirm_user(%User{} = user) do
    user |> User.confirm_changeset() |> Repo.update()
  end

  @doc """
  Decide which screen the user lands on after a successful login or
  registration (Phase 6 D-04, VERIFY-01).

  Returns:
    * `:main_menu` — user is confirmed (`confirmed_at != nil`), OR
                    `require_email_verification` is disabled globally.
    * `:verify`   — user is unconfirmed AND verification is required.

  Reads the `require_email_verification` config key with a safe default of
  `true` — a missing seed entry (stale test DB) defaults to "verification
  required" rather than silently bypassing the check.

  Retroactive bypass policy (REQUIREMENTS locked): an existing user with
  `confirmed_at: nil` gains access on their next login when the sysop flips
  the toggle to `false`; no DB migration is performed.
  """
  @spec post_login_screen(User.t()) :: :main_menu | :verify
  def post_login_screen(%User{confirmed_at: confirmed_at}) do
    cond do
      confirmed_at != nil ->
        :main_menu

      Foglet.Config.require_email_verification?() == false ->
        :main_menu

      true ->
        :verify
    end
  end

  @doc """
  Build and persist an email verification code for `user`. Returns the raw 6-char
  alphanumeric code (the value to show/email/log to the user). The code expires in
  15 minutes. See D-08, D-10.
  """
  @spec build_verify_code(User.t()) :: {:ok, String.t()} | {:error, Ecto.Changeset.t()}
  def build_verify_code(%User{} = user) do
    {raw_code, token_struct} = UserToken.build_verify_code(user)

    case Repo.insert(token_struct) do
      {:ok, _} -> {:ok, raw_code}
      {:error, cs} -> {:error, cs}
    end
  end

  @doc """
  Persist and attempt delivery of an email verification code.

  Delivery is available only when `Foglet.Config.delivery_mode/0` is `"email"`.
  Provider-specific errors are intentionally collapsed so TUI callers can keep
  user-facing copy generic.
  """
  @spec deliver_verification_code(User.t()) ::
          {:ok, :attempted} | {:error, :unavailable | :delivery_failed | Ecto.Changeset.t()}
  def deliver_verification_code(%User{} = user) do
    case Foglet.Config.delivery_mode() do
      "email" ->
        with {:ok, code} <- build_verify_code(user),
             {:ok, _delivery} <- Foglet.Mailer.deliver(Email.verification_code(user, code)) do
          {:ok, :attempted}
        else
          {:error, %Ecto.Changeset{} = changeset} -> {:error, changeset}
          {:error, _reason} -> {:error, :delivery_failed}
        end

      "no_email" ->
        {:error, :unavailable}
    end
  end

  @doc """
  Request terminal-native password reset delivery for a handle or email.

  In email delivery mode this function is enumeration-safe: active matches,
  unknown identifiers, deleted accounts, inactive accounts, and provider
  failures all return the same outward result.
  """
  @spec request_password_reset_delivery(String.t()) ::
          {:ok, :generic_response} | {:error, :unavailable}
  def request_password_reset_delivery(identifier) when is_binary(identifier) do
    case Foglet.Config.delivery_mode() do
      "no_email" ->
        {:error, :unavailable}

      "email" ->
        identifier
        |> String.trim()
        |> find_reset_delivery_user()
        |> maybe_deliver_password_reset()

        {:ok, :generic_response}
    end
  end

  @doc """
  Verify an email code for `user`. On success, confirms the user (sets `confirmed_at`)
  and returns `{:ok, confirmed_user}`. On failure returns:
    - `{:error, :invalid_code}` — code did not match any non-expired verify token
    - `{:error, :expired}` — token exists but inserted_at > 15 minutes ago
  See D-10, D-12.
  """
  @spec verify_email_code(User.t(), String.t()) ::
          {:ok, User.t()} | {:error, :invalid_code | :expired}
  def verify_email_code(%User{email: email} = user, code)
      when is_binary(code) and byte_size(code) > 0 do
    valid_row =
      code
      |> UserToken.verify_code_query(email)
      |> Repo.one()

    cond do
      valid_row != nil and valid_row.user_id == user.id ->
        Repo.transact(fn ->
          with {:ok, confirmed} <- user |> User.confirm_changeset() |> Repo.update() do
            Repo.delete_all(UserToken.by_user_and_contexts_query(user, ["email_verify"]))
            {:ok, confirmed}
          end
        end)

      expired_exists?(user, code) ->
        {:error, :expired}

      true ->
        {:error, :invalid_code}
    end
  end

  defp expired_exists?(%User{id: user_id, email: email}, code) do
    validity = UserToken.email_verify_validity_minutes()

    query =
      from t in UserToken,
        where:
          t.token == ^code and t.context == "email_verify" and
            t.sent_to == ^email and t.user_id == ^user_id and
            t.inserted_at <= ago(^validity, "minute")

    Repo.exists?(query)
  end

  defp find_reset_delivery_user(""), do: nil

  defp find_reset_delivery_user(identifier) do
    case get_user_by_handle(identifier) || get_user_by_email(identifier) do
      %User{status: :active, deleted_at: nil} = user -> user
      _other -> nil
    end
  end

  defp maybe_deliver_password_reset(nil), do: :ok

  defp maybe_deliver_password_reset(%User{} = user) do
    {raw_token, token_struct} = UserToken.build_email_token(user, "reset_password")

    with {:ok, _token} <- Repo.insert(token_struct) do
      _ = Foglet.Mailer.deliver(Email.password_reset(user, raw_token))
      :ok
    end
  end

  @doc """
  Build and persist a reset-password token for operator-assisted retrieval.

  Returns the raw token once so the caller can hand it to the user through a
  supported operator-controlled channel. Only the hashed token row is stored.
  """
  @spec generate_reset_token_for_operator(User.t()) ::
          {:ok, String.t()} | {:error, Ecto.Changeset.t()}
  def generate_reset_token_for_operator(%User{} = user) do
    {raw_token, token_struct} = UserToken.build_email_token(user, "reset_password")

    case Repo.insert(token_struct) do
      {:ok, _token} -> {:ok, raw_token}
      {:error, %Ecto.Changeset{} = changeset} -> {:error, changeset}
    end
  end

  defp notify_sysops_pending_registration(%User{} = pending_user) do
    case Config.delivery_mode() do
      "email" ->
        from(u in User, where: u.role == :sysop and u.status == :active and not is_nil(u.email))
        |> QueryHelpers.not_deleted()
        |> Repo.all()
        |> Enum.each(fn sysop ->
          _ = Mailer.deliver(Email.pending_approval_notification(sysop, pending_user))
          :ok
        end)

      "no_email" ->
        :ok
    end
  end

  defp deliver_status_transition_notification(%User{} = user, :pending, :active) do
    deliver_status_email(user, &Email.approval_notification/1)
  end

  defp deliver_status_transition_notification(%User{} = user, :pending, :rejected) do
    deliver_status_email(user, &Email.rejection_notification/1)
  end

  defp deliver_status_transition_notification(_user, _from, _to), do: :not_applicable

  defp deliver_status_email(%User{} = user, build_email) when is_function(build_email, 1) do
    case Config.delivery_mode() do
      "email" ->
        case Mailer.deliver(build_email.(user)) do
          {:ok, _delivery} -> :attempted
          {:error, reason} -> {:failed, reason}
        end

      "no_email" ->
        :skipped_no_email
    end
  end

  @doc """
  Delete a user with anonymization.

  Current anonymization flow:
    1. Delete all user_tokens for this user
    2. Delete all ssh_keys for this user
    3. Rewrite posts authored by the user to the tombstone user
    4. Apply deletion_changeset to the user row (clears PII, sets deleted_at)

  The tombstone user is seeded, not created here. If matching posts exist
  and the seed row is missing, the foreign key fails the transaction.
  Phase 6+ will add direct_messages handling.
  The user row is preserved so FK references (future) remain valid.
  """
  @spec delete_user(User.t()) :: {:ok, User.t()} | {:error, Ecto.Changeset.t()}
  def delete_user(%User{} = user) do
    Repo.transact(fn ->
      Repo.delete_all(UserToken.by_user_and_contexts_query(user, :all))
      Repo.delete_all(from(k in SSHKey, where: k.user_id == ^user.id))

      Repo.update_all(from(p in Post, where: p.user_id == ^user.id),
        set: [user_id: tombstone_user_id()]
      )

      user |> User.deletion_changeset() |> Repo.update()
    end)
  end

  # ---------- Invites ----------

  @spec create_invite(User.t()) ::
          {:ok, Invite.t()} | {:error, :forbidden | :limit_reached | Ecto.Changeset.t()}
  def create_invite(%User{} = actor) do
    with :ok <- Bodyguard.permit(Foglet.Authorization, :generate_invite, actor, :site),
         :ok <- ensure_invite_generation_policy(actor),
         :ok <- ensure_invite_generation_limit(actor) do
      insert_invite(actor, 5)
    else
      {:error, :forbidden} -> {:error, :forbidden}
      {:error, :limit_reached} -> {:error, :limit_reached}
    end
  end

  @spec list_invites(User.t()) :: {:ok, [invite_status()]} | {:error, :forbidden}
  def list_invites(%User{} = actor) do
    with :ok <- Bodyguard.permit(Foglet.Authorization, :generate_invite, actor, :site) do
      invites =
        Repo.all(from(i in Invite, order_by: [desc: i.inserted_at]))
        |> Enum.map(&invite_status_map/1)

      {:ok, invites}
    end
  end

  @spec get_invite_status(String.t()) :: {:ok, invite_status()} | {:error, :not_found}
  def get_invite_status(code) when is_binary(code) do
    case Repo.get_by(Invite, code: code) do
      %Invite{} = invite -> {:ok, invite_status_map(invite)}
      nil -> {:error, :not_found}
    end
  end

  @spec revoke_invite(User.t(), String.t()) ::
          {:ok, Invite.t()} | {:error, :forbidden | :not_found | :unavailable}
  def revoke_invite(%User{} = actor, code) when is_binary(code) do
    with :ok <- Bodyguard.permit(Foglet.Authorization, :revoke_invite, actor, :site) do
      case Repo.get_by(Invite, code: code) do
        nil ->
          {:error, :not_found}

        %Invite{} = invite ->
          revoke_available_invite(invite, code)
      end
    end
  end

  defp ensure_invite_generation_policy(%User{role: :sysop}), do: :ok

  defp ensure_invite_generation_policy(%User{role: :mod}) do
    case Foglet.Config.invite_code_generators() do
      policy when policy in ["mods", "any_user"] -> :ok
      _policy -> {:error, :forbidden}
    end
  end

  defp ensure_invite_generation_policy(%User{role: :user}) do
    case Foglet.Config.invite_code_generators() do
      "any_user" -> :ok
      _policy -> {:error, :forbidden}
    end
  end

  defp ensure_invite_generation_policy(%User{}), do: {:error, :forbidden}

  defp ensure_invite_generation_limit(%User{role: :user, id: user_id}) do
    if Foglet.Config.invite_code_generators() == "any_user" do
      case Foglet.Config.invite_generation_per_user_limit() do
        0 ->
          :ok

        limit when is_integer(limit) and limit > 0 ->
          count = Repo.aggregate(from(i in Invite, where: i.issuer_id == ^user_id), :count)

          if count >= limit do
            {:error, :limit_reached}
          else
            :ok
          end
      end
    else
      :ok
    end
  end

  defp ensure_invite_generation_limit(%User{}), do: :ok

  defp insert_invite(%User{} = actor, attempts_remaining) do
    %Invite{issuer_id: actor.id}
    |> Invite.changeset(%{code: generate_invite_code()})
    |> Repo.insert()
    |> case do
      {:ok, invite} ->
        {:ok, invite}

      {:error, changeset} = error ->
        if invite_code_collision?(changeset) and attempts_remaining > 1 do
          insert_invite(actor, attempts_remaining - 1)
        else
          error
        end
    end
  end

  defp invite_code_collision?(%Ecto.Changeset{errors: errors}) do
    Keyword.has_key?(errors, :code)
  end

  defp generate_invite_code do
    16
    |> :crypto.strong_rand_bytes()
    |> Base.encode32(case: :upper, padding: false)
    |> String.replace(~r/[^A-Z0-9]/, "")
  end

  defp invite_status_map(%Invite{} = invite) do
    %{
      code: invite.code,
      issuer_id: invite.issuer_id,
      inserted_at: invite.inserted_at,
      consumed_at: invite.consumed_at,
      consumed_by_user_id: invite.consumed_by_user_id,
      revoked_at: invite.revoked_at,
      status: Invite.status(invite)
    }
  end

  defp revoke_available_invite(%Invite{} = invite, code) do
    if Invite.status(invite) == :available do
      now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

      query =
        from i in Invite,
          where: i.code == ^code and is_nil(i.consumed_at) and is_nil(i.revoked_at)

      case Repo.update_all(query, set: [revoked_at: now, updated_at: now]) do
        {1, _rows} -> {:ok, Repo.get!(Invite, invite.id)}
        {0, _rows} -> {:error, :unavailable}
      end
    else
      {:error, :unavailable}
    end
  end

  # ---------- SSH Keys ----------

  @spec register_ssh_key(User.t(), map()) ::
          {:ok, SSHKey.t()} | {:error, Ecto.Changeset.t()}
  def register_ssh_key(%User{} = user, attrs) do
    %SSHKey{user_id: user.id}
    |> SSHKey.changeset(attrs)
    |> Repo.insert()
  end

  @spec list_ssh_keys(User.t()) :: [SSHKey.t()]
  def list_ssh_keys(%User{} = user) do
    Repo.all(from k in SSHKey, where: k.user_id == ^user.id, order_by: [asc: :inserted_at])
  end

  @spec revoke_ssh_key(User.t(), Ecto.UUID.t() | String.t()) ::
          {:ok, SSHKey.t()} | {:error, :not_found}
  def revoke_ssh_key(%User{} = actor, key_id) do
    case Repo.get_by(SSHKey, id: key_id, user_id: actor.id) do
      %SSHKey{} = key -> Repo.delete(key)
      nil -> {:error, :not_found}
    end
  end

  @doc """
  Lookup a user by an OpenSSH-format public key. Used by Phase 3 SSH
  pubkey auth. Returns `{:ok, user}` if the fingerprint matches a
  registered active user.
  """
  @spec get_user_by_public_key(String.t()) :: {:ok, User.t()} | {:error, :not_found}
  def get_user_by_public_key(public_key_text) when is_binary(public_key_text) do
    with {:ok, fp} <- SSHKey.compute_fingerprint(public_key_text),
         %User{deleted_at: nil} = user <-
           Repo.one(
             from k in SSHKey,
               where: k.fingerprint == ^fp,
               join: u in assoc(k, :user),
               where: is_nil(u.deleted_at) and u.status == :active,
               select: u
           ) do
      {:ok, user}
    else
      _ -> {:error, :not_found}
    end
  end

  @spec authenticate_by_public_key(String.t()) :: {:ok, User.t()} | {:error, :not_found}
  def authenticate_by_public_key(public_key_text) when is_binary(public_key_text) do
    with {:ok, fp} <- SSHKey.compute_fingerprint(public_key_text),
         {%SSHKey{} = key, %User{} = user} <- get_active_ssh_key_and_user(fp) do
      now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

      case Repo.update_all(from(k in SSHKey, where: k.id == ^key.id),
             set: [last_used_at: now, updated_at: now]
           ) do
        {1, _rows} -> {:ok, user}
        _ -> {:error, :not_found}
      end
    else
      _ -> {:error, :not_found}
    end
  end

  defp get_active_ssh_key_and_user(fingerprint) do
    Repo.one(
      from k in SSHKey,
        where: k.fingerprint == ^fingerprint,
        join: u in assoc(k, :user),
        where: is_nil(u.deleted_at) and u.status == :active,
        select: {k, u}
    )
  end

  # ---------- Tokens (no mailer in Phase 1 — D-01) ----------

  @doc """
  Generate a confirmation token, persist it, and return the caller-built
  delivery value.
  """
  @spec deliver_user_confirmation_instructions(User.t(), (String.t() -> String.t())) ::
          {:ok, String.t()} | {:error, :already_confirmed}
  def deliver_user_confirmation_instructions(%User{confirmed_at: nil} = user, url_fn)
      when is_function(url_fn, 1) do
    {raw, token_struct} = UserToken.build_email_token(user, "confirm")
    {:ok, _} = Repo.insert(token_struct)
    {:ok, url_fn.(raw)}
  end

  def deliver_user_confirmation_instructions(%User{}, _url_fn) do
    {:error, :already_confirmed}
  end

  @doc """
  Generate a reset-password token, persist it, and return the caller-built
  delivery value.
  """
  @spec deliver_user_reset_password_instructions(User.t(), (String.t() -> String.t())) ::
          {:ok, String.t()}
  def deliver_user_reset_password_instructions(%User{} = user, url_fn)
      when is_function(url_fn, 1) do
    {raw, token_struct} = UserToken.build_email_token(user, "reset_password")
    {:ok, _} = Repo.insert(token_struct)
    {:ok, url_fn.(raw)}
  end
end
