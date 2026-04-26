---
phase: 17-theme-and-mode-metadata
plan: "04"
subsystem: tui-widgets
tags:
  - theme
  - tui
  - widgets
  - tdd
dependency_graph:
  requires:
    - 17-02
    - 17-03
    - THEME-01
    - THEME-02
  provides:
    - Theme-routed current widget primitives
    - Focused widget theme hygiene coverage
  affects:
    - Foglet.TUI.Widgets.Input.Button
    - Foglet.TUI.Widgets.Input.Menu
    - Foglet.TUI.Widgets.List.SmartList
    - Foglet.TUI.Widgets.Display.Progress
    - Foglet.TUI.Widgets.Input.Tabs
    - Foglet.TUI.Widgets.List.SelectionList
    - Foglet.TUI.Widgets.Modal
    - Foglet.TUI.Modal
tech_stack:
  added: []
  patterns:
    - Direct theme-slot rendering for widgets where Raxol defaults leak color atoms
    - Presentation.theme_mappings/0 consumption for tab state styling
    - Optional theme-aware empty-state rendering while preserving caller-owned row styling
key_files:
  created:
    - .planning/phases/17-theme-and-mode-metadata/17-04-SUMMARY.md
    - test/foglet_bbs/tui/widgets/list/selection_list_test.exs
  modified:
    - lib/foglet_bbs/tui/modal.ex
    - lib/foglet_bbs/tui/widgets/display/progress.ex
    - lib/foglet_bbs/tui/widgets/input/button.ex
    - lib/foglet_bbs/tui/widgets/input/menu.ex
    - lib/foglet_bbs/tui/widgets/input/tabs.ex
    - lib/foglet_bbs/tui/widgets/list/selection_list.ex
    - lib/foglet_bbs/tui/widgets/list/smart_list.ex
    - lib/foglet_bbs/tui/widgets/modal.ex
    - test/foglet_bbs/tui/widgets/display/progress_test.exs
    - test/foglet_bbs/tui/widgets/input/button_test.exs
    - test/foglet_bbs/tui/widgets/input/menu_test.exs
    - test/foglet_bbs/tui/widgets/list/smart_list_test.exs
    - test/foglet_bbs/tui/widgets/modal_test.exs
decisions:
  - Kept SelectionList row presentation caller-owned; only the widget-owned empty state is theme-routed.
  - Rendered Menu and SmartList locally for visible output while preserving Raxol event handling, because downstream renderers ignored the supplied theme maps.
  - Added `:success` as a modal type so generic modal body states can use the Phase 17 success slot directly.
metrics:
  completed_at: 2026-04-25T15:12:00Z
  duration: approximately 110 minutes
  tasks_completed: 3
  files_changed: 15
requirements_completed:
  - THEME-01
  - THEME-02
---

# Phase 17 Plan 04: Widget Theme Routing Summary

Current widget primitives that are not owned by later v1.3 phases now route their visible styling through `Foglet.TUI.Theme` slots and focused tests.

## What Changed

- Button roles now use semantic slots for primary, secondary, danger, success, and disabled states.
- Menu and SmartList keep their existing state/event handling, but render visible rows locally so theme slot values are present in output instead of Raxol default color atoms.
- Display.Progress uses `theme.accent` for in-progress fill and `theme.success` for complete progress.
- Tabs now consumes `Presentation.theme_mappings().tabs` for selected, unselected, indicator, and border slot names.
- SelectionList gained optional `render/4` theme support for the widget-owned empty state while preserving caller-owned row rendering for non-empty lists.
- Generic Modal now supports `:info`, `:success`, `:warning`, `:error`, and `:confirm` semantic slots.

## Task Commits

| Task | Commit | Description |
|------|--------|-------------|
| 17-04-01 RED | `2927ee5` | Added failing catalog primitive theme coverage. |
| 17-04-01 GREEN | `bd26b32` | Routed Button, Menu, SmartList, and Display.Progress through theme slots. |
| 17-04-02 | `1c99780` | Aligned Tabs with `Presentation.theme_mappings().tabs`. |
| 17-04-03 | `d9ac2e0` | Routed Modal and SelectionList widget-owned states through semantic slots. |
| 17-04-03 FIX | `2fe8fe4` | Tightened SelectionList render specs for Dialyzer. |

## Verification

Passed:

- `rtk mix test test/foglet_bbs/tui/widgets/input/button_test.exs test/foglet_bbs/tui/widgets/input/menu_test.exs test/foglet_bbs/tui/widgets/list/smart_list_test.exs test/foglet_bbs/tui/widgets/display/progress_test.exs` - 55 tests, 0 failures.
- `rtk mix test test/foglet_bbs/tui/widgets/input/tabs_test.exs test/foglet_bbs/tui/widgets/input/radio_group_test.exs test/foglet_bbs/tui/widgets/input/checkbox_test.exs` - 39 tests, 0 failures.
- `rtk mix test test/foglet_bbs/tui/widgets/list/selection_list_test.exs test/foglet_bbs/tui/widgets/progress/spinner_test.exs test/foglet_bbs/tui/widgets/modal_test.exs` - 23 tests, 0 failures.
- Full 17-04 focused widget suite - 117 tests, 0 failures.
- `rtk mix test test/foglet_bbs/tui/theme_test.exs test/foglet_bbs/tui/presentation_test.exs` - 22 tests, 0 failures.
- `rtk mix precommit` - passed successfully.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Raxol renderer ignored supplied menu/list theme maps**
- **Found during:** Task 17-04-01 focused tests.
- **Issue:** Menu and SmartList tests showed Raxol output still used default styles and did not include the supplied theme slot values.
- **Fix:** Kept Raxol state/event handling, but rendered visible rows directly in Foglet wrappers.
- **Files modified:** `lib/foglet_bbs/tui/widgets/input/menu.ex`, `lib/foglet_bbs/tui/widgets/list/smart_list.ex`.
- **Commit:** `bd26b32`.

**2. [Rule 3 - Blocking] SelectionList render spec was too broad for Dialyzer**
- **Found during:** `rtk mix precommit`.
- **Issue:** Dialyzer rejected `any()`/`map()` supertypes for the concrete flex-column render return.
- **Fix:** Added a precise `flex_column()` return type.
- **Files modified:** `lib/foglet_bbs/tui/widgets/list/selection_list.ex`.
- **Commit:** `2fe8fe4`.

## Deferred Issues

None.

## Known Stubs

None found in files created or modified by this plan.

## Threat Flags

None. This plan changes presentation styling only; it adds no authorization decision, persistence path, network endpoint, or secret handling.

## TDD Gate Compliance

- RED gate present: `2927ee5`.
- GREEN gate present: `bd26b32`.
- Follow-up implementation/fix commits: `1c99780`, `d9ac2e0`, `2fe8fe4`.

## Self-Check: PASSED

All planned tasks are complete, focused tests pass, precommit passes, and shared orchestrator artifacts were not updated by this worktree.
