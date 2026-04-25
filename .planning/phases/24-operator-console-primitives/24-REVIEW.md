---
phase: 24-operator-console-primitives
reviewed: 2026-04-25T22:33:47Z
depth: standard
files_reviewed: 13
files_reviewed_list:
  - lib/foglet_bbs/tui/widgets/display/badge.ex
  - test/foglet_bbs/tui/widgets/display/badge_test.exs
  - lib/foglet_bbs/tui/widgets/display/kv_grid.ex
  - test/foglet_bbs/tui/widgets/display/kv_grid_test.exs
  - lib/foglet_bbs/tui/widgets/display/console_table.ex
  - test/foglet_bbs/tui/widgets/display/console_table_test.exs
  - lib/foglet_bbs/tui/widgets/workspace/inspector.ex
  - test/foglet_bbs/tui/widgets/workspace/inspector_test.exs
  - lib/foglet_bbs/tui/widgets/modal/form.ex
  - test/foglet_bbs/tui/widgets/modal/form_test.exs
  - lib/foglet_bbs/tui/widgets/README.md
  - lib/foglet_bbs/tui/widgets/display/tree.ex
  - lib/foglet_bbs/tui/widgets/list/board_tree.ex
findings:
  critical: 1
  warning: 1
  info: 0
  total: 2
status: issues_found
---

# Phase 24: Code Review Report

**Reviewed:** 2026-04-25T22:33:47Z
**Depth:** standard
**Files Reviewed:** 13
**Status:** issues_found

## Summary

Reviewed the Phase 24 primitive-only widget changes and their focused tests. The implementation keeps domain boundaries intact and the focused suite passes, but two API-contract defects remain: `ConsoleTable` ignores its disabled selection flag, and `KvGrid` advertises badge metadata without correctly rendering metadata beyond bare atoms.

## Critical Issues

### CR-01: ConsoleTable Emits Selection Actions Even When Selection Is Disabled

**File:** `lib/foglet_bbs/tui/widgets/display/console_table.ex:42`

**Issue:** `init/1` stores `selectable = Keyword.get(opts, :selectable, false)`, but the value is never passed into the underlying table or checked by `handle_event/2`. As a result, a table initialized with the default `selectable: false` still delegates Enter to `Display.Table`, which returns `{:row_selected, row}` for the focused row. Future operator-console screens can therefore receive row-selection actions from a primitive they explicitly configured as non-selectable.

**Fix:**

```elixir
def handle_event(%{key: :enter}, %__MODULE__{selectable: false} = state) do
  {state, nil}
end

def handle_event(event, %__MODULE__{} = state) do
  {table, action} = Table.handle_event(event, state.table)
  {%{state | table: table, last_action: action}, action}
end
```

Add a regression test that initializes `ConsoleTable.init(columns: ..., rows: rows, selectable: false)` and asserts Enter returns `{state, nil}` without changing `last_action`.

## Warnings

### WR-01: KvGrid Badge Metadata Is Rendered As Inspect Text Instead Of Badge Options

**File:** `lib/foglet_bbs/tui/widgets/display/kv_grid.ex:76`

**Issue:** The plan and README describe optional badge metadata, but `KvGrid` only handles `:badge` or `:state` as direct values and passes them straight to `Badge.render/2`. If a caller supplies metadata such as `%{badge: %{state: :healthy, label: "db"}}` or `%{badge: [state: :pending, role: :warning]}`, `Badge.render/2` receives the whole map/keyword as the badge state and renders its string representation rather than the requested state, label, and role. Width reservation uses the same raw term at line 88, so richer metadata also produces misleading truncation math.

**Fix:** Normalize badge metadata before rendering and width calculation. For example:

```elixir
defp badge_for(%{badge: %{state: state} = badge}, theme),
  do: Badge.render(state, Keyword.merge([theme: theme], Map.to_list(Map.delete(badge, :state))))

defp badge_for(%{badge: state}, theme) when not is_nil(state),
  do: Badge.render(state, theme: theme)

defp badge_text_width(%{state: state} = badge) do
  label = Map.get(badge, :label, state)
  TextWidth.display_width("[#{label}]")
end

defp badge_text_width(state), do: TextWidth.display_width("[#{state}]")
```

Add tests for at least one metadata badge with a custom label and role so `flatten_text/1` proves the caller-provided label is rendered and line widths remain bounded.

---

_Reviewed: 2026-04-25T22:33:47Z_
_Reviewer: the agent (gsd-code-reviewer)_
_Depth: standard_
