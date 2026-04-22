---
phase: quick-260422-mpz
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - mix.exs
  - config/config.exs
  - lib/foglet_bbs/ssh/rate_limiter.ex
  - lib/foglet_bbs/ssh/cli_handler.ex
  - test/foglet_bbs/ssh/rate_limiter_test.exs
autonomous: true
requirements:
  - SSH connection rate limiting per IP using Hammer v7

must_haves:
  truths:
    - "An IP making 10 SSH channel connections within 60 s is allowed for each"
    - "The 11th SSH channel connection from that IP within 60 s is rejected with a message and the channel is closed"
    - "A second IP is not affected by a different IP hitting the limit"
    - "Foglet.SSH.RateLimiter.allow?/1 returns true when under limit and false when over"
    - "Rate limiting is enforced in CLIHandler.handle_msg({:ssh_channel_up, ...}) after the connection limit passes"
  artifacts:
    - path: "lib/foglet_bbs/ssh/rate_limiter.ex"
      provides: "Hammer v7 wrapper exposing allow?/1"
      exports: ["allow?/1"]
    - path: "test/foglet_bbs/ssh/rate_limiter_test.exs"
      provides: "Unit tests for RateLimiter, bucket reset via Hammer.delete_buckets/1"
    - path: "mix.exs"
      provides: "{:hammer, \"~> 7.3.0\"} dep"
      contains: "hammer"
    - path: "config/config.exs"
      provides: "Hammer ETS backend config"
      contains: "config :hammer"
  key_links:
    - from: "lib/foglet_bbs/ssh/cli_handler.ex"
      to: "lib/foglet_bbs/ssh/rate_limiter.ex"
      via: "Foglet.SSH.RateLimiter.allow?(peer) called in handle_msg ssh_channel_up"
      pattern: "RateLimiter\\.allow\\?"
    - from: "lib/foglet_bbs/ssh/rate_limiter.ex"
      to: "Hammer"
      via: "Hammer.hit/3 called with \"ssh:<ip>\" key"
      pattern: "Hammer\\.hit"
---

<objective>
Add per-IP SSH connection rate limiting: 10 connections per 60 seconds per source IP.
A new `Foglet.SSH.RateLimiter` module wraps Hammer v7, and `CLIHandler` enforces the
limit at `{:ssh_channel_up, ...}` alongside the existing connection-count gate.

Purpose: Prevent a single IP from exhausting available connections or brute-forcing
the daemon with rapid connection attempts.

Output:
- `lib/foglet_bbs/ssh/rate_limiter.ex` — Hammer v7 wrapper
- `lib/foglet_bbs/ssh/cli_handler.ex` — rate limit enforcement in ssh_channel_up
- `test/foglet_bbs/ssh/rate_limiter_test.exs` — unit tests using Hammer.delete_buckets/1
- `mix.exs` — `:hammer` dep added
- `config/config.exs` — Hammer ETS backend config added
</objective>

<execution_context>
@/Users/brendan.turner/Dev/personal/foglet_bbs/.claude/get-shit-done/workflows/execute-plan.md
@/Users/brendan.turner/Dev/personal/foglet_bbs/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@/Users/brendan.turner/Dev/personal/foglet_bbs/CLAUDE.md
@/Users/brendan.turner/Dev/personal/foglet_bbs/lib/foglet_bbs/ssh/cli_handler.ex
@/Users/brendan.turner/Dev/personal/foglet_bbs/mix.exs
@/Users/brendan.turner/Dev/personal/foglet_bbs/config/config.exs

<interfaces>
<!-- Key contracts the executor needs. Extracted from codebase. -->

From lib/foglet_bbs/ssh/cli_handler.ex — the enforcement point:

```elixir
# Existing ssh_channel_up handler (lines 77-119):
def handle_msg({:ssh_channel_up, channel_id, connection_ref}, %__MODULE__{} = state) do
  peer = read_peer(connection_ref)   # returns {ip_tuple, port} | :unknown

  case check_connection_limit() do
    :over_limit ->
      _ = :ssh_connection.send(connection_ref, channel_id,
            "Connection limit reached. Try again later.\r\n")
      _ = :ssh_connection.close(connection_ref, channel_id)
      {:ok, %__MODULE__{over_limit: true, channel_id: channel_id, connection_ref: connection_ref}}

    :ok ->
      increment_connection_count()
      # ... normal path
  end
end

# read_peer/1 return values (lines 267-274):
#   {ip_tuple, port}   — e.g. {{127,0,0,1}, 54321}
#   :unknown           — if :ssh.connection_info raised

# closed handler (lines 207-220): guards decrement with `unless state.over_limit`
# The rate-limited path must also set over_limit: true so decrement is skipped.
```

Hammer v7 API (locked per D-01 / CONTEXT.md):
```elixir
# hit/3 — increment and check
Hammer.hit(key :: String.t(), scale_ms :: integer(), limit :: integer())
  :: {:allow, count :: integer()}
   | {:deny, retry_after_ms :: integer()}
   | {:error, reason :: term()}

# Reset a key's bucket — deterministic in tests (no Process.sleep needed)
Hammer.delete_buckets(key :: String.t()) :: {:ok, integer()} | {:error, term()}
```
</interfaces>
</context>

<tasks>

<task type="auto" tdd="true">
  <name>Task 1: Add Hammer dep, config, and RateLimiter module</name>
  <files>mix.exs, config/config.exs, lib/foglet_bbs/ssh/rate_limiter.ex, test/foglet_bbs/ssh/rate_limiter_test.exs</files>
  <behavior>
    - allow?({127,0,0,1}) returns true for the first 10 calls (same IP, within 60 s window)
    - allow?({127,0,0,1}) returns false on the 11th call
    - allow?({10,0,0,1}) returns true independently when {127,0,0,1} has hit its limit
    - allow?(:unknown) returns true (fail-open for unresolvable peers; all :unknown connections share one bucket)
  </behavior>
  <action>
1. **mix.exs** — add `{:hammer, "~> 7.3.0"}` to the deps list (per D-01). No additional backend package needed; `:hammer_backend_ets` is bundled.

2. **config/config.exs** — add Hammer ETS backend config before the `import_config` line (per D-05):

   ```elixir
   config :hammer,
     backend: {Hammer.Backend.ETS,
               [expiry_ms: 60_000 * 60 * 4,
                cleanup_interval_ms: 60_000 * 10]}
   ```

3. **lib/foglet_bbs/ssh/rate_limiter.ex** — create `Foglet.SSH.RateLimiter` (per D-04):

   ```elixir
   defmodule Foglet.SSH.RateLimiter do
     @moduledoc """
     Per-IP SSH connection rate limiter backed by Hammer v7 (ETS).
     Enforces @rate_limit_max connections per @rate_limit_window_ms per source IP.
     """

     @rate_limit_max 10
     @rate_limit_window_ms 60_000

     @spec allow?(peer :: {:inet.ip_address(), :inet.port_number()} | :unknown) :: boolean()
     def allow?(peer) do
       key = ip_key(peer)
       case Hammer.hit(key, @rate_limit_window_ms, @rate_limit_max) do
         {:allow, _count} -> true
         {:deny, _retry_after_ms} -> false
         {:error, _reason} -> true
       end
     end

     @spec ip_key(peer :: {:inet.ip_address(), :inet.port_number()} | :unknown) :: String.t()
     defp ip_key({ip_tuple, _port}) when is_tuple(ip_tuple) do
       "ssh:" <> (ip_tuple |> :inet.ntoa() |> to_string())
     end
     defp ip_key(:unknown), do: "ssh:unknown"
   end
   ```

4. **test/foglet_bbs/ssh/rate_limiter_test.exs** — write tests FIRST, then verify module makes them pass:

   ```elixir
   defmodule Foglet.SSH.RateLimiterTest do
     use ExUnit.Case, async: false  # Hammer ETS is global state

     alias Foglet.SSH.RateLimiter

     @test_ip_1 {127, 0, 0, 1}
     @test_ip_2 {10, 0, 0, 1}

     setup do
       Hammer.delete_buckets("ssh:127.0.0.1")
       Hammer.delete_buckets("ssh:10.0.0.1")
       Hammer.delete_buckets("ssh:unknown")
       :ok
     end

     test "allows connections under the limit" do
       for _ <- 1..10 do
         assert RateLimiter.allow?({@test_ip_1, 54_321}) == true
       end
     end

     test "denies the 11th connection from the same IP" do
       for _ <- 1..10 do
         RateLimiter.allow?({@test_ip_1, 54_321})
       end
       assert RateLimiter.allow?({@test_ip_1, 54_321}) == false
     end

     test "different IPs have independent buckets" do
       for _ <- 1..10 do
         RateLimiter.allow?({@test_ip_1, 54_321})
       end
       assert RateLimiter.allow?({@test_ip_2, 54_322}) == true
     end

     test "allow? with :unknown peer does not crash and fails open" do
       assert RateLimiter.allow?(:unknown) == true
     end
   end
   ```

   Run `mix test test/foglet_bbs/ssh/rate_limiter_test.exs` and confirm all tests pass.
  </action>
  <verify>
    <automated>mix test test/foglet_bbs/ssh/rate_limiter_test.exs</automated>
  </verify>
  <done>All 4 RateLimiter tests pass. `mix deps.get` succeeds with hammer 7.3.x resolved. RateLimiter module compiles without warnings.</done>
</task>

<task type="auto" tdd="true">
  <name>Task 2: Enforce rate limit in CLIHandler ssh_channel_up</name>
  <files>lib/foglet_bbs/ssh/cli_handler.ex</files>
  <behavior>
    - When rate limit allows AND connection limit allows: proceed to normal connection path (unchanged)
    - When rate limit denies: send "Rate limit exceeded. Try again later.\r\n", close channel, set over_limit: true (so closed handler skips decrement)
    - When connection limit denies: existing behavior unchanged (send "Connection limit reached...", close)
    - Ordering: check connection limit first; only call RateLimiter.allow? when connection limit passes (avoids counting rate-limited connections toward the connection counter)
  </behavior>
  <action>
Modify `handle_msg({:ssh_channel_up, channel_id, connection_ref}, state)` in
`lib/foglet_bbs/ssh/cli_handler.ex` (per D-02).

The existing `peer = read_peer(connection_ref)` call is already at the top of the
function (line 78). The modification nests the rate limit check INSIDE the `:ok`
branch of `check_connection_limit/0`, BEFORE `increment_connection_count/0`, so that
rate-limited connections are never counted against the global limit:

```elixir
def handle_msg({:ssh_channel_up, channel_id, connection_ref}, %__MODULE__{} = state) do
  peer = read_peer(connection_ref)

  case check_connection_limit() do
    :over_limit ->
      _ =
        :ssh_connection.send(
          connection_ref,
          channel_id,
          "Connection limit reached. Try again later.\r\n"
        )

      _ = :ssh_connection.close(connection_ref, channel_id)

      {:ok, %__MODULE__{
        over_limit: true,
        channel_id: channel_id,
        connection_ref: connection_ref
      }}

    :ok ->
      if Foglet.SSH.RateLimiter.allow?(peer) do
        increment_connection_count()
        pubkey_user = resolve_pubkey_user(peer)
        session_pid = start_session(pubkey_user)

        Logger.info(
          "[SSH.CLIHandler] Channel up — peer=#{inspect(peer)} " <>
            "user=#{inspect(pubkey_user && pubkey_user.handle)} " <>
            "session_pid=#{inspect(session_pid)}"
        )

        {:ok, %__MODULE__{
          state
          | channel_id: channel_id,
            connection_ref: connection_ref,
            peer: peer,
            session_pid: session_pid
        }}
      else
        _ =
          :ssh_connection.send(
            connection_ref,
            channel_id,
            "Rate limit exceeded. Try again later.\r\n"
          )

        _ = :ssh_connection.close(connection_ref, channel_id)

        {:ok, %__MODULE__{
          over_limit: true,
          channel_id: channel_id,
          connection_ref: connection_ref
        }}
      end
  end
end
```

Important: the rate-limited branch sets `over_limit: true` — this ensures the
existing `handle_ssh_msg({:ssh_cm, _, {:closed, _}}, state)` guard
(`unless state.over_limit do decrement_connection_count() end`) correctly skips
decrement for rate-limited connections (which never incremented).

After modifying cli_handler.ex, run `mix precommit` and fix any warnings/errors.
Dialyzer may flag the new `if` returning either `{:ok, state}` path — if so, keep
the `case/2` form consistent with the existing style.
  </action>
  <verify>
    <automated>mix compile --warnings-as-errors</automated>
  </verify>
  <done>
- `mix compile --warnings-as-errors` exits 0.
- `mix credo --strict` exits 0.
- `mix test` (full suite) exits 0 — no regressions.
- `mix precommit` exits 0 with no warnings or errors.
  </done>
</task>

</tasks>

<threat_model>
## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| public internet → SSH daemon | Unauthenticated TCP connections from any IP arrive here |
| SSH daemon → CLIHandler | Channel-up event fires once per connection; enforcement point |

## STRIDE Threat Register

| Threat ID | Category | Component | Disposition | Mitigation Plan |
|-----------|----------|-----------|-------------|-----------------|
| T-mpz-01 | Denial of Service | SSH daemon | mitigate | Per-IP rate limit (10 req/60 s) via Hammer ETS; connection limit (500) already in place |
| T-mpz-02 | Denial of Service | Hammer ETS backend | accept | Hammer fails open on {:error, _} — availability over strictness; backend failure is logged implicitly via error tuple |
| T-mpz-03 | Spoofing | ip_key derivation | accept | Rate limit key is derived from :ssh.connection_info peer tuple, which is the OS-reported remote IP — cannot be spoofed at the application layer (TCP source address is still spoofable at network layer, but that is a network-layer concern outside app scope) |
| T-mpz-04 | Elevation of Privilege | RateLimiter.allow? | accept | Returns boolean; no privilege data involved; fail-open on error maintains availability without granting elevated access |
</threat_model>

<verification>
After both tasks are complete:

1. Full test suite passes: `mix test`
2. Precommit clean: `mix precommit`
3. Hammer dep resolved: `mix deps.get` shows `hammer 7.3.x`
4. Config present: `config/config.exs` contains `config :hammer, backend: {Hammer.Backend.ETS, ...}`
5. RateLimiter module exists at `lib/foglet_bbs/ssh/rate_limiter.ex` and is `Foglet.SSH.RateLimiter`
6. CLIHandler ssh_channel_up handler contains `Foglet.SSH.RateLimiter.allow?(peer)` call
7. Rate-limited branch sets `over_limit: true` so the closed handler skips connection count decrement
</verification>

<success_criteria>
- `Foglet.SSH.RateLimiter.allow?/1` returns true for the 10th call and false for the 11th from the same IP
- CLIHandler closes the channel and sends a human-readable message when rate limited
- Rate-limited connections do not count against the global connection limit
- `mix precommit` exits 0 (compile, format, credo, sobelow, dialyzer all pass)
- All existing tests continue to pass
</success_criteria>

<output>
After completion, create `.planning/quick/260422-mpz-ssh-connection-rate-limiting-design-choi/260422-mpz-01-SUMMARY.md`
</output>
