---
phase: quick-260422-mpz
plan: "01"
subsystem: ssh
tags: [rate-limiting, hammer, ssh, security]
dependency_graph:
  requires: []
  provides: [ssh-rate-limiting]
  affects: [lib/foglet_bbs/ssh/cli_handler.ex, lib/foglet_bbs/ssh/supervisor.ex]
tech_stack:
  added: [hammer 7.3.0]
  patterns: [use Hammer backend :ets, supervised GenServer ETS table, TDD RED/GREEN]
key_files:
  created:
    - lib/foglet_bbs/ssh/rate_limiter.ex
    - test/foglet_bbs/ssh/rate_limiter_test.exs
  modified:
    - mix.exs
    - mix.lock
    - lib/foglet_bbs/ssh/supervisor.ex
    - lib/foglet_bbs/ssh/cli_handler.ex
decisions:
  - "Hammer v7 uses module-based API (use Hammer, backend: :ets) not global Hammer.hit/3"
  - "RateLimiter started as supervised child of SSH.Supervisor with clean_period: 10 min"
  - "Tests use start_supervised! + direct :ets.match_delete for deterministic bucket resets"
  - "Rate limit check nested inside :ok branch of check_connection_limit/0 to avoid counting toward global limit"
  - "Removed stale config :hammer (v6-style, no effect in v7 which reads opts from start_link)"
metrics:
  duration: "~25 minutes"
  completed: "2026-04-22"
  tasks_completed: 2
  files_changed: 6
---

# Phase quick-260422-mpz Plan 01: SSH Rate Limiting Summary

**One-liner:** Per-IP SSH rate limiting (10 req/60 s) via Hammer v7 module-based ETS backend, enforced in CLIHandler before connection count increment.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Add Hammer dep, RateLimiter module, tests | 368d55a | mix.exs, mix.lock, rate_limiter.ex, supervisor.ex, rate_limiter_test.exs |
| 2 | Enforce rate limit in CLIHandler ssh_channel_up | 19052cf | cli_handler.ex |

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Hammer v7 uses module-based API, not global Hammer.hit/3**

- **Found during:** Task 1 RED phase
- **Issue:** The PLAN.md and RESEARCH.md specified conflicting Hammer versions. PLAN.md
  said `{:hammer, "~> 7.3.0"}` with `Hammer.hit/3` as a global function. RESEARCH.md
  documented the v6 API (`check_rate/3`). In actual Hammer 7.3.0, there is no global
  `Hammer` module with `hit/3` — the library requires `use Hammer, backend: :ets` to
  define a custom module, which injects `start_link/1`, `hit/3`, etc. into that module.
- **Fix:** `Foglet.SSH.RateLimiter` uses `use Hammer, backend: :ets` and calls `hit/3`
  on itself (`hit(key, scale, limit)` without module prefix inside the module). The module
  also needs to be started as a supervised GenServer (it owns the ETS table).
- **Files modified:** lib/foglet_bbs/ssh/rate_limiter.ex, lib/foglet_bbs/ssh/supervisor.ex
- **Commit:** 368d55a

**2. [Rule 1 - Bug] Hammer v7 has no Hammer.delete_buckets/1 global function**

- **Found during:** Task 1 RED phase (test setup failed)
- **Issue:** The PLAN.md tests used `Hammer.delete_buckets/1` for test bucket resets.
  This function does not exist in Hammer v7 (it was a v6 API). The v7 ETS backend stores
  keys as `{key, window}` tuples in a named ETS table.
- **Fix:** Tests use `:ets.match_delete(RateLimiter, {{key, :_}, :_, :_})` directly,
  which is deterministic and requires no clock tricks.
- **Files modified:** test/foglet_bbs/ssh/rate_limiter_test.exs
- **Commit:** 368d55a

**3. [Rule 1 - Bug] RateLimiter GenServer must be started before ETS table exists**

- **Found during:** Task 1 GREEN phase (tests failed with ArgumentError — ETS table not found)
- **Issue:** The test ran the module but the ETS table (created by `RateLimiter.start_link/1`)
  didn't exist yet. The full application supervisor wasn't started in the test environment.
- **Fix:** Added `setup_all do start_supervised!({RateLimiter, clean_period: :timer.minutes(10)}) end`
  to the test module. This starts the GenServer once for the test module and cleans up after.
- **Files modified:** test/foglet_bbs/ssh/rate_limiter_test.exs
- **Commit:** 368d55a

**4. [Rule 1 - Bug] config :hammer stanza is a v6-ism with no effect in v7**

- **Found during:** Task 1 (after confirming Hammer v7 reads no application config)
- **Issue:** The PLAN.md instructed adding `config :hammer, backend: {Hammer.Backend.ETS, ...}`
  to config.exs. In Hammer v7, configuration is passed to `start_link/1` directly; the
  library does not call `Application.get_env/2`. Adding the stanza was harmless but misleading.
- **Fix:** Did not add the stanza (or added then removed it). Configuration lives in the
  `{Foglet.SSH.RateLimiter, clean_period: :timer.minutes(10)}` child spec in supervisor.ex.
- **Files modified:** config/config.exs (stanza removed)
- **Commit:** 368d55a

## Known Stubs

None.

## Threat Flags

None — no new network endpoints or auth paths introduced beyond what the threat model covers.
The `allow?/1` function is purely boolean and contains no privilege-escalation surface.

## Self-Check: PASSED

- [x] `lib/foglet_bbs/ssh/rate_limiter.ex` exists
- [x] `test/foglet_bbs/ssh/rate_limiter_test.exs` exists
- [x] Commit 368d55a exists
- [x] Commit 19052cf exists
- [x] 867 tests, 0 failures
- [x] `mix precommit` exits 0 (compile, format, credo, sobelow, dialyzer all pass)
- [x] `CLIHandler` contains `Foglet.SSH.RateLimiter.allow?(peer)`
- [x] Rate-limited branch sets `over_limit: true`
