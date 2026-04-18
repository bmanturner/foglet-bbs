defmodule Foglet.SSH.KeyCB do
  @moduledoc """
  SSH public-key authentication callback module.

  Implements Erlang's :ssh_server_key_api behaviour:
    * host_key/2 — returns the server's private host key
    * is_auth_key/3 — decides whether a presented public key matches a
      registered user (SSH-03)

  Design notes:
    * Username arrives as an Erlang charlist; converted via List.to_string/1
      at the boundary (Pitfall 2 — never String.to_atom/1).
    * Public key arrives in Erlang :public_key record form; we convert to
      the OpenSSH text format with :ssh_file.encode/2 so we can compute the
      same SHA256 fingerprint the Foglet.Accounts.SSHKey schema stores.
  """

  @behaviour :ssh_server_key_api

  alias Foglet.Accounts

  @impl true
  def host_key(algorithm, opts) do
    :ssh_file.host_key(algorithm, opts)
  end

  @impl true
  def is_auth_key(public_key, user, opts) when is_list(user) do
    handle = List.to_string(user)
    auth_key_for?(handle, public_key, opts)
  end

  # Fallback for already-binary user (some test harnesses pass binary).
  def is_auth_key(public_key, user, opts) when is_binary(user) do
    auth_key_for?(user, public_key, opts)
  end

  # --- Private ---

  defp auth_key_for?(handle, public_key, _opts) do
    case encode_public_key(public_key) do
      {:ok, openssh_text} ->
        ensure_handle_matches?(handle, openssh_text)

      _ ->
        false
    end
  end

  defp encode_public_key(public_key) do
    text = :ssh_file.encode([{public_key, []}], :openssh_key)
    {:ok, to_string(text)}
  rescue
    _ -> :error
  catch
    _, _ -> :error
  end

  defp ensure_handle_matches?(handle, openssh_text) do
    case Accounts.get_user_by_public_key(openssh_text) do
      {:ok, user} -> user.handle == handle and is_nil(user.deleted_at)
      _ -> false
    end
  end
end
