---
phase: 16-unicode-width-foundation
plan: 04
subsystem: ui
tags: [tui, unicode, display-width, compose, layout-smoke, exunit]

requires:
  - phase: 16-01
    provides: Foglet.TUI.TextWidth shared display-width helper
  - phase: 16-02
    provides: Width-aware ListRow metadata layout
  - phase: 16-03
    provides: Width-aware keybar, modal, and main-menu clipping paths
provides:
  - Width-aware composer cursor insertion using Foglet.TUI.TextWidth.split_at/2
  - Representative 64x22, 80x24, and 132x50 size-contract tests
  - Source scan documenting migrated layout paths and character-count boundaries
affects: [phase-16, tui-widgets, compose, layout-smoke, unicode-layout]

tech-stack:
  added: []
  patterns:
    - Composer cursor display splits by terminal display width, not grapheme index.
    - Size-contract tests flatten representative widget render trees and assert TextWidth.display_width/1.
    - Product counters and limits remain documented character-count policies.

key-files:
  created:
    - .planning/phases/16-unicode-width-foundation/16-WIDTH-SCAN.md
    - .planning/phases/16-unicode-width-foundation/16-04-SUMMARY.md
  modified:
    - lib/foglet_bbs/tui/widgets/compose.ex
    - test/foglet_bbs/tui/widgets/compose_test.exs
    - test/foglet_bbs/tui/layout_smoke_test.exs

key-decisions:
  - "Use Foglet.TUI.TextWidth.split_at/2 for Compose.render_input/4 cursor insertion."
  - "Keep Raxol's current milestone-glyph display-width model as the Phase 16 test oracle."
  - "Document PostComposer and NewThread length counters as character-count policy, not terminal layout width."

requirements-completed: [WIDTH-02, WIDTH-03, WIDTH-04, WIDTH-05]

duration: 14min
completed: 2026-04-25
---

# Phase 16 Plan 04: Composer and Width Scan Summary

**Composer cursor rendering now uses terminal display-width splitting, with multi-size layout contracts and an explicit scan boundary between display width and product character counts.**

## Performance

- **Duration:** 14 min
- **Completed:** 2026-04-25
- **Tasks:** 3
- **Files modified:** 5

## Accomplishments

- Migrated `Compose.render_input/4` from `String.split_at/2` to `Foglet.TUI.TextWidth.split_at/2`.
- Added composer cursor coverage for ASCII, CJK, combining marks, and `● ◆ ▸ ▾ ✓ ×`.
- Added representative size-contract coverage for row, keybar, modal, and compose paths at `{64, 22}`, `{80, 24}`, and `{132, 50}`.
- Created `16-WIDTH-SCAN.md` documenting migrated layout paths and intentional character-count boundaries in `PostComposer` and `NewThread`.

## Task Commits

1. **Task 1 RED: Add composer Unicode cursor coverage** - `742fa91` (test)
2. **Task 1 GREEN: Render composer cursor by display width** - `56b4dc3` (feat)
3. **Task 2: Add Unicode size contracts** - `fba7981` (test)
4. **Task 3: Document Unicode width scan** - `d2d85f2` (docs)

## Files Created/Modified

- `lib/foglet_bbs/tui/widgets/compose.ex` - Composer cursor insertion now calls `TextWidth.split_at/2`.
- `test/foglet_bbs/tui/widgets/compose_test.exs` - Added render-tree flattening and Unicode cursor assertions.
- `test/foglet_bbs/tui/layout_smoke_test.exs` - Added Phase 16 representative size-contract tests.
- `.planning/phases/16-unicode-width-foundation/16-WIDTH-SCAN.md` - Recorded source scan, migrated paths, and character-count boundaries.
- `.planning/phases/16-unicode-width-foundation/16-04-SUMMARY.md` - Execution summary.

## Decisions Made

- Kept `Compose.translate_key/1`, placeholder behavior, and caller-owned editor sizing unchanged.
- Treated the initial Task 2 pass as expected because previous Phase 16 plans had already migrated row, keybar, modal, and main-menu paths; Task 2 was coverage hardening.
- Left pre-existing Credo findings outside 16-04 untouched to honor the plan boundary.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Corrected milestone glyph cursor test expectation to Raxol display width**
- **Found during:** Task 1
- **Issue:** The RED glyph test assumed every milestone glyph occupied one terminal column. Raxol's current display-width model reports the full fixture at 11 columns and places display column 6 after `▸ `.
- **Fix:** Kept the glyph coverage but aligned the expected cursor placement with `Foglet.TUI.TextWidth.split_at/2`.
- **Files modified:** `test/foglet_bbs/tui/widgets/compose_test.exs`
- **Verification:** `rtk mix test test/foglet_bbs/tui/widgets/compose_test.exs`
- **Committed in:** `56b4dc3`

---

**Total deviations:** 1 auto-fixed test-oracle issue
**Impact on plan:** No scope expansion. The implementation still uses `TextWidth.split_at/2` and the test still proves the cursor does not split inside the glyph fixture.

## Issues Encountered

- `rtk mix precommit` fails on pre-existing Credo issues outside 16-04 scope:
  - `lib/foglet_bbs/tui/widgets/list/list_row.ex` alias ordering.
  - `test/foglet_bbs/tui/widgets/list/list_row_test.exs` alias ordering.
  - `lib/foglet_bbs/tui/text_width.ex` single-condition `cond` refactor suggestion.
- Vendored Raxol continues to emit existing compile warnings during test/precommit runs.
- Focused Phase 16 tests emit an existing type warning in `test/foglet_bbs/tui/widgets/modal_test.exs` for an intentional `FunctionClauseError` assertion.

## Known Stubs

None. Stub-pattern scan hits were existing placeholder options, nil assertions, or test fixtures; no new unimplemented UI data path was introduced.

## Threat Flags

None - this plan changed display-only TUI rendering/tests and documentation. It introduced no new network endpoints, auth paths, file access patterns, schema changes, or trust-boundary expansion beyond the planned terminal display-width boundary.

## User Setup Required

None.

## Verification

- `rtk mix test test/foglet_bbs/tui/widgets/compose_test.exs` - 29 tests, 0 failures.
- `rtk mix test test/foglet_bbs/tui/layout_smoke_test.exs` - 20 tests, 0 failures.
- `rtk mix test test/foglet_bbs/tui/text_width_test.exs test/foglet_bbs/tui/widgets/list/list_row_test.exs test/foglet_bbs/tui/widgets/chrome/key_bar_test.exs test/foglet_bbs/tui/widgets/modal_test.exs test/foglet_bbs/tui/widgets/compose_test.exs test/foglet_bbs/tui/layout_smoke_test.exs` - 101 tests, 0 failures.
- `rtk rg -n "TextWidth\\.split_at|alias Foglet\\.TUI\\.TextWidth" lib/foglet_bbs/tui/widgets/compose.ex` - matched required implementation.
- `rtk rg -n "String\\.split_at" lib/foglet_bbs/tui/widgets/compose.ex` - no matches.
- `rtk rg -n "cafe\\\\u0301|漢字|●|◆|▸|▾|✓|×|█" test/foglet_bbs/tui/widgets/compose_test.exs` - matched required coverage.
- `rtk rg -n "64, 22|80, 24|132, 50|TextWidth\\.display_width|ListRow|KeyBar|Modal|Compose|●|◆|▸|▾|✓|×" test/foglet_bbs/tui/layout_smoke_test.exs` - matched required coverage.
- `rtk rg -n "String\\\\\\.\\(length\\|slice\\|split_at\\|pad_leading\\|pad_trailing\\)|character-count|post body length|thread title length|Foglet\\.TUI\\.TextWidth" .planning/phases/16-unicode-width-foundation/16-WIDTH-SCAN.md` - matched required scan documentation.
- `rtk mix precommit` - failed on out-of-scope pre-existing Credo findings listed above.

## Orchestrator Notes

Per the user request, this executor did not update `.planning/STATE.md`, `.planning/ROADMAP.md`, or `.planning/REQUIREMENTS.md`; the orchestrator owns shared tracking files after execution.

## Next Phase Readiness

Phase 16's width foundation is complete from this plan's perspective: composer cursor rendering, representative terminal-size contracts, and the migrated-path scan are in place. Remaining precommit cleanup is localized to prior Phase 16 helper/list-row code.

## Self-Check: PASSED

- Found `lib/foglet_bbs/tui/widgets/compose.ex`
- Found `test/foglet_bbs/tui/widgets/compose_test.exs`
- Found `test/foglet_bbs/tui/layout_smoke_test.exs`
- Found `.planning/phases/16-unicode-width-foundation/16-WIDTH-SCAN.md`
- Found `.planning/phases/16-unicode-width-foundation/16-04-SUMMARY.md`
- Found commits `742fa91`, `56b4dc3`, `fba7981`, and `d2d85f2`

---
*Phase: 16-unicode-width-foundation*
*Completed: 2026-04-25*
