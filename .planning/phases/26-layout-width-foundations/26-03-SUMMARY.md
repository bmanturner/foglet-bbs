---
phase: 26-layout-width-foundations
plan: 03
subsystem: ui
tags: [tui, boards, viewport, width, elixir, raxol]

requires:
  - phase: 26-layout-width-foundations
    provides: [drawable width contracts, compact layout smoke patterns]
provides:
  - BoardTree visible-height windowing that preserves cursor ownership
  - Compact Boards screen body budgeting for 64x22 frames
  - Overlarge Boards directory smoke coverage for height and width bounds
affects: [phase-26, phase-33, boards-screen, tui-width]

tech-stack:
  added: []
  patterns:
    - Treat BoardTree visible height as a logical row window over Raxol visible nodes.
    - Convert compact screen row budgets to BoardTree logical rows before rendering.
    - Keep Boards row width as drawable inner-frame width, not raw terminal columns.

key-files:
  created:
    - .planning/phases/26-layout-width-foundations/26-03-SUMMARY.md
  modified:
    - lib/foglet_bbs/tui/widgets/list/board_tree.ex
    - lib/foglet_bbs/tui/screens/board_list.ex
    - test/foglet_bbs/tui/widgets/list/board_tree_test.exs
    - test/foglet_bbs/tui/screens/board_list_test.exs
    - test/foglet_bbs/tui/layout_smoke_test.exs

key-decisions:
  - "BoardTree windowing derives the focused row from Raxol tree cursor and visible nodes without mutating tree state."
  - "Boards screen passes drawable content width and a compact logical tree-row budget into BoardTree."
  - "Compact Boards rendering reserves detail/feedback/inspector rows only when they fit, with the tree winning at small heights."

patterns-established:
  - "Screen body budgets subtract frame rows before allocating reusable widget viewports."
  - "Widgets own cursor state; screens pass viewport constraints without introducing parallel selected indexes."

requirements-completed:
  - LAYOUT-03

duration: 6min
completed: 2026-04-26
---

# Phase 26 Plan 03: Boards Viewport Summary

**Cursor-preserving BoardTree windowing plus compact 64x22 Boards screen budgeting**

## Performance

- **Duration:** 6 min
- **Started:** 2026-04-26T22:14:37Z
- **Completed:** 2026-04-26T22:20:15Z
- **Tasks:** 2
- **Files modified:** 5 implementation/test files, plus this summary

## Accomplishments

- Added `visible_height:` support to `BoardTree.render/2`, preserving default full-tree rendering when omitted or set to `:all`.
- Added compact Boards screen body budgeting that passes drawable width and visible tree height into `BoardTree`.
- Added widget, screen, and layout smoke tests proving overlarge directories stay bounded and focused rows remain reachable.

## Task Commits

1. **Task 1: Add BoardTree visible-height windowing** - `d863084` (feat)
2. **Task 2: Apply compact Boards screen body budgeting** - `2944f95` (feat)

## Files Created/Modified

- `lib/foglet_bbs/tui/widgets/list/board_tree.ex` - Adds render-only visible-window slicing over `RaxolTree.visible_nodes/1`.
- `lib/foglet_bbs/tui/screens/board_list.ex` - Budgets compact body rows, forwards `visible_height:`, and keeps width as drawable content width.
- `test/foglet_bbs/tui/widgets/list/board_tree_test.exs` - Covers large trees, bounded rendered rows, and focused row visibility after navigation.
- `test/foglet_bbs/tui/screens/board_list_test.exs` - Covers overlarge compact directories and continued keyboard reachability.
- `test/foglet_bbs/tui/layout_smoke_test.exs` - Covers 64x22 overlarge Boards frame height and width bounds.

## Decisions Made

- Kept cursor/selection ownership entirely inside `BoardTree` and the underlying Raxol tree state.
- Treated `visible_height:` as logical tree rows, then converted screen body-row budgets to that logical row count because BoardTree uses newline separator elements between rows.
- Continued passing `row_width(state)` as `cols - 4`, matching the drawable inner-frame width contract established earlier in Phase 26.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Converted compact screen row budget to logical BoardTree rows**
- **Found during:** Task 2 verification
- **Issue:** Passing the raw compact body-row budget to `BoardTree.visible_height:` overflowed the 64x22 layout because BoardTree renders newline separator elements between logical rows.
- **Fix:** Added `visible_tree_rows/1` so Boards converts body rows to the logical BoardTree row count before rendering.
- **Files modified:** `lib/foglet_bbs/tui/screens/board_list.ex`, `test/foglet_bbs/tui/layout_smoke_test.exs`
- **Verification:** `rtk mix test test/foglet_bbs/tui/screens/board_list_test.exs test/foglet_bbs/tui/layout_smoke_test.exs`
- **Committed in:** `2944f95`

---

**Total deviations:** 1 auto-fixed bug.
**Impact on plan:** The fix was required for the planned 64x22 frame-bound guarantee. No architectural changes.

## Issues Encountered

- `rtk mix precommit` failed in Dialyzer on out-of-scope files also reported by Plan 02: `lib/foglet_bbs/mix_task_helpers.ex`, login/register/verify state specs, `lib/mix/tasks/foglet.board_subscriptions.ex`, and `lib/mix/tasks/foglet.user.status.ex`. Compile, Credo, and Sobelow completed before the Dialyzer failure.
- Unrelated worktree changes in `lib/foglet_bbs/tui/screens/login.ex`, `lib/mix/tasks/foglet.board_subscriptions.ex`, `.claude/worktrees/`, and `REFACTORING.md` were left unstaged.

## Known Stubs

None introduced by this plan. Stub-scan matches in `layout_smoke_test.exs` are existing login/composer placeholder fixtures outside this plan's Boards scope.

## Threat Flags

None. This plan changed presentation-only TUI rendering and introduced no network endpoints, auth paths, file access, persistence writes, or trust-boundary schema changes.

## Verification

- `rtk mix test test/foglet_bbs/tui/widgets/list/board_tree_test.exs` - passed, 31 tests.
- `rtk mix test test/foglet_bbs/tui/screens/board_list_test.exs` - passed, 18 tests.
- `rtk mix test test/foglet_bbs/tui/layout_smoke_test.exs` - passed, 58 tests.
- `rtk mix test test/foglet_bbs/tui/screens/board_list_test.exs test/foglet_bbs/tui/layout_smoke_test.exs` - passed, 76 tests.
- `rtk mix precommit` - failed in Dialyzer on out-of-scope files after compile, Credo, and Sobelow; see Issues Encountered.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

Phase 33 can build category Enter behavior on top of the existing BoardTree cursor ownership. Future Boards work should keep `width:` drawable and `visible_height:` logical.

## Self-Check: PASSED

- Found `.planning/phases/26-layout-width-foundations/26-03-SUMMARY.md`.
- Found task commit `d863084`.
- Found task commit `2944f95`.

---
*Phase: 26-layout-width-foundations*
*Completed: 2026-04-26*
