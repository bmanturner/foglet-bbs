---
phase: 16-unicode-width-foundation
plan: 03
subsystem: ui
tags: [tui, unicode, display-width, chrome, modal, main-menu, exunit]

requires:
  - phase: 16-01
    provides: Foglet.TUI.TextWidth display-width helper
provides:
  - Width-aware Chrome.KeyBar rendering with optional width bounds
  - Display-width-aware modal word wrapping
  - Display-width-aware main-menu oneliner clipping
  - Unicode regression coverage for keybar, modal, and main-menu clipping
affects: [phase-16, chrome, modal, main-menu, unicode-layout]

tech-stack:
  added: []
  patterns:
    - Use Foglet.TUI.TextWidth for terminal display-width-sensitive render paths.
    - Measure flattened widget output with TextWidth.display_width/1 in focused tests.

key-files:
  created:
    - test/foglet_bbs/tui/widgets/chrome/key_bar_test.exs
    - .planning/phases/16-unicode-width-foundation/deferred-items.md
  modified:
    - lib/foglet_bbs/tui/widgets/chrome/key_bar.ex
    - lib/foglet_bbs/tui/widgets/modal.ex
    - lib/foglet_bbs/tui/screens/main_menu.ex
    - test/foglet_bbs/tui/widgets/modal_test.exs
    - test/foglet_bbs/tui/layout_smoke_test.exs

key-decisions:
  - "KeyBar preserves existing render/2 compatibility and adds render/3 width bounds through optional opts."
  - "Modal wrapping keeps whitespace word splitting intact while changing line-fit checks to display columns."
  - "Main-menu oneliner clipping now uses TextWidth.slice_to_width/2 for both handle and body limits."

patterns-established:
  - "Chrome, modal, and menu display paths use TextWidth instead of direct grapheme or String.length width assumptions."
  - "Unicode smoke tests assert display-width bounds with CJK, combining marks, and milestone glyphs."

requirements-completed: [WIDTH-02, WIDTH-03, WIDTH-04, WIDTH-05]

duration: 18min
completed: 2026-04-25
---

# Phase 16 Plan 03: Chrome, Modal, and Menu Width Migration Summary

**Chrome key hints, modal wrapping, and main-menu oneliner clipping now share Foglet.TUI.TextWidth for Unicode-safe terminal display bounds.**

## Performance

- **Duration:** 18 min
- **Started:** 2026-04-25T13:53:24Z
- **Completed:** 2026-04-25T14:11:32Z
- **Tasks:** 3
- **Files modified:** 7

## Accomplishments

- Added `Chrome.KeyBar` Unicode width tests for ASCII, CJK, combining marks, and milestone glyphs at 64 and 80 columns.
- Added modal Unicode wrapping coverage and converted modal line-fit assertions from `String.length/1` to `TextWidth.display_width/1`.
- Migrated `Chrome.KeyBar`, `Modal.word_wrap/2`, and `MainMenu.clip/2` to consume `Foglet.TUI.TextWidth`.
- Updated layout smoke coverage so the main-menu oneliner row stays within the display-width budget for wide Unicode handles and bodies.

## Task Commits

Each task was committed atomically:

1. **Task 1: Add keybar and modal Unicode width tests** - `28ea078` (test)
2. **Task 2: Migrate Chrome.KeyBar and Modal.word_wrap to TextWidth** - `01e7ab3` (feat)
3. **Task 3 RED: Add main-menu Unicode clipping test** - `1d59146` (test)
4. **Task 3 GREEN: Migrate main-menu clipping to TextWidth** - `7f1dc78` (feat)
5. **Task 2 cleanup: Order modal width test aliases** - `d770f95` (style)

## Files Created/Modified

- `test/foglet_bbs/tui/widgets/chrome/key_bar_test.exs` - New display-width contracts for keybar rendering.
- `test/foglet_bbs/tui/widgets/modal_test.exs` - Modal wrapping assertions now use `TextWidth.display_width/1` and cover Unicode.
- `test/foglet_bbs/tui/layout_smoke_test.exs` - Main-menu Unicode oneliner clipping smoke coverage and current board-list fixture shape.
- `lib/foglet_bbs/tui/widgets/chrome/key_bar.ex` - Width-aware optional render path using `TextWidth`.
- `lib/foglet_bbs/tui/widgets/modal.ex` - Word wrapping checks terminal display width.
- `lib/foglet_bbs/tui/screens/main_menu.ex` - Oneliner clipping uses `TextWidth.slice_to_width/2`.
- `.planning/phases/16-unicode-width-foundation/deferred-items.md` - Out-of-scope precommit blockers discovered during execution.

## Decisions Made

- Keep `KeyBar.render(theme, keys)` behavior compatible by adding `opts \\ []` instead of changing call sites.
- Truncate keybar descriptions before key labels, and preserve leftmost hints before lower-priority rightmost descriptions.
- Keep modal long-word behavior unchanged; the migration only changes line-fit measurement to display width.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Updated layout smoke harness drift**
- **Found during:** Task 3 (Migrate main-menu clipping to TextWidth)
- **Issue:** The required focused command included `layout_smoke_test.exs`, which had stale assumptions: it used `ExUnit.Case` despite render paths reading DB-backed config, and the board-list fixture no longer matched the category-tree board directory shape.
- **Fix:** Switched the smoke test module to `FogletBbs.DataCase, async: false` and updated the board-list fixture to the current category/board entry shape.
- **Files modified:** `test/foglet_bbs/tui/layout_smoke_test.exs`
- **Verification:** `rtk mix test test/foglet_bbs/tui/widgets/chrome/key_bar_test.exs test/foglet_bbs/tui/widgets/modal_test.exs test/foglet_bbs/tui/layout_smoke_test.exs`
- **Committed in:** `7f1dc78`

---

**Total deviations:** 1 auto-fixed blocking test harness issue
**Impact on plan:** Required for the plan's mandated verification command. Runtime scope stayed limited to main-menu clipping.

## Issues Encountered

- `rtk mix precommit` still fails on pre-existing Credo findings outside 16-03 scope:
  - `lib/foglet_bbs/tui/widgets/list/list_row.ex` alias ordering.
  - `test/foglet_bbs/tui/widgets/list/list_row_test.exs` alias ordering.
  - `lib/foglet_bbs/tui/text_width.ex` single-condition `cond` refactor suggestion.
- Vendored Raxol emitted existing compile warnings during test/precommit runs.

## Known Stubs

None. Stub-pattern scan hits were existing test placeholders or intentional empty-string control flow, not unimplemented UI data paths.

## User Setup Required

None - no external service configuration required.

## Verification

- `rtk mix test test/foglet_bbs/tui/widgets/chrome/key_bar_test.exs test/foglet_bbs/tui/widgets/modal_test.exs test/foglet_bbs/tui/layout_smoke_test.exs` - 35 tests, 0 failures
- `rtk mix precommit` - failed on pre-existing Credo findings listed in Issues Encountered.

## Next Phase Readiness

Chrome footer hints, modal body wrapping, and main-menu oneliner rows are ready for later Unicode-heavy facelift work. Remaining precommit cleanup belongs to prior helper/list-row scope or a dedicated cleanup pass.

## Self-Check: PASSED

- Found `lib/foglet_bbs/tui/widgets/chrome/key_bar.ex`
- Found `lib/foglet_bbs/tui/widgets/modal.ex`
- Found `lib/foglet_bbs/tui/screens/main_menu.ex`
- Found `test/foglet_bbs/tui/widgets/chrome/key_bar_test.exs`
- Found `test/foglet_bbs/tui/widgets/modal_test.exs`
- Found `test/foglet_bbs/tui/layout_smoke_test.exs`
- Found `.planning/phases/16-unicode-width-foundation/16-03-SUMMARY.md`
- Found commits `28ea078`, `01e7ab3`, `1d59146`, `7f1dc78`, and `d770f95`

---
*Phase: 16-unicode-width-foundation*
*Completed: 2026-04-25*
