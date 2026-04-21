---
phase: 08
plan: "03"
subsystem: tui-widgets
tags: [raxol, widget, display, progress, stateful, stateless, theme, d-14, d-16, pitfall-8, pitfall-9]
dependency_graph:
  requires:
    - "lib/foglet_bbs/tui/theme.ex"
    - "vendor/raxol/lib/raxol/ui/components/table.ex"
    - "vendor/raxol/lib/raxol/ui/components/display/tree.ex"
    - "vendor/raxol/lib/raxol/ui/components/progress/spinner.ex"
    - "lib/foglet_bbs/tui/widgets/chrome/key_bar.ex"
  provides:
    - "lib/foglet_bbs/tui/widgets/display/table.ex"
    - "lib/foglet_bbs/tui/widgets/display/tree.ex"
    - "lib/foglet_bbs/tui/widgets/display/progress.ex"
    - "lib/foglet_bbs/tui/widgets/progress/spinner.ex"
  affects:
    - "Future screens using tabular data, hierarchical navigation, or progress/loading UIs"
tech_stack:
  added: []
  patterns:
    - "Pattern 2 (stateful delegation) for Table and Tree: defstruct + init/1 + handle_event/2 + render/2"
    - "Pattern 1 (stateless DSL composition) for Progress and Spinner: render/2 only, no struct"
    - "build_<widget>_theme/1 private helper convention for theme-prop map construction"
    - "Direct DSL render bypassing Raxol component internals when theme control is needed (Tree, Progress)"
    - "Event translation layer: Foglet %{key: atom} → Raxol {:key, {:arrow_*, nil}} tuples for Table"
    - "Column normalization: inject :align/:width defaults Raxol.UI.Components.Table requires"
    - "MapSet.size delta used to derive :node_expanded/:node_collapsed/:node_activated action atoms"
key_files:
  created:
    - "lib/foglet_bbs/tui/widgets/display/table.ex"
    - "lib/foglet_bbs/tui/widgets/display/tree.ex"
    - "lib/foglet_bbs/tui/widgets/display/progress.ex"
    - "lib/foglet_bbs/tui/widgets/progress/spinner.ex"
    - "test/foglet_bbs/tui/widgets/display/table_test.exs"
    - "test/foglet_bbs/tui/widgets/display/tree_test.exs"
    - "test/foglet_bbs/tui/widgets/display/progress_test.exs"
    - "test/foglet_bbs/tui/widgets/progress/spinner_test.exs"
  modified: []
decisions:
  - "Display.Tree renders via visible_nodes/1 + direct DSL instead of RaxolTree.render/2 — Raxol Tree ignores the theme: key in state and uses StyleHelper + Core.Defaults.selected_style() internally, so delegating to its render would leak non-theme colors"
  - "Display.Progress renders via pure DSL instead of Raxol.UI.Components.Display.Progress — Pitfall 8 defense: the Raxol component's extract_colors/1 defaults to :green/:black/:white when theme prop is absent or improperly routed; bypassing its render guarantees zero color atom leakage"
  - "Progress.Spinner uses RaxolSpinner.spinner/3 with :type keyword (not :style) — confirmed from source: opts key is :type, the @spinner_frames map is keyed by atom type"
  - "Table.normalize_column/1 injects :align/:width/:format defaults — Raxol.UI.Components.Table accesses column.align and column.width directly without nil guards, crashing if absent"
  - "Table init sets selected_row: 0 explicitly — Raxol Table initializes selected_row: nil, and its down-arrow handler does nil + 1 causing ArithmeticError"
metrics:
  duration_minutes: 11
  completed_date: "2026-04-21"
  tasks_completed: 2
  tasks_total: 2
  tests_written: 45
  files_created: 8
---

# Phase 08 Plan 03: Display.Table, Display.Tree, Display.Progress, Progress.Spinner Summary

Four Foglet TUI widget wrappers for the Display and Progress buckets: Table and Tree (stateful Pattern 2 with full D-14 triplet) plus Progress and Spinner (stateless Pattern 1 DSL composition with D-16 compliance).

## What Was Built

### Display.Table (`lib/foglet_bbs/tui/widgets/display/table.ex`)

Stateful facade (D-14) over `Raxol.UI.Components.Table`. Exposes `init/1`, `handle_event/2`, `render/2`.

- `build_table_theme/1` constructs `%{box, header, row, selected_row}` map from `Foglet.TUI.Theme` slots
- `normalize_column/1` fills required `:align`, `:width`, `:format` fields Raxol accesses directly
- `translate_event/1` maps `%{key: :down}` → `{:key, {:arrow_down, nil}}` (Raxol Table's event format)
- Action atoms: `{:row_selected, row}`, `{:sort_changed, column}`, `{:filter_changed, term}`, `nil`
- Defaults: `@default_page_size 10`
- 15 tests covering init, render smoke, theme slot routing, handle_event D-14, hygiene D-18

### Display.Tree (`lib/foglet_bbs/tui/widgets/display/tree.ex`)

Stateful facade (D-14) over `Raxol.UI.Components.Display.Tree`. Exposes `init/1`, `handle_event/2`, `render/2`.

- Renders using `RaxolTree.visible_nodes/1` + direct `text/2` DSL rows instead of `RaxolTree.render/2` — Raxol's internal render ignores the `theme:` key and uses `StyleHelper` + `Core.Defaults.selected_style()`, making theme-slot routing impossible through delegation
- `derive_action/3` uses MapSet.size delta to produce `:node_expanded`/`:node_collapsed`/`:node_activated`
- Pitfall 9 documented in moduledoc: node maps require `:id`, `:label`, `:children` keys
- Defaults: `@default_indent_size 2`
- 13 tests covering init, render smoke, theme slot routing, expand/collapse/activate D-14, hygiene D-18

### Display.Progress (`lib/foglet_bbs/tui/widgets/display/progress.ex`)

Stateless (D-16) pure DSL progress bar. No struct, no `handle_event/2`.

- Bypasses `Raxol.UI.Components.Display.Progress` entirely — Pitfall 8 defense against `:green`/`:black`/`:white` defaults in `extract_colors/1`
- Emits `[`, filled `█` chars (accent.fg), empty spaces (dim.fg), `]` using theme slots
- Optional label and percentage display, both using `primary.fg`
- Defaults: `@default_width 40`
- 11 tests covering smoke, label, boundaries (0.0/1.0), Pitfall 8 refutes, alt-theme differential

### Progress.Spinner (`lib/foglet_bbs/tui/widgets/progress/spinner.ex`)

Stateless (D-16) outlier: wraps `RaxolSpinner.spinner/3` pure string utility.

- Calls `spinner(nil, frame, type: style)` — confirmed `:type` is the correct opts key (not `:style`) from source review
- Wraps returned glyph in `text/2` with `theme.accent.fg` and `theme.accent.style`
- Defaults: `@default_style :line`, `@default_frame_duration_ms 100`
- 6 tests covering smoke, frame advance → different glyph, accent.fg slot, hygiene D-18

## Requirements Closed

- **REQ-W-02**: Display.Table implemented with sortable/filterable/selectable surface
- **REQ-W-03**: Display.Tree implemented with expand/collapse and keyboard nav
- **REQ-W-04**: Display.Progress implemented (stateless, D-16)
- **REQ-W-05**: Progress.Spinner implemented (stateless, D-16)

## Action Atom Vocabulary Added

| Widget | Action |
|--------|--------|
| Display.Table | `{:row_selected, row}`, `{:sort_changed, col}`, `{:filter_changed, term}`, `nil` |
| Display.Tree | `:node_expanded`, `:node_collapsed`, `:node_activated`, `nil` |

## Theme Slots Consumed Per Widget

| Widget | Slots |
|--------|-------|
| Display.Table | `border.fg`, `title.fg`, `primary.fg`, `selected.fg`, `selected.bg` |
| Display.Tree | `primary.fg`, `selected.fg`, `selected.bg`, `selected.style` |
| Display.Progress | `border.fg`, `accent.fg`, `dim.fg`, `primary.fg` |
| Progress.Spinner | `accent.fg`, `accent.style` |

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Raxol Table columns require :align/:width fields**

- **Found during:** Task 1 GREEN phase (render crash — `key :align not found`)
- **Issue:** `Raxol.UI.Components.Table.create_header_cell/4` accesses `column.align` directly; callers passing minimal `%{id, label}` specs crash at render time
- **Fix:** `normalize_column/1` private helper injects `:align :left`, `:width 20`, `:format nil` defaults before passing to Raxol
- **Files modified:** `lib/foglet_bbs/tui/widgets/display/table.ex`
- **Commit:** 72b8dc3

**2. [Rule 1 - Bug] Raxol Table selected_row initializes nil, crashes on down-arrow**

- **Found during:** Task 1 GREEN phase (ArithmeticError — `nil + 1`)
- **Issue:** `Raxol.UI.Components.Table.init/1` sets `selected_row: nil`; the down-arrow handler does `state.selected_row + 1` without a nil guard
- **Fix:** Explicitly set `selected_row: 0` after `RaxolTable.init/1` in our `init/1`
- **Files modified:** `lib/foglet_bbs/tui/widgets/display/table.ex`
- **Commit:** 72b8dc3

**3. [Rule 1 - Bug] RaxolTree.render/2 ignores theme: state key, emits non-theme colors**

- **Found during:** Task 1 GREEN phase (theme slot routing test failure)
- **Issue:** Raxol's Tree render uses `StyleHelper.merge_component_styles_with_focus` and `Raxol.Core.Defaults.selected_style()` internally — the `theme:` key in state is not consumed for node styling
- **Fix:** Rewrote `Display.Tree.render/2` to use `RaxolTree.visible_nodes/1` + direct `text/2` DSL emission with theme slots, bypassing `RaxolTree.render/2`
- **Files modified:** `lib/foglet_bbs/tui/widgets/display/tree.ex`
- **Commit:** 72b8dc3

**4. [Rule 2 - Missing Defense] Display.Progress Pitfall 8 requires bypassing Raxol component**

- **Found during:** Task 2 implementation (confirmed from Progress source `extract_colors/1`)
- **Issue:** `Raxol.UI.Components.Display.Progress.extract_colors/1` defaults `fg: :green, bg: :black, border: :white, text: :white` — even with a `theme:` prop, `StyleHelper.merge_component_styles` might not route our theme subkeys correctly
- **Fix:** `Display.Progress.render/2` bypasses Raxol's Progress component entirely, emitting themed DSL rows directly with `█`/` ` chars
- **Files modified:** `lib/foglet_bbs/tui/widgets/display/progress.ex`
- **Commit:** 0e370a0

**5. [Rule 1 - Bug] RaxolSpinner.spinner/3 uses :type key, not :style**

- **Found during:** Task 2 implementation (source review of spinner.ex line 54)
- **Issue:** Plan skeleton showed `RaxolSpinner.spinner(style, frame, %{})` — but actual signature is `spinner(message, frame, opts)` where opts uses `:type` (not `:style`) to select animation
- **Fix:** Call `RaxolSpinner.spinner(nil, frame, type: style)` — nil message gives glyph-only, `:type` selects the animation style
- **Files modified:** `lib/foglet_bbs/tui/widgets/progress/spinner.ex`
- **Commit:** 0e370a0

**6. [Rule 1 - Bug] Test: single-row Table always uses selected_row style, not primary.fg**

- **Found during:** Task 1 GREEN phase (theme slot routing test for primary.fg)
- **Issue:** `selected_row: 0` means a single-row table always renders with selected_row theme colors; `primary.fg` (row style) only appears on unselected rows
- **Fix:** Updated test to use two rows `[%{name: "Alice"}, %{name: "Bob"}]` so row 1 renders with `primary.fg`
- **Files modified:** `test/foglet_bbs/tui/widgets/display/table_test.exs`
- **Commit:** 72b8dc3

**7. [Rule 1 - Bug] Test: single-node Tree always renders cursor with selected.fg, not primary.fg**

- **Found during:** Task 1 GREEN phase (theme slot routing test for primary.fg)
- **Issue:** A single-node tree always has cursor = that node; all nodes render with selected slot colors
- **Fix:** Updated test to use two sibling nodes; cursor starts at `:a`, so `:b` renders with `primary.fg`
- **Files modified:** `test/foglet_bbs/tui/widgets/display/tree_test.exs`
- **Commit:** 72b8dc3

## Known Stubs

None. All widgets render real output from actual inputs.

## Threat Flags

None. No new network endpoints, auth paths, file access, or schema changes introduced.

## TDD Gate Compliance

Both tasks followed RED → GREEN sequence:

1. `test(08-03)` commit 584a0b3 (Table+Tree failing tests — RED gate)
2. `feat(08-03)` commit 72b8dc3 (Table+Tree implementation — GREEN gate)
3. `test(08-03)` commit 0d3a24c (Progress+Spinner failing tests — RED gate)
4. `feat(08-03)` commit 0e370a0 (Progress+Spinner implementation — GREEN gate)

## Self-Check: PASSED

All 8 created files exist on disk. All 4 task commits (584a0b3, 72b8dc3, 0d3a24c, 0e370a0) confirmed in git log. 45 tests pass with 0 failures.
