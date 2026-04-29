---
phase: 35-auth-home-screens
plan: "03"
subsystem: tui
tags: [elixir, raxol, tui, main-menu, oneliners, screen-contract, effects]

requires:
  - phase: 34-runtime-contract-effects
    provides: [Foglet.TUI.Context, Foglet.TUI.Effect, generic screen task routing]
  - phase: 35-auth-home-screens
    plan: "01"
    provides: [Login reducer migration pattern]
  - phase: 35-auth-home-screens
    plan: "02"
    provides: [Register and Verify reducer migration pattern]
provides:
  - MainMenu.State struct for oneliner rows, selection, pending hide target, status, and errors
  - MainMenu init/update/render contract over Foglet.TUI.Context
  - MainMenu-owned oneliner load/create/hide reducer handling and screen-tagged task effects
  - App regression coverage for MainMenu screen-local state via App.screen_state_for/2
affects: [phase-35-auth-home-screens, phase-36-board-thread-directory-flow, phase-39-app-shell-cleanup, main-menu, oneliners, tui-runtime]

tech-stack:
  added: []
  patterns:
    - Stateful MainMenu reducer owns home-screen oneliner state and emits Effect values
    - App compatibility paths route oneliner load results into MainMenu screen_state
    - Modal submit callbacks use generic screen modal-submit plumbing pending full App cleanup in 35-04

key-files:
  created:
    - lib/foglet_bbs/tui/screens/main_menu/state.ex
    - .planning/phases/35-auth-home-screens/35-03-SUMMARY.md
  modified:
    - lib/foglet_bbs/tui/screens/main_menu.ex
    - lib/foglet_bbs/tui/app.ex
    - test/foglet_bbs/tui/screens/main_menu_test.exs
    - test/foglet_bbs/tui/app_test.exs

key-decisions:
  - "MainMenu now uses a first-class State struct for recent oneliners, selection, pending hide target, status, and form errors."
  - "MainMenu reducer tests assert local state and Effect values instead of legacy handle_key/2 or App top-level oneliner fields."
  - "App still carries transitional oneliner compatibility clauses for Plan 35-04 cleanup, but load results now feed MainMenu screen_state."

patterns-established:
  - "MainMenu.update/3 accepts {:modal_submit, kind, payload} messages and emits screen-tagged Effect.task/3 requests."
  - "MainMenu task-result clauses unwrap App task results and keep modal error state in the reducer."
  - "App tests use App.screen_state_for(state, :main_menu) for home-screen oneliner assertions."

requirements-completed: [SCREEN-02]

duration: 15min
completed: 2026-04-28
---

# Phase 35 Plan 03: MainMenu Screen State Summary

**MainMenu now owns oneliner rows, selection, composer/hide submissions, and task results through a screen-local reducer.**

## Performance

- **Duration:** 15 min
- **Started:** 2026-04-28T19:58:47Z
- **Completed:** 2026-04-28T20:13:06Z
- **Tasks:** 3
- **Files modified:** 5

## Accomplishments

- Added `Foglet.TUI.Screens.MainMenu.State` with oneliner rows, selected index, pending hide target, lifecycle status, and reducer-visible errors.
- Migrated MainMenu from legacy `render/1` and `handle_key/2` to `init/1`, `update/3`, and `render/2` over `Foglet.TUI.Context`.
- Moved oneliner selection, composer/hide modal decisions, submit requests, and create/hide/load results into `MainMenu.update/3`.
- Updated MainMenu and App tests to assert `%MainMenu.State{}` plus effects, including `App.screen_state_for(state, :main_menu)`.

## Task Commits

1. **Task 1: Add MainMenu.State and reducer-owned oneliner state transitions** - `8384850` (feat)
2. **Task 2: Move MainMenu navigation and oneliner composer/hide decisions into update/3** - `09125bc` (feat)
3. **Task 3: Move oneliner create/hide results and visibility tests to MainMenu state** - `6e6c28a` (feat)

## Files Created/Modified

- `lib/foglet_bbs/tui/screens/main_menu/state.ex` - New screen-local state struct and helpers for rows, selection, pending hide, and errors.
- `lib/foglet_bbs/tui/screens/main_menu.ex` - New MainMenu screen contract, reducer key handling, modal submit handling, oneliner task effects, and task-result handling.
- `lib/foglet_bbs/tui/app.ex` - Generic session dispatch effect and compatibility routing so oneliner loads feed MainMenu screen state.
- `test/foglet_bbs/tui/screens/main_menu_test.exs` - Reducer/effect tests for render data, navigation, selection, modal open, submit validation, create/hide results, and role gating.
- `test/foglet_bbs/tui/app_test.exs` - App regression checks for MainMenu state through `App.screen_state_for/2`.

## Decisions Made

- Kept App's full Phase 35 local-flow clause deletion for Plan 35-04, but changed oneliner load compatibility to populate MainMenu screen-local state now.
- Used reducer-local errors plus modal-open effects for create/hide failures so failed form submissions release modal submit locks.
- Preserved hide visibility as advisory UI through `Bodyguard.permit?(Authorization, :hide_oneliner, user, :site)` while leaving authoritative authorization in `Foglet.Oneliners.hide_entry/3`.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Routed legacy oneliner loads into MainMenu screen_state**
- **Found during:** Task 3 (Move oneliner create/hide results and visibility tests to MainMenu state)
- **Issue:** App's existing `{:load_oneliners}` task still returned `{:oneliners_loaded, entries}` and updated top-level `recent_oneliners`, so post-login loads would not reach the new MainMenu render source of truth.
- **Fix:** Changed the compatibility task to return `{:screen_task_result, :main_menu, :load_oneliners, {:ok, entries}}` and made `{:oneliners_loaded, entries}` delegate through MainMenu's reducer.
- **Files modified:** `lib/foglet_bbs/tui/app.ex`, `test/foglet_bbs/tui/app_test.exs`
- **Verification:** `rtk mix test test/foglet_bbs/tui/screens/main_menu_test.exs test/foglet_bbs/tui/app_test.exs`; `rtk mix compile --warnings-as-errors`
- **Committed in:** `6e6c28a`

---

**Total deviations:** 1 auto-fixed (1 bug)
**Impact on plan:** The fix was required to keep authenticated MainMenu oneliner loads functional after moving render state into the screen reducer. No product scope was added.

## Issues Encountered

- Existing `AppTest` still emits sandbox ownership warnings from unrelated Sysop/ShellVisibility config reads, but the targeted tests pass.
- `rtk mix compile --warnings-as-errors` still prints dependency warnings from vendored `raxol`, but exits 0 for the Foglet app.
- While this plan was running, unrelated Phase 36 planning commits/files appeared in the worktree. They were not staged or modified by this plan.

## Known Stubs

None. Stub scan matches were existing form placeholders and test assertions, not goal-blocking implementation stubs.

## Threat Flags

None. This plan preserved the declared MainMenu reducer, Authorization policy, and modal-form trust boundaries without adding new network, file, auth, or schema surfaces.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

Plan 35-04 can remove the remaining App compatibility clauses and genericize modal submit plumbing fully. MainMenu already owns the state and reducer behavior needed for that cleanup.

## Verification

- `rtk mix test test/foglet_bbs/tui/screens/main_menu_test.exs` - passed
- `rtk mix test test/foglet_bbs/tui/screens/main_menu_test.exs test/foglet_bbs/tui/app_test.exs` - passed
- `rtk mix compile --warnings-as-errors` - passed

## Self-Check: PASSED

- `FOUND_SUMMARY` for `.planning/phases/35-auth-home-screens/35-03-SUMMARY.md`
- Found task commit `8384850`
- Found task commit `09125bc`
- Found task commit `6e6c28a`
- Stub scan found no goal-blocking stubs in modified implementation files; matches were form placeholders and test assertions.

---
*Phase: 35-auth-home-screens*
*Completed: 2026-04-28*
