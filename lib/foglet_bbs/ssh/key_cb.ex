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

  @process_offer_key {__MODULE__, :offered_public_key}

  @impl true
  def is_auth_key(public_key, _user, opts) do
    # The OTP key callback receives daemon key_cb options, not the live SSH peer.
    # Keep the offered key in the auth process until `connect/3` receives the
    # authenticated peer and can write the peer-keyed stash CLIHandler consumes.
    Process.put(@process_offer_key, public_key)

    # Tests and older callback paths may still pass :peer explicitly; keep that
    # direct write as a harmless compatibility path.
    peer = extract_peer(opts)
    Foglet.SSH.PubkeyStash.put(peer, public_key)

    # Always allow structurally valid SSH keys through the transport. Foglet
    # resolves account identity inside the session layer; unmatched keys become
    # guest/registration sessions rather than authenticated users.
    true
  end

  @doc false
  def connect(_user, peer, method) when method in ["publickey", ~c"publickey", :publickey] do
    case Process.get(@process_offer_key) do
      nil ->
        :ok

      public_key ->
        Process.delete(@process_offer_key)
        Foglet.SSH.PubkeyStash.put(normalize_peer(peer), public_key)
        :ok
    end
  end

  def connect(_user, _peer, _method), do: :ok

  # --- Private ---

  defp extract_peer(opts) do
    opts
    |> Keyword.get(:peer)
    |> normalize_peer()
  end

  defp normalize_peer({transport, {ip, port}})
       when is_atom(transport) and is_tuple(ip) and is_integer(port),
       do: {ip, port}

  defp normalize_peer({{ip, port}, _socket}) when is_tuple(ip) and is_integer(port),
    do: {ip, port}

  defp normalize_peer({ip, port}) when is_tuple(ip) and is_integer(port), do: {ip, port}

  defp normalize_peer(_peer), do: :unknown
end
