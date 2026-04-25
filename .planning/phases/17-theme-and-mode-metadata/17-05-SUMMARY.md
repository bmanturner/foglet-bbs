---
phase: 17-theme-and-mode-metadata
plan: 05
subsystem: ui
tags: [tui, widgets, theme, visual-contracts, raxol]

requires:
  - phase: 17-theme-and-mode-metadata
    provides: Phase 17 theme and presentation metadata plus Phase 17-04 widget retheme baseline
provides:
  - Widget visual-shape contracts for Phase 17 primitives
  - Canonical tab strip rendering owned by Foglet widgets
  - Semantic selection marks, action/menu row contracts, progress/loading glyphs, and modal body regions
affects: [chrome-v2, tui-widgets, screen-facelift]

tech-stack:
  added: []
  patterns:
    - Targeted flattened-text assertions for widget shape contracts
    - Theme-routed style-run assertions for glyph, key, label, and metadata regions

key-files:
  created:
    - .planning/phases/17-theme-and-mode-metadata/17-05-SUMMARY.md
  modified:
    - lib/foglet_bbs/tui/widgets/input/tabs.ex
    - lib/foglet_bbs/tui/widgets/input/radio_group.ex
    - lib/foglet_bbs/tui/widgets/input/checkbox.ex
    - lib/foglet_bbs/tui/widgets/input/button.ex
    - lib/foglet_bbs/tui/widgets/input/menu.ex
    - lib/foglet_bbs/tui/widgets/list/selection_list.ex
    - lib/foglet_bbs/tui/widgets/list/smart_list.ex
    - lib/foglet_bbs/tui/widgets/display/progress.ex
    - lib/foglet_bbs/tui/widgets/progress/spinner.ex
    - lib/foglet_bbs/tui/widgets/modal.ex
    - test/foglet_bbs/tui/widgets/input/tabs_test.exs
    - test/foglet_bbs/tui/widgets/input/radio_group_test.exs
    - test/foglet_bbs/tui/widgets/input/checkbox_test.exs
    - test/foglet_bbs/tui/widgets/input/button_test.exs
    - test/foglet_bbs/tui/widgets/input/menu_test.exs
    - test/foglet_bbs/tui/widgets/list/selection_list_test.exs
    - test/foglet_bbs/tui/widgets/list/smart_list_test.exs
    - test/foglet_bbs/tui/widgets/display/progress_test.exs
    - test/foglet_bbs/tui/widgets/progress/spinner_test.exs
    - test/foglet_bbs/tui/widgets/modal_test.exs
    - test/support/foglet/tui/widget_helpers.ex

key-decisions:
  - "Widget contracts are encoded as targeted flattened-text and style-run tests rather than runtime reads of SCREENS.md."
  - "Backward-compatible APIs remain available where callers may still rely on older ASCII forms."
  - "Full screen conversion, RichRow, EditorFrame, badge/grid/table primitives, and Chrome V2 remain out of scope."

patterns-established:
  - "Primitive-owned marks use semantic glyphs while routing all color through Foglet.TUI.Theme."
  - "Command-like controls separate key, label, metadata, and destructive treatment into distinct styled runs."
  - "Low-width progress/loading affordances prefer compact terminal glyph contracts."

requirements-completed:
  - THEME-02
  - CHROME-03
  - CONSOLE-01

duration: unknown
completed: 2026-04-25
---

# Phase 17: Widget Visual Contract Remediation Summary

**Phase 17 widgets now carry explicit terminal visual contracts for glyphs, spacing, and theme-routed styled regions.**

## Performance

- **Duration:** Not measured; executor stalled after task commits and the orchestrator completed the summary/recovery path.
- **Started:** 2026-04-25
- **Completed:** 2026-04-25
- **Tasks:** 6
- **Files modified:** 21

## Accomplishments

- Added widget helper support for flattened-text and style-run assertions that fail on glyph, spacing, or style regressions.
- Made `Input.Tabs` own the canonical tab strip shape with a movable active indicator.
- Updated selection controls, action/menu primitives, progress/loading primitives, and modal bodies to expose milestone-aligned visual contracts while keeping styling theme-routed.

## Task Commits

1. **Task 17-05-01: Add Visual Contract Test Helpers** - `6870d66` (`test`)
2. **Task 17-05-02: Own The Tab Strip Shape** - `d062058` (`feat`)
3. **Task 17-05-03: Update Selection Controls To Semantic Marks** - `481961a` (`feat`)
4. **Task 17-05-04: Update Action And Menu Primitives** - `ddf0bed` (`feat`)
5. **Task 17-05-05: Update Progress And Loading Primitives** - `b3bbce5` (`feat`)
6. **Task 17-05-06: Tighten Generic Modal Body Styling** - `7a56f23` (`feat`)

## Files Created/Modified

- `test/support/foglet/tui/widget_helpers.ex` - Adds reusable visual-contract assertions for flattened text and styled runs.
- `lib/foglet_bbs/tui/widgets/input/tabs.ex` - Renders the canonical active-indicator tab strip directly.
- `lib/foglet_bbs/tui/widgets/input/radio_group.ex` - Adds semantic selection marks while preserving compatibility paths.
- `lib/foglet_bbs/tui/widgets/input/checkbox.ex` - Adds semantic checked/unchecked state marks.
- `lib/foglet_bbs/tui/widgets/input/button.ex` - Separates shortcut/key text from action labels and semantic treatment.
- `lib/foglet_bbs/tui/widgets/input/menu.ex` - Adds glyph, metadata, shortcut row shaping and removes sentinel-style proofing.
- `lib/foglet_bbs/tui/widgets/list/selection_list.ex` - Adds optional simple-label row rendering with selected/normal shape.
- `lib/foglet_bbs/tui/widgets/list/smart_list.ex` - Adds compact state glyphs, multi-select marks, and empty/filter-empty affordances.
- `lib/foglet_bbs/tui/widgets/display/progress.ex` - Adds compact segmented progress and threshold styling.
- `lib/foglet_bbs/tui/widgets/progress/spinner.ex` - Adds optional message rendering with separate glyph/message styling.
- `lib/foglet_bbs/tui/widgets/modal.ex` - Adds title, divider, message, and action footer regions with separated key/label styling.
- `test/foglet_bbs/tui/widgets/**/*.exs` - Encodes visual shape contracts for the touched primitives.

## Decisions Made

- Kept `SCREENS.md` as planning input only; tests encode selected widget contracts directly.
- Preserved primitive scope and avoided screen-body conversion work reserved for later v1.3 phases.
- Kept existing compatibility behavior where callers may still depend on older textual forms.

## Deviations from Plan

- None for implementation scope. The executor completion signal was not received after the first five task commits, so the orchestrator finished task 6 commit, summary creation, tracking, and verification.

## Issues Encountered

- The executor stalled before writing `17-05-SUMMARY.md`. Spot checks showed commits for tasks 1-5, and the remaining uncommitted diff was scoped to task 6 plus formatter changes. The orchestrator closed the stalled executor and completed recovery in the main worktree.

## User Setup Required

None - no external service configuration required.

## Verification

- `rtk mix test test/foglet_bbs/tui/widgets/input/tabs_test.exs test/foglet_bbs/tui/widgets/input/radio_group_test.exs test/foglet_bbs/tui/widgets/input/checkbox_test.exs test/foglet_bbs/tui/widgets/input/button_test.exs test/foglet_bbs/tui/widgets/input/menu_test.exs test/foglet_bbs/tui/widgets/list/selection_list_test.exs test/foglet_bbs/tui/widgets/list/smart_list_test.exs test/foglet_bbs/tui/widgets/display/progress_test.exs test/foglet_bbs/tui/widgets/progress/spinner_test.exs test/foglet_bbs/tui/widgets/modal_test.exs` - 143 tests, 0 failures.

## Next Phase Readiness

Phase 17 now supplies stable theme and widget primitive contracts for later v1.3 screen/chrome work. Phase 18 and subsequent screen phases can compose these primitives without redefining their low-level glyph and style language.

---
*Phase: 17-theme-and-mode-metadata*
*Completed: 2026-04-25*
