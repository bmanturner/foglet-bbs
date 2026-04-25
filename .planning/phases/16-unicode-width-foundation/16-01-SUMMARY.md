---
phase: 16-unicode-width-foundation
plan: 01
subsystem: ui
tags: [tui, unicode, display-width, raxol, exunit]

requires: []
provides:
  - Foglet-owned TUI display-width helper wrapping Raxol text measurement
  - Helper coverage for ASCII, accented Latin, combining marks, CJK, and milestone glyphs
affects: [phase-16, tui-widgets, unicode-layout, raxol]

tech-stack:
  added: []
  patterns:
    - Thin Foglet.TUI.TextWidth facade over Raxol.UI.TextMeasure
    - Display-only truncation, padding, and slicing kept separate from product validation

key-files:
  created:
    - lib/foglet_bbs/tui/text_width.ex
    - test/foglet_bbs/tui/text_width_test.exs
  modified: []

key-decisions:
  - "Use Raxol.UI.TextMeasure as the display-width source of truth behind a Foglet-owned API."
  - "Repair split results to grapheme boundaries after Raxol splitting so combining marks are not separated from their base character."
  - "Document TextWidth as terminal layout infrastructure, not product validation or authorization policy."

patterns-established:
  - "TextWidth facade: Foglet TUI layout code should call Foglet.TUI.TextWidth instead of direct Raxol or String width operations."
  - "Raxol-anchored glyph tests: milestone glyph widths are asserted against Raxol's current model."

requirements-completed: [WIDTH-01, WIDTH-03]

duration: 3min
completed: 2026-04-25
---

# Phase 16 Plan 01: Text Width Helper Summary

**Foglet.TUI.TextWidth now centralizes terminal display-width measurement, display-width splitting, truncation, slicing, and padding on top of Raxol.**

## Performance

- **Duration:** 3 min
- **Started:** 2026-04-25T13:46:48Z
- **Completed:** 2026-04-25T13:50:00Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments

- Added `Foglet.TUI.TextWidth` with `display_width/1`, `split_at/2`, `slice_to_width/2`, `truncate/2`, `truncate/3`, `pad_trailing/2`, and `pad_leading/2`.
- Locked helper behavior for ASCII, accented Latin, combining marks, CJK, and glyphs `●`, `◆`, `▸`, `▾`, `✓`, `×`.
- Preserved the Phase 16 boundary between terminal display layout and character-count product validation.

## Task Commits

Each task was committed atomically:

1. **Task 1: Create TextWidth helper tests before implementation** - `2718957` (test)
2. **Task 2: Implement Foglet.TUI.TextWidth as thin Raxol wrapper** - `88c1190` (feat)

## Files Created/Modified

- `lib/foglet_bbs/tui/text_width.ex` - Foglet-owned display-width API over Raxol measurement and split primitives.
- `test/foglet_bbs/tui/text_width_test.exs` - Helper regression tests for required Unicode classes and convenience functions.

## Decisions Made

- Raxol remains the primitive source for display-width measurement and initial display-width splitting.
- Foglet repairs split output to grapheme boundaries when needed, because the required combining-mark behavior must not separate a combining mark from its base character.
- Empty output for non-positive truncation widths is intentional so tiny terminal widths do not crash render paths.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Repaired Raxol split output at combining-mark boundaries**
- **Found during:** Task 2 (Implement Foglet.TUI.TextWidth as thin Raxol wrapper)
- **Issue:** `Raxol.UI.TextMeasure.split_at_display_width/2` returned `{"cafe", "́"}` for `"cafe\u0301"` at width 4, leaving the combining mark detached.
- **Fix:** `Foglet.TUI.TextWidth.split_at/2` still calls Raxol's split primitive first, then adjusts the result to the nearest valid grapheme boundary that fits the requested display width.
- **Files modified:** `lib/foglet_bbs/tui/text_width.ex`
- **Verification:** `rtk mix test test/foglet_bbs/tui/text_width_test.exs`
- **Committed in:** `88c1190`

---

**Total deviations:** 1 auto-fixed bug
**Impact on plan:** Required for WIDTH-03 correctness. Scope stayed within the helper contract.

## Issues Encountered

- Vendored Raxol emitted existing compile warnings during test runs. They were unrelated to this plan and did not block the focused helper tests.

## Known Stubs

None.

## User Setup Required

None - no external service configuration required.

## Verification

- `rtk mix test test/foglet_bbs/tui/text_width_test.exs` - 17 tests, 0 failures

## Next Phase Readiness

The shared width helper is ready for later Phase 16 plans to migrate row, chrome, modal, clipping, and composer paths without duplicating Unicode width logic.

## Self-Check: PASSED

- Found `lib/foglet_bbs/tui/text_width.ex`
- Found `test/foglet_bbs/tui/text_width_test.exs`
- Found `.planning/phases/16-unicode-width-foundation/16-01-SUMMARY.md`
- Found task commits `2718957` and `88c1190`

---
*Phase: 16-unicode-width-foundation*
*Completed: 2026-04-25*
