---
phase: 26-layout-width-foundations
plan: 01
subsystem: ui
tags: [tui, width, widgets, elixir, raxol]

requires: []
provides:
  - Grapheme-aware `Foglet.TUI.TextWidth.wrap/2`
  - Drawable-width-aware `Display.Table` column resolution
  - `ConsoleTable` width forwarding for compact operator tables
affects: [phase-26, phase-29, phase-31, phase-33, tui-width]

tech-stack:
  added: []
  patterns:
    - Resolve table widths at widget initialization from drawable content width.
    - Truncate table cells and headers with `TextWidth.truncate/2` at cell boundaries.

key-files:
  created:
    - .planning/phases/26-layout-width-foundations/26-01-SUMMARY.md
  modified:
    - lib/foglet_bbs/tui/text_width.ex
    - lib/foglet_bbs/tui/widgets/display/table.ex
    - lib/foglet_bbs/tui/widgets/display/console_table.ex
    - test/foglet_bbs/tui/text_width_test.exs
    - test/foglet_bbs/tui/widgets/display/table_test.exs
    - test/foglet_bbs/tui/widgets/display/console_table_test.exs

key-decisions:
  - "Table width budgets are treated as drawable content widths; callers must subtract screen frame borders before passing `:width`."
  - "Foglet resolves table column widths before Raxol rendering because Raxol adds separator padding per cell."
  - "No-space wrapping and table elision use `TextWidth` grapheme-aware helpers rather than byte or character slicing."

patterns-established:
  - "Width-aware table state stores `available_width` and normalized Raxol columns."
  - "ConsoleTable remains a facade and forwards width/page options into Display.Table."

requirements-completed:
  - LAYOUT-04
  - LAYOUT-05
  - LAYOUT-06

duration: 9min
completed: 2026-04-26
---

# Phase 26 Plan 01: Width Table Primitives Summary

**Grapheme-aware wrapping plus drawable-width table sizing for compact TUI layouts**

## Performance

- **Duration:** 9 min
- **Started:** 2026-04-26T21:44:57Z
- **Completed:** 2026-04-26T21:53:40Z
- **Tasks:** 2
- **Files modified:** 6 implementation/test files, plus this summary

## Accomplishments

- Added `Foglet.TUI.TextWidth.wrap/2` with newline preservation, word-boundary wrapping, no-space splitting, and grapheme-cluster safety.
- Added width-aware `Display.Table` initialization for fixed, `:auto`, and `{:ratio, n}` columns against drawable content width.
- Added table and console-table tests for 64-column framed width, compact invite headers, ellipsis rendering, and grapheme wrapping cases.

## Task Commits

1. **Task 1: Add grapheme-aware TextWidth.wrap/2** - `7dd1742` (feat)
2. **Task 2: Add width-aware table and ConsoleTable rendering contracts** - `644769b` (feat)

## Files Created/Modified

- `lib/foglet_bbs/tui/text_width.ex` - Adds reusable visual wrapping helper built on existing display-width primitives.
- `lib/foglet_bbs/tui/widgets/display/table.ex` - Resolves drawable-width column budgets and truncates headers/cells at cell boundaries.
- `lib/foglet_bbs/tui/widgets/display/console_table.ex` - Accepts and forwards `:width` to `Display.Table`.
- `test/foglet_bbs/tui/text_width_test.exs` - Covers ASCII, CJK, combining marks, ZWJ emoji, newlines, empty inputs, and ssh-rsa-shaped blobs.
- `test/foglet_bbs/tui/widgets/display/table_test.exs` - Covers compact width resolution, framed width budgets, page size, and ellipsis.
- `test/foglet_bbs/tui/widgets/display/console_table_test.exs` - Covers compact invite columns and width forwarding through the facade.

## Decisions Made

- Treat `:width` as caller-provided drawable content width, not raw terminal columns.
- Account for Raxol's per-cell padding when resolving Foglet table widths, so table lines fit the provided budget.
- Preserve current default table behavior when no width is supplied; width-aware truncation only activates for explicit budgets.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed wrapping reducer ordering and trailing separator handling**
- **Found during:** Task 1 verification
- **Issue:** Early wrapping output could reverse no-space chunks and retain trailing separator whitespace at wrap boundaries.
- **Fix:** Reworked wrapping state to preserve render order and trim line-ending whitespace when a line is completed.
- **Files modified:** `lib/foglet_bbs/tui/text_width.ex`, `test/foglet_bbs/tui/text_width_test.exs`
- **Verification:** `rtk mix test test/foglet_bbs/tui/text_width_test.exs`
- **Committed in:** `7dd1742`

**2. [Rule 1 - Bug] Preserved default ConsoleTable behavior without explicit width**
- **Found during:** Task 2 verification
- **Issue:** Width-normalized row truncation initially applied even when no width budget was supplied, changing existing default fixture output.
- **Fix:** Limited row truncation to explicit positive width budgets.
- **Files modified:** `lib/foglet_bbs/tui/widgets/display/table.ex`
- **Verification:** `rtk mix test test/foglet_bbs/tui/widgets/display/table_test.exs test/foglet_bbs/tui/widgets/display/console_table_test.exs`
- **Committed in:** `644769b`

**3. [Rule 3 - Blocking] Fixed Credo alias ordering before precommit**
- **Found during:** Plan-level `rtk mix precommit`
- **Issue:** Credo failed on alias ordering in the table module and table test.
- **Fix:** Reordered aliases alphabetically and amended the Task 2 commit.
- **Files modified:** `lib/foglet_bbs/tui/widgets/display/table.ex`, `test/foglet_bbs/tui/widgets/display/table_test.exs`
- **Verification:** `rtk mix precommit`
- **Committed in:** `644769b`

---

**Total deviations:** 3 auto-fixed (2 bugs, 1 blocking quality gate)
**Impact on plan:** All fixes were scoped to planned files and necessary for correctness or required verification. No architectural changes.

## Issues Encountered

- Raxol table headers do not pad labels the same way row cells are padded, so Foglet now pads resolved header labels enough to keep compact headers visibly separated while staying within the drawable table budget.

## Known Stubs

None.

## Threat Flags

None. This plan changed presentation-only TUI helpers and introduced no new network endpoints, auth paths, file access, persistence writes, or trust-boundary schema changes.

## Verification

- `rtk mix test test/foglet_bbs/tui/text_width_test.exs` - passed, 24 tests.
- `rtk mix test test/foglet_bbs/tui/widgets/display/table_test.exs test/foglet_bbs/tui/widgets/display/console_table_test.exs` - passed, 28 tests.
- `rtk mix test test/foglet_bbs/tui/text_width_test.exs test/foglet_bbs/tui/widgets/display/table_test.exs test/foglet_bbs/tui/widgets/display/console_table_test.exs` - passed, 52 tests.
- `rtk mix precommit` - passed successfully.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

Phase 26 follow-up plans can now consume `TextWidth.wrap/2` and the explicit width contracts in `Display.Table`/`ConsoleTable`. Downstream screen work still needs to pass drawable frame widths instead of raw terminal column counts.

## Self-Check: PASSED

- Found `.planning/phases/26-layout-width-foundations/26-01-SUMMARY.md`.
- Found task commit `7dd1742`.
- Found task commit `644769b`.

---
*Phase: 26-layout-width-foundations*
*Completed: 2026-04-26*
