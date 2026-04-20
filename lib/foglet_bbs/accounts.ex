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

  alias Ecto.Multi
  alias Foglet.Accounts.{SSHKey, User, UserToken}
  alias FogletBbs.Repo

  @tombstone_user_id "00000000-0000-0000-0000-000000000001"

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
    Multi.new()
    |> Multi.update(:user, User.password_changeset(user, attrs))
    |> Multi.delete_all(
      :invalidate_tokens,
      UserToken.by_user_and_contexts_query(user, ["reset_password"])
    )
    |> Repo.transaction()
    |> case do
      {:ok, %{user: updated}} -> {:ok, updated}
      {:error, :user, changeset, _} -> {:error, changeset}
    end
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

      Foglet.Config.get("require_email_verification", true) == false ->
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
        result =
          Multi.new()
          |> Multi.update(:confirm, User.confirm_changeset(user))
          |> Multi.delete_all(
            :cleanup,
            UserToken.by_user_and_contexts_query(user, ["email_verify"])
          )
          |> Repo.transaction()

        case result do
          {:ok, %{confirm: confirmed}} -> {:ok, confirmed}
          {:error, :confirm, cs, _} -> {:error, cs}
        end

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

  In Phase 1 (no posts table yet):
    1. Delete all user_tokens for this user
    2. Delete all ssh_keys for this user
    3. Apply deletion_changeset to the user row (clears PII, sets deleted_at)

  Phase 2+ will add a Multi step rewriting `posts.user_id` to
  `tombstone_user_id/0`. Phase 6+ will add direct_messages handling.
  The user row is preserved so FK references (future) remain valid.
  """
  @spec delete_user(User.t()) ::
          {:ok, User.t()} | {:error, Ecto.Changeset.t() | :transaction_failed}
  def delete_user(%User{} = user) do
    Multi.new()
    |> Multi.delete_all(
      :delete_tokens,
      UserToken.by_user_and_contexts_query(user, :all)
    )
    |> Multi.delete_all(
      :delete_ssh_keys,
      from(k in SSHKey, where: k.user_id == ^user.id)
    )
    |> Multi.update(:anonymize, User.deletion_changeset(user))
    |> Repo.transaction()
    |> case do
      {:ok, %{anonymize: updated}} -> {:ok, updated}
      {:error, _op, %Ecto.Changeset{} = cs, _} -> {:error, cs}
      {:error, _op, _reason, _} -> {:error, :transaction_failed}
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
