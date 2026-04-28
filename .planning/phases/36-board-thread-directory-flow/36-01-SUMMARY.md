---
phase: 36-board-thread-directory-flow
plan: "01"
subsystem: ui
tags: [tui, raxol, screen-contract, board-list, effects]

requires:
  - phase: 34-runtime-contract-effects
    provides: [Foglet.TUI.Context, Foglet.TUI.Effect, screen init/update/render contract]
  - phase: 35-auth-home-screens
    provides: [MainMenu reducer/effect migration pattern]
provides:
  - BoardList owns board directory data, loading status, feedback, and BoardTree state
  - BoardList emits screen-tagged load and subscription task effects
  - BoardList emits ThreadList navigation with selected board route params
  - MainMenu enters BoardList through a BoardList-owned load task
affects: [thread-list-migration, app-shell-cleanup, board-directory-rendering]

tech-stack:
  added: []
  patterns: [screen-local reducer state, screen-tagged task effects, route-param navigation]

key-files:
  created:
    - .planning/phases/36-board-thread-directory-flow/36-01-SUMMARY.md
  modified:
    - lib/foglet_bbs/tui/screens/board_list.ex
    - lib/foglet_bbs/tui/screens/board_list/state.ex
    - lib/foglet_bbs/tui/screens/main_menu.ex
    - test/foglet_bbs/tui/screens/board_list_test.exs
    - test/foglet_bbs/tui/screens/main_menu_test.exs

key-decisions:
  - "BoardList stores directory rows, BoardTree state, status, feedback, and task lifecycle in BoardList.State."
  - "BoardList-to-ThreadList navigation carries visible board identity through route params instead of mutating App current_board."
  - "MainMenu board navigation emits a BoardList-tagged load task instead of an App-owned load dispatch."

patterns-established:
  - "BoardList reducer messages consume :load, task_result tuples, key events, and board_activity messages at the screen boundary."
  - "Subscription tasks bind only current user, board id, and the resolved boards context module before the task closure."

requirements-completed: [SCREEN-03]

duration: 8min
completed: 2026-04-28
---

# Phase 36 Plan 01: BoardList Screen Contract Summary

**Board directory browsing now runs through BoardList-owned state, task effects, and route-param navigation.**

## Performance

- **Duration:** 8 min
- **Started:** 2026-04-28T20:44:27Z
- **Completed:** 2026-04-28T20:52:41Z
- **Tasks:** 3
- **Files modified:** 5

## Accomplishments

- Expanded `BoardList.State` into the local source of truth for directory rows, `BoardTree`, load status, feedback, and task lifecycle.
- Migrated `BoardList` to `init/1`, `update/3`, and `render/2`, removing legacy `handle_key/2`, `render/1`, and `load_boards/1`.
- Reworked BoardList/MainMenu tests to assert reducer state, task effects, navigation route params, and preserved render smoke contracts.
- Updated MainMenu board entry to emit `Effect.navigate(:board_list, %{})` plus a BoardList-tagged `:load_boards` task.

## Task Commits

1. **Task 1: Expand BoardList.State for directory ownership** - `5ffd914` (feat)
2. **Task 2: Add BoardList init/update/render and task effects** - `96aef26` (feat)
3. **Task 3: Migrate BoardList tests and MainMenu board entry dispatch** - `e0864b2` (feat)

## Files Created/Modified

- `lib/foglet_bbs/tui/screens/board_list/state.ex` - Added directory, status, feedback, operation, and error fields.
- `lib/foglet_bbs/tui/screens/board_list.ex` - Added BoardList reducer/render contract, screen-tagged tasks, subscription result handling, board activity refresh, and route-param navigation.
- `lib/foglet_bbs/tui/screens/main_menu.ex` - Replaced BoardList App dispatch with a BoardList-owned load task.
- `test/foglet_bbs/tui/screens/board_list_test.exs` - Rewrote coverage around local state, task effects, navigation effects, and render smoke contracts.
- `test/foglet_bbs/tui/screens/main_menu_test.exs` - Updated board navigation assertions for BoardList-owned loading.

## Decisions Made

- Board identity in the ThreadList navigation params is limited to `id`, `name`, and `slug`, matching the visible directory identity and avoiding hidden board fields.
- Subscription closures keep domain behavior in `Foglet.Boards` and only capture the current user, board id, and resolved boards module.
- Board activity refresh stays asynchronous by emitting a `:load_boards` task rather than doing synchronous domain work in `update/3`.

## Deviations from Plan

None - plan executed as written.

## Issues Encountered

- The local Node SDK shim was not installed, so state loading used the checked-in planning files and normal repo tooling. This did not block plan execution.
- Vendored Raxol warnings are printed during test and compile commands, but `rtk mix compile --warnings-as-errors` exited 0.

## Known Stubs

None. Stub scan only found test assertions, existing MainMenu form placeholders, and pre-existing documentation language; none are unbacked data stubs introduced by this plan.

## Threat Flags

None. The new BoardList task effects match the plan threat model: mutations stay inside `Foglet.Boards`, route params contain visible board identity, and board activity refresh remains asynchronous.

## Verification

- `rtk mix test test/foglet_bbs/tui/screens/board_list_test.exs` - passed
- `rtk mix test test/foglet_bbs/tui/screens/board_list_test.exs test/foglet_bbs/tui/screens/main_menu_test.exs` - passed
- `rtk mix compile --warnings-as-errors` - passed

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

BoardList is ready for Phase 36 ThreadList and App-shell cleanup work. The remaining App-level board/thread compatibility belongs to later Phase 36 plans and Phase 39 cleanup.

## Self-Check: PASSED

- Summary file exists at `.planning/phases/36-board-thread-directory-flow/36-01-SUMMARY.md`.
- Task commit `5ffd914` is visible in git history.
- Task commit `96aef26` is visible in git history.
- Task commit `e0864b2` is visible in git history.

---
*Phase: 36-board-thread-directory-flow*
*Completed: 2026-04-28*
