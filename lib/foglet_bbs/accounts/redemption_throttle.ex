defmodule Foglet.Accounts.RedemptionThrottle do
  @moduledoc """
  In-memory redemption throttle for short account codes.

  FOG-572 deliberately keeps this boundary in the Accounts runtime layer rather
  than the SSH/TUI layer so every reset-token and invite-code redemption path
  shares the same abuse control. The process owns an ETS table and is supervised
  under `FogletBbs.Supervisor`; if it crashes the table is rebuilt empty, which
  fails open for availability and records a restart via normal OTP supervision.

  Keys are a combination of:

    * a per-kind global bucket, which limits broad online guessing; and
    * a per-code fingerprint bucket, which limits repeated probes of the same
      code without storing or logging the raw code/token.

  The raw code is never stored. The table stores only SHA-256 fingerprints of a
  scoped value and short rolling-window counters.
  """

  use GenServer

  require Logger

  @table :foglet_accounts_redemption_throttle
  @window_ms :timer.minutes(15)
  @per_code_limit 5
  @global_limit 100

  @type kind :: :reset_password | :invite_code
  @type outcome :: :throttled | :succeeded

  @doc false
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Records a redemption attempt and returns whether it may continue.

  `raw_code` is accepted only long enough to derive an opaque fingerprint. It is
  not stored, emitted in logs, or returned.
  """
  @spec check(kind(), String.t()) :: :ok | {:error, :throttled}
  def check(kind, raw_code)
      when kind in [:reset_password, :invite_code] and is_binary(raw_code) do
    ensure_table!()

    now_ms = System.monotonic_time(:millisecond)
    code_fingerprint = fingerprint(kind, raw_code)

    global = increment({kind, :global}, now_ms)
    per_code = increment({kind, :code, code_fingerprint}, now_ms)

    if global <= @global_limit and per_code <= @per_code_limit do
      :ok
    else
      audit(kind, :throttled, code_fingerprint, global, per_code)
      {:error, :throttled}
    end
  end

  @doc "Records a successful redemption and clears the per-code bucket."
  @spec succeeded(kind(), String.t()) :: :ok
  def succeeded(kind, raw_code)
      when kind in [:reset_password, :invite_code] and is_binary(raw_code) do
    ensure_table!()
    code_fingerprint = fingerprint(kind, raw_code)
    :ets.delete(@table, {kind, :code, code_fingerprint})
    audit(kind, :succeeded, code_fingerprint, nil, nil)
    :ok
  end

  @doc false
  @spec reset_for_tests() :: :ok
  def reset_for_tests do
    ensure_table!()
    :ets.delete_all_objects(@table)
    :ok
  end

  @impl true
  def init(_opts) do
    create_table()
    {:ok, %{table: @table}}
  end

  defp increment(key, now_ms) do
    case :ets.lookup(@table, key) do
      [{^key, count, window_started_ms}] when now_ms - window_started_ms < @window_ms ->
        new_count = count + 1
        :ets.insert(@table, {key, new_count, window_started_ms})
        new_count

      _expired_or_missing ->
        :ets.insert(@table, {key, 1, now_ms})
        1
    end
  end

  defp ensure_table! do
    case :ets.whereis(@table) do
      :undefined -> create_table()
      _tid -> :ok
    end
  end

  defp create_table do
    case :ets.whereis(@table) do
      :undefined ->
        _ = :ets.new(@table, [:set, :named_table, :public, read_concurrency: true])
        :ok

      _tid ->
        :ok
    end
  end

  defp fingerprint(kind, raw_code) do
    :crypto.hash(:sha256, "foglet:redemption:#{kind}:#{raw_code}")
    |> Base.encode16(case: :lower)
    |> binary_part(0, 16)
  end

  defp audit(kind, :throttled, code_fingerprint, global_count, per_code_count) do
    Logger.warning(
      "account redemption throttled kind=#{kind} code_fingerprint=#{code_fingerprint} " <>
        "global_attempts=#{global_count} code_attempts=#{per_code_count}"
    )
  end

  defp audit(kind, :succeeded, code_fingerprint, _global_count, _per_code_count) do
    Logger.info("account redemption succeeded kind=#{kind} code_fingerprint=#{code_fingerprint}")
  end
end
