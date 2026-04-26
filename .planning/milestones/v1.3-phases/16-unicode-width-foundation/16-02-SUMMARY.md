---
phase: 16-unicode-width-foundation
plan: 02
subsystem: ui
tags: [tui, unicode, display-width, list-row, raxol, exunit]

requires:
  - phase: 16-01
    provides: Foglet.TUI.TextWidth shared display-width helper
provides:
  - Width-aware ListRow metadata layout using Foglet.TUI.TextWidth
  - Unicode row-width regression coverage for accented Latin, combining marks, CJK, and milestone glyphs
  - ASCII ListRow compatibility assertions measured by terminal display width
affects: [phase-16, tui-widgets, list-row, unicode-layout]

tech-stack:
  added: []
  patterns:
    - Display-width row layout delegates measurement, truncation, and padding to Foglet.TUI.TextWidth
    - Metadata-priority rows preserve right metadata and truncate titles first

key-files:
  created:
    - .planning/phases/16-unicode-width-foundation/16-02-SUMMARY.md
  modified:
    - lib/foglet_bbs/tui/widgets/list/list_row.ex
    - test/foglet_bbs/tui/widgets/list/list_row_test.exs

key-decisions:
  - "Use Foglet.TUI.TextWidth for all ListRow.render_with_metadata/6 layout-sensitive width math."
  - "Keep the existing metadata-priority contract: metadata remains visible and title text truncates first."
  - "Preserve compact ASCII truncation behavior for tight rows while measuring by terminal columns."

patterns-established:
  - "ListRow display-width migration: marker, title, metadata, padding, and truncation are computed in terminal columns."
  - "Widget row-width tests should assert Foglet.TUI.TextWidth.display_width/1 for layout-sensitive flattened output."

requirements-completed: [WIDTH-02, WIDTH-03, WIDTH-04]

duration: 4min
completed: 2026-04-25
---

# Phase 16 Plan 02: ListRow Width Migration Summary

**ListRow metadata rows now align by terminal display columns while preserving right-side metadata and existing ASCII row behavior.**

## Performance

- **Duration:** 4 min
- **Started:** 2026-04-25T13:52:47Z
- **Completed:** 2026-04-25T13:56:37Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments

- Migrated `ListRow.render_with_metadata/6` layout math to `Foglet.TUI.TextWidth`.
- Added row-width tests for `café`, `cafe\u0301`, CJK text, and milestone glyphs `●`, `◆`, `▸`, `▾`, `✓`, `×`.
- Converted layout-sensitive row assertions from grapheme length to display width while retaining exact ASCII compatibility checks.

## Task Commits

Each task was committed atomically:

1. **Task 1: Add Unicode row-width assertions while preserving ASCII baselines** - `f27ddec` (test)
2. **Task 2: Migrate ListRow metadata layout math to TextWidth** - `b6cb929` (feat)

## Files Created/Modified

- `lib/foglet_bbs/tui/widgets/list/list_row.ex` - Uses `TextWidth.display_width/1`, `TextWidth.truncate/2`, and `TextWidth.pad_trailing/2` for metadata row layout.
- `test/foglet_bbs/tui/widgets/list/list_row_test.exs` - Adds display-width assertions and Unicode row fixtures.
- `.planning/phases/16-unicode-width-foundation/16-02-SUMMARY.md` - Execution summary for this plan.

## Decisions Made

- Kept `render/3` unchanged because the plan only targeted metadata row layout.
- Preserved the metadata-priority contract: metadata remains fully visible, padding clamps to zero when necessary, and title truncation absorbs width pressure first.
- Used `TextWidth.truncate/2` for wide-title truncation and a compact two-column fallback for tight rows to keep ASCII-heavy behavior stable.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

- The RED test run failed as expected before production migration: the CJK metadata row rendered one display column wider than the requested width under the old grapheme-count math.
- Vendored Raxol emitted existing compile warnings during focused test runs. They were unrelated to this plan and did not block verification.

## Known Stubs

None.

## Threat Flags

None - this plan changed display-only TUI row rendering and did not introduce new network endpoints, auth paths, file access, schema changes, or trust-boundary expansion beyond the planned row rendering boundary.

## User Setup Required

None - no external service configuration required.

## Verification

- `rtk mix test test/foglet_bbs/tui/widgets/list/list_row_test.exs` - 19 tests, 0 failures
- `rg -n "TextWidth\\.display_width|cafe\\\\u0301|漢字|●|◆|▸|▾|✓|×" test/foglet_bbs/tui/widgets/list/list_row_test.exs` - matched required coverage
- `rg -n "String\\.length\\(flat\\)" test/foglet_bbs/tui/widgets/list/list_row_test.exs` - no matches
- `rg -n "TextWidth\\." lib/foglet_bbs/tui/widgets/list/list_row.ex` - matched migrated layout math
- `rg -n "String\\.length\\(|String\\.slice\\(|String\\.pad_" lib/foglet_bbs/tui/widgets/list/list_row.ex` - no matches

## Orchestrator Notes

Per execution instructions, this executor did not update `.planning/STATE.md`, `.planning/ROADMAP.md`, or `.planning/REQUIREMENTS.md`; the orchestrator owns shared tracking after wave execution.

## Next Phase Readiness

`ListRow.render_with_metadata/6` is ready for Unicode-heavy row titles and metadata in later facelift plans. The `TextWidth` helper pattern is now proven in a real widget path.

## Self-Check: PASSED

- Found `lib/foglet_bbs/tui/widgets/list/list_row.ex`
- Found `test/foglet_bbs/tui/widgets/list/list_row_test.exs`
- Found `.planning/phases/16-unicode-width-foundation/16-02-SUMMARY.md`
- Found task commits `f27ddec` and `b6cb929`

---
*Phase: 16-unicode-width-foundation*
*Completed: 2026-04-25*
