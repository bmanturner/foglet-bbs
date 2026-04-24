defmodule Foglet.Accounts do
  @moduledoc """
  User accounts, SSH keys, and token generation.

  Public API consumed by:
    * Phase 1 Mix tasks (`mix foglet.user.*`)
    * Phase 3 SSH auth (`authenticate_by_password/2`, `get_user_by_public_key/1`)
    * Phase 10 email delivery (the `deliver_*` functions will gain a
      mailer call there; for now they only persist the token and return
      the URL — per CONTEXT D-01).

  Design notes:
    * Hand-rolled per CONTEXT D-07 — not `mix phx.gen.auth` output.
    * `:password` is a virtual field on User; never persisted.
    * `user_tokens` stores SHA256 hashes; raw token returned to caller.
    * Account deletion preserves the user row (sets `deleted_at`) so
      foreign keys remain valid. Post rewrites to the tombstone user
      are layered in when `posts` exists (Phase 2+).
  """

  import Ecto.Query, warn: false

  alias Foglet.Accounts.{Invite, SSHKey, User, UserToken}
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
    if Foglet.Config.registration_mode() == "invite_only" do
      register_invite_only_user(attrs)
    else
      register_open_user(attrs)
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
      is_nil(invite_code) or String.trim(to_string(invite_code)) == "" ->
        {:error, invite_code_error(user_changeset)}

      not user_changeset.valid? ->
        {:error, user_changeset}

      true ->
        code = String.trim(to_string(invite_code))

        case Repo.transact(fn ->
               with {:ok, user} <- Repo.insert(user_changeset),
                    {:ok, user} <- consume_invite_for_user(Repo, code, user) do
                 {:ok, user}
               end
             end) do
          {:ok, user} ->
            # D-06: subscribe to default boards after successful registration.
            Foglet.Boards.subscribe_to_defaults(user.id)
            {:ok, user}

          {:error, :invalid_invite_code} ->
            {:error, invite_code_error(user_changeset)}

          {:error, %Ecto.Changeset{} = changeset} ->
            {:error, changeset}
        end
    end
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

  @doc """
  Create a new user account in `:pending` status (sysop-approved registration mode, D-05).
  Same validation as `register_user/1`; differs only in the persisted status value.
  Login is blocked for pending users in Phase 3's login flow.
  """
  @spec register_pending_user(map()) :: {:ok, User.t()} | {:error, Ecto.Changeset.t()}
  def register_pending_user(attrs) do
    %User{status: :pending}
    |> User.registration_changeset(attrs)
    |> Repo.insert()
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

  @doc """
  Lookup a user by an OpenSSH-format public key. Used by Phase 3 SSH
  pubkey auth. Returns `{:ok, user}` if the fingerprint matches a
  registered, non-deleted user.
  """
  @spec get_user_by_public_key(String.t()) :: {:ok, User.t()} | {:error, :not_found}
  def get_user_by_public_key(public_key_text) when is_binary(public_key_text) do
    with {:ok, fp} <- SSHKey.compute_fingerprint(public_key_text),
         %User{deleted_at: nil} = user <-
           Repo.one(
             from k in SSHKey,
               where: k.fingerprint == ^fp,
               join: u in assoc(k, :user),
               where: is_nil(u.deleted_at),
               select: u
           ) do
      {:ok, user}
    else
      _ -> {:error, :not_found}
    end
  end

  # ---------- Tokens (no mailer in Phase 1 — D-01) ----------

  @doc """
  Generate a confirmation token, persist it, and return the URL built
  via `url_fn`. No email sent in Phase 1 (D-01). Phase 10 adds Swoosh
  delivery here.
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
  Generate a reset-password token, persist it, and return the URL.
  No email sent in Phase 1 (D-01, IDNT-08). Phase 10 adds delivery.
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
