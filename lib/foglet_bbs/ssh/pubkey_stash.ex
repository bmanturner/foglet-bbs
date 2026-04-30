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
  keyword list. We stash `{peer_key, public_key, inserted_at_ms}` in an ETS
  table named `__MODULE__`. The CLIHandler reads the stash immediately after
  `ssh_channel_up` using the peer address it finds via
  `:ssh.connection_info(connection_ref, [:peer])`. After reading, it deletes
  the entry to prevent stale data.

  ## TTL / sweep

  Entries are timestamped on `put/2` using `System.monotonic_time(:millisecond)`.
  `pop/1` treats expired entries as `:miss` and deletes them, so a stale offer
  cannot be consumed by a later connection from the same peer tuple. `sweep/2`
  removes stale orphan entries (e.g. when a connection dies before
  `ssh_channel_up` fires) and returns the number of entries deleted.

  Missing or expired stash entries still result in guest sessions; the TTL
  does not change `no_auth_needed: true` or any authentication outcome.
  """

  @table __MODULE__
  @ttl_ms :timer.minutes(5)

  @doc "Ensure the ETS table exists. Called from Application.start/2."
  def init do
    case :ets.whereis(@table) do
      :undefined ->
        _ = :ets.new(@table, [:named_table, :public, :set])
        :ok

      _tid ->
        :ok
    end
  end

  @doc "Store a public key record keyed by peer `{ip, port}` or `:unknown`."
  @spec put(term(), term()) :: true
  def put(peer_key, public_key) do
    put(peer_key, public_key, System.monotonic_time(:millisecond))
  end

  @doc """
  Store a public key record with an explicit insertion timestamp. Intended for
  deterministic tests; production callers should use `put/2`.
  """
  @spec put(term(), term(), integer()) :: true
  def put(peer_key, public_key, now_ms) when is_integer(now_ms) do
    :ets.insert(@table, {peer_key, public_key, now_ms})
  end

  @doc """
  Retrieve and delete the public key for the given peer.
  Returns `{:ok, public_key}` or `:miss`. Expired entries return `:miss`.
  """
  @spec pop(term()) :: {:ok, term()} | :miss
  def pop(:unknown), do: :miss

  def pop(peer_key) do
    pop(peer_key, System.monotonic_time(:millisecond))
  end

  @doc """
  Retrieve and delete the public key for the given peer using `now_ms` to
  evaluate TTL. Expired entries return `:miss`. Legacy two-tuple entries
  without a timestamp are accepted for compatibility during rollout.
  """
  @spec pop(term(), integer()) :: {:ok, term()} | :miss
  def pop(:unknown, _now_ms), do: :miss

  def pop(peer_key, now_ms) when is_integer(now_ms) do
    case :ets.take(@table, peer_key) do
      [{^peer_key, public_key, inserted_at_ms}] ->
        if now_ms - inserted_at_ms <= @ttl_ms do
          {:ok, public_key}
        else
          :miss
        end

      [{^peer_key, public_key}] ->
        # Legacy entry without timestamp — accept for compatibility.
        {:ok, public_key}

      [] ->
        :miss
    end
  end

  @doc """
  Delete stash entries older than `ttl_ms`. Returns the number of entries
  removed. Entries without a timestamp (legacy two-tuple shape) are not
  swept here; they will be consumed by the next `pop/2` call site.
  """
  @spec sweep(integer(), integer()) :: non_neg_integer()
  def sweep(now_ms \\ System.monotonic_time(:millisecond), ttl_ms \\ @ttl_ms)
      when is_integer(now_ms) and is_integer(ttl_ms) do
    cutoff = now_ms - ttl_ms

    match_spec = [
      {{:"$1", :"$2", :"$3"}, [{:<, :"$3", cutoff}], [true]}
    ]

    :ets.select_delete(@table, match_spec)
  end
end
