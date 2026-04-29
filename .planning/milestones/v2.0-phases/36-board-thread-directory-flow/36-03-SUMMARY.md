---
phase: 36-board-thread-directory-flow
plan: "03"
subsystem: ui
tags: [tui, raxol, app-shell, board-list, thread-list, pubsub]

requires:
  - phase: 36-board-thread-directory-flow
    provides: [BoardList screen-owned reducer, ThreadList screen-owned reducer]
provides:
  - App no longer owns BoardList or ThreadList directory local-flow clauses
  - ThreadList board PubSub topics derive from route params or ThreadList.State
  - BoardList and ThreadList render fixtures and smoke tests seed screen-local state
affects: [phase-37-post-reader-composer-flow, phase-39-app-shell-cleanup, tui-render-fixtures]

tech-stack:
  added: []
  patterns: [screen-owned reducer state, route-param topic derivation, local-state render fixtures]

key-files:
  created:
    - .planning/phases/36-board-thread-directory-flow/36-03-SUMMARY.md
  modified:
    - lib/foglet_bbs/tui/app.ex
    - lib/foglet_bbs/tui/render_fixtures.ex
    - lib/foglet_bbs/tui/screens/board_list.ex
    - lib/foglet_bbs/tui/screens/board_list/state.ex
    - lib/foglet_bbs/tui/screens/thread_list.ex
    - lib/foglet_bbs/tui/screens/thread_list/state.ex
    - test/foglet_bbs/tui/app_runtime_contract_test.exs
    - test/foglet_bbs/tui/app_test.exs
    - test/foglet_bbs/tui/layout_smoke_test.exs

key-decisions:
  - "App treats BoardList and ThreadList task results as generic screen_task_result messages instead of legacy top-level assignments."
  - "ThreadList board PubSub topic derivation intentionally ignores current_board and uses route params before ThreadList.State."
  - "Render fixtures keep top-level current_board/current_thread only for Phase 37 compatibility screens."

patterns-established:
  - "Migrated directory screens receive load, task result, and PubSub refresh messages through screen reducers."
  - "Canonical render fixtures seed screen_state with first-class local state structs."

requirements-completed: [SCREEN-03]

duration: 8min
completed: 2026-04-28
---

# Phase 36 Plan 03: App Shell Directory Cleanup Summary

**Board and thread directory rendering, task results, and board-topic subscriptions now use screen-local state instead of App-owned directory fields.**

## Performance

- **Duration:** 8 min
- **Started:** 2026-04-28T20:57:21Z
- **Completed:** 2026-04-28T21:05:15Z
- **Tasks:** 3
- **Files modified:** 9

## Accomplishments

- Removed App-owned BoardList/ThreadList local-flow handlers for board loads, thread loads, subscription results, and top-level directory assignment.
- Added App tests proving screen-task results update `screen_state[:board_list]` and `screen_state[:thread_list]` without mutating legacy top-level fields.
- Changed ThreadList PubSub board topics to use route params or `%ThreadList.State{}` and ignore `current_board`.
- Updated render fixtures, layout smoke tests, and module docs to seed and describe BoardList/ThreadList as screen-owned reducers.

## Task Commits

Each task was committed atomically:

1. **Task 1: Remove App board/thread directory local-flow clauses** - `bbd1330` (feat)
2. **Task 2: Derive ThreadList PubSub topics from route params or screen state** - `b6b71a6` (feat)
3. **Task 3: Update render fixtures, smoke tests, and docs for local state** - `50a6a55` (docs)

**Plan metadata:** this summary commit

## Files Created/Modified

- `lib/foglet_bbs/tui/app.ex` - Removed legacy directory-flow clauses and added route/local ThreadList topic derivation.
- `lib/foglet_bbs/tui/render_fixtures.ex` - Seeds BoardList and ThreadList through local state structs.
- `lib/foglet_bbs/tui/screens/board_list.ex` - Documents BoardList as a screen-owned reducer.
- `lib/foglet_bbs/tui/screens/board_list/state.ex` - Documents local directory/tree/status/feedback ownership.
- `lib/foglet_bbs/tui/screens/thread_list.ex` - Documents ThreadList as a screen-owned reducer over route params.
- `lib/foglet_bbs/tui/screens/thread_list/state.ex` - Documents selected board identity, rows, status, and selection ownership.
- `test/foglet_bbs/tui/app_runtime_contract_test.exs` - Removed stale legacy-field assumptions from generic runtime tests.
- `test/foglet_bbs/tui/app_test.exs` - Added reducer-routing, no-top-level-mutation, and PubSub topic source tests.
- `test/foglet_bbs/tui/layout_smoke_test.exs` - Renders BoardList and ThreadList smoke cases from local state structs.

## Decisions Made

- BoardList refresh after read-pointer flush and board activity now enters the BoardList reducer via `:load`, preserving unread refresh behavior without App-owned directory tasks.
- ThreadList board topics do not fall back to `current_board`; a missing route/local board id means no board topic.
- Phase 37 compatibility fields remain only in render fixtures for post reader/composer screens that still depend on top-level current board/thread fields.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Removed stale runtime-contract test field**
- **Found during:** Task 1
- **Issue:** `app_runtime_contract_test.exs` still referenced a removed `recent_oneliners` App field, causing struct construction failures.
- **Fix:** Swapped the preservation assertion to an existing legacy field, `current_thread_list`.
- **Files modified:** `test/foglet_bbs/tui/app_runtime_contract_test.exs`
- **Verification:** `rtk mix test test/foglet_bbs/tui/app_runtime_contract_test.exs test/foglet_bbs/tui/app_test.exs`
- **Committed in:** `bbd1330`

**2. [Rule 3 - Blocking] Seeded ThreadList local state in App render smoke test**
- **Found during:** Task 1
- **Issue:** A direct `current_screen: :thread_list` view smoke bypassed navigation initialization and called `ThreadList.render/2` with nil local state.
- **Fix:** Updated the smoke setup to provide `%ThreadList.State{}` explicitly.
- **Files modified:** `test/foglet_bbs/tui/app_test.exs`
- **Verification:** `rtk mix test test/foglet_bbs/tui/app_runtime_contract_test.exs test/foglet_bbs/tui/app_test.exs`
- **Committed in:** `bbd1330`

---

**Total deviations:** 2 auto-fixed (2 blocking)
**Impact on plan:** Both fixes were test-harness updates required by the migration boundary; no product scope changed.

## Issues Encountered

- Vendored Raxol warnings are printed during test and compile commands, but the targeted tests and `rtk mix compile --warnings-as-errors` exited 0.
- Existing unrelated dirty files were present before this executor started: `AGENTS.md`, `.claude/worktrees/`, and `LOGIN.md`. They were left untouched and unstaged.

## Known Stubs

None. Stub scan found only test assertions/placeholders and existing nil/empty-state checks; no unbacked UI data stubs were introduced.

## Threat Flags

None. The only trust-boundary change was the planned PubSub topic derivation from route/local ThreadList state.

## Verification

- `rtk mix test test/foglet_bbs/tui/app_runtime_contract_test.exs test/foglet_bbs/tui/app_test.exs` - passed
- `rtk mix test test/foglet_bbs/tui/app_test.exs` - passed
- `rtk mix test test/foglet_bbs/tui/screens/board_list_test.exs test/foglet_bbs/tui/screens/thread_list_test.exs test/foglet_bbs/tui/layout_smoke_test.exs` - passed
- `rtk mix test test/foglet_bbs/tui/screens/board_list_test.exs test/foglet_bbs/tui/screens/thread_list_test.exs test/foglet_bbs/tui/app_runtime_contract_test.exs test/foglet_bbs/tui/app_test.exs test/foglet_bbs/tui/layout_smoke_test.exs` - passed, 260 tests
- `rtk mix compile --warnings-as-errors` - passed

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

Phase 37 can migrate PostReader and composer flows knowing BoardList/ThreadList rows, feedback, selection, and topic source are no longer App-owned. The remaining top-level `current_board`, `current_thread`, and `current_thread_list` compatibility fields are isolated to later post/composer cleanup.

## Self-Check: PASSED

- Summary file exists at `.planning/phases/36-board-thread-directory-flow/36-03-SUMMARY.md`.
- Task commit `bbd1330` is visible in git history.
- Task commit `b6b71a6` is visible in git history.
- Task commit `50a6a55` is visible in git history.
- No STATE.md or ROADMAP.md updates were made by this executor.

---
*Phase: 36-board-thread-directory-flow*
*Completed: 2026-04-28*
