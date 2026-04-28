---
phase: 35-auth-home-screens
plan: "02"
subsystem: tui
tags: [elixir, raxol, tui, auth, register, verify, screen-contract, effects]

requires:
  - phase: 34-runtime-contract-effects
    provides: [Foglet.TUI.Context, Foglet.TUI.Effect, generic App screen task routing]
  - phase: 35-auth-home-screens
    plan: "01"
    provides: [Login screen reducer migration pattern, App generic task routing coverage]
provides:
  - Register screen init/update/render contract over Register.State maps
  - Register registration task submission through Effect.task/3
  - Register registration result handling through Register.update/3
  - Verify screen init/update/render contract over Verify.State maps
  - Verify submit/resend task submission and cooldown handling through Effect.task/3
  - App regression coverage for generic Register and Verify screen task routing
affects: [phase-35-auth-home-screens, phase-39-app-shell-cleanup, register, verify, auth, tui-runtime]

tech-stack:
  added: []
  patterns:
    - Screen reducers expose init/update/render over Foglet.TUI.Context
    - Auth screens emit Effect.task/3 and consume {:task_result, op, result}
    - App routes Register and Verify task results generically via {:screen_task_result, screen_key, op, result}

key-files:
  created:
    - .planning/phases/35-auth-home-screens/35-02-SUMMARY.md
  modified:
    - lib/foglet_bbs/tui/screens/register.ex
    - lib/foglet_bbs/tui/screens/register/state.ex
    - lib/foglet_bbs/tui/screens/verify.ex
    - lib/foglet_bbs/tui/screens/verify/state.ex
    - lib/foglet_bbs/tui/app.ex
    - test/foglet_bbs/tui/screens/register_test.exs
    - test/foglet_bbs/tui/screens/verify_test.exs
    - test/foglet_bbs/tui/app_test.exs

key-decisions:
  - "Register and Verify keep their map-shaped state modules while exposing the Phase 34 screen contract."
  - "Register uses Effect.session({:set_current_user, user}) before Verify navigation and Effect.session({:set_user, user}) for main-menu promotion."
  - "Verify successful submit promotes through Effect.session({:set_user, confirmed_user}) so App remains the session/runtime interpreter."
  - "App no longer owns Register or Verify-specific production delegation clauses."

patterns-established:
  - "Reducer tests drive Register.init/1, Register.update/3, Verify.init/1, and Verify.update/3 directly and assert Effect values for task, modal, session, and navigation outcomes."
  - "App loads screen modules before checking migrated render/update callbacks, preventing unloaded migrated screens from falling back to removed legacy callbacks."

requirements-completed: [SCREEN-01]

duration: 14min
completed: 2026-04-28
---

# Phase 35 Plan 02: Register and Verify Screen Contract Summary

**Register and Verify now own onboarding state, code entry, async auth outcomes, and task effects through screen reducers.**

## Performance

- **Duration:** 14 min
- **Started:** 2026-04-28T19:41:00Z
- **Completed:** 2026-04-28T19:55:00Z
- **Tasks:** 3
- **Files modified:** 8

## Accomplishments

- Migrated `Foglet.TUI.Screens.Register` to `init/1`, `update/3`, and `render/2` over local `Register.State`.
- Replaced Register wizard/App delegation with reducer-owned invite-code, combined-form, registration-result, verification-delivery, and pending-approval handling.
- Migrated `Foglet.TUI.Screens.Verify` to `init/1`, `update/3`, and `render/2` over local `Verify.State`.
- Replaced Verify event/App delegation with reducer-owned code entry, submit, resend, cooldown, no-user, success, invalid, expired, and failure handling.
- Removed App production clauses for `{:register_wizard, _}` and `{:verify_event, _}`, leaving generic `{:screen_task_result, screen_key, op, result}` routing.

## Task Commits

1. **Task 1: Move Register wizard and registration outcomes into Register.update/3** - `267d0ec` (feat)
2. **Task 2: Move Verify code entry, submit, resend, cooldown, and outcomes into Verify.update/3** - `87bb061` (feat)
3. **Task 3: Replace App delegation tests with generic onboarding task routing checks** - `f53694a` (fix)

## Files Created/Modified

- `lib/foglet_bbs/tui/screens/register.ex` - New screen contract, local reducer key/wizard/result handling, registration task effect submission.
- `lib/foglet_bbs/tui/screens/register/state.ex` - Updated ownership docs for reducer-owned Register state.
- `lib/foglet_bbs/tui/screens/verify.ex` - New screen contract, local reducer code-entry/result handling, submit/resend task effect submission.
- `lib/foglet_bbs/tui/screens/verify/state.ex` - Updated ownership docs for reducer-owned Verify state.
- `lib/foglet_bbs/tui/app.ex` - Removed Register/Verify delegation hooks and hardened migrated screen callback detection.
- `test/foglet_bbs/tui/screens/register_test.exs` - Register reducer/effect tests for invite, open, sysop-approved, validation, delivery failure, session promotion, and pending approval.
- `test/foglet_bbs/tui/screens/verify_test.exs` - Verify reducer/effect tests for entry, backspace, submit, invalid, expired, cooldown, resend, resend failure, and no-user behavior.
- `test/foglet_bbs/tui/app_test.exs` - Generic task-result routing assertions for Register and Verify active screen state.

## Decisions Made

- Kept Register and Verify local state map-shaped for this migration slice to avoid a broad state-shape refactor while moving ownership to the reducer boundary.
- Used task effects for registration, verification submit, and resend so domain work still runs through App runtime plumbing and returns as tagged screen task results.
- Preserved pending approval by emitting the modal plus `Effect.session({:terminate_after_modal, :pending_approval})`, keeping session termination in App.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Loaded migrated screen modules before callback detection**
- **Found during:** Task 3 (Replace App delegation tests with generic onboarding task routing checks)
- **Issue:** Migrated screens no longer export legacy `render/1`, `handle_key/2`, or delegation callbacks. If App checks callback exports before the module is loaded, it can miss the new contract and fall back to removed legacy callbacks.
- **Fix:** App now uses `Code.ensure_loaded?/1` before checking `update/3` in task routing and before checking `render/2` in screen rendering.
- **Files modified:** `lib/foglet_bbs/tui/app.ex`
- **Verification:** `rtk mix test test/foglet_bbs/tui/screens/register_test.exs test/foglet_bbs/tui/screens/verify_test.exs test/foglet_bbs/tui/app_test.exs`; `rtk mix compile --warnings-as-errors`
- **Committed in:** `f53694a`

---

**Total deviations:** 1 auto-fixed (1 blocking)
**Impact on plan:** The fix is required for migrated production screens to be routable/renderable through the new contract. No product scope was added.

## Issues Encountered

- Existing `AppTest` still emits sandbox ownership warnings from unrelated Sysop/ShellVisibility paths, but the targeted tests pass. No plan code changes were needed for those pre-existing warnings.
- `rtk mix compile --warnings-as-errors` still prints dependency warnings from the vendored `raxol` app, but exits 0 for the Foglet app.

## Known Stubs

None.

## Threat Flags

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

MainMenu/oneliner migration can follow the same pattern: local state in the screen, task effects out, `{:screen_task_result, :main_menu, op, result}` back in, and App as interpreter only. Phase 39 can later remove remaining legacy local-flow machinery after the remaining screen families migrate.

## Verification

- `rtk mix test test/foglet_bbs/tui/screens/register_test.exs` - passed
- `rtk mix test test/foglet_bbs/tui/screens/verify_test.exs` - passed
- `rtk mix test test/foglet_bbs/tui/screens/register_test.exs test/foglet_bbs/tui/screens/verify_test.exs test/foglet_bbs/tui/app_test.exs` - passed
- `rtk mix compile --warnings-as-errors` - passed

## Self-Check: PASSED

- `FOUND_SUMMARY` for `.planning/phases/35-auth-home-screens/35-02-SUMMARY.md`
- Found task commit `267d0ec`
- Found task commit `87bb061`
- Found task commit `f53694a`
- Stub scan found no goal-blocking stubs in modified implementation files; matches were existing UI placeholders, ordinary empty-state/test assertions, and map updates.

---
*Phase: 35-auth-home-screens*
*Completed: 2026-04-28*
