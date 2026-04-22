# Quick Task 260422-mpz: SSH connection rate limiting - Context

**Gathered:** 2026-04-22
**Status:** Ready for planning

<domain>
## Task Boundary

Add per-IP SSH connection rate limiting: a new module, integration into the SSH
daemon, and tests that exercise the limit.

</domain>

<decisions>
## Implementation Decisions

### Library
- Use **Hammer** (`:hammer` dep, `~> 7.3.0`) — battle-tested token bucket backed by ETS.
- Do NOT use raw ETS counters for the rate limiter itself (Hammer handles the
  sliding window and edge cases).

### Enforcement point
- **`CLIHandler.handle_msg({:ssh_channel_up, ...})`** — alongside the existing
  `check_connection_limit/0`. Close the channel with `:ssh_connection.close/2`
  and send a rejection message on deny.
- `connectfun` is NOT viable: OTP's implementation discards the return value
  (it is a logging hook, not a gate). Verified against OTP source.
- Do NOT add rate limiting inside `KeyCB.is_auth_key/3` (only called for
  pubkey-offering clients; gaps with `no_auth_needed: true`).

### Rate limit parameters
- **10 connections per 60 seconds per IP** (per-exact-IP, not per-subnet).
- Module attributes: `@rate_limit_max 10`, `@rate_limit_window_ms 60_000`.

### New module
- `Foglet.SSH.RateLimiter` — thin wrapper over Hammer; exposes a single
  `allow?(ip :: term()) :: boolean()` function.
- Hammer backend: `:hammer_backend_ets` (no extra infra required, keeps
  everything in-process).

### Claude's Discretion
- Exact Hammer supervisor tree integration (start Hammer backends as part of
  `Foglet.SSH.Supervisor` or Application supervision is left to Claude).
- Format of the rate-limit key passed to Hammer (e.g. `"ssh:#{ip_string}"`).
- Test strategy details (sync vs. async, exact assertion style).

</decisions>

<specifics>
## Specific Ideas

- `CLIHandler` reads peer via `:ssh.connection_info(connection_ref, [:peer])` —
  already normalized to `{ip_tuple, port}`. Pass the IP tuple to `RateLimiter`.
- Hammer v7 API: `Hammer.hit(key, scale_ms, limit)` → `{:allow, count} | {:deny, limit} | {:error, reason}`.
- Testing: use `Hammer.delete_buckets(key)` in `setup` to reset state between tests — no `Process.sleep` needed.

</specifics>

<canonical_refs>
## Canonical References

- `lib/foglet_bbs/ssh/cli_handler.ex` — enforcement point; `check_connection_limit/0` is the pattern to follow.
- `lib/foglet_bbs/ssh/supervisor.ex` — NOT modified for rate limiting.
- `lib/foglet_bbs/ssh/key_cb.ex` — NOT modified.
- Hammer v7 docs: https://hexdocs.pm/hammer/

</canonical_refs>
