---
phase: 13-board-subscription-management
plan: 2
subsystem: tui
tags: [tui, raxol, board-subscriptions, empty-states]

requires:
  - phase: 13-board-subscription-management
    provides: Required-subscription board policy and Foglet.Boards subscription APIs
provides:
  - Terminal category-tree board directory with inline subscription status
  - Focused-board subscribe and unsubscribe TUI commands
  - Honest NewThread empty states for no subscriptions versus no active boards
affects: [board-directory, new-thread, tui-app-command-routing]

tech-stack:
  added: []
  patterns:
    - Raxol Display.Tree screen-local state via sibling state module
    - TUI screen commands routed through Foglet.TUI.App async domain tasks

key-files:
  created:
    - lib/foglet_bbs/tui/screens/board_list/state.ex
  modified:
    - lib/foglet_bbs/tui/app.ex
    - lib/foglet_bbs/tui/screens/board_list.ex
    - lib/foglet_bbs/tui/screens/new_thread.ex
    - lib/foglet_bbs/tui/screens/new_thread/state.ex
    - test/foglet_bbs/tui/screens/board_list_test.exs
    - test/foglet_bbs/tui/screens/new_thread_test.exs

key-decisions:
  - "BoardList keeps state.board_list as the board-directory snapshot and stores tree cursor/feedback in BoardList.State."
  - "Subscribe and unsubscribe actions are separate focused-board commands; Enter remains leaf-only open-board navigation."

patterns-established:
  - "Board directory tree nodes use map nodes with atom ids and board metadata in :data."
  - "NewThread derives subscribed boards plus active-board availability from the board-directory snapshot."

requirements-completed: [SUBS-01, SUBS-02, SUBS-03, SUBS-05]

duration: not measured
completed: 2026-04-24
---

# Phase 13 Plan 2: Board Directory TUI Summary

**Terminal category-tree board directory with focused subscribe/unsubscribe actions and honest new-thread empty states.**

## Performance

- **Duration:** Not measured
- **Started:** 2026-04-24
- **Completed:** 2026-04-24
- **Tasks:** 2
- **Files modified:** 8

## Accomplishments

- Replaced the subscribed-only BoardList with `Foglet.TUI.Widgets.Display.Tree` over `Boards.board_directory_for/1`.
- Added board labels for `[subscribed]`, `[unsubscribed]`, and `[required]`, preserving unread suffixes for subscribed boards.
- Added focused `s` and `u` commands that route through `Foglet.TUI.App` to `Foglet.Boards.subscribe_user_to_board/2` and `unsubscribe_user_from_board/2`.
- Updated NewThread loading and empty copy so no-subscription users are pointed to `Subscribe from Boards`, while no-active-board sites say `No active boards are available`.

## Task Commits

1. **Task 13-02-01 RED:** `19a9988` test(13-02): add failing board directory tree tests
2. **Task 13-02-01 GREEN:** `c0eccda` feat(13-02): render board directory tree
3. **Task 13-02-02 RED:** `3ecd7de` test(13-02): add failing subscription action tests
4. **Task 13-02-02 GREEN:** `63ae0dd` feat(13-02): wire board subscription actions
5. **Plan metadata:** `e253873` docs(13-02): complete board directory plan

## Files Created/Modified

- `lib/foglet_bbs/tui/app.ex` - Loads board-directory snapshots, routes subscribe/unsubscribe command tasks, reloads after success, and derives NewThread board availability.
- `lib/foglet_bbs/tui/screens/board_list.ex` - Renders the category tree, handles collapse/expand, Enter leaf activation, focused subscribe/unsubscribe, and feedback.
- `lib/foglet_bbs/tui/screens/board_list/state.ex` - Holds BoardList tree state and feedback.
- `lib/foglet_bbs/tui/screens/new_thread.ex` - Replaces sysop-directed empty copy with subscription-action and no-active-board copy.
- `lib/foglet_bbs/tui/screens/new_thread/state.ex` - Tracks active-board count for empty-state classification.
- `test/foglet_bbs/tui/screens/board_list_test.exs` - Covers directory tree rendering, collapse/expand, leaf-only open, focused actions, and required-board feedback.
- `test/foglet_bbs/tui/screens/new_thread_test.exs` - Covers NewThread empty-state copy.

## Decisions Made

- Kept the App field name `board_list` for the directory snapshot to avoid expanding the top-level App struct surface in this plan.
- Initialized category nodes expanded so subscribed and unsubscribed board leaves are visible together on first render while still supporting collapse.

## Deviations from Plan

None - plan executed within the requested owned files and API boundaries.

## Issues Encountered

- The fresh worktree initially lacked dependencies; resolved with `rtk mix deps.get`.
- A follow-up summary correction was needed because the first summary had a stale Task 13-02-02 commit hash.

## User Setup Required

None - no external service configuration required.

## Verification

- `rtk mix test test/foglet_bbs/tui/screens/board_list_test.exs` - passed, 8 tests.
- `rtk mix test test/foglet_bbs/tui/screens/board_list_test.exs test/foglet_bbs/tui/screens/new_thread_test.exs` - passed, 52 tests.
- `rg -n "Display.Tree|\\[subscribed\\]|\\[unsubscribed\\]|\\[required\\]|node_activated" lib/foglet_bbs/tui/screens/board_list.ex test/foglet_bbs/tui/screens/board_list_test.exs` - confirmed tree rendering and tests.
- `rg -n "Ask your sysop" lib/foglet_bbs/tui/screens/board_list.ex lib/foglet_bbs/tui/screens/new_thread.ex test/foglet_bbs/tui/screens` - no production matches; test-only negative assertions remain.
- `rg -n "Subscribe from Boards|No active boards are available|subscribe_to_board|unsubscribe_from_board" lib/foglet_bbs/tui test/foglet_bbs/tui/screens` - confirmed command wiring and copy tests.

## Known Stubs

None.

## Threat Flags

None.

## Self-Check: PASSED

- Summary exists at `.planning/phases/13-board-subscription-management/13-02-SUMMARY.md`.
- Task commits exist on branch `gsd-phase-13-02`.
- No `.planning/STATE.md` or `.planning/ROADMAP.md` changes were made or committed.

## Next Phase Readiness

The TUI now consumes the Phase 13 Plan 1 context APIs for user subscription management. Plan 13-03 can implement the break-glass Mix task against the same context boundary.

---
*Phase: 13-board-subscription-management*
*Completed: 2026-04-24*
