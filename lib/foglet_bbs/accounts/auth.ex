defmodule Foglet.Accounts.Auth do
  @moduledoc """
  Authentication functions for `Foglet.Accounts`.

  Handles password-based and public-key-based authentication.
  """

  import Ecto.Query, warn: false

  alias Foglet.Accounts.{SSHKey, User}
  alias FogletBbs.Repo

  @type public_key_lookup :: %{
          required(:user) => User.t(),
          required(:ssh_key) => SSHKey.t(),
          required(:fingerprint) => String.t()
        }

  @type session_authorization ::
          {:ok, :authorized, User.t()}
          | {:ok, :verify, User.t()}
          | {:error, :pending | :rejected | :suspended | :deleted}

  @doc """
  Verify handle + password. Always runs an Argon2 hash comparison
  (even on unknown handle) to prevent timing-based user enumeration.
  Rejects deleted users.
  """
  @spec authenticate_by_password(String.t(), String.t()) ::
          {:ok, User.t()} | {:error, :invalid_credentials}
  def authenticate_by_password(handle, password)
      when is_binary(handle) and is_binary(password) do
    user = Repo.get_by(User, handle: handle)

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

  @doc """
  Find the account and key row for an OpenSSH-format public key.

  This is a lookup only: it intentionally returns non-deleted users regardless
  of account status so SSH callers can distinguish "no stored key" from
  "stored key, but the account must pass a gate before full access".
  """
  @spec lookup_by_public_key(String.t()) :: {:ok, public_key_lookup()} | {:error, :not_found}
  def lookup_by_public_key(public_key_text) when is_binary(public_key_text) do
    with {:ok, fp} <- SSHKey.compute_fingerprint(public_key_text),
         {%SSHKey{} = key, %User{deleted_at: nil} = user} <-
           get_ssh_key_and_non_deleted_user(fp) do
      {:ok, %{ssh_key: key, user: user, fingerprint: fp}}
    else
      _ -> {:error, :not_found}
    end
  end

  @doc """
  Decide whether a matched public-key user may enter a full session.

  Active + confirmed users are authorized. Active but unconfirmed users are a
  matched identity that must route to email verification. Pending, rejected,
  suspended, and deleted users are explicit blocked outcomes.
  """
  @spec authorize_session(User.t()) :: session_authorization()
  def authorize_session(%User{deleted_at: deleted_at}) when not is_nil(deleted_at),
    do: {:error, :deleted}

  def authorize_session(%User{status: :active, confirmed_at: %DateTime{}} = user),
    do: {:ok, :authorized, user}

  def authorize_session(%User{status: :active} = user), do: {:ok, :verify, user}

  def authorize_session(%User{status: status}) when status in [:pending, :rejected, :suspended],
    do: {:error, status}

  @spec authenticate_by_public_key(String.t()) :: {:ok, User.t()} | {:error, :not_found}
  def authenticate_by_public_key(public_key_text) when is_binary(public_key_text) do
    with {:ok, %{ssh_key: key, user: user}} <- lookup_by_public_key(public_key_text),
         {:ok, :authorized, user} <- authorize_session(user),
         :ok <- record_key_use(key) do
      {:ok, user}
    else
      _ -> {:error, :not_found}
    end
  end

  defp record_key_use(%SSHKey{} = key) do
    now = DateTime.utc_now() |> DateTime.truncate(:microsecond)

    case Repo.update_all(from(k in SSHKey, where: k.id == ^key.id),
           set: [last_used_at: now, updated_at: now]
         ) do
      {1, _rows} -> :ok
      _ -> {:error, :not_found}
    end
  end

  defp get_ssh_key_and_non_deleted_user(fingerprint) do
    Repo.one(
      from k in SSHKey,
        where: k.fingerprint == ^fingerprint,
        join: u in assoc(k, :user),
        where: is_nil(u.deleted_at),
        select: {k, u}
    )
  end
end
