defmodule Foglet.SSH.PubkeyStash do
  @moduledoc """
  ETS-backed stash for SSH public keys offered during connection.

  ## Problem being solved

  Erlang's `:ssh` does not expose the public key a client offered to the
  SSH channel handler (`ssh_server_channel` callbacks). `is_auth_key/3` in
  `KeyCB` is called during the handshake — before `ssh_channel_up` fires —
  so the pubkey must be saved somewhere the CLIHandler can retrieve it.

  ## Approach

  `KeyCB.is_auth_key/3` receives the connecting peer address via the `opts`
  keyword list. We stash `{peer_key => public_key_record}` in an ETS table
  named `__MODULE__`. The CLIHandler reads the stash immediately after
  `ssh_channel_up` using the peer address it finds via
  `:ssh.connection_info(connection_ref, [:peer])`. After reading, it deletes
  the entry to prevent stale data.

  ## TTL / eviction

  Entries are deleted by the reader. If a connection dies before the channel
  handler starts (unlikely but possible), the entry stays. A low-priority
  periodic sweep is not implemented — the stash is bounded by max_sessions
  (500) and each entry is a small Erlang term.
  """

  @table __MODULE__

  @doc "Ensure the ETS table exists. Called from Application.start/2."
  def init do
    if :ets.whereis(@table) == :undefined do
      :ets.new(@table, [:named_table, :public, :set])
    end

    :ok
  end

  @doc "Store a public key record keyed by peer `{ip, port}` or `:unknown`."
  @spec put(term(), term()) :: true
  def put(peer_key, public_key) do
    :ets.insert(@table, {peer_key, public_key})
  end

  @doc """
  Retrieve and delete the public key for the given peer.
  Returns `{:ok, public_key}` or `:miss`.
  """
  @spec pop(term()) :: {:ok, term()} | :miss
  def pop(:unknown), do: :miss

  def pop(peer_key) do
    case :ets.take(@table, peer_key) do
      [{^peer_key, public_key}] -> {:ok, public_key}
      [] -> :miss
    end
  end
end
