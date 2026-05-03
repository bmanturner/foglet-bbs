defmodule Foglet.SSH.KeyCB do
  @moduledoc """
  SSH public-key callback module (`:ssh_server_key_api` behaviour).

  ## Architecture decision (D-13 rewrite / #7 audit fix)

  We chose **Option A** for `is_auth_key/3`:

  - Always return `true` so every structurally valid SSH key can pass the SSH
    transport. Foglet does account identity and access gates after the channel
    starts; an unmatched key becomes a guest/registration session, not an
    authenticated account.
  - Record the offered pubkey in `Foglet.SSH.PubkeyStash` (an ETS table) keyed
    by `{peer_ip, peer_port}`. The CLIHandler reads this stash on
    `{:ssh_channel_up, ...}` to decide whether to skip the login screen.

  Option B (keep the username+key check) was rejected because it couples auth
  state to SSH-layer callbacks that Erlang doesn't expose cleanly to the channel
  handler; Option A keeps the correlation simple and self-contained.

  Host-key loading still delegates to `:ssh_file.host_key/2`.
  """

  @behaviour :ssh_server_key_api

  @impl true
  def host_key(algorithm, opts) do
    :ssh_file.host_key(algorithm, opts)
  end

  @impl true
  def is_auth_key(public_key, _user, opts) do
    # Stash the offered pubkey for CLIHandler to pick up after channel_up.
    # Peer address is available as {ip, port} in opts under :peer.
    peer = extract_peer(opts)
    Foglet.SSH.PubkeyStash.put(peer, public_key)
    # Always allow structurally valid SSH keys through the transport. Foglet
    # resolves account identity inside the session layer; unmatched keys become
    # guest/registration sessions rather than authenticated users.
    true
  end

  # --- Private ---

  defp extract_peer(opts) do
    case Keyword.get(opts, :peer) do
      {{ip, port}, _socket} -> {ip, port}
      {ip, port} when is_tuple(ip) and is_integer(port) -> {ip, port}
      _ -> :unknown
    end
  end
end
