# Phase 7: Migrate Hand-Rolled UI Components to Raxol Widgets — Pattern Map

**Mapped:** 2026-04-20
**Files analyzed:** 8 (2 source modifications, 1 source stays unchanged, 3 test creates/modifies, 2 caller updates)
**Analogs found:** 8 / 8

---

## File Classification

| New/Modified File | Role | Data Flow | Closest Analog | Match Quality |
|-------------------|------|-----------|----------------|---------------|
| `lib/foglet_bbs/tui/widgets/modal.ex` | render function (thin adapter) | request-response | `lib/foglet_bbs/tui/widgets/chrome/screen_frame.ex` | exact — explicit-arg `render/N` that receives theme directly |
| `lib/foglet_bbs/tui/app.ex` | caller / orchestrator | request-response | `lib/foglet_bbs/tui/app.ex` (self — `render_modal_overlay/2` + theme extraction) | exact — same file, extends existing pattern |
| `lib/foglet_bbs/tui/screens/post_reader.ex` | screen / state holder | event-driven + CRUD | `lib/foglet_bbs/tui/screens/post_reader.ex` (self — replaces `scroll_offset` with Viewport state) | exact — same file, replaces one state field |
| `lib/foglet_bbs/tui/widgets/post/post_card.ex` | render function | transform | `lib/foglet_bbs/tui/widgets/post/markdown_body.ex` (flat line list return) | role-match — both produce structured Raxol element children |
| `lib/foglet_bbs/tui/widgets/post/markdown_body.ex` | render function | transform | `lib/foglet_bbs/tui/widgets/post/markdown_body.ex` (self — scroll slicing moves out to Viewport) | exact — same file, `window_lines/3` pipeline removed from caller path |
| `test/foglet_bbs/tui/widgets/modal_test.exs` | test | — | `test/foglet_bbs/tui/widgets/modal_test.exs` (existing — extend, not replace) | exact — file already exists |
| `test/foglet_bbs/tui/screens/post_reader_test.exs` | test | — | `test/foglet_bbs/tui/screens/post_reader_test.exs` (existing — update assertions) | exact — file already exists |
| `test/foglet_bbs/tui/widgets/post/post_card_test.exs` | test | — | `test/foglet_bbs/tui/widgets/list/list_row_test.exs` | role-match — same flatten_text helper + theme slot inspect pattern |

---

## Pattern Assignments

### `lib/foglet_bbs/tui/widgets/modal.ex` (render function, request-response)

**Analog:** `lib/foglet_bbs/tui/widgets/chrome/screen_frame.ex`

The explicit-arg pattern: `ScreenFrame.render/4` receives `state, title, content_element, key_list` and extracts the theme from `state` itself. For `Modal.render/2`, the theme is passed as an explicit second argument (not extracted from state) because Modal's only caller is `app.ex`, which already holds the extracted theme at call time. This is consistent with how `ListRow.render/3` and `KeyBar.render/2` accept `theme` explicitly rather than a full state.

**Imports pattern** (`screen_frame.ex` lines 23–26, `modal.ex` lines 27–27):
```elixir
import Raxol.Core.Renderer.View

alias Foglet.TUI.Theme
alias Foglet.TUI.Widgets.Chrome.KeyBar   # (Modal doesn't need these aliases)
```

**Current `render/1` signature** (`modal.ex` lines 39–54):
```elixir
@spec render(modal_spec()) :: any()
def render(%{message: msg} = spec) do
  type = Map.get(spec, :type, :info)
  title = Map.get(spec, :title, title_for(type))
  color = color_for(type)              # returns hardcoded atom: :red, :yellow, :green

  wrapped_lines =
    msg
    |> word_wrap(@wrap_width)
    |> Enum.map(fn line -> text(line, fg: color) end)

  column [] do
    [text(" #{title} ", style: [:bold]), divider()] ++
      wrapped_lines ++
      [text(key_hint_for(type), style: [:dim])]
  end
end
```

**Target `render/2` signature** — add `theme` arg, replace hardcoded color atoms with theme slots:
```elixir
@spec render(modal_spec(), Theme.t()) :: any()
def render(%{message: msg} = spec, %Theme{} = theme) do
  type = Map.get(spec, :type, :info)
  title = Map.get(spec, :title, title_for(type))
  msg_fg = color_for_type(type, theme)   # reads theme.error.fg, theme.warning.fg, etc.

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

defp color_for_type(:error, theme), do: theme.error.fg
defp color_for_type(:warning, theme), do: theme.warning.fg
defp color_for_type(:confirm, theme), do: theme.warning.fg
defp color_for_type(_info, theme), do: theme.primary.fg
```

**Theme slot injection pattern** — from `list_row.ex` lines 50–54 and 172–193:
```elixir
# Direct slot access on the theme struct — same approach in every widget
text(full, fg: theme.selected.fg, bg: theme.selected.bg, style: selected_style)
text(full, fg: theme.unselected.fg)
text(padding_part, fg: theme.dim.fg)
```

**What to preserve:** `word_wrap/2`, `title_for/1`, `key_hint_for/1` — all private helpers are unchanged. Only `color_for/1` is replaced by `color_for_type/2`.

---

### `lib/foglet_bbs/tui/app.ex` (caller, request-response)

**Analog:** `lib/foglet_bbs/tui/widgets/chrome/screen_frame.ex` lines 34–34 (theme extraction idiom)

The theme extraction pattern used everywhere else in the codebase:

**Theme extraction pattern** (`screen_frame.ex` line 34, `size_gate.ex` lines 67–71, `post_reader.ex` line 32):
```elixir
# From screen_frame.ex:34 — the canonical form
theme = (Map.get(state, :session_context) || %{}) |> Map.get(:theme) || Theme.default()

# From size_gate.ex:67-71 — same pattern, piped differently
theme =
  (Map.get(state, :session_context) || %{})
  |> Map.get(:theme)
  |> Kernel.||(Theme.default())
```

**Current `render_modal_overlay/2`** (`app.ex` lines 173–181):
```elixir
defp render_modal_overlay(modal, _terminal_size) do
  column justify: :center, align: :center do
    [
      box style: %{border: :double, padding: 1} do
        Widgets.Modal.render(modal)
      end
    ]
  end
end
```

**Target `render_modal_overlay/2`** — extract theme from state, pass to `Modal.render/2`, add `border_fg`:
```elixir
defp render_modal_overlay(modal, state) do
  theme = (Map.get(state, :session_context) || %{}) |> Map.get(:theme) || Theme.default()

  column justify: :center, align: :center do
    [
      box style: %{border: :double, padding: 1, border_fg: theme.border.fg} do
        Widgets.Modal.render(modal, theme)
      end
    ]
  end
end
```

**Call site change** — `app.ex` line 158 (inside `view/1`):
```elixir
# BEFORE
render_modal_overlay(state.modal, state.terminal_size)

# AFTER
render_modal_overlay(state.modal, state)
```

The `alias Foglet.TUI.Theme` already exists in `app.ex` (verified at line 21 area via `alias Raxol.Core.Runtime.Command`). Check whether `Theme` is explicitly aliased or accessed via `Widgets.Modal` — if not aliased, add it following the existing alias block pattern.

---

### `lib/foglet_bbs/tui/screens/post_reader.ex` (screen, event-driven)

**Analog:** `vendor/raxol/lib/raxol/ui/components/display/viewport.ex` (Viewport API reference)

The Viewport is a plain module used without `use Raxol.UI.Components.Base.Component` in the caller.

**Current screen state shape** (`post_reader.ex` lines 209–215):
```elixir
defp default_screen_state do
  %{
    selected_post_index: 0,
    scroll_offset: 0,      # ← replaced by viewport
    render_cache: %{}      # ← preserved unchanged
  }
end
```

**Target screen state shape** — `scroll_offset` removed, `viewport` Viewport state added:
```elixir
alias Raxol.UI.Components.Display.Viewport

defp default_screen_state do
  {:ok, vp} = Viewport.init(%{
    id: "post_reader_vp",
    children: [],
    visible_height: 10,      # updated at render time
    show_scrollbar: false,   # BBS aesthetic
    scroll_top: 0
  })

  %{
    selected_post_index: 0,
    viewport: vp,            # replaces scroll_offset
    render_cache: %{}        # preserved unchanged
  }
end
```

**Current `scroll_post/2`** (`post_reader.ex` lines 305–333) — manual clamp math:
```elixir
defp scroll_post(state, delta) do
  ...
  total_lines = PostCard.body_line_count(Map.get(post, :body))
  max_offset = max(total_lines - available_height, 0)
  new_offset = (ss.scroll_offset + delta) |> max(0) |> min(max_offset)
  ss = %{ss | scroll_offset: new_offset}
  ...
end
```

**Target `scroll_post/2`** — delegates to `Viewport.update/2`:
```elixir
# Viewport.update/2 call pattern (from viewport.ex lines 90-99)
{new_vp, []} = Viewport.update({:scroll_by, delta}, ss.viewport)
ss = %{ss | viewport: new_vp}
```

**Current `advance_post/2`** (`post_reader.ex` line 285) — resets scroll_offset on N/P:
```elixir
ss = %{ss | selected_post_index: new_idx, scroll_offset: 0}
```

**Target `advance_post/2`** — reset via Viewport.update:
```elixir
{reset_vp, []} = Viewport.update({:scroll_to, 0}, ss.viewport)
ss = %{ss | selected_post_index: new_idx, viewport: reset_vp}
```

**Viewport render call pattern** (from `viewport.ex` lines 174–213):
```elixir
# Viewport.render/2 takes (vp_state, context_map) and returns a %{type: :row, ...} element
# context_map is %{} in our case (no focus manager wired)
rendered = Viewport.render(vp_state, %{})
```

**Target `render_post_content/5`** — sets `visible_height` and `children` before rendering:
```elixir
defp render_post_content(state, ss, theme, w, h) do
  ...
  available_height = max(h - 10, 5)
  tuples = ss.render_cache[{post.id, w}] || parse_body(state, post)

  # Pre-render children with theme hex — Viewport passes through unmodified
  themed_lines = PostCard.render_lines(post, tuples, w, theme, index: idx, total: total)
  # themed_lines is a list of individual Raxol row elements (one per line)

  {vp_with_height, []} = Viewport.update({:set_visible_height, available_height}, ss.viewport)
  {vp_with_children, []} = Viewport.update({:set_children, themed_lines}, vp_with_height)

  Viewport.render(vp_with_children, %{})
end
```

**Children granularity decision** (Open Question 1 from RESEARCH.md): Viewport children must be a flat list of individual Raxol row elements — one per logical body line — so j/k scrolls by one line at a time. This means `PostCard` or `MarkdownBody` must be able to return the line list before wrapping in the outer `column`. See PostCard and MarkdownBody sections below.

---

### `lib/foglet_bbs/tui/widgets/post/post_card.ex` (render function, transform)

**Analog:** `lib/foglet_bbs/tui/widgets/post/markdown_body.ex` lines 159–165 (flat list before column wrap)

Currently `PostCard.render_from_tuples/5` calls `MarkdownBody.render_tuples/4` which internally does `column do rows end`. After the Viewport migration, the column wrapper must not exist — instead the individual rows are passed as Viewport children.

**Current rendering pipeline** (`post_card.ex` lines 83–87 and `markdown_body.ex` lines 84–93):
```elixir
# post_card.ex: render_from_tuples calls MarkdownBody which wraps in a column
def render_from_tuples(post, tuples, width, %Theme{} = theme, opts \\ []) do
  body_element = MarkdownBody.render_tuples(tuples, width, theme, body_opts(opts))
  assemble_card(post, theme, body_element, opts)   # body_element is a column
end

# markdown_body.ex: lines_to_column/2 wraps in column
defp lines_to_column(line_groups, theme) do
  rows = Enum.map(line_groups, fn group -> line_group_to_row(group, theme) end)
  column style: %{gap: 0} do rows end
end
```

**Target:** Add a `render_lines/5` function to PostCard (or expose a `render_line_list/4` from MarkdownBody) that returns the flat list of row elements without the column wrapper. The Viewport receives this list as `children:`.

**Pattern to replicate** — flat list return before the column wrap, from `markdown_body.ex` lines 159–165:
```elixir
# The rows list produced here is what Viewport needs as children
defp lines_to_column(line_groups, theme) do
  rows = Enum.map(line_groups, fn group -> line_group_to_row(group, theme) end)
  # Currently: column style: %{gap: 0} do rows end
  # New helper: just return rows (the list), let Viewport wrap them
end
```

**New PostCard function target signature** (named to avoid conflating with existing `render_from_tuples/5`):
```elixir
@doc """
Returns the body as a flat list of Raxol row elements for Viewport use.
Viewport.update({:set_children, list}, vp) expects this shape.
Does NOT include the post header (Post 1 of N, By @handle, divider).
"""
@spec render_body_lines(post_like(), [MarkdownBody.tuple_entry()], pos_integer(), Theme.t(), keyword()) :: [any()]
def render_body_lines(post, tuples, width, %Theme{} = theme, opts \\ []) do
  MarkdownBody.render_tuples_as_lines(tuples, width, theme, body_opts(opts))
end
```

**Existing `assemble_card/4` pattern** (`post_card.ex` lines 109–125) — the header elements (dim text, divider) are built separately and remain as non-Viewport content:
```elixir
defp assemble_card(post, theme, body_element, opts) do
  index = Keyword.get(opts, :index, 0)
  total = Keyword.get(opts, :total, 1)

  header_line_1 = text("Post #{index + 1} of #{total}", fg: theme.dim.fg)
  header_line_2 = text(author_line(post), fg: theme.dim.fg)
  header_divider = divider(char: "─", style: %{fg: theme.border.fg})

  column style: %{gap: 0} do
    [header_line_1, header_line_2, header_divider, body_element]
  end
end
```

After the Viewport migration, `render_post_content/5` in `post_reader.ex` builds the header separately (using the existing `assemble_card` elements) and passes only the body line list to Viewport. The planner must decide whether to keep a header column above the Viewport or whether the Viewport receives header + body lines all as children.

---

### `lib/foglet_bbs/tui/widgets/post/markdown_body.ex` (render function, transform)

**Analog:** `lib/foglet_bbs/tui/widgets/post/markdown_body.ex` (self — expose the pre-column line list)

The `window_lines/3` helper is the scroll slicing that moves to the Viewport. After migration, `render_tuples/4` no longer needs `scroll_offset:` or `max_lines:` opts — Viewport handles windowing. The `window_lines/3` private function becomes dead code (or is removed).

**Current `render_tuples/4`** (`markdown_body.ex` lines 84–93):
```elixir
def render_tuples(tuples, width, %Theme{} = theme, opts \\ []) do
  scroll_offset = Keyword.get(opts, :scroll_offset, 0)
  max_lines = Keyword.get(opts, :max_lines, :all)

  tuples
  |> group_by_newline()
  |> window_lines(scroll_offset, max_lines)    # ← scroll slicing — moves to Viewport
  |> lines_to_column(theme)
end
```

**New `render_tuples_as_lines/4`** — returns the flat list of row elements, no column wrap, no windowing:
```elixir
@doc """
Returns a flat list of Raxol row elements — one per logical line.
Used by PostCard.render_body_lines/5 to supply Viewport children.
No windowing — Viewport.update({:set_children, list}, vp) handles slicing.
"""
@spec render_tuples_as_lines([tuple_entry()], pos_integer(), Theme.t(), keyword()) :: [any()]
def render_tuples_as_lines(tuples, _width, %Theme{} = theme, _opts \\ []) do
  tuples
  |> group_by_newline()
  |> Enum.map(fn group -> line_group_to_row(group, theme) end)
end
```

**`group_by_newline/1` and `line_group_to_row/2` are unchanged** (`markdown_body.ex` lines 117–128, 171–181):
```elixir
defp group_by_newline(tuples) do
  tuples
  |> Enum.chunk_by(&newline?/1)
  |> Enum.reject(&newline_group?/1)
end

defp line_group_to_row([{s, style}], theme) do
  styled_text(s, style, theme)
end

defp line_group_to_row(tuples, theme) do
  children = Enum.map(tuples, fn {s, style} -> styled_text(s, style, theme) end)
  row style: %{gap: 0} do children end
end
```

**Backward compatibility:** `render_tuples/4` with `scroll_offset:` / `max_lines:` opts can remain for existing callers (e.g. `PostCard.render_from_tuples/5` which is still used for non-Viewport rendering paths). The new `render_tuples_as_lines/4` is additive.

---

### `test/foglet_bbs/tui/widgets/modal_test.exs` (test — extend existing)

**Analog:** `test/foglet_bbs/tui/widgets/modal_test.exs` (existing file) + `test/foglet_bbs/tui/widgets/list/list_row_test.exs` lines 219–236 (theme slot inspection pattern)

The file already exists with `describe "render/1 (D-20)"` tests that call `Modal.render/1`. After the thin-adapter change, those tests must be updated to pass a theme as the second argument.

**Current test call pattern** (`modal_test.exs` lines 29–46):
```elixir
describe "render/1 (D-20)" do
  test "returns a non-nil view element for :info" do
    assert _ = Modal.render(%{type: :info, message: "Hello"})
  end
  ...
  test "raises when :message is missing" do
    assert_raise FunctionClauseError, fn -> Modal.render(%{type: :info}) end
  end
end
```

**Target test call pattern** — add `theme` arg, update the describe label, add theme slot assertions:
```elixir
defp theme, do: Foglet.TUI.Theme.default()

describe "render/2 — thin adapter (Phase 7)" do
  test "returns a non-nil view element for :info" do
    assert _ = Modal.render(%{type: :info, message: "Hello"}, theme())
  end

  test "raises when :message is missing" do
    assert_raise FunctionClauseError, fn ->
      Modal.render(%{type: :info}, theme())
    end
  end
end
```

**Theme slot assertion pattern** — from `list_row_test.exs` lines 162–166 (inspect for hex value):
```elixir
# No hardcoded color atoms in Modal output (Wave 0 gap test)
test "no hardcoded color atoms appear in the rendered tree" do
  tree = Modal.render(%{type: :error, message: "Oh no"}, theme())
  serialized = inspect(tree, printable_limit: :infinity, limit: :infinity)

  refute serialized =~ ":red"
  refute serialized =~ ":yellow"
  refute serialized =~ ":green"
end

# Theme slot fg values appear in output
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

test ":info modal uses theme.primary.fg for message text" do
  t = theme()
  tree = Modal.render(%{type: :info, message: "ok"}, t)
  serialized = inspect(tree, printable_limit: :infinity, limit: :infinity)
  assert serialized =~ to_string(t.primary.fg)
end

test "title uses theme.title.fg" do
  t = theme()
  tree = Modal.render(%{type: :info, message: "ok"}, t)
  serialized = inspect(tree, printable_limit: :infinity, limit: :infinity)
  assert serialized =~ to_string(t.title.fg)
end

test "key hint uses theme.dim.fg" do
  t = theme()
  tree = Modal.render(%{type: :info, message: "ok"}, t)
  serialized = inspect(tree, printable_limit: :infinity, limit: :infinity)
  assert serialized =~ to_string(t.dim.fg)
end
```

---

### `test/foglet_bbs/tui/screens/post_reader_test.exs` (test — update assertions)

**Analog:** `test/foglet_bbs/tui/screens/post_reader_test.exs` (existing — update state shape assertions)

The existing tests assert on `screen_state[:post_reader].scroll_offset` directly. After the Viewport migration, those field names change to `viewport.scroll_top`.

**Current scroll-related assertions to update** (`post_reader_test.exs` lines 277–355):
```elixir
# BEFORE — asserts scroll_offset integer
assert s1.screen_state[:post_reader].scroll_offset == 1
assert s1.screen_state[:post_reader].scroll_offset == 0
assert s2.screen_state[:post_reader].scroll_offset == 2
assert s3.screen_state[:post_reader].scroll_offset == 0
```

**Target assertions after Viewport migration:**
```elixir
# AFTER — asserts viewport.scroll_top integer
assert s1.screen_state[:post_reader].viewport.scroll_top == 1
assert s1.screen_state[:post_reader].viewport.scroll_top == 0
assert s2.screen_state[:post_reader].viewport.scroll_top == 2
assert s3.screen_state[:post_reader].viewport.scroll_top == 0
```

**`render_cache` assertions are unchanged** — cache is keyed on `{post.id, width}` and lives at the same path (`screen_state[:post_reader].render_cache`).

**Legacy-state migration test** (`post_reader_test.exs` line 412–432) — must be updated since the legacy pre-Phase-2 shape no longer has `scroll_offset` either:
```elixir
# The legacy state migration test should now assert on viewport.scroll_top
test "j works against a legacy-shaped state (no crash)" do
  s = p2_state(%{
    posts: [p2_post(body: "A\n\nB\n\nC\n\nD")],
    screen_state: %{post_reader: %{selected_post_index: 0}}
  })

  {:update, s1, _} = PostReader.handle_key(%{key: :char, char: "j"}, s)
  # viewport.scroll_top is 0 or 1 depending on content height vs available height
  assert s1.screen_state[:post_reader].viewport.scroll_top in [0, 1]
end
```

---

### `test/foglet_bbs/tui/widgets/post/post_card_test.exs` (test — extend for new function)

**Analog:** `test/foglet_bbs/tui/widgets/list/list_row_test.exs` (flatten_text helper + inspect pattern)

The file already contains tests for `PostCard.render/4` and `PostCard.render_from_tuples/5`. New tests are needed for `PostCard.render_body_lines/5` which returns a list of Raxol elements.

**Existing helper pattern** (`post_card_test.exs` lines 8–25 — copied from list_row_test.exs):
```elixir
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

**New tests for flat list return:**
```elixir
describe "render_body_lines/5 — flat list for Viewport children" do
  test "returns a list (not a column element)" do
    post = sample_post(%{body: "Hello.\n\nWorld."})
    tuples = Foglet.Markdown.render("Hello.\n\nWorld.")
    result = PostCard.render_body_lines(post, tuples, 80, theme())
    assert is_list(result)
  end

  test "each element in the list is a Raxol view element map" do
    post = sample_post(%{body: "Line one.\n\nLine two."})
    tuples = Foglet.Markdown.render("Line one.\n\nLine two.")
    result = PostCard.render_body_lines(post, tuples, 80, theme())
    assert Enum.all?(result, &is_map/1)
    assert Enum.all?(result, fn el -> Map.has_key?(el, :type) end)
  end

  test "list length equals the number of logical lines" do
    body = "A\n\nB\n\nC"
    tuples = Foglet.Markdown.render(body)
    post = sample_post(%{body: body})
    result = PostCard.render_body_lines(post, tuples, 80, theme())
    assert length(result) == 3
  end

  test "flat text content matches body (no header content in list)" do
    body = "Hello **world**."
    tuples = Foglet.Markdown.render(body)
    post = sample_post(%{body: body})
    result = PostCard.render_body_lines(post, tuples, 80, theme())
    flat = flatten_text(result)
    assert flat =~ "world"
    # No "Post 1 of 1" header — render_body_lines is body-only
    refute flat =~ "Post"
  end
end
```

---

## Shared Patterns

### Theme Extraction (from state)
**Source:** `lib/foglet_bbs/tui/widgets/chrome/screen_frame.ex` line 34
**Apply to:** `app.ex` `render_modal_overlay/2` update
```elixir
theme = (Map.get(state, :session_context) || %{}) |> Map.get(:theme) || Theme.default()
```

### Theme Slot Injection into `text/2`
**Source:** `lib/foglet_bbs/tui/widgets/list/list_row.ex` lines 50–54
**Apply to:** `modal.ex` `render/2` body — every `text/2` call takes explicit `fg:` from a theme slot, never a color atom
```elixir
text(full, fg: theme.selected.fg, bg: theme.selected.bg, style: selected_style)
text(full, fg: theme.unselected.fg)
```

### No Hardcoded Color Atoms
**Source:** `test/foglet_bbs/tui/widgets/list/list_row_test.exs` lines 219–236
**Apply to:** `modal_test.exs` new theme-hygiene tests
```elixir
refute serialized =~ ":green"
refute serialized =~ ":cyan"
refute serialized =~ ":red"
refute serialized =~ ":yellow"
```

### Viewport Plain Module Usage (no `use Raxol.UI.Components.Base.Component`)
**Source:** `vendor/raxol/lib/raxol/ui/components/display/viewport.ex` lines 34–64, 73–99, 174–213
**Apply to:** `post_reader.ex` — Viewport is called as a plain module: `Viewport.init/1`, `Viewport.update/2`, `Viewport.render/2`
```elixir
alias Raxol.UI.Components.Display.Viewport

{:ok, vp} = Viewport.init(%{id: "...", children: [], visible_height: 10, show_scrollbar: false})
{new_vp, []} = Viewport.update({:scroll_by, delta}, vp)
{new_vp, []} = Viewport.update({:scroll_to, 0}, vp)
{new_vp, []} = Viewport.update({:set_visible_height, h}, vp)
{new_vp, []} = Viewport.update({:set_children, list}, vp)
rendered = Viewport.render(vp_state, %{})
```

### Test Helper — flatten_text + inspect for theme slots
**Source:** `test/foglet_bbs/tui/widgets/list/list_row_test.exs` lines 9–26, 162–175
**Apply to:** All new widget tests and post_card_test extensions — copy the `flatten_text/1` + `collect_text/2` + `maybe_add_content/2` block verbatim; use `inspect(result, printable_limit: :infinity, limit: :infinity)` for theme slot assertions

---

## No Analog Found

None — all 8 target files have a clear analog in the codebase.

---

## Metadata

**Analog search scope:** `lib/foglet_bbs/tui/`, `test/foglet_bbs/tui/`, `vendor/raxol/lib/raxol/ui/components/display/`
**Files read:** 13 source files, 3 test files
**Pattern extraction date:** 2026-04-20
