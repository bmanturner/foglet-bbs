---
phase: 6
plan: "02"
subsystem: tui-screens
tags: [email-verification, login, register, config-toggle, security]
dependency_graph:
  requires: ["06-01"]
  provides: ["06-03"]
  affects: [login.ex, register.ex]
tech_stack:
  added: []
  patterns: [compile-time Mix.env() guard, inner case dispatch via Accounts API]
key_files:
  created: []
  modified:
    - lib/foglet_bbs/tui/screens/login.ex
    - lib/foglet_bbs/tui/screens/register.ex
    - test/foglet_bbs/tui/screens/login_test.exs
    - test/foglet_bbs/tui/screens/register_test.exs
decisions:
  - "Collapse two :active branches in login.ex into one dispatching through post_login_screen/1 rather than pattern-matching confirmed_at inline"
  - "Wrap Logger.info verify-code in if Mix.env() != :prod compile-time guard to prevent prod log leakage"
  - "Add resend_cooldown_until: nil to verify_state initialiser at both entry points so Plan 06-03 has a clean default"
metrics:
  duration: "~15 minutes"
  completed: "2026-04-20"
  tasks_completed: 4
  files_changed: 4
requirements:
  - VERIFY-01
---

# Phase 6 Plan 02: Route Login + Register via `post_login_screen/1` Summary

Surgical refactor of two TUI call sites — `login.ex:submit_login/1` and `register.ex:submit/2` — to dispatch through `Accounts.post_login_screen/1` instead of inline `confirmed_at: nil` pattern matching. Logger verify-code calls are now compile-guarded behind `if Mix.env() != :prod`. Both verify_state initialisers include `resend_cooldown_until: nil` in anticipation of Plan 06-03.

## What Was Built

**Task 1 — login.ex submit_login/1 refactor:**
- Collapsed the old two-clause `{:ok, %{status: :active, confirmed_at: nil}}` + `{:ok, %{status: :active}}` structure into a single `:active` branch with an inner `case Accounts.post_login_screen(user)` dispatch.
- `:verify` branch: builds code, logs dev-only, sets `current_screen: :verify` with `verify_state` including `resend_cooldown_until: nil`.
- `:main_menu` branch: emits `{:promote_session, user}` unchanged (preserves SSH-05 session supervisor).
- `Logger.info` wrapped in `if Mix.env() != :prod do ... end` — compile-stripped in prod releases.

**Task 2 — register.ex submit/2 refactor:**
- Same inner-case pattern for the "open/invite_only" happy path.
- `:verify` branch: same structure as login.
- `:main_menu` branch: sets `current_user` and `register_wizard: nil`, emits `{:promote_session, user}`.
- Auto-fixed [Rule 1 - Bug]: existing test at line 47 asserted `verify_state == %{buffer: "", attempts: 0, cooldown_until: nil}` — updated to include `resend_cooldown_until: nil` to match the new shape.

**Task 3 — login_test.exs additions:**
Three new tests under `"submit_login/1 — VERIFY-01 retroactive bypass"`:
1. Unconfirmed user + toggle=true routes to `:verify` with full verify_state shape.
2. Unconfirmed user + toggle=false routes via `{:promote_session, user}` (VERIFY-01 retroactive bypass).
3. Confirmed user always promotes regardless of toggle value (invariance test).

**Task 4 — register_test.exs additions:**
Two new tests under `"submit/2 — VERIFY-01 post-registration routing"`:
1. Open mode + toggle=true routes to `:verify` with `resend_cooldown_until` in verify_state.
2. Open mode + toggle=false routes via `{:promote_session, user}` bypassing verify screen.

## Commits

| Hash | Type | Description |
|------|------|-------------|
| 99dc2f8 | feat | Route login submit_login/1 via post_login_screen/1 |
| 59b9944 | feat | Route register submit/2 via post_login_screen/1 |
| aa100a9 | test | Add VERIFY-01 retroactive bypass tests to login_test.exs |
| 48bd736 | test | Add VERIFY-01 post-registration routing tests to register_test.exs |

## Test Results

- `mix test test/foglet_bbs/tui/screens/login_test.exs test/foglet_bbs/tui/screens/register_test.exs`: **48 tests, 0 failures**
- Login file: 25 original + 3 new = 28 passing
- Register file: 18 original + 2 new = 20 passing

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Updated existing register_test.exs verify_state assertion**
- **Found during:** Task 2 implementation
- **Issue:** The existing "open mode: handle → email → password → :verify" test (line 47) asserted `verify_state == %{buffer: "", attempts: 0, cooldown_until: nil}`. Adding `resend_cooldown_until: nil` to the verify_state initialiser in register.ex would have broken this test.
- **Fix:** Updated the assertion to `%{buffer: "", attempts: 0, cooldown_until: nil, resend_cooldown_until: nil}`.
- **Files modified:** `test/foglet_bbs/tui/screens/register_test.exs`
- **Commit:** 59b9944

## Known Stubs

None — all code paths are fully wired. The `resend_cooldown_until: nil` field is intentionally `nil` at initialisation; Plan 06-03 will add the resend logic that uses it.

## Threat Flags

None — no new network endpoints, auth paths, or schema changes introduced.

## Self-Check: PASSED

- `lib/foglet_bbs/tui/screens/login.ex` exists: FOUND
- `lib/foglet_bbs/tui/screens/register.ex` exists: FOUND
- `test/foglet_bbs/tui/screens/login_test.exs` exists: FOUND
- `test/foglet_bbs/tui/screens/register_test.exs` exists: FOUND
- Commit 99dc2f8 exists: FOUND
- Commit 59b9944 exists: FOUND
- Commit aa100a9 exists: FOUND
- Commit 48bd736 exists: FOUND
