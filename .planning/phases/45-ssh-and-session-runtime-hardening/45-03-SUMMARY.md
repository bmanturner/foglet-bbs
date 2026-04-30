---
phase: 45-ssh-and-session-runtime-hardening
plan: 45-03
subsystem: ssh
tags: [ssh, cli_handler, lifecycle, ets, connection_counter, rate_limiter, idempotent_cleanup]

requires:
  - phase: 45-ssh-and-session-runtime-hardening
    provides: [pubkey_stash_ttl, promotion_audit_metadata, ssh_peer_in_session_context]
provides:
  - Single cleanup helper in Foglet.SSH.CLIHandler covering alt-screen leave, lifecycle stop, session stop, optional channel close, and counter decrement
  - Idempotent cleanup via cleanup_done? + counter_counted? state flags
  - Proven balance of the global SSH connection counter across normal close, EOF-to-close, lifecycle exit, over-limit reject, rate-limit reject, crash-during-init, and idempotent re-cleanup
  - Test-only entry point channel_up_for_test/4 plus assert_counter! helper enabling deterministic unit coverage of rejection branches
affects: [phase-46+, ssh runtime hardening, future cleanup refactors]

tech-stack:
  added: []
  patterns:
    - "State-flag idempotence: cleanup_done? short-circuits the helper; counter_counted? gates exactly-once decrement"
    - "Test-only public entry point (@doc false def channel_up_for_test/4) for branches that would otherwise require real SSH connection_info"
    - "safe_ssh_send/safe_ssh_close wrappers tolerant of nil refs/channels"

key-files:
  created: []
  modified:
    - lib/foglet_bbs/ssh/cli_handler.ex
    - test/foglet_bbs/ssh/cli_handler_test.exs

key-decisions:
  - "Used state-flag idempotence (cleanup_done?/counter_counted?) rather than helper-options or callback-specific wrappers — chosen for grep-friendliness and minimal contract surface"
  - "Extracted do_channel_up/4 + channel_up_for_test/4 instead of mocking :ssh.connection_info/2 — keeps production logic untouched and unit tests deterministic"
  - "Only the lifecycle-EXIT path passes close_channel: true to cleanup/2; :closed and terminate are already triggered by a closed channel so they skip the active close"

patterns-established:
  - "SSH cleanup helper pattern: idempotent, single-helper delegation from every termination-sensitive callback"
  - "Counter ownership flag: counter_counted? on the channel state tracks whether a decrement is owed"
  - "Direct ETS counter assertions in tests via assert_counter! helper rather than indirect probing"

requirements-completed: [SSH-03, SSH-04]

duration: 9min
completed: 2026-04-30
---

# Phase 45 Plan 45-03: Unified CLIHandler Cleanup And Counter Balance Summary

**Centralized SSH channel cleanup behind a single idempotent helper and proved the global connection counter stays balanced across every roadmap-listed lifecycle and rejection path.**

## Performance

- **Duration:** ~9 min
- **Started:** 2026-04-30T00:58:46Z
- **Completed:** 2026-04-30T01:07:49Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments
- Added `cleanup_done?` and `counter_counted?` flags to the `Foglet.SSH.CLIHandler` struct
- Introduced one private `cleanup/2` helper owning alt-screen leave, lifecycle stop, session stop, optional channel close, and counter decrement (gated by `counter_counted?`)
- Routed lifecycle EXIT, `:closed`, and `terminate/2` through `cleanup/2` so callback ordering does not double-decrement or leak counter state
- Made over-limit and rate-limit reject paths fully self-contained: they set `cleanup_done?: true` / `counter_counted?: false` so any later cleanup delivery is a no-op
- Extracted `do_channel_up/4` and a `@doc false` `channel_up_for_test/4` entry point so unit tests can drive the rejection branches deterministically without a real SSH connection
- Added `assert_counter!` helper plus 8 new tests covering normal close, EOF-to-close, lifecycle EXIT, over-limit reject, rate-limit reject, crash-during-init, and two idempotence variants

## Task Commits

1. **Task 45-03-01: centralize SSH cleanup with idempotent helper** — `596d3251` (refactor)
2. **Task 45-03-02: prove SSH connection counter balance across lifecycle paths** — `1601328c` (test)

## Files Created/Modified
- `lib/foglet_bbs/ssh/cli_handler.ex` — Added cleanup state flags, `cleanup/2` helper, `do_channel_up/4` extraction, `channel_up_for_test/4` test entry point, `safe_ssh_send`/`safe_ssh_close` nil-tolerant wrappers; rewired lifecycle EXIT, `:closed`, and `terminate/2` to delegate to `cleanup/2`
- `test/foglet_bbs/ssh/cli_handler_test.exs` — Added `connection counter balance (SSH-04)` describe block with 8 lifecycle/rejection-path tests, `assert_counter!` helper; updated existing `:closed` and lifecycle-EXIT tests to thread the new `counter_counted?` flag and assert `cleanup_done?` on the returned state

## Decisions Made
- **State flags over option-passing or wrapper functions for idempotence.** The plan explicitly left this open ("downstream agents may choose"). Flags are grep-friendly (`rg counter_counted?` shows every site that owes a decrement) and keep the cleanup contract on the struct rather than spread across callers.
- **`safe_ssh_send`/`safe_ssh_close` wrappers** were added to keep the rejection branches safe to call from unit tests with `connection_ref: nil`. Production behavior is unchanged for real refs; the wrappers return `:ok` for nil and rescue/catch for any unexpected error.
- **`:closed` and `terminate/2` pass `close_channel: false`** — both are already triggered by a closed channel, so re-closing is wasteful. Only lifecycle EXIT actively closes the channel because the channel is still open at that point and the client needs the alt-screen leave to reach it before teardown.

## Deviations from Plan

None - plan executed exactly as written. Two narrow extensions stayed within the plan's stated discretion:

1. The plan said "uses a test-supported helper if needed" for the over-limit/rate-limit drivers. We added `channel_up_for_test/4` (`@doc false`) plus `safe_ssh_send`/`safe_ssh_close` wrappers — the minimum production-side surface needed to make the rejection branches deterministically testable.
2. The plan listed seven required tests; we added one additional "rejected state stays at start across :closed and terminate" test to make the rejected-state idempotence invariant explicit, since over-limit/rate-limit returned states are now reachable to subsequent callbacks.

## Issues Encountered

- The two `def handle_msg/2` clauses (`:ssh_channel_up` and `:EXIT`) had `do_channel_up/4` and `channel_up_for_test/4` defined between them, triggering Elixir's `clauses with the same name and arity should be grouped together` warning. Resolved by moving both helpers below `terminate/2`.
- The shared deps cache between worktrees was missing; symlinked `deps -> /Users/brendan.turner/Dev/personal/foglet_bbs/deps` so `mix compile` could resolve dependencies. `_build` is intentionally not symlinked to avoid races.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- Cleanup is centralized through one helper, giving subsequent SSH refactors a single point to extend.
- Counter is provably balanced across every spec-listed path. Future cleanup additions only need to honor `counter_counted?` to keep the invariant.
- `channel_up_for_test/4` is `@doc false` and intended for tests; if production callers ever need a non-`:ssh.connection_info` peer (for example, a fixed peer in a non-SSH transport), the same internal `do_channel_up/4` can be reused.

## Self-Check: PASSED

- `lib/foglet_bbs/ssh/cli_handler.ex` — FOUND
- `test/foglet_bbs/ssh/cli_handler_test.exs` — FOUND
- Commit `596d3251` — FOUND in `git log`
- Commit `1601328c` — FOUND in `git log`
- `rtk mix test test/foglet_bbs/ssh/cli_handler_test.exs` exits 0 (24 tests, 0 failures)
- `rtk mix test test/foglet_bbs/ssh` exits 0 (50 tests, 0 failures)
- `rtk mix format --check-formatted` — clean
- `rtk mix credo --strict` on the touched files — clean (59 mods/funs, no issues)

---
*Phase: 45-ssh-and-session-runtime-hardening*
*Completed: 2026-04-30*
