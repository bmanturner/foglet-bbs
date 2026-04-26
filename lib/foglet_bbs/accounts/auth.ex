defmodule Foglet.Accounts.Auth do
  @moduledoc """
  Authentication functions for `Foglet.Accounts`.

  Handles password-based and public-key-based authentication.
  """

  import Ecto.Query, warn: false

  alias Foglet.Accounts.{SSHKey, User}
  alias FogletBbs.Repo

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
end
