# Quick Task 260422-mpz: SSH Connection Rate Limiting — Research

**Researched:** 2026-04-22
**Domain:** Elixir Hammer 6.x rate limiting + Erlang OTP `:ssh` daemon callbacks
**Confidence:** HIGH (all critical claims verified against OTP source and hexdocs)

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- Library: **Hammer** (`:hammer ~> 6.0`), ETS backend (`:hammer_backend_ets`).
- Enforcement point: `connectfun` callback in `Supervisor.daemon_opts/1`.
- Rate limit: 10 connections per 60 seconds per IP, per-exact-IP.
- Module: `Foglet.SSH.RateLimiter` exposing `allow?(ip :: term()) :: boolean()`.
- Do NOT use raw ETS for the rate limiter itself.
- Do NOT add rate limiting inside `KeyCB.is_auth_key/3` or `CLIHandler.handle_msg`.
- `@rate_limit_max 10`, `@rate_limit_window_ms 60_000`.

### Claude's Discretion
- Exact Hammer supervisor tree integration (SSH.Supervisor vs. Application).
- Format of the rate-limit key.
- Test strategy details.

### Deferred Ideas (OUT OF SCOPE)
- None listed.
</user_constraints>

---

## CRITICAL ARCHITECTURAL FINDING: `connectfun` fires POST-auth, not at TCP accept

This is the most important finding in this research. The CONTEXT.md assumes `connectfun`
fires at raw TCP accept time. **It does not.**

### What the OTP source actually shows

`connectfun` is defined in `ssh_options.erl` as a 3-arity fun — `(User, Peer, Method)`.
It is called from `ssh_fsm_userauth_server.erl:191`:

```erlang
connected_fun(User, Method, #data{ssh_params = #ssh{peer = {_,Peer}}} = D) ->
    ?CALL_FUN(connectfun,D)(User, Peer, Method).
```

The `?CALL_FUN` macro (defined in `ssh_connection_handler.erl`) expands to:

```erlang
catch (?GET_OPT(Key, opts))
```

Two consequences:
1. **The return value is discarded** — `catch expr` returns the value, but `connected_fun/3`
   is called in a void context and nothing checks its result. Returning `false` does nothing.
2. **It fires after the full SSH handshake.** `connected_fun` is called from
   `connected_state/5`, which is called only when authentication succeeds (including the
   trivial `no_auth_needed: true` success path). By the time `connectfun` runs, the TCP
   connection, TCP session, and SSH key exchange are all complete.

[VERIFIED: `github.com/erlang/otp/blob/master/lib/ssh/src/ssh_fsm_userauth_server.erl` line 191]
[VERIFIED: `github.com/erlang/otp/blob/master/lib/ssh/src/ssh_connection_handler.erl` line 77 (CALL_FUN macro)]
[VERIFIED: `github.com/erlang/otp/blob/master/lib/ssh/src/ssh_options.erl` — return type `_`]

### What DOES fire at TCP accept time?

`ssh_acceptor.erl:acceptor_loop/6` is the only place TCP connections are gated. It checks
`max_sessions` (already used via `max_sessions: 500`) but has **no user-facing callback**
for custom per-peer logic. There is no `access_filter` or `tcpip_tunnel_in_ac` option.

[VERIFIED: `github.com/erlang/otp/blob/master/lib/ssh/src/ssh_acceptor.erl` — full acceptor_loop source]

### What connectfun IS useful for in this project

Even though `connectfun` fires post-auth and cannot drop connections, it still fires once
per successful connection, before any channel opens. For rate limiting purposes this means:

- With `no_auth_needed: true`, the SSH handshake completes very quickly (no round-trips for
  auth challenge). `connectfun` fires early enough to be a useful enforcement point.
- The correct enforcement action is to **close the connection from within `connectfun`** by
  calling `:ssh.close/1` or by refusing to open channels.

However, the cleanest and confirmed-possible approach is to enforce inside
`CLIHandler.handle_msg({:ssh_channel_up, ...})`, which already has the peer IP available via
`read_peer/1` and has precedent for connection gating (the existing `check_connection_limit`
pattern). This is where the code should land if the "drop connection" semantic is required.

**Recommendation for the planner:** Use `connectfun` for early logging/counting but enforce
rate limiting by closing the connection in `CLIHandler.handle_msg/2` (`:ssh_channel_up`
message), following the exact same pattern as `check_connection_limit/0`. Alternatively,
use `connectfun` with an explicit `:ssh.close/1` call — but verify this compiles given
that connection_ref is not available inside `connectfun` (only `peer` is passed).

---

## 1. Hammer 6.x API

### Primary function: `check_rate/3`

```elixir
Hammer.check_rate(id :: String.t(), scale_ms :: integer(), limit :: integer())
  :: {:allow, count :: integer()}
   | {:deny, limit :: integer()}
   | {:error, reason :: term()}
```

[VERIFIED: hexdocs.pm/hammer/6.2.0/Hammer.html]

- `id` — string bucket key, e.g. `"ssh:192.168.1.1"`
- `scale_ms` — sliding window in milliseconds
- `limit` — max hits allowed per window
- Returns `{:allow, count}` when the request is within limit, `{:deny, limit}` when exceeded.

The v5-to-v6 function name is **unchanged** — still `check_rate/3`. (v7 renamed it to
`hit/3` and changed the `{:deny, limit}` second element to `retry_after_ms`. Since the
locked dep is `~> 6.0`, use `check_rate/3`.)

[VERIFIED: hexdocs.pm/hammer/6.1.0/readme.html — v6 uses check_rate; hexdocs.pm/hammer/upgrade-v7.html confirms rename happened in v7]

### Supporting functions

```elixir
# Reset a key's bucket — useful in tests
Hammer.delete_buckets(id :: String.t()) :: {:ok, count :: integer()} | {:error, reason}

# Inspect without incrementing
Hammer.inspect_bucket(id, scale_ms, limit)
  :: {:ok, {count, count_remaining, ms_to_next_bucket, created_at, updated_at}}
   | {:error, reason}
```

[VERIFIED: hexdocs.pm/hammer/6.2.0/Hammer.html]

---

## 2. Hammer ETS Backend: Supervision

### How it starts

Hammer is an OTP application. When `:hammer` is in your deps, it starts automatically at
application boot. You do **not** need to add a child to any supervisor.

The ETS backend process (`Hammer.Backend.ETS`) is started by the Hammer application
supervisor. Configuration is via `config.exs`:

```elixir
# config/config.exs
config :hammer,
  backend: {Hammer.Backend.ETS,
            [expiry_ms: 60_000 * 60 * 4,        # 4-hour bucket expiry
             cleanup_interval_ms: 60_000 * 10]}  # clean up every 10 min
```

If no config is provided, Hammer defaults to ETS with sensible defaults anyway.

[VERIFIED: hexdocs.pm/hammer/6.2.0/tutorial.html]
[VERIFIED: hexdocs.pm/hammer/6.0.0/Hammer.Backend.ETS.html — child_spec provided but launched by Hammer app automatically]

### Implication for `Foglet.SSH.RateLimiter`

`Foglet.SSH.RateLimiter` does not need to start any process. It is a pure wrapper
module. Add `:hammer` to `mix.exs` deps and config, and `Hammer.check_rate/3` works
immediately in any process.

---

## 3. `connectfun` Exact Specification

| Property | Value |
|----------|-------|
| Option name | `:connectfun` |
| Arity | 3 |
| Signature | `fun(User :: charlist(), Peer :: {:inet.ip_address(), :inet.port_number()}, Method :: charlist()) -> _` |
| Return value | Ignored — discarded via `catch expr` |
| Fires when | After SSH authentication succeeds (post-handshake) |
| `no_auth_needed: true` | Still fires — `none` method immediately authorized |
| Can drop connection? | Not natively — return value is not checked |

[VERIFIED: erlang.org/doc/apps/ssh/ssh.html — option type signature]
[VERIFIED: github.com/erlang/otp/blob/master/lib/ssh/src/ssh_fsm_userauth_server.erl — call site]
[VERIFIED: github.com/erlang/otp/blob/master/lib/ssh/src/ssh_connection_handler.erl — CALL_FUN macro]

### `peer` argument format

The `Peer` argument in `connectfun` is `{inet:ip_address(), inet:port_number()}`:
- IPv4: `{{192, 168, 1, 1}, 54321}`
- IPv6: `{{0, 0, 0, 0, 0, 0, 0, 1}, 54321}`

This matches the existing `read_peer/1` pattern already in `CLIHandler`:

```elixir
defp read_peer(connection_ref) do
  case :ssh.connection_info(connection_ref, [:peer]) do
    [{:peer, {{ip, port}, _socket}}] -> {ip, port}
    [{:peer, {ip, port}}] when is_tuple(ip) and is_integer(port) -> {ip, port}
    _ -> :unknown
  end
end
```

The IP portion is an Erlang ip_address tuple — must be converted to a string key for Hammer.

[VERIFIED: github.com/erlang/otp/blob/master/lib/ssh/src/ssh_options.erl — connectfun type spec]
[CITED: erlang.org/doc/apps/ssh/ssh.html]

---

## 4. Rate Limit Key Format

**Recommendation:** Use a string key `"ssh:#{ip_string}"` where `ip_string` is derived via
`:inet.ntoa(ip_tuple) |> to_string()`.

Rationale:
- Hammer's `id` argument is typed as `String.t()` in the public API. [VERIFIED: hexdocs.pm/hammer/6.2.0/Hammer.html]
- Tuple keys would require serialization anyway for the ETS lookup.
- `:inet.ntoa({192,168,1,1})` returns `'192.168.1.1'` (charlist) — wrap with `to_string/1`.
- Namespacing with `"ssh:"` avoids collisions if Hammer is used elsewhere in the app.

```elixir
defp ip_key({ip_tuple, _port}) when is_tuple(ip_tuple) do
  "ssh:#{:inet.ntoa(ip_tuple) |> to_string()}"
end
defp ip_key(:unknown), do: "ssh:unknown"
```

Note: `"ssh:unknown"` as a fallback means all connections with unresolvable peers share
a single bucket. This is safe since `read_peer` returning `:unknown` should be rare.

---

## 5. Testing Strategy

### The problem with `check_connection_limit`-style tests

The existing `check_connection_limit` pattern uses raw ETS counters that can be reset
with `:ets.insert/2`. Hammer's ETS buckets are internal and not directly writable, but
Hammer provides `delete_buckets/1` for exactly this use case.

### Deterministic test pattern — no sleep needed

```elixir
# test/foglet_bbs/ssh/rate_limiter_test.exs
setup do
  # Reset the bucket for this test's IP before each test case
  Hammer.delete_buckets("ssh:127.0.0.1")
  :ok
end

test "allows connections under the limit" do
  for _ <- 1..10 do
    assert Foglet.SSH.RateLimiter.allow?({127, 0, 0, 1}) == true
  end
end

test "denies the 11th connection" do
  for _ <- 1..10 do
    Foglet.SSH.RateLimiter.allow?({127, 0, 0, 1})
  end
  assert Foglet.SSH.RateLimiter.allow?({127, 0, 0, 1}) == false
end

test "different IPs have independent buckets" do
  for _ <- 1..10 do
    Foglet.SSH.RateLimiter.allow?({127, 0, 0, 1})
  end
  # Different IP is not rate-limited
  assert Foglet.SSH.RateLimiter.allow?({10, 0, 0, 1}) == true
end
```

`Hammer.delete_buckets/1` resets the sliding window without touching the clock — fully
deterministic. No `Process.sleep/1` needed.

[VERIFIED: hexdocs.pm/hammer/6.2.0/Hammer.html — delete_buckets/1 documented]

### Caveat: Hammer application must be started in test env

Since `:hammer` is a runtime dependency, it will be started by `mix test` automatically
as part of the application supervision tree. No `start_supervised!/1` call needed for
Hammer itself.

---

## 6. `mix.exs` Dep Addition

```elixir
{:hammer, "~> 6.0"},
```

No additional backend package needed — `:hammer_backend_ets` is bundled with `:hammer`
in v6. (In v7 it was split out, but v6 bundles it.)

[VERIFIED: hexdocs.pm/hammer/6.1.0/readme.html — v6 ETS backend is built-in]

---

## 7. Module Skeleton

```elixir
defmodule Foglet.SSH.RateLimiter do
  @moduledoc """
  Per-IP SSH connection rate limiter backed by Hammer (ETS).

  Enforces @rate_limit_max connections per @rate_limit_window_ms per source IP.
  Called from Foglet.SSH.Supervisor connectfun (or CLIHandler ssh_channel_up).
  """

  @rate_limit_max 10
  @rate_limit_window_ms 60_000

  @spec allow?(peer :: {:inet.ip_address(), :inet.port_number()} | :unknown) :: boolean()
  def allow?(peer) do
    key = ip_key(peer)
    case Hammer.check_rate(key, @rate_limit_window_ms, @rate_limit_max) do
      {:allow, _count} -> true
      {:deny, _limit} -> false
      {:error, _reason} -> true  # fail-open on backend error
    end
  end

  defp ip_key({ip_tuple, _port}) when is_tuple(ip_tuple) do
    "ssh:#{:inet.ntoa(ip_tuple) |> to_string()}"
  end
  defp ip_key(:unknown), do: "ssh:unknown"
end
```

---

## 8. connectfun wiring in `daemon_opts/1`

Given that `connectfun` cannot drop connections, the CONTEXT.md assumption that
`connectfun` is the enforcement point requires clarification:

**Option A — Wire in `daemon_opts/1` via `connectfun` + explicit close (UNCERTAIN)**

The peer IP is available, but `connectfun` does not receive a connection handle.
To close the connection from `connectfun` you would need another mechanism. This
is not straightforward from the OTP API.

**Option B — Wire in `CLIHandler.handle_msg({:ssh_channel_up, ...})` (RECOMMENDED)**

This follows the exact existing pattern (`check_connection_limit`), has access to
`connection_ref` and `peer`, and can call `:ssh_connection.close/2` to drop the channel.
This approach is already proven to work in the codebase.

```elixir
# In handle_msg({:ssh_channel_up, channel_id, connection_ref}, state):
peer = read_peer(connection_ref)
case {check_connection_limit(), Foglet.SSH.RateLimiter.allow?(peer)} do
  {:ok, true} ->
    # proceed
  {_, false} ->
    _ = :ssh_connection.send(connection_ref, channel_id,
          "Rate limit exceeded. Try again later.\r\n")
    _ = :ssh_connection.close(connection_ref, channel_id)
    {:ok, %__MODULE__{over_limit: true, channel_id: channel_id,
                      connection_ref: connection_ref}}
  {:over_limit, _} ->
    # existing over_limit path unchanged
end
```

**Option C — Add `connectfun` for logging only, enforce in CLIHandler (BEST)**

Add `connectfun` to `daemon_opts/1` purely to log the connection event (consistent
with its documented purpose). Enforce rate limiting in `CLIHandler`. Clean separation
of concerns.

---

## Common Pitfalls

### Pitfall 1: Assuming `connectfun` return value is checked
**What goes wrong:** Writing `connectfun: fn _, _, _ -> false end` to drop connections —
does nothing. The return value is discarded by the `?CALL_FUN` macro.
**Prevention:** Enforce by closing the channel or connection reference explicitly.
**Warning signs:** Rate limited clients still connect successfully.

### Pitfall 2: Using v7 API with v6 dep
**What goes wrong:** Using `hit/3` (v7) instead of `check_rate/3` (v6) — compile error.
**Prevention:** The locked dep is `~> 6.0`. Use `check_rate/3`. The v7 upgrade guide
documents the rename.

### Pitfall 3: Not resetting Hammer buckets between tests
**What goes wrong:** Test ordering matters — a test that hammers past the limit affects
subsequent tests.
**Prevention:** Call `Hammer.delete_buckets("ssh:#{ip}")` in `setup` for each test.

### Pitfall 4: Forgetting the `{:error, reason}` return from `check_rate`
**What goes wrong:** Pattern match on only `{:allow, _}` and `{:deny, _}` crashes if
Hammer's ETS table is unavailable.
**Prevention:** Match all three clauses. Fail-open on `{:error, _}` is the safe default
for an SSH daemon (connectivity over strictness).

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | Fail-open on `{:error, _}` is the right policy for SSH rate limiter | Module Skeleton | Could allow traffic during backend failure; operator may prefer fail-closed |

---

## Sources

### Primary (HIGH confidence)
- `github.com/erlang/otp/blob/master/lib/ssh/src/ssh_fsm_userauth_server.erl` — `connectfun` call site, confirmed `connected_fun/3` wrapper, post-auth
- `github.com/erlang/otp/blob/master/lib/ssh/src/ssh_connection_handler.erl` — `CALL_FUN` macro definition (return discarded)
- `github.com/erlang/otp/blob/master/lib/ssh/src/ssh_options.erl` — `connectfun` option schema, return type `_`
- `github.com/erlang/otp/blob/master/lib/ssh/src/ssh_acceptor.erl` — TCP accept loop, no user-facing callback
- `github.com/erlang/otp/blob/master/lib/ssh/src/ssh_auth.erl` — `no_auth_needed: true` auth path
- `hexdocs.pm/hammer/6.2.0/Hammer.html` — `check_rate/3`, `delete_buckets/1`, `inspect_bucket/3` signatures
- `hexdocs.pm/hammer/6.2.0/tutorial.html` — ETS backend config, supervision
- `hexdocs.pm/hammer/6.0.0/Hammer.Backend.ETS.html` — backend options
- `hexdocs.pm/hammer/upgrade-v7.html` — v6→v7 diff confirming `check_rate` was renamed to `hit` in v7

### Secondary (MEDIUM confidence)
- `erlang.org/doc/apps/ssh/ssh.html` — `connectfun` option public documentation (type `fun(string(), {ip, port}, string()) -> _`)
