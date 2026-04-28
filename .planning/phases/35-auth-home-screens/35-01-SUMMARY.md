---
phase: 35-auth-home-screens
plan: "01"
subsystem: tui
tags: [elixir, raxol, tui, auth, screen-contract, effects]

requires:
  - phase: 34-runtime-contract-effects
    provides: [Foglet.TUI.Context, Foglet.TUI.Effect, App screen task routing]
provides:
  - Login screen init/update/render contract over Login.State maps
  - Login authentication task submission through Effect.task/3
  - Login task-result handling through Login.update/3
  - App regression coverage for generic Login screen task routing
affects: [phase-35-auth-home-screens, phase-39-app-shell-cleanup, login, auth, tui-runtime]

tech-stack:
  added: []
  patterns:
    - Screen reducers expose init/update/render over Foglet.TUI.Context
    - Screens emit Effect.task/3 and consume {:task_result, op, result}
    - App routes screen task results generically via {:screen_task_result, screen_key, op, result}

key-files:
  created:
    - .planning/phases/35-auth-home-screens/35-01-SUMMARY.md
  modified:
    - lib/foglet_bbs/tui/screens/login.ex
    - lib/foglet_bbs/tui/app.ex
    - test/foglet_bbs/tui/screens/login_test.exs
    - test/foglet_bbs/tui/app_test.exs

key-decisions:
  - "Login remains map-shaped through Foglet.TUI.Screens.Login.State while exposing the Phase 34 screen contract."
  - "Login verification routing uses a session effect to set the current user before navigating to Verify."
  - "App no longer owns Login-specific login_result or task_error result clauses."

patterns-established:
  - "Reducer tests drive Login.init/1 and Login.update/3 directly and assert Effect values for session, navigation, modal, quit, and task outcomes."
  - "Migrated screens that may not yet be loaded are detected with Code.ensure_loaded?/1 before App chooses the new contract path."

requirements-completed: [SCREEN-01]

duration: 10min
completed: 2026-04-28
---

# Phase 35 Plan 01: Login Screen Contract Summary

**Login now owns auth/reset local state through init/update/render and submits authentication through Phase 34 task effects.**

## Performance

- **Duration:** 10 min
- **Started:** 2026-04-28T19:30:52Z
- **Completed:** 2026-04-28T19:40:28Z
- **Tasks:** 2
- **Files modified:** 4

## Accomplishments

- Migrated `Foglet.TUI.Screens.Login` to `init/1`, `update/3`, and `render/2` over its existing map-shaped `Login.State`.
- Replaced legacy login command submission with `Effect.task(:login, :login, fun)` and reducer-owned task-result handling.
- Reworked Login tests to drive local reducer state/effects instead of `handle_key/2`, `handle_login_result/2`, or App-owned login result messages.
- Removed App's Login-specific `{:login_result, _}` and `{:task_error, :login, _}` ownership, keeping only generic `{:screen_task_result, ...}` routing.

## Task Commits

1. **Task 1: Add Login init/update/render around existing Login.State** - `8cd456a` (feat)
2. **Task 2: Move Login result preservation tests to reducer/effect assertions** - `efa7fa1` (fix)

## Files Created/Modified

- `lib/foglet_bbs/tui/screens/login.ex` - New screen contract, local reducer key/result handling, task-effect login submission.
- `lib/foglet_bbs/tui/app.ex` - Generic session current-user effect support, robust new-contract detection, removal of Login result clauses.
- `test/foglet_bbs/tui/screens/login_test.exs` - Login reducer/effect tests for menu, form, reset, auth success/failure, verification, and status modals.
- `test/foglet_bbs/tui/app_test.exs` - Generic `:screen_task_result` routing assertion for Login local state.

## Decisions Made

- Preserved `Login.State.default/0` as the local state shape rather than introducing a struct during this slice.
- Kept reset request and reset-token submission synchronous because the existing behavior is synchronous; task-result clauses exist for compatibility if those flows become task-backed later.
- Added `Effect.session({:set_current_user, user})` so successful login requiring verification can preserve the existing Verify route user context without promoting to main menu.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing Critical] Added current-user session effect for verification routing**
- **Found during:** Task 1 (Add Login init/update/render around existing Login.State)
- **Issue:** The Phase 34 effects had `{:set_user, user}` for main-menu promotion but no way for Login to set the Verify route's current user without using App-shaped state mutation.
- **Fix:** Added App interpretation for `Effect.session({:set_current_user, user})` and used it with `Effect.navigate(:verify, %{})`.
- **Files modified:** `lib/foglet_bbs/tui/app.ex`, `lib/foglet_bbs/tui/screens/login.ex`
- **Verification:** `rtk mix test test/foglet_bbs/tui/screens/login_test.exs`
- **Committed in:** `8cd456a`

**2. [Rule 3 - Blocking] Loaded screen modules before new-contract detection**
- **Found during:** Task 2 (Move Login result preservation tests to reducer/effect assertions)
- **Issue:** `function_exported?/3` returned false for unloaded migrated screens in an App key-routing test, causing App to fall back to legacy `handle_key/2`.
- **Fix:** `new_contract_screen?/2` now uses `Code.ensure_loaded?/1` before checking for `update/3` and absence of `handle_key/2`.
- **Files modified:** `lib/foglet_bbs/tui/app.ex`
- **Verification:** `rtk mix test test/foglet_bbs/tui/screens/login_test.exs test/foglet_bbs/tui/app_test.exs`
- **Committed in:** `efa7fa1`

---

**Total deviations:** 2 auto-fixed (1 missing critical, 1 blocking)
**Impact on plan:** Both fixes were required for the reducer migration to work through the generic App runtime path. No product scope was added.

## Issues Encountered

- Existing `AppTest` emits sandbox ownership warnings from unrelated Sysop/ShellVisibility paths, but the targeted tests pass. No plan code changes were needed for those pre-existing warnings.

## Known Stubs

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

Register, Verify, and MainMenu migrations can now follow the same reducer/effect pattern: local state in the screen, task effects out, `{:screen_task_result, screen_key, op, result}` back in, and App as interpreter only.

## Verification

- `rtk mix test test/foglet_bbs/tui/screens/login_test.exs` - passed
- `rtk mix test test/foglet_bbs/tui/screens/login_test.exs test/foglet_bbs/tui/app_test.exs` - passed
- `rtk mix compile --warnings-as-errors` - passed

## Self-Check: PASSED

- `FOUND_SUMMARY` for `.planning/phases/35-auth-home-screens/35-01-SUMMARY.md`
- Found task commit `8cd456a`
- Found task commit `efa7fa1`
- Stub scan found no goal-blocking stubs in modified implementation files; matches were existing test assertions/placeholders in unrelated App flows.

---
*Phase: 35-auth-home-screens*
*Completed: 2026-04-28*
