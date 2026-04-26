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
  Verify handle + password. Delegates to `Foglet.Accounts.Auth`.
  """
  defdelegate authenticate_by_password(handle, password), to: Foglet.Accounts.Auth

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
          Repo.all(
            from u in User,
              where: is_nil(u.deleted_at),
              order_by: [asc: u.inserted_at]
          )

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

  @doc "Reset a user's password. Delegates to `Foglet.Accounts.Verification`."
  defdelegate reset_user_password(user, attrs), to: Foglet.Accounts.Verification

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

  @doc "Build a verification code. Delegates to `Foglet.Accounts.Verification`."
  defdelegate build_verify_code(user), to: Foglet.Accounts.Verification

  @doc "Deliver a verification code. Delegates to `Foglet.Accounts.Verification`."
  defdelegate deliver_verification_code(user), to: Foglet.Accounts.Verification

  @doc "Request terminal-native password reset delivery. Delegates to `Foglet.Accounts.Verification`."
  defdelegate request_password_reset_delivery(identifier), to: Foglet.Accounts.Verification

  @doc "Verify an email code. Delegates to `Foglet.Accounts.Verification`."
  defdelegate verify_email_code(user, code), to: Foglet.Accounts.Verification

  @doc "Generate a reset token for operator-assisted retrieval. Delegates to `Foglet.Accounts.Verification`."
  defdelegate generate_reset_token_for_operator(user), to: Foglet.Accounts.Verification

  defp notify_sysops_pending_registration(%User{} = pending_user) do
    case Config.delivery_mode() do
      "email" ->
        Repo.all(
          from u in User,
            where:
              u.role == :sysop and u.status == :active and is_nil(u.deleted_at) and
                not is_nil(u.email)
        )
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

  @doc "Generate an invite code. Delegates to `Foglet.Accounts.Invites`."
  defdelegate create_invite(actor), to: Foglet.Accounts.Invites

  @doc "List all invites with status. Delegates to `Foglet.Accounts.Invites`."
  defdelegate list_invites(actor), to: Foglet.Accounts.Invites

  @doc "Look up invite status by code. Delegates to `Foglet.Accounts.Invites`."
  defdelegate get_invite_status(code), to: Foglet.Accounts.Invites

  @doc "Revoke an unredeemed invite. Delegates to `Foglet.Accounts.Invites`."
  defdelegate revoke_invite(actor, code), to: Foglet.Accounts.Invites

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

  @doc "Lookup a user by an OpenSSH-format public key. Delegates to `Foglet.Accounts.Auth`."
  defdelegate get_user_by_public_key(public_key_text), to: Foglet.Accounts.Auth

  @doc "Authenticate via SSH public key. Delegates to `Foglet.Accounts.Auth`."
  defdelegate authenticate_by_public_key(public_key_text), to: Foglet.Accounts.Auth

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
