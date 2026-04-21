---
phase: "08"
phase_name: build-local-widget-library-from-raxol-primitives
status: issues_found
depth: standard
files_reviewed: 27
diff_base: c71d7b9
findings:
  critical: 0
  warning: 6
  info: 8
  total: 14
generated: "2026-04-20"
---

# Phase 8: Code Review Report

**Reviewed:** 2026-04-20
**Depth:** standard
**Files Reviewed:** 27
**Status:** issues_found

## Summary

Phase 8 ships a local widget catalog (input/, display/, progress/, list/, chrome/) wrapping Raxol primitives, plus a documentation index, plus a 2-line audit comment in `size_gate.ex`. Theme hygiene is rigorously enforced — every widget routes colors through `Foglet.TUI.Theme` slots and ships D-18 hygiene tests that grep the serialized render tree for forbidden color atoms. The cross-bucket smoke test (`catalog_smoke_test.exs`) is a nice belt-and-suspenders catch for slot leaks during composition.

No Critical findings. Several Warnings around input validation at widget boundaries (NaN/integer handling in `Display.Progress`, out-of-range `selected_index` in `RadioGroup`, fragile `normalize_tab/1`), and one Warning about non-deterministic auto-generated menu IDs producing unroutable `{:menu_action, id}` tuples. Info findings are largely test-file duplication and minor dead/defensive code.

## Warnings

### WR-01: `Display.Progress.render/2` crashes on integer progress

**File:** `lib/foglet_bbs/tui/widgets/display/progress.ex:40`
**Issue:** Guard is `is_float(progress)`. Calling `Progress.render(0, theme: t)` (integer) raises `FunctionClauseError`. The catalog smoke test only exercises `0.5`; the per-widget test only exercises `0.0`/`0.5`/`1.0`. A caller doing arithmetic such as `current / total` will produce a float, but a caller passing `0` for "not started" or `1` for "complete" will crash. The `0.0..1.0` contract in the docstring is also violated by NaN/infinity floats — `floor(NaN * width)` raises `ArithmeticError`.
**Fix:**
```elixir
def render(progress, opts) when is_number(progress) and is_list(opts) do
  %Theme{} = theme = Keyword.fetch!(opts, :theme)
  # ...
  progress = progress |> to_float() |> sanitize() |> clamp(0.0, 1.0)
  # ...
end

defp to_float(n) when is_integer(n), do: n * 1.0
defp to_float(n) when is_float(n), do: n

# Guard against NaN/Infinity (NaN != NaN, Infinity is not finite)
defp sanitize(n) when n != n, do: 0.0   # NaN
defp sanitize(n), do: n
```

### WR-02: `Input.RadioGroup.render/3` silently swallows out-of-range `selected_index`

**File:** `lib/foglet_bbs/tui/widgets/input/radio_group.ex:35-48`
**Issue:** When `selected_index >= length(options)` (e.g., a stale index after the option list shrinks), every row is rendered with `( )` and nobody is highlighted. No crash, no warning — the widget just shows an inconsistent state to the user. Negative indices behave the same way. Likely places this happens: a parent screen mutates options without resetting the index.
**Fix:** Either clamp on render, or assert and let it crash so the bug surfaces in development:
```elixir
def render(options, selected_index, opts)
    when is_list(options) and is_integer(selected_index) and is_list(opts) do
  %Theme{} = theme = Keyword.fetch!(opts, :theme)

  selected_index =
    cond do
      options == [] -> -1
      selected_index < 0 -> 0
      selected_index >= length(options) -> length(options) - 1
      true -> selected_index
    end
  # …
end
```
Add a test for `RadioGroup.render(["a", "b"], 5, theme: ...)` so the contract is pinned.

### WR-03: `Input.Menu` auto-generated IDs are non-deterministic and unroutable

**File:** `lib/foglet_bbs/tui/widgets/input/menu.ex:114`
**Issue:** `Map.put_new_lazy(:id, fn -> :erlang.unique_integer([:positive]) end)` mints a fresh process-monotonic integer every time `init/1` runs. The action returned on activation is `{:menu_action, cursor_id}` — so a screen written like

```elixir
Menu.init(items: [%{label: "New"}, %{label: "Open"}])
# …
{:menu_action, id} -> dispatch(id)
```

receives an integer that depends on VM uptime and execution order. There's no stable mapping back to "New" vs "Open" — the screen can't `case` on it. The moduledoc says "Pitfall 7 — every item must have :id," yet the code silently auto-generates one and lets the caller hit a downstream dead end.
**Fix:** Either require `:id` (raise on missing, mirroring Raxol's own contract) or derive a deterministic id from the label index path:
```elixir
defp normalize_item(item, path \\ []) when is_map(item) do
  unless Map.has_key?(item, :id) or Map.has_key?(item, :label) do
    raise ArgumentError, "Menu items require :id or :label"
  end
  id = Map.get_lazy(item, :id, fn -> {:auto, path ++ [item.label]} end)
  # …
end
```
At minimum, change the moduledoc Pitfall 7 note from "fills in defaults" to "raises if neither :id nor a derivable label is present" so callers know auto-generated ids will not round-trip.

### WR-04: `Input.Tabs.normalize_tab/1` raises `FunctionClauseError` on bad input

**File:** `lib/foglet_bbs/tui/widgets/input/tabs.ex:89-90`
**Issue:** Two clauses only — `is_binary(label)` and `%{label: _}`. A tab passed as `nil`, an atom, a tuple, or a map without `:label` produces a confusing `FunctionClauseError` deep inside `Enum.map`. Compared to other widgets in this phase (`Menu` normalizes in-place, `TextInput` defaults missing values), this clause is the strictest in the catalog.
**Fix:** Add a fallback that raises with a helpful message, or accept atoms:
```elixir
defp normalize_tab(label) when is_binary(label), do: %{label: label}
defp normalize_tab(label) when is_atom(label) and not is_nil(label), do: %{label: Atom.to_string(label)}
defp normalize_tab(%{label: _} = tab), do: tab
defp normalize_tab(other),
  do: raise ArgumentError, "Tabs.init :tabs entry must be a string or %{label: …}; got #{inspect(other)}"
```

### WR-05: `Display.Table` initial `:selected_row = 0` synthesizes a "selection" on empty tables

**File:** `lib/foglet_bbs/tui/widgets/display/table.ex:88-89`
**Issue:** `init/1` unconditionally sets `selected_row: 0` even when `rows: []`. Pressing Enter on an empty table calls `derive_action` → `Enum.at([], 0)` → nil → `nil` action returned. That's safe, but the rendered tree still highlights "row 0" with `selected.fg/selected.bg` — the user sees a phantom selection bar above an empty table.
**Fix:** Initialize `selected_row` to `nil` (or `-1`) when rows are empty, and gate the highlighting on `is_integer(selected_row) and selected_row < length(data)`. Alternatively, document that empty tables are visually undefined and add a `if rows == [], do: render_empty_state(theme)` short-circuit in `render/2`.

### WR-06: `Display.Tree.derive_action` may misclassify `:enter` on parents

**File:** `lib/foglet_bbs/tui/widgets/display/tree.ex:126-137`
**Issue:** The `cond` chain is:
1. `after_size > before_size → :node_expanded`
2. `after_size < before_size → :node_collapsed`
3. `key == :enter → :node_activated`
4. `true → nil`

If RaxolTree's `:enter` handler on a parent toggles expansion (collapses an already-expanded parent), branch 2 fires `:node_collapsed` — fine. But if `:enter` on an *already-collapsed* parent does nothing in Raxol (some implementations bind only to `:right` for expand), branches 1 and 2 don't fire, branch 3 fires `:node_activated` — for a parent. The doc contract says `:node_activated — Enter on a leaf node`. The current code would emit `:node_activated` for a parent in that scenario.
**Fix:** Disambiguate by inspecting the cursor node's children:
```elixir
defp derive_action(before_rs, after_rs, %{key: key})
     when key in [:enter, :right, :left, :space] do
  before_size = MapSet.size(Map.get(before_rs, :expanded, MapSet.new()))
  after_size = MapSet.size(Map.get(after_rs, :expanded, MapSet.new()))
  cursor = Map.get(after_rs, :cursor)
  cursor_node = find_node(Map.get(after_rs, :nodes, []), cursor)

  cond do
    after_size > before_size -> :node_expanded
    after_size < before_size -> :node_collapsed
    key == :enter and is_leaf?(cursor_node) -> :node_activated
    true -> nil
  end
end
```
Or update the moduledoc to document the actual semantics: ":node_activated — Enter pressed and expansion did not change."

## Info

### IN-01: `SizeGate.render/1` defends against terminal_size that `too_small?/1` couldn't return true for

**File:** `lib/foglet_bbs/tui/size_gate.ex:74-78`
**Issue:** `too_small?/1` returns `true` only when `terminal_size` is `{cols, rows}` with both integers; for missing/nil/anything else it returns `false`. So `render/1` is only ever called with a well-formed `terminal_size`. The `case Map.get(state, :terminal_size) do {c, r} -> ...; _ -> {0, 0} end` defensive fallback is dead code in the App.view path. Harmless, but worth a comment or removal to keep the "render is reachable only after `too_small?/1`" invariant visible.
**Fix:** Either delete the fallback (`{cols, rows} = state.terminal_size`) or add `# Defensive: App.view only calls us after too_small?/1, so the fallback is unreachable in production.`

### IN-02: 11 test files duplicate `flatten_text`/`collect_text` helpers verbatim

**File:** `test/foglet_bbs/tui/widgets/display/progress_test.exs:9-24` (and 10 other test files in the same diff)
**Issue:** The 16-line `flatten_text` + `collect_text` + `maybe_add_content` block is copy-pasted into every D-18 widget test. This is ~175 lines of duplicated test infrastructure. If the rendered tree shape changes (new `:label` key, different child layout), each file must be updated individually. The file headers acknowledge this with `# --- Local helpers (copied from list_row_test.exs pattern) ---`.
**Fix:** Extract to `test/support/foglet/tui/widget_helpers.ex` (or similar) and `import` it in each test:
```elixir
defmodule Foglet.TUI.WidgetHelpers do
  def flatten_text(tree), do: tree |> collect_text([]) |> Enum.reverse() |> Enum.join("")
  # ...
end
```
Then in each test: `import Foglet.TUI.WidgetHelpers`. Wire `test/support` into `mix.exs` `elixirc_paths` if not already done.

### IN-03: D-18 hygiene tests use substring scan that will match legitimate hex codes

**File:** `test/foglet_bbs/tui/widgets/display/table_test.exs:155` (and similar across all hygiene tests)
**Issue:** `refute serialized =~ ":red"` is a substring check. If a future theme uses a slot value like `"hovered_red"` or a key like `:hovered_red`, the test will fail spuriously. More importantly, `=~ ":green"` would fail if `inspect` ever serializes a string atom containing the substring. Today's themes use hex strings (`"#33ff66"`), so the tests pass — but the assertion is fragile.
**Fix:** Use word-boundary regex or `Regex.match?(~r/(?<![\w-]):red(?![\w-])/, serialized)`:
```elixir
for color <- ~w(red green cyan yellow blue magenta white black) do
  refute Regex.match?(~r/(?<![\w-]):#{color}\b/, serialized),
         "leaked :#{color} atom"
end
```
This prevents both false positives (substring matches inside legitimate values) and tightens the contract to "atom literal only."

### IN-04: `Input.Button` lacks contract test for unknown `:role`

**File:** `lib/foglet_bbs/tui/widgets/input/button.ex:52-56`
**Issue:** `role_style/3` falls through to the `_secondary` clause for any unknown role. If a typo (`:warning` instead of `:danger`) reaches the widget, the user gets a silently-styled secondary button with no warning. The button tests cover the four documented roles and `disabled`, but not `Button.render("x", role: :bogus, theme: t)`.
**Fix:** Either add a `role in [:primary, :secondary, :danger, :success]` guard on `render/2` (so typos crash loudly), or document that unknown roles fall back to `:secondary`.

### IN-05: `to_string(t.border.fg)` is a no-op in test assertions

**File:** `test/foglet_bbs/tui/widgets/display/table_test.exs:68, 76, 90, 99` (and similar across other widget tests)
**Issue:** All `theme.<slot>.fg` values are already strings ("#555555"). `to_string("#555555")` returns the same string. Style nit, but it's worth removing for clarity — readers might think the slot is sometimes a non-string.
**Fix:** `assert serialized =~ t.border.fg`

### IN-06: `SmartList.handle_event` action is computed from a translated/untranslated event mismatch

**File:** `lib/foglet_bbs/tui/widgets/list/smart_list.ex:114-123`
**Issue:** `translate_event_for_select_list/1` rewrites `%{key: :char, char: c}` → `%{key: c, char: c}` for Raxol consumption. But `derive_action` later receives the *original* (untranslated) `event` — line 121. Pattern matching on `%{key: :char}` works because `event` is the pre-translation map. This is correct, but subtle and only obvious if you trace the variable lifetimes. A future refactor that hoists the translation up or reuses `raxol_data` for derivation will silently break the `:char` action.
**Fix:** Add a comment at line 121 making the invariant explicit:
```elixir
# NOTE: derive_action receives the ORIGINAL event (with :key => :char),
# not raxol_data (where :key has been replaced with the character string).
# Do not collapse these — pattern matches downstream depend on it.
action = derive_action(rs, new_rs, event, st.multiple)
```

### IN-07: `Display.Tree.render` drops `theme.selected.bg` when nil

**File:** `lib/foglet_bbs/tui/widgets/display/tree.ex:101-106`
**Issue:** `text(label, fg: theme.selected.fg, bg: theme.selected.bg, style: ...)` always passes `bg:` regardless of whether the slot defines one. All current Foglet themes set `selected.bg` (verified in `theme.ex`), but a future theme that omits `bg` would pass `bg: nil` to Raxol's `text/2`. Behavior depends on Raxol — probably renders without bg, but unverified.
**Fix:** Mirror the conditional pattern in other widgets:
```elixir
attrs =
  [fg: theme.selected.fg, style: Map.get(theme.selected, :style, [])]
  |> then(fn a -> if bg = Map.get(theme.selected, :bg), do: [{:bg, bg} | a], else: a end)
text(label, attrs)
```

### IN-08: `chrome/screen_frame.ex` and `chrome/status_bar.ex` chained `Map.get` falls into the same idiom three different times in this phase

**File:** `lib/foglet_bbs/tui/widgets/chrome/screen_frame.ex:34`, `lib/foglet_bbs/tui/widgets/chrome/status_bar.ex:37`, `lib/foglet_bbs/tui/size_gate.ex:67-70`
**Issue:** All three sites read `theme = (Map.get(state, :session_context) || %{}) |> Map.get(:theme) || Theme.default()`. The pattern is identical and now lives in three files. With the widget catalog landing, the natural home is `Theme.from_state(state)`.
**Fix:** Add `Theme.from_state/1` and replace the three call sites:
```elixir
# theme.ex
@spec from_state(map()) :: t()
def from_state(state) do
  (Map.get(state, :session_context) || %{}) |> Map.get(:theme) || default()
end
```
Not in scope for Phase 8 if it touches files outside the diff, but worth filing as Phase 9 cleanup.
