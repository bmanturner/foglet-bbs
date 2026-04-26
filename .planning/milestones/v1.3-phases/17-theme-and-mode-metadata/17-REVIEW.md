---
phase: 17-theme-and-mode-metadata
reviewed: 2026-04-25T18:25:01Z
depth: standard
files_reviewed: 25
files_reviewed_list:
  - lib/foglet_bbs/tui/presentation.ex
  - lib/foglet_bbs/tui/theme.ex
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
  - test/foglet_bbs/tui/presentation_test.exs
  - test/foglet_bbs/tui/theme_test.exs
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
findings:
  critical: 0
  warning: 2
  info: 0
  total: 2
status: issues_found
---

# Phase 17: Code Review Report

**Reviewed:** 2026-04-25T18:25:01Z
**Depth:** standard
**Files Reviewed:** 25
**Status:** issues_found

## Summary

Reviewed the presentation metadata, theme registry, themed widget wrappers, and the matching tests at standard depth. No security issues were found. The main risks are two edge cases where widget-normalized state can become ambiguous or visually invalid.

Verification run:

```bash
rtk mix test test/foglet_bbs/tui/presentation_test.exs test/foglet_bbs/tui/theme_test.exs test/foglet_bbs/tui/widgets/input/tabs_test.exs test/foglet_bbs/tui/widgets/input/radio_group_test.exs test/foglet_bbs/tui/widgets/input/checkbox_test.exs test/foglet_bbs/tui/widgets/input/button_test.exs test/foglet_bbs/tui/widgets/input/menu_test.exs test/foglet_bbs/tui/widgets/list/selection_list_test.exs test/foglet_bbs/tui/widgets/list/smart_list_test.exs test/foglet_bbs/tui/widgets/display/progress_test.exs test/foglet_bbs/tui/widgets/progress/spinner_test.exs test/foglet_bbs/tui/widgets/modal_test.exs
```

Result: 165 tests, 0 failures.

## Warnings

### WR-01: Auto-generated menu IDs collide for duplicate labels

**File:** `lib/foglet_bbs/tui/widgets/input/menu.ex:151`

**Issue:** `normalize_item/2` derives missing IDs from only the label path:

```elixir
Map.put_new_lazy(:id, fn -> "auto:" <> Enum.join(path, "/") end)
```

Two sibling menu items with the same label and no explicit `:id` normalize to the same ID. Raxol uses IDs for cursor state, submenu `open_path`, and action return values, so duplicate auto IDs can make selection, submenu expansion, and `{:menu_action, id}` ambiguous. This is plausible for menus with repeated verbs such as multiple `"Open"` or `"Delete"` entries under different grouped sections.

**Fix:** Include a sibling index in the generated path, or detect duplicate generated IDs and raise with a helpful message so callers provide explicit IDs. For example:

```elixir
defp normalize_items(items, parent_path) when is_list(items) do
  items
  |> Enum.with_index()
  |> Enum.map(fn {item, index} -> normalize_item(item, parent_path, index) end)
end

defp normalize_item(item, parent_path, index) when is_map(item) do
  label = Map.fetch!(item, :label)
  path = parent_path ++ ["#{index}:#{label}"]

  item
  |> Map.put_new_lazy(:id, fn -> "auto:" <> Enum.join(path, "/") end)
  |> Map.update(:children, [], fn kids -> normalize_items(kids, path) end)
end
```

### WR-02: Out-of-range tab active index renders no selected tab

**File:** `lib/foglet_bbs/tui/widgets/input/tabs.ex:68`

**Issue:** `init/1` passes caller-provided `:active` directly into Raxol state. `render/2` only marks a tab selected when `idx == active_index`, so `active: -1` or `active: 99` renders every tab as unselected until a navigation event corrects state. That can leave a screen with no visible active tab after initialization.

**Fix:** Clamp the active index after tab normalization, mirroring the defensive behavior already used by `RadioGroup`.

```elixir
active_index =
  opts
  |> Keyword.get(:active, 0)
  |> clamp_active_index(normalized_tabs)

raxol_opts = [
  tabs: normalized_tabs,
  active_index: active_index,
  active_indicator: @default_active_indicator
]

defp clamp_active_index(_idx, []), do: 0
defp clamp_active_index(idx, _tabs) when idx < 0, do: 0
defp clamp_active_index(idx, tabs), do: min(idx, length(tabs) - 1)
```

---

_Reviewed: 2026-04-25T18:25:01Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
