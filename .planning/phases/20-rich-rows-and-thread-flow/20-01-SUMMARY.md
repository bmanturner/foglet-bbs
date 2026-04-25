---
phase: 20-rich-rows-and-thread-flow
plan: 01
subsystem: tui
tags: [tui, widget, test-scaffold, rich-row]
requires: []
provides:
  - RichRow widget contract tests for selection, glyphs, metadata, width, and theme routing
affects: [20-rich-rows-and-thread-flow, rich-row, thread-list]
tech-stack:
  added: []
  patterns:
    - Widget contract tests using Foglet.TUI.WidgetHelpers
key-files:
  created:
    - test/foglet_bbs/tui/widgets/list/rich_row_test.exs
  modified: []
key-decisions:
  - "RichRow contract keeps the state cluster fixed at four cells: unread, sticky, locked, separator."
  - "Unknown state atoms render as whitespace so later phases can reuse the API without domain coupling."
patterns-established:
  - "RichRow tests assert style runs through helper-level text run inspection instead of serialized tree shape."
requirements-completed: [RICHROW-01, THREADS-02]
duration: 15min
completed: 2026-04-25
---

# Phase 20 Plan 01: RichRow Test Scaffold Summary

**RichRow RED contract covering state glyphs, selection precedence, optional metadata, width math, and theme hygiene**

## Performance

- **Duration:** 15min
- **Started:** 2026-04-25T20:49:00Z
- **Completed:** 2026-04-25T20:54:11Z
- **Tasks:** 1
- **Files modified:** 1

## Accomplishments

- Added `Foglet.TUI.Widgets.List.RichRowTest` with 25 focused assertions.
- Covered the selected/unselected state-glyph matrix, generic state atoms, cluster width, glyph identity, optional metadata, and no hardcoded color atom leakage.
- Included the selection-vs-state-glyph precedence checks so selected rows keep selected background while glyph foregrounds still route through semantic theme slots.

## Task Commits

1. **Task 1: Create rich_row_test.exs scaffold with full RED matrix** - `247c262` (test)

## Files Created/Modified

- `test/foglet_bbs/tui/widgets/list/rich_row_test.exs` - RichRow public contract and acceptance matrix.

## Decisions Made

- Corrected the 20-cell width fixture to use `width: 30`, which gives the title exactly 20 cells after the focus marker, four-cell cluster, two-cell gap, and `@a` metadata.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed internally inconsistent minimum-title fixture**
- **Found during:** Task 1 targeted verification
- **Issue:** The scaffold used `width: 35` while expecting a 20-cell truncation. That width leaves a 25-cell title budget under the RichRow contract.
- **Fix:** Changed the fixture to `width: 30` and updated the width assertion to match.
- **Files modified:** `test/foglet_bbs/tui/widgets/list/rich_row_test.exs`
- **Verification:** `rtk mix test test/foglet_bbs/tui/widgets/list/rich_row_test.exs`
- **Committed in:** `247c262`

**Total deviations:** 1 auto-fixed Rule 1 issue.
**Impact on plan:** The contract remains the same; the fixture now exercises the intended 20-cell budget.

## Issues Encountered

- `rtk mix precommit` is blocked by out-of-scope Credo findings in `test/foglet_bbs/tui/screens/thread_list_test.exs` and `lib/foglet_bbs/tui/screens/main_menu.ex`. Those files were outside this executor's ownership boundary and were not modified.

## Known Stubs

None.

## User Setup Required

None.

## Next Phase Readiness

Plan 20-04 can use this scaffold as the GREEN target for the stateless `RichRow` widget implementation.

## Self-Check: PASSED

- Verified file exists: `test/foglet_bbs/tui/widgets/list/rich_row_test.exs`
- Verified task commit exists: `247c262`
- Verified targeted tests pass after Plan 20-04 implementation: `25 tests, 0 failures`

---
*Phase: 20-rich-rows-and-thread-flow*
*Completed: 2026-04-25*
