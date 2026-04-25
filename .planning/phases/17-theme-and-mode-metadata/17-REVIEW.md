---
phase: 17-theme-and-mode-metadata
reviewed: 2026-04-25T17:20:51Z
depth: standard
files_reviewed: 19
files_reviewed_list:
  - lib/foglet_bbs/tui/presentation.ex
  - lib/foglet_bbs/tui/theme.ex
  - lib/foglet_bbs/tui/modal.ex
  - lib/foglet_bbs/tui/widgets/display/progress.ex
  - lib/foglet_bbs/tui/widgets/input/button.ex
  - lib/foglet_bbs/tui/widgets/input/menu.ex
  - lib/foglet_bbs/tui/widgets/input/tabs.ex
  - lib/foglet_bbs/tui/widgets/list/selection_list.ex
  - lib/foglet_bbs/tui/widgets/list/smart_list.ex
  - lib/foglet_bbs/tui/widgets/modal.ex
  - test/foglet_bbs/tui/presentation_test.exs
  - test/foglet_bbs/tui/theme_test.exs
  - test/foglet_bbs/tui/widgets/display/progress_test.exs
  - test/foglet_bbs/tui/widgets/input/button_test.exs
  - test/foglet_bbs/tui/widgets/input/menu_test.exs
  - test/foglet_bbs/tui/widgets/input/tabs_test.exs
  - test/foglet_bbs/tui/widgets/list/selection_list_test.exs
  - test/foglet_bbs/tui/widgets/list/smart_list_test.exs
  - test/foglet_bbs/tui/widgets/modal_test.exs
findings:
  critical: 0
  warning: 0
  info: 0
  total: 0
status: clean
resolved_findings:
  warning: 3
resolved_at: 2026-04-25T17:29:00Z
---

# Phase 17: Code Review Report

**Reviewed:** 2026-04-25T17:20:51Z
**Depth:** standard
**Files Reviewed:** 19
**Status:** clean after fixes

## Summary

Reviewed the Phase 17 presentation metadata, semantic theme slots, widget theme routing, and focused tests. The initial review found three warning-level issues in the local Menu and SmartList renderers. Those issues have been fixed and covered by regression tests.

Verification run:

`rtk mix test test/foglet_bbs/tui/presentation_test.exs test/foglet_bbs/tui/theme_test.exs test/foglet_bbs/tui/widgets/display/progress_test.exs test/foglet_bbs/tui/widgets/input/button_test.exs test/foglet_bbs/tui/widgets/input/menu_test.exs test/foglet_bbs/tui/widgets/input/tabs_test.exs test/foglet_bbs/tui/widgets/list/selection_list_test.exs test/foglet_bbs/tui/widgets/list/smart_list_test.exs test/foglet_bbs/tui/widgets/modal_test.exs` - passed, 111 tests.

## Resolved Warnings

### WR-01: Menu Render Ignores Open Submenus

**File:** `lib/foglet_bbs/tui/widgets/input/menu.ex:98`
**Issue:** `render/2` renders only `rs.items`, so after `handle_event/2` opens a submenu and moves `rs.cursor` into a child, the view still shows only top-level items. Raxol's menu state keeps `open_path` and exposes visible flattened rows, but the wrapper bypasses that when it maps only `:items`. This breaks nested menu usability: the selected child can be active in state but invisible.
**Fix:** Render the visible menu chain, including depth indentation, instead of raw top-level items. Use the same state fields Raxol updates:

```elixir
defp visible_items(%{items: items, open_path: open_path}) do
  flatten_visible(items, open_path, 0)
end

defp flatten_visible([], _open_path, _depth), do: []

defp flatten_visible([item | rest], open_path, depth) do
  children =
    if item.id in open_path and item.children != [] do
      flatten_visible(item.children, open_path, depth + 1)
    else
      []
    end

  [{item, depth}] ++ children ++ flatten_visible(rest, open_path, depth)
end
```

Then render `{item, depth}` rows and add a test that opens a submenu with Enter/Right and asserts child labels are present.

**Resolution:** Fixed in `fix(17-04): resolve review findings for menu and smart list`. `Menu.render/2` now flattens visible open submenu chains and `menu_test.exs` covers opened submenu output.

### WR-02: SmartList Render Ignores Filtering And Scroll Window

**File:** `lib/foglet_bbs/tui/widgets/list/smart_list.ex:240`
**Issue:** `render_options/2` maps over all `rs.options` every time. It does not respect `filtered_options`, `scroll_offset`, or `visible_items`, even though `handle_event/2` delegates navigation/search to Raxol state that maintains those fields. Large lists render every option instead of the visible window, and applied filters/pages are not reflected in the output.
**Fix:** Derive the visible option slice from the Raxol state before rendering:

```elixir
defp render_options(rs, theme) do
  effective_options = Map.get(rs, :filtered_options) || Map.get(rs, :options, [])
  visible_items = Map.get(rs, :visible_items) || Map.get(rs, :page_size, @default_page_size)
  scroll_offset = Map.get(rs, :scroll_offset, 0)
  focused_index = Map.get(rs, :focused_index, 0)

  effective_options
  |> Enum.slice(scroll_offset, visible_items)
  |> Enum.with_index(scroll_offset)
  |> Enum.map(fn {{label, _value}, index} ->
    # existing focused/unfocused themed row rendering
  end)
end
```

Add tests for a list longer than the visible window and for a state with `filtered_options` set.

**Resolution:** Fixed in `fix(17-04): resolve review findings for menu and smart list`. `SmartList.render/2` now uses `filtered_options`, `visible_items`, and `scroll_offset`; regression tests cover both filtered and windowed state.

### WR-03: Menu Accepts Id-Only Items But Render Requires Labels

**File:** `lib/foglet_bbs/tui/widgets/input/menu.ex:135`
**Issue:** `normalize_item/2` permits any item that has either `:id` or `:label`, and the docs say only items missing both are rejected. However `render_item/3` later calls `Map.fetch!(item, :label)`, so an id-only item initializes successfully and crashes at render time. That is a public API mismatch and an avoidable runtime failure.
**Fix:** Either require `:label` during normalization or synthesize one from `:id`. Requiring labels matches the render contract most directly:

```elixir
unless Map.has_key?(item, :label) do
  raise ArgumentError,
        "Foglet.TUI.Widgets.Input.Menu items require :label; got #{inspect(item)}"
end
```

Update the docs and tests so id-only menu items fail during `normalize_items/1` rather than later during rendering.

**Resolution:** Fixed in `fix(17-04): resolve review findings for menu and smart list`. `Menu.normalize_items/1` now requires `:label`, and id-only inputs fail during normalization.

---

_Reviewed: 2026-04-25T17:20:51Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
