---
phase: 21-board-directory-facelift
plan: 04
subsystem: ui
tags: [tui, board-list, board-tree, raxol, layout-smoke]

requires:
  - phase: 21-board-directory-facelift
    provides: "21-01 added last_post_at to board directory entries"
  - phase: 21-board-directory-facelift
    provides: "21-03 added BoardTree render/key/focused_board_entry APIs"
provides:
  - "BoardList screen migrated from Display.Tree to BoardTree"
  - "BoardList.State carries board_tree instead of tree"
  - "Screen tests assert glyph-only board rows, TimeAgo ages, and no bracket labels"
  - "Layout smoke coverage enforces BoardList size contract at 64x22, 80x24, and 132x50"
affects: [tui, board-directory, layout-smoke]

tech-stack:
  added: []
  patterns:
    - "Screens consume BoardTree.focused_board_entry/1 instead of matching tree internals"
    - "BoardList layout tests use state.board_list direct render seam"

key-files:
  created:
    - ".planning/phases/21-board-directory-facelift/21-04-SUMMARY.md"
  modified:
    - "lib/foglet_bbs/tui/app.ex"
    - "lib/foglet_bbs/tui/screens/board_list.ex"
    - "lib/foglet_bbs/tui/screens/board_list/state.ex"
    - "test/foglet_bbs/tui/screens/board_list_test.exs"
    - "test/foglet_bbs/tui/layout_smoke_test.exs"

key-decisions:
  - "BoardList row width passes terminal columns minus ScreenFrame overhead to BoardTree."
  - "App boards_loaded state reset now clears board_tree after the State.tree rename."

patterns-established:
  - "BoardList screen stores BoardTree.t in screen-local state and delegates cursor lookup to BoardTree."
  - "BoardList row tests assert glyph semantics and TimeAgo magnitudes without exact age literals."

requirements-completed: [BOARDS-04, BOARDS-01, BOARDS-02]

duration: 65min
completed: 2026-04-25
---

# Phase 21 Plan 04: BoardList BoardTree Migration Summary

**BoardList now renders and navigates through BoardTree with glyph-only row assertions and size-contract layout coverage.**

## Performance

- **Duration:** 65 min
- **Started:** 2026-04-25T21:21:00Z
- **Completed:** 2026-04-25T22:25:57Z
- **Tasks:** 3
- **Files modified:** 5

## Accomplishments

- Migrated `Foglet.TUI.Screens.BoardList` from `Display.Tree` node ownership to `Foglet.TUI.Widgets.List.BoardTree`.
- Renamed screen-local state from `tree` to `board_tree` and routed Enter/s/u focus lookups through `BoardTree.focused_board_entry/1`.
- Updated BoardList tests to assert `⚿`/`✓`/`+`/`◆`, regex age magnitudes, em-dash nil age, and absence of bracket labels.
- Added BoardList layout smoke coverage at `64x22`, `80x24`, and `132x50` with interval overlap checks.

## Task Commits

1. **Task 1: Migrate BoardList screen + State to BoardTree** - `efa5895` (feat)
2. **Task 2: Update BoardList screen tests** - `5e6872d` (test)
3. **Task 3: Add BoardList layout size contract** - `5e6872d` (test)

## Files Created/Modified

- `lib/foglet_bbs/tui/screens/board_list.ex` - delegates tree init/render/key handling and focused board lookup to `BoardTree`.
- `lib/foglet_bbs/tui/screens/board_list/state.ex` - stores `board_tree: BoardTree.t() | nil`.
- `lib/foglet_bbs/tui/app.ex` - clears `board_tree` after async board reload.
- `test/foglet_bbs/tui/screens/board_list_test.exs` - asserts glyph rows, TimeAgo age magnitudes, em-dash nil age, and no bracket labels.
- `test/foglet_bbs/tui/layout_smoke_test.exs` - adds BoardList size contract and extends existing board fixtures with `last_post_at`.
- `.planning/phases/21-board-directory-facelift/21-04-SUMMARY.md` - execution summary.

## Decisions Made

- Passed `row_width(state)` into `BoardTree.render/2` so BoardTree can preserve trailing glyph/unread/age columns within the ScreenFrame body budget.
- Kept the existing feedback flash strings exactly as-is; word-boundary refutes apply to the no-flash row render test only.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Updated App board reload reset after State.tree rename**
- **Found during:** Task 1 verification
- **Issue:** `rtk mix compile --warnings-as-errors` failed because `Foglet.TUI.App.do_update({:boards_loaded, ...})` still updated `%BoardList.State{tree: nil}` after the state field was renamed.
- **Fix:** Changed the reset to `%{board_list_state | board_tree: nil}`.
- **Files modified:** `lib/foglet_bbs/tui/app.ex`
- **Verification:** `rtk mix compile --warnings-as-errors` exits 0.
- **Committed in:** `efa5895`

---

**Total deviations:** 1 auto-fixed Rule 3 blocking issue.
**Impact on plan:** Required for the State.tree -> State.board_tree migration to compile; no behavior beyond clearing the rebuilt BoardTree on reload.

## Issues Encountered

- The isolated worktree initially lacked fetched deps, so `rtk mix format` could not load formatter imports. Ran `rtk mix deps.get`, then formatting/checks succeeded.
- Third-party dependency warnings from `raxol` and related packages appear during compile/test output, but project compile with warnings-as-errors exits 0 after the App state-field fix.

## Verification

- `rtk mix deps.get`
- `rtk mix format lib/foglet_bbs/tui/app.ex lib/foglet_bbs/tui/screens/board_list.ex lib/foglet_bbs/tui/screens/board_list/state.ex test/foglet_bbs/tui/screens/board_list_test.exs test/foglet_bbs/tui/layout_smoke_test.exs`
- `rtk mix compile --warnings-as-errors`
- `rtk mix test test/foglet_bbs/tui/screens/board_list_test.exs test/foglet_bbs/tui/layout_smoke_test.exs`
- `rtk mix test test/foglet_bbs/tui/widgets/list/board_tree_test.exs test/foglet_bbs/tui/screens/board_list_test.exs test/foglet_bbs/tui/layout_smoke_test.exs`
- `rtk mix format --check-formatted`
- `rtk mix credo lib/foglet_bbs/tui/app.ex lib/foglet_bbs/tui/screens/board_list.ex lib/foglet_bbs/tui/screens/board_list/state.ex test/foglet_bbs/tui/screens/board_list_test.exs test/foglet_bbs/tui/layout_smoke_test.exs`

## Known Stubs

None.

## Threat Flags

None.

## User Setup Required

None.

## Next Phase Readiness

BoardList now consumes the BoardTree integration boundary. The orchestrator can merge and run broader validation for the phase.

## Self-Check: PASSED

- Summary file exists.
- Task commits recorded: `efa5895`, `5e6872d`.
- No tracked file deletions in task commits.

---
*Phase: 21-board-directory-facelift*
*Completed: 2026-04-25*
