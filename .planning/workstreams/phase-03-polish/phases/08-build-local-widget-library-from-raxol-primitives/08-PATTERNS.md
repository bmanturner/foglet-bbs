# Phase 8: Build local widget library from Raxol primitives — Pattern Map

**Mapped:** 2026-04-20
**Files analyzed:** 23 (11 widgets + 11 tests + 1 README)
**Analogs found:** 23 / 23

## Summary

Every new widget file has a strong in-repo analog. Three implementation patterns emerge, each anchored by a single existing template file:

- **Pattern 1 (stateless-utility)** → template: `lib/foglet_bbs/tui/widgets/chrome/key_bar.ex`
- **Pattern 2 (delegation to a Raxol component module)** → template: `lib/foglet_bbs/tui/widgets/compose.ex` (struct-held-by-parent, `translate_key/1` + `render_input/3` triplet)
- **Pattern 3 (DSL-only compose for RadioGroup)** → closest analog: `lib/foglet_bbs/tui/widgets/chrome/key_bar.ex` (per-row `text/2` composition via `column style: %{gap: 0}`)

All tests follow `test/foglet_bbs/tui/widgets/list/list_row_test.exs` (canonical `flatten_text/1` + `collect_text/2` helpers) and `test/foglet_bbs/tui/widgets/modal_test.exs` (canonical theme-hygiene assertion block).

The repo has **no existing `README.md` under `lib/`** — the widget index is greenfield. Shape specified below.

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `lib/foglet_bbs/tui/widgets/input/button.ex` | widget (stateless) | request-response | `lib/foglet_bbs/tui/widgets/chrome/key_bar.ex` | exact (theme-slot-only, `text/2` emission) |
| `lib/foglet_bbs/tui/widgets/input/checkbox.ex` | widget (stateless) | request-response | `lib/foglet_bbs/tui/widgets/chrome/key_bar.ex` | exact |
| `lib/foglet_bbs/tui/widgets/input/radio_group.ex` | widget (stateless) | request-response | `lib/foglet_bbs/tui/widgets/chrome/key_bar.ex` + `list/selection_list.ex` | exact (per-row compose via `column`) |
| `lib/foglet_bbs/tui/widgets/input/text_input.ex` | widget (stateful) | event-driven | `lib/foglet_bbs/tui/widgets/compose.ex` | exact (stateful facade over a Raxol input) |
| `lib/foglet_bbs/tui/widgets/input/tabs.ex` | widget (stateful) | event-driven | `lib/foglet_bbs/tui/widgets/compose.ex` | role-match (wraps a different Raxol component) |
| `lib/foglet_bbs/tui/widgets/input/menu.ex` | widget (stateful) | event-driven | `lib/foglet_bbs/tui/widgets/compose.ex` | role-match |
| `lib/foglet_bbs/tui/widgets/display/table.ex` | widget (stateful) | event-driven | `lib/foglet_bbs/tui/widgets/compose.ex` + `modal.ex` (theme map building) | role-match |
| `lib/foglet_bbs/tui/widgets/display/tree.ex` | widget (stateful) | event-driven | `lib/foglet_bbs/tui/widgets/compose.ex` | role-match |
| `lib/foglet_bbs/tui/widgets/display/progress.ex` | widget (stateless) | request-response | `lib/foglet_bbs/tui/widgets/modal.ex` (stateless dispatch over `Raxol.UI.Components.*`) | role-match |
| `lib/foglet_bbs/tui/widgets/progress/spinner.ex` | widget (stateless) | request-response | `lib/foglet_bbs/tui/widgets/chrome/key_bar.ex` (emits `text/2` directly, no Raxol component render) | role-match |
| `lib/foglet_bbs/tui/widgets/list/smart_list.ex` | widget (stateful) | event-driven | `lib/foglet_bbs/tui/widgets/compose.ex` + `list/selection_list.ex` | exact (sibling of SelectionList, stateful flavour) |
| `lib/foglet_bbs/tui/widgets/README.md` | docs index | N/A | *(no existing analog under `lib/`)* — shape specified below | greenfield |
| `test/foglet_bbs/tui/widgets/input/button_test.exs` | test | request-response | `test/foglet_bbs/tui/widgets/modal_test.exs` (stateless + theme hygiene) | exact |
| `test/foglet_bbs/tui/widgets/input/checkbox_test.exs` | test | request-response | `test/foglet_bbs/tui/widgets/modal_test.exs` | exact |
| `test/foglet_bbs/tui/widgets/input/radio_group_test.exs` | test | request-response | `test/foglet_bbs/tui/widgets/list/list_row_test.exs` (row-compose assertions) | exact |
| `test/foglet_bbs/tui/widgets/input/text_input_test.exs` | test | event-driven | `test/foglet_bbs/tui/widgets/compose_test.exs` (event-translation assertions) | exact |
| `test/foglet_bbs/tui/widgets/input/tabs_test.exs` | test | event-driven | `test/foglet_bbs/tui/widgets/compose_test.exs` + `modal_test.exs` | exact |
| `test/foglet_bbs/tui/widgets/input/menu_test.exs` | test | event-driven | `test/foglet_bbs/tui/widgets/compose_test.exs` | exact |
| `test/foglet_bbs/tui/widgets/display/table_test.exs` | test | event-driven | `test/foglet_bbs/tui/widgets/compose_test.exs` + `modal_test.exs` | exact |
| `test/foglet_bbs/tui/widgets/display/tree_test.exs` | test | event-driven | `test/foglet_bbs/tui/widgets/compose_test.exs` | exact |
| `test/foglet_bbs/tui/widgets/display/progress_test.exs` | test | request-response | `test/foglet_bbs/tui/widgets/modal_test.exs` | exact |
| `test/foglet_bbs/tui/widgets/progress/spinner_test.exs` | test | request-response | `test/foglet_bbs/tui/widgets/modal_test.exs` | exact |
| `test/foglet_bbs/tui/widgets/list/smart_list_test.exs` | test | event-driven | `test/foglet_bbs/tui/widgets/list/list_row_test.exs` + `compose_test.exs` | exact |

---

## Shared Patterns (apply to every widget unless overridden)

### A. Theme-slot-only styling with module-constant defaults (D-07 / D-08 / D-09)

**Source:** `lib/foglet_bbs/tui/widgets/chrome/key_bar.ex` lines 1–43 (cleanest example in the repo)
**Apply to:** every new widget module

```elixir
# lib/foglet_bbs/tui/widgets/chrome/key_bar.ex (full file, 43 lines)
defmodule Foglet.TUI.Widgets.Chrome.KeyBar do
  @moduledoc """
  Themed bottom-of-screen key hint bar for Foglet BBS.

  Renders a single row of "[KEY] Description" hints. Colors come from
  the theme's accent slot (key bracket) and dim slot (description).

  Called by Chrome.ScreenFrame — screens do not call this directly.

  UI-SPEC contract:
    Key bracket: fg: theme.accent.fg, style: [:bold]
    Description: fg: theme.dim.fg
    Format: "[{KEY}] {Description}" per hint, gap: 2 between hints
  """

  import Raxol.Core.Renderer.View

  alias Foglet.TUI.Theme

  @doc """
  Renders the key bar.

  `theme` — a `%Foglet.TUI.Theme{}` struct (passed from ScreenFrame).
  `keys`  — list of `{key_label, description}` pairs,
             e.g. `[{"j/k", "Navigate"}, {"Enter", "Select"}]`.
  """
  @spec render(Theme.t(), [{String.t(), String.t()}]) :: any()
  def render(theme, keys) when is_list(keys) do
    accent_style = Map.get(theme.accent, :style, [])

    labels =
      Enum.flat_map(keys, fn {k, d} ->
        [
          text("[#{k}] ", fg: theme.accent.fg, style: accent_style),
          text("#{d}  ", fg: theme.dim.fg)
        ]
      end)

    row style: %{gap: 0} do
      labels
    end
  end
end
```

**Mirror rules for new widgets (Pattern 1 + DSL slot routing):**
- `@moduledoc` opens with a one-line summary, then spells out which theme slots the widget consumes (see key-bar "UI-SPEC contract:" block). Add a "Honours: D-07, D-09, D-13, D-16" line for Phase 8 widgets.
- `import Raxol.Core.Renderer.View` and `alias Foglet.TUI.Theme` are the only imports at module top.
- Module-constant defaults (D-08): declare as module attributes at the top of the file — e.g., `@default_role :secondary`, `@default_page_size 10`, `@default_width 40`. Never read from a shared `Widgets.Defaults` module (D-08 forbids).
- All colors via `theme.<slot>.fg` / `theme.<slot>.bg`; all ANSI styles via `Map.get(theme.<slot>, :style, [])`. Never reach for `:red`, `:green`, etc. atoms.
- Outer block macros take keyword lists; `style:` values are maps: `row style: %{gap: 0} do ... end` (see Pitfall 4 in RESEARCH.md §Common Pitfalls).

### B. Stateful-widget-held-by-parent skeleton (D-14 / D-15)

**Source:** `lib/foglet_bbs/tui/widgets/compose.ex` lines 1–148 (canonical `translate_key/1` + `render_input/3` triplet generalizing to D-14's `init/1` + `handle_event/2` + `render/2`)
**Apply to:** every new stateful widget (`SmartList`, `Display.Table`, `Display.Tree`, `Input.TextInput`, `Input.Tabs`, `Input.Menu`)

Key excerpt — moduledoc shape:

```elixir
# lib/foglet_bbs/tui/widgets/compose.ex:1-24
defmodule Foglet.TUI.Widgets.Compose do
  @moduledoc """
  Shared plumbing for BBS composer screens (COMPOSE-01, COMPOSE-02).

  Extracted from `Foglet.TUI.Screens.PostComposer` and
  `Foglet.TUI.Screens.NewThread` where ~80 LOC of identical helpers sat
  duplicated (Phase 4 D-09, D-10).

  This module is intentionally narrow in scope:

    * `translate_key/1` — Raxol key event map → `MultiLineInput.update/2` message
    * `render_input/3`   — `%MultiLineInput{}` state → `column` of themed `text/2`
                           rows with a `\u2588` cursor block injected at
                           `cursor_pos` when `focused?` is true
  ...
  """

  import Raxol.Core.Renderer.View

  alias Foglet.TUI.Theme
  alias Raxol.UI.Components.Input.MultiLineInput
```

Key excerpt — key-event translation (inspiration for each new widget's `handle_event/2`):

```elixir
# lib/foglet_bbs/tui/widgets/compose.ex:60-94
@spec translate_key(key_event()) :: input_message() | nil
def translate_key(%{key: :backspace}), do: {:backspace}
def translate_key(%{key: :delete}), do: {:delete}
def translate_key(%{key: :enter}), do: {:enter}
def translate_key(%{key: :up}), do: {:move_cursor, :up}
def translate_key(%{key: :down}), do: {:move_cursor, :down}
def translate_key(%{key: :left}), do: {:move_cursor, :left}
def translate_key(%{key: :right}), do: {:move_cursor, :right}
def translate_key(%{key: :home}), do: {:move_cursor_line_start}
def translate_key(%{key: :end}), do: {:move_cursor_line_end}
def translate_key(%{key: :page_up}), do: {:move_cursor_page, :up}
def translate_key(%{key: :page_down}), do: {:move_cursor_page, :down}

def translate_key(%{key: :char, char: c}) when is_binary(c) do
  case String.to_charlist(c) do
    [cp | _] when cp >= 32 -> {:input, cp}
    _ -> nil
  end
end

def translate_key(_), do: nil
```

**Mirror rules for new stateful widgets (Pattern 2):**
- Define `defstruct [:raxol_state, :last_action, ...]` at top of module (pick fields that shadow the wrapped component's state keys where useful).
- `init/1` is a pure constructor: `{:ok, raxol_state} = RaxolComponent.init(keyword_opts)` → return `%__MODULE__{raxol_state: raxol_state, last_action: nil}`. **Always pass keyword lists to Raxol component `init/1`**, not maps (Pitfall 2 in RESEARCH.md).
- `handle_event/2` wraps the Foglet key event before delegating:
  ```elixir
  raxol_event = %Raxol.Core.Events.Event{type: :key, data: event}
  {new_rs, _cmds} = RaxolComponent.handle_event(raxol_event, rs, %{})
  action = derive_action(rs, new_rs, event)
  {%{st | raxol_state: new_rs, last_action: action}, action}
  ```
  Never rebind `state` inside `if/case/cond` branches (CLAUDE.md gotcha — return the new state as the block value).
- `render/2` calls `RaxolComponent.render(rs, %{})` and optionally wraps in a themed outer `box`.
- Compose's module shape (section-header comments separating `translate_key` / `render`, single-responsibility public API) is worth mirroring.

### C. Theme-map building for Raxol component modules (style prop shape)

**Source:** `lib/foglet_bbs/tui/widgets/modal.ex` lines 42–67 (canonical `color_for_type` dispatch to theme slots)
**Apply to:** stateful widgets that must pass a `theme:` prop map to a Raxol component (`Display.Table`, `Display.Tree`, `Display.Progress`, `Input.Menu`)

```elixir
# lib/foglet_bbs/tui/widgets/modal.ex:42-67
@spec render(modal_spec(), Theme.t()) :: any()
def render(%{message: msg} = spec, %Theme{} = theme) do
  type = Map.get(spec, :type, :info)
  title = Map.get(spec, :title, title_for(type))
  msg_fg = color_for_type(type, theme)

  wrapped_lines =
    msg
    |> word_wrap(@wrap_width)
    |> Enum.map(fn line -> text(line, fg: msg_fg) end)

  column [] do
    [text(" #{title} ", fg: theme.title.fg, style: [:bold]), divider()] ++
      wrapped_lines ++
      [text(key_hint_for(type), fg: theme.dim.fg)]
  end
end

defp title_for(:info), do: "Info"
defp title_for(:error), do: "Error"
defp title_for(:warning), do: "Warning"
defp title_for(:confirm), do: "Confirm"

defp color_for_type(:error, %Theme{} = theme), do: theme.error.fg
defp color_for_type(:warning, %Theme{} = theme), do: theme.warning.fg
defp color_for_type(:confirm, %Theme{} = theme), do: theme.warning.fg
defp color_for_type(_info, %Theme{} = theme), do: theme.primary.fg
```

For the Phase 8 stateful widgets that have to pass a `theme:` map into a Raxol component (the component-module style key shape), use a private `build_<widget>_theme/1` function that takes `%Foglet.TUI.Theme{}` and returns the Raxol-shaped map. Example shape for `Display.Table` (from RESEARCH.md §Code Examples §Example 1):

```elixir
defp build_table_theme(%Foglet.TUI.Theme{} = t) do
  %{
    box: %{border_fg: t.border.fg},
    header: %{fg: t.title.fg, style: [:bold]},
    row: %{fg: t.primary.fg},
    selected_row: %{fg: t.selected.fg, bg: t.selected.bg}
  }
end
```

### D. Moduledoc shape with D-## citations

**Source:** `lib/foglet_bbs/tui/widgets/chrome/screen_frame.ex` lines 1–21 + `lib/foglet_bbs/tui/widgets/post/post_card.ex` lines 1–40 + `lib/foglet_bbs/tui/widgets/modal.ex` lines 1–25
**Apply to:** every new widget module

Pattern observed across all three:
1. One-line summary with the requirement ID in parens: `"... for Foglet BBS (FRAME-01, FRAME-02)."` / `"... (D-20)."`.
2. Short prose describing *what it does* (2–5 lines).
3. Explicit contract block (call signatures, options) under a **bold section** (`## Contract` in post_card; `Signature (locked — D-05):` in screen_frame).
4. Explicit opt-out / scope note when relevant (`This module does NOT cover:` in compose.ex).

For Phase 8 widgets, the moduledoc should open with:
```
@moduledoc """
<one-line summary> (D-02).

<2–5 line prose — what wraps what, why it exists>.

Honours:
  * D-07/D-09 — colors come from theme slots only
  * D-13     — `theme:` keyword arg
  * D-14     — `init/1` + `handle_event/2` + `render/2` (no process)    # stateful only
  * D-16     — no state struct (purely stateless)                        # stateless only

## Contract
  <call signatures, options, event types, action atoms>
"""
```

The existing moduledocs that cite requirement IDs parenthetically (e.g., `(WIDGET-01, RENDER-01)` in PostCard, `(D-20)` in Modal) are the closest in-repo analog to the "Honours D-##" block — extend the convention to explicit D-## listing.

### E. Test helpers — `flatten_text/1` + `collect_text/2`

**Source:** `test/foglet_bbs/tui/widgets/list/list_row_test.exs` lines 9–24 (the canonical copy — also present verbatim in `post/markdown_body_test.exs:10-25` and `post/post_card_test.exs:8-23`)
**Apply to:** every new widget test file

```elixir
# test/foglet_bbs/tui/widgets/list/list_row_test.exs:9-24
defp flatten_text(tree), do: tree |> collect_text([]) |> Enum.reverse() |> Enum.join("")

defp collect_text(nil, acc), do: acc
defp collect_text(list, acc) when is_list(list), do: Enum.reduce(list, acc, &collect_text/2)

defp collect_text(%{children: children} = node, acc) do
  acc = maybe_add_content(node, acc)
  collect_text(children, acc)
end

defp collect_text(%{content: content}, acc) when is_binary(content), do: [content | acc]
defp collect_text(%{text: t}, acc) when is_binary(t), do: [t | acc]
defp collect_text(_other, acc), do: acc

defp maybe_add_content(%{content: content}, acc) when is_binary(content), do: [content | acc]
defp maybe_add_content(_node, acc), do: acc
```

**Extraction decision (re shared test helper movement to `test/support/`):**

The helpers are currently duplicated across four test files (`modal_test.exs`, `list/list_row_test.exs`, `post/markdown_body_test.exs`, `post/post_card_test.exs`). Adding 11 more copies is ~165 lines of duplication. **However, this repo's `test/support/` directory contains only Phoenix-style fixtures/cases (`accounts_fixtures.ex`, `boards_fixtures.ex`, `conn_case.ex`, `data_case.ex`) — no `tui_case.ex` or widget-test helper module exists yet.**

- **Recommendation for the planner:** Do *not* extract in this phase — stay consistent with the existing duplicated-helper convention. The redundancy is load-bearing for "each test file is readable standalone" (the same rationale the MarkdownBody and PostCard tests implicitly endorsed). If extraction becomes desirable later, the target location following repo convention is `test/support/widget_case.ex` — a `defmodule Foglet.TUI.WidgetCase` module using `ExUnit.CaseTemplate` + `using do quote do ... end` (matching `test/support/conn_case.ex` / `data_case.ex` shape).
- The D-18 test bar is cheap to satisfy via copy-paste; the planner can defer this cleanup to a later phase.

### F. Theme-hygiene assertion block

**Source:** `test/foglet_bbs/tui/widgets/modal_test.exs` lines 145–161 (the canonical hygiene test)
**Apply to:** every new widget test file

```elixir
# test/foglet_bbs/tui/widgets/modal_test.exs:145-161
describe "render/2 — theme hygiene (Phase 7)" do
  test "no hardcoded color atoms appear in the rendered tree" do
    for type <- [:info, :error, :warning, :confirm] do
      tree = Modal.render(%{type: type, message: "x"}, theme())
      serialized = inspect(tree, printable_limit: :infinity, limit: :infinity)

      refute serialized =~ ":red",
             "#{type} modal leaked :red atom: #{serialized}"

      refute serialized =~ ":yellow",
             "#{type} modal leaked :yellow atom: #{serialized}"

      refute serialized =~ ":green",
             "#{type} modal leaked :green atom: #{serialized}"
    end
  end
end
```

And the theme-slot-routing variant from the same file (lines 107–143) which asserts **positively** that the expected slot color is present:

```elixir
# test/foglet_bbs/tui/widgets/modal_test.exs:107-127
describe "render/2 — theme slot routing (Phase 7)" do
  test ":error modal uses theme.error.fg for message text" do
    t = theme()
    tree = Modal.render(%{type: :error, message: "fail"}, t)
    serialized = inspect(tree, printable_limit: :infinity, limit: :infinity)
    assert serialized =~ to_string(t.error.fg)
  end

  test ":warning modal uses theme.warning.fg for message text" do
    t = theme()
    tree = Modal.render(%{type: :warning, message: "careful"}, t)
    serialized = inspect(tree, printable_limit: :infinity, limit: :infinity)
    assert serialized =~ to_string(t.warning.fg)
  end
  ...
end
```

Every Phase 8 widget test file must include:
1. A `describe "render/… — smoke (D-18)"` block (minimum two assertions: `refute is_nil(result)` and a `flatten_text(result) =~ "..."` label check).
2. A `describe "render/… — theme hygiene (D-18)"` block containing both the hardcoded-atom refute (above) and an alt-theme differential test: `Theme.default()` vs `Theme.resolve(:danger)` render trees must differ after `inspect/1`.

The test template in RESEARCH.md §Code Examples §Example 4 is a verbatim-usable scaffold — planner can copy it into each button/checkbox/etc. test file and swap the module alias.

---

## Pattern Assignments (per-file)

### Plan 08-01: Input stateless — Button, Checkbox, RadioGroup

#### `lib/foglet_bbs/tui/widgets/input/button.ex` (widget, stateless, request-response)

**Analog:** `lib/foglet_bbs/tui/widgets/chrome/key_bar.ex`

**Why:** Key-bar is the canonical theme-slot-routed, module-constant-defaulted, bare-text-emission widget in the repo. Button differs only in role branching — which maps cleanly onto key-bar's accent/dim slot selection (line 34 pattern).

**Structural template (full key_bar.ex above in Shared Pattern A). Copy:**
- `import Raxol.Core.Renderer.View` + `alias Foglet.TUI.Theme` at top.
- `@default_role :secondary` module constant (mirrors key_bar's lack of hidden defaults — each new default is declared as `@default_*` per D-08).
- `role_style/3` private dispatch on role × disabled → `{fg, style_list}` tuple (direct analog: RESEARCH.md §Pattern 1 §Button skeleton lines 320–324).
- Return a bare `text(content, fg: fg, style: style)`. No outer `box`/`column` wrapper (per RESEARCH.md §Open Questions #1: inline widgets render bare, let the screen position them).

**Moduledoc shape:** key_bar.ex lines 1–14 (UI-SPEC contract block documenting every theme slot the widget touches).

#### `lib/foglet_bbs/tui/widgets/input/checkbox.ex` (widget, stateless, request-response)

**Analog:** `lib/foglet_bbs/tui/widgets/chrome/key_bar.ex`

**Why:** Same stateless-utility shape as Button. Checkbox is a label + mark prefix (`[x]` / `[ ]`) styled by theme — reduces to one `text/2` call with role-style logic branching on `checked?` × `disabled`.

**Structural template:** same as Button above. Defaults: `@on_marker "[x]"`, `@off_marker "[ ]"` (mirrors Modal's `@wrap_width 50` module-constant pattern at `modal.ex:39`). `theme.selected.fg` for checked, `theme.unselected.fg` for unchecked, `theme.dim.fg` for disabled.

#### `lib/foglet_bbs/tui/widgets/input/radio_group.ex` (widget, stateless, request-response)

**Analog:** `lib/foglet_bbs/tui/widgets/chrome/key_bar.ex` (for theme slots + `text/2` emission) + `lib/foglet_bbs/tui/widgets/list/selection_list.ex` (for the per-option compose loop)

**Why:** No Raxol component module exists (verified — RESEARCH.md §REQ-W-09). Composition from `text/2` primitives is the only route. SelectionList's `Enum.with_index |> Enum.map → rows → column style: %{gap: 0}` shape (lines 30–43) is the exact skeleton.

**Copy-template — the `column`-of-rows loop:**

```elixir
# lib/foglet_bbs/tui/widgets/list/selection_list.ex:30-43
def render(items, selected_index, row_renderer_fn)
    when is_list(items) and is_integer(selected_index) and is_function(row_renderer_fn, 1) do
  rows =
    items
    |> Enum.with_index()
    |> Enum.map(fn {item, idx} ->
      selected = idx == selected_index
      row_renderer_fn.({item, idx, selected})
    end)

  column style: %{gap: 0} do
    rows
  end
end
```

RadioGroup inlines the row renderer (instead of taking a callable) because the marker/prefix logic is fixed per D-09 (no caller-supplied style). Module constants: `@on_marker "(o)"`, `@off_marker "( )"`. Theme slots: `theme.selected.fg` for the selected option, `theme.unselected.fg` for the rest.

---

### Plan 08-02: Input stateful — TextInput, Tabs, Menu

#### `lib/foglet_bbs/tui/widgets/input/text_input.ex` (widget, stateful, event-driven)

**Analog:** `lib/foglet_bbs/tui/widgets/compose.ex`

**Why:** Compose is the only existing widget that holds a Raxol component's state and exposes a pure `(event, state) -> new_state` transition. TextInput differs by wrapping `Raxol.UI.Components.Input.TextInput` (single-line) instead of `MultiLineInput`, but the shape is identical: defstruct with `:raxol_state`, `init/1` constructing via `RaxolComponent.init/1`, `handle_event/2` wrapping the event as `%Raxol.Core.Events.Event{}`.

**Mirror structure:**
- Compose's header (lines 1–39): moduledoc + `import` + `alias Raxol.UI.Components.Input.MultiLineInput` → for TextInput becomes `alias Raxol.UI.Components.Input.TextInput, as: RaxolTextInput`.
- Per RESEARCH.md §Open Questions #5 recommendation: delegate directly to `TextInput.handle_event/3` via `%Event{}` wrapping (Pattern 2 shape from RESEARCH.md §Pattern 2 §Tree example lines 386–391).
- `handle_event/2` returns `{st, action}` where `action` is one of `:submitted`, `:cancelled`, `:changed`, or `nil` (action-atom convention from RESEARCH.md §Open Questions #4).

Defstruct fields (planner discretion — RESEARCH.md §User Constraints §Claude's Discretion):
```elixir
defstruct [:raxol_state, :validator, :on_submit, last_action: nil]
```

#### `lib/foglet_bbs/tui/widgets/input/tabs.ex` (widget, stateful, event-driven)

**Analog:** `lib/foglet_bbs/tui/widgets/compose.ex`

**Why:** Same Pattern-2 shape. Tabs' state (active tab index, keyboard Left/Right/1–9 routing) lives inside `Raxol.UI.Components.Input.Tabs`; our wrapper holds the raxol_state and emits `{:tab_changed, index}` actions.

Per Pitfall 6 in RESEARCH.md, add a moduledoc note that digit-input conflicts are the parent screen's responsibility (D-15 confirms). Default constants: `@default_active_indicator "▌"` or `"▼"` — planner decides.

#### `lib/foglet_bbs/tui/widgets/input/menu.ex` (widget, stateful, event-driven)

**Analog:** `lib/foglet_bbs/tui/widgets/compose.ex`

**Why:** Same Pattern-2 shape. Menu is the most complex because of `open_path :: [atom()]` nested state (Pitfall 7 in RESEARCH.md) — but the delegation pattern is identical.

Additional mirror: `init/1` must normalize caller-supplied menu items (fill in `:id`, `:disabled`, `:shortcut` when omitted) before calling `RaxolMenu.init/1`. The normalization lives in a private `normalize_items/1` — pattern reference: `modal.ex`'s `title_for/1` / `color_for_type/2` private dispatch style.

---

### Plan 08-03: Display + Progress — Table, Tree, Progress, Spinner

#### `lib/foglet_bbs/tui/widgets/display/table.ex` (widget, stateful, event-driven)

**Analog:** `lib/foglet_bbs/tui/widgets/compose.ex` (for structure) + `lib/foglet_bbs/tui/widgets/modal.ex` (for the private color-dispatch pattern applied to build_table_theme)

**Why:** Pattern 2 (stateful delegation). Table is the only widget in the bucket with an explicit documented theme-map shape (`%{box, header, row, selected_row}` per RESEARCH.md §Code Examples §Example 1). That shape needs a private builder function — modal.ex's `color_for_type/2` private dispatch is the closest in-repo analog.

**Mirror specifics:**
- `defstruct [:raxol_state, :columns, :sortable, :filterable, last_action: nil]`.
- `init/1` passes `options: %{sortable: true, searchable: true}` to `RaxolTable.init/1` when flags are set.
- `render/2` merges theme into `rs.theme` before calling `RaxolTable.render/2`:

```elixir
def render(%__MODULE__{raxol_state: rs}, opts) do
  theme = Keyword.fetch!(opts, :theme)
  rs_with_theme = %{rs | theme: build_table_theme(theme)}
  RaxolTable.render(rs_with_theme, %{})
end

defp build_table_theme(%Foglet.TUI.Theme{} = t) do
  %{
    box: %{border_fg: t.border.fg},
    header: %{fg: t.title.fg, style: [:bold]},
    row: %{fg: t.primary.fg},
    selected_row: %{fg: t.selected.fg, bg: t.selected.bg}
  }
end
```

- Actions: `{:sort_changed, column}`, `{:filter_changed, term}`, `{:row_selected, row}`.

#### `lib/foglet_bbs/tui/widgets/display/tree.ex` (widget, stateful, event-driven)

**Analog:** `lib/foglet_bbs/tui/widgets/compose.ex`

**Why:** Pattern 2 (stateful delegation). RESEARCH.md §Pattern 2 lines 337–417 provides a near-complete implementation scaffold — copy it with minor adaptations.

Actions per RESEARCH.md §Open Questions #4: `:node_expanded`, `:node_collapsed`, `:node_activated`. Default constant: `@default_indent_size 2`.

Pitfall 9 reminder in moduledoc: Tree nodes MUST be `%{id, label, children, data}` maps (not keyword lists or structs).

#### `lib/foglet_bbs/tui/widgets/display/progress.ex` (widget, stateless, request-response)

**Analog:** `lib/foglet_bbs/tui/widgets/modal.ex`

**Why:** Stateless widget that delegates to a Raxol component module (`Raxol.UI.Components.Display.Progress.init/1` + `render/2` called inside a single `render/2` function). Modal's `render/2` pattern — compute theme-derived fields, build the Raxol-facing struct, emit the element tree — is the exact shape. RESEARCH.md §Code Examples §Example 3 gives a full scaffold (lines 658–690).

**Critical:** Pitfall 8 — must construct a `theme:` prop map including `%{progress: %{fg, bg, border, text}}` or Raxol leaks hardcoded `:green`/`:black`/`:white`. Defaults: `@default_width 40`.

#### `lib/foglet_bbs/tui/widgets/progress/spinner.ex` (widget, stateless, request-response)

**Analog:** `lib/foglet_bbs/tui/widgets/chrome/key_bar.ex`

**Why:** Spinner is an *outlier* (RESEARCH.md §Plan Breakdown §Outlier watchlist) — it does NOT delegate to a Raxol component render function. It calls `Raxol.UI.Components.Progress.Spinner.spinner/3` which returns a plain string (frame-based). The wrapper's `render/2` emits that string as a single `text/2` — same shape as key_bar's inline text emission.

Module constants: `@default_style :line` (per RESEARCH.md §Open Questions #2 recommendation), `@default_frame_duration_ms 100`. Theme slot: `theme.accent.fg` (matches BBS "processing indicator" aesthetic — animated emphasis = accent slot).

---

### Plan 08-04: List — SmartList

#### `lib/foglet_bbs/tui/widgets/list/smart_list.ex` (widget, stateful, event-driven)

**Analog:** `lib/foglet_bbs/tui/widgets/compose.ex` (Pattern 2 stateful facade) + `lib/foglet_bbs/tui/widgets/list/selection_list.ex` (sibling convention — same bucket, stateless flavour)

**Why:** SmartList is the most complex wrapper (search + pagination + multi-select). It sits beside SelectionList (D-03: SelectionList stays lean), which establishes the bucket's naming and positioning. Structurally it's a Pattern 2 delegation to `Raxol.UI.Components.Input.SelectList`.

**Mirror selection_list.ex's moduledoc framing** (lines 1–17):

```elixir
# lib/foglet_bbs/tui/widgets/list/selection_list.ex:1-17
defmodule Foglet.TUI.Widgets.List.SelectionList do
  @moduledoc """
  Shared selection list renderer for Foglet BBS (LIST-04, WIDGET-01).

  A pure rendering widget — no internal state. Parent screens own
  selected_index (in state.screen_state). Navigation (j/k/Enter)
  stays in screen modules.

  API:
    SelectionList.render(items, selected_index, row_renderer_fn)
  ...
```

SmartList's moduledoc should explicitly position itself as the **stateful sibling** to SelectionList — "Stateless rendering → SelectionList. Search/pagination/multi-select → SmartList."

**Pattern 2 delegation specifics** (differs from other Pattern-2 widgets because `SelectList.init/1` accepts maps via `validate_props!/1` — Pitfall 2 in RESEARCH.md):
- `defstruct [:raxol_state, :on_submit, :enable_search, :multiple, :page_size, last_action: nil]`.
- `init/1` calls `RaxolSelectList.init(%{options: opts, enable_search: ..., multiple: ..., page_size: @default_page_size})`.
- Actions: `{:item_selected, value}`, `{:items_selected, [values]}` (multi-select), `{:search_changed, term}`.

---

### Plan 08-05: README + integration

#### `lib/foglet_bbs/tui/widgets/README.md` (docs index, greenfield)

**Analog:** None under `lib/` — the repo's only first-party READMEs are the project root `/README.md` and the vendored `docs/raxol/*` READMEs.

**Specified shape** (Claude's discretion per D-12; format recommendation — a two-column Markdown table keyed on module name, one row per D-02 widget + unchanged neighbors):

```markdown
# Foglet.TUI.Widgets — Widget Catalog Index

Every widget in this directory routes colors/styles through
`Foglet.TUI.Theme` (D-07, D-09) and accepts the theme as an explicit
`theme:` keyword argument (D-13). Stateful widgets expose the
`init/1 + handle_event/2 + render/2` triplet; stateless widgets expose
`render/*` only (D-14, D-16).

## Chrome (Phase 1, unchanged)
| Module | File | Description |
|---|---|---|
| `Chrome.ScreenFrame` | [`chrome/screen_frame.ex`](chrome/screen_frame.ex) | Outer frame wrapping every screen |
| `Chrome.StatusBar`   | [`chrome/status_bar.ex`](chrome/status_bar.ex)   | Top-of-screen title + handle bar |
| `Chrome.KeyBar`      | [`chrome/key_bar.ex`](chrome/key_bar.ex)         | Bottom-of-screen key hints |

## Compose / Modal (Phase 4 / 7, flat — unchanged per D-11)
| Module | File | Description |
|---|---|---|
| `Compose` | [`compose.ex`](compose.ex) | Shared plumbing for post/thread composers |
| `Modal`   | [`modal.ex`](modal.ex)     | Modal body (info/error/warning/confirm) |

## Post (Phase 1–3, unchanged)
| Module | File | Description |
|---|---|---|
| `Post.MarkdownBody` | [`post/markdown_body.ex`](post/markdown_body.ex) | Themed markdown renderer |
| `Post.PostCard`     | [`post/post_card.ex`](post/post_card.ex)         | Per-post card (header + body) |

## List
| Module | File | Description |
|---|---|---|
| `List.SelectionList` | [`list/selection_list.ex`](list/selection_list.ex) | Stateless selection list (D-03) |
| `List.ListRow`       | [`list/list_row.ex`](list/list_row.ex)             | Single list row with optional metadata |
| `List.SmartList`     | [`list/smart_list.ex`](list/smart_list.ex)         | Stateful: search + pagination + multi-select (D-02, Phase 8) |

## Input (Phase 8)
| Module | File | Description |
|---|---|---|
| `Input.Button`     | [`input/button.ex`](input/button.ex)         | Themed button with `:role` |
| `Input.Checkbox`   | [`input/checkbox.ex`](input/checkbox.ex)     | Toggle with on_toggle |
| `Input.RadioGroup` | [`input/radio_group.ex`](input/radio_group.ex) | Single-choice selector (DSL-composed) |
| `Input.TextInput`  | [`input/text_input.ex`](input/text_input.ex) | Single-line input with validator/mask |
| `Input.Tabs`       | [`input/tabs.ex`](input/tabs.ex)             | Tab bar with Left/Right/1–9 nav |
| `Input.Menu`       | [`input/menu.ex`](input/menu.ex)             | Nested dropdown / context menu |

## Display (Phase 8)
| Module | File | Description |
|---|---|---|
| `Display.Table`    | [`display/table.ex`](display/table.ex)       | Sortable / filterable / selectable table |
| `Display.Tree`     | [`display/tree.ex`](display/tree.ex)         | Hierarchical tree with expand/collapse |
| `Display.Progress` | [`display/progress.ex`](display/progress.ex) | Animated progress bar (stateless) |

## Progress (Phase 8)
| Module | File | Description |
|---|---|---|
| `Progress.Spinner` | [`progress/spinner.ex`](progress/spinner.ex) | Indeterminate spinner (stateless) |
```

---

## Per-test-file pattern assignments

Every new test file follows the **same skeleton**:

1. `use ExUnit.Case, async: true`.
2. `alias Foglet.TUI.Theme` + `alias Foglet.TUI.Widgets.<...>` as the widget under test.
3. Copy `flatten_text/1` + `collect_text/2` + `maybe_add_content/2` verbatim from `test/foglet_bbs/tui/widgets/list/list_row_test.exs:9-24` (Shared Pattern E above).
4. `defp theme, do: Theme.default()` + `defp alt_theme, do: Theme.resolve(:danger)` — two-line private helpers (matches Modal test `theme/0` at line 28).
5. Two `describe` blocks per D-18:
   - `"render/… — smoke (D-18)"` — at least `refute is_nil(result)` + label-in-tree assertion.
   - `"render/… — theme hygiene (D-18)"` — hardcoded-atom refute (mirror `modal_test.exs:146-161`) + alt-theme differential test (see RESEARCH.md §Code Examples §Example 4 lines 760–768).
6. **Stateful widgets add a third `describe`:** `"handle_event/2 (D-14)"` — deterministic state-transition + action-atom assertions. Pattern source: `test/foglet_bbs/tui/widgets/compose_test.exs` `describe "translate_key/1 — …"` blocks (lines 12–80).

Per-test-file callouts:

| Test file | Smoke template | State template | Notes |
|-----------|---------------|----------------|-------|
| `input/button_test.exs` | modal_test.exs `describe "render/2 (Phase 7 thin adapter)"` | n/a (stateless) | Verbatim adaptation of RESEARCH.md §Code Examples §Example 4 |
| `input/checkbox_test.exs` | modal_test.exs | n/a | Toggle on/off visual differential |
| `input/radio_group_test.exs` | list_row_test.exs `describe "render/3 — backwards compatibility"` (flat `flatten_text` assertion) | n/a | Assert marker + prefix pattern per option |
| `input/text_input_test.exs` | modal_test.exs | compose_test.exs `describe "translate_key/1 — …"` | Assert `{state, :submitted}` on Enter |
| `input/tabs_test.exs` | modal_test.exs | compose_test.exs | Assert `{state, {:tab_changed, n}}` on Left/Right/digits |
| `input/menu_test.exs` | modal_test.exs | compose_test.exs | Test normalize_items default insertion + nested open_path |
| `display/table_test.exs` | modal_test.exs `describe "render/2 — theme slot routing"` (positive slot assertions) | compose_test.exs | Assert build_table_theme/1 wiring |
| `display/tree_test.exs` | modal_test.exs | compose_test.exs | Expand/collapse state-transition tests |
| `display/progress_test.exs` | modal_test.exs | n/a | Pitfall 8 — refute `:green`/`:black`/`:white` leak |
| `progress/spinner_test.exs` | modal_test.exs | n/a | Assert frame-index advance → different glyph |
| `list/smart_list_test.exs` | list_row_test.exs (for list-shape) + modal_test.exs (for hygiene) | compose_test.exs | Search-buffer + page-change state transitions |

---

## No Analog Found

None. Every new `.ex` widget file has a clear analog; every new `.exs` test file has a clear analog. The only greenfield file is `lib/foglet_bbs/tui/widgets/README.md`, and its shape is specified above.

## Metadata

**Analog search scope:** `lib/foglet_bbs/tui/widgets/` (all subdirectories) + `test/foglet_bbs/tui/widgets/` + `test/support/` + repo-wide `README.md` glob.
**Files scanned:** 9 widget modules (7 existing pre-Phase 8 + Modal + PostCard moduledocs) + 4 widget test files + 4 `test/support/` Phoenix helpers.
**Pattern extraction date:** 2026-04-20
