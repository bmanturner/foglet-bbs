# Stack Research — Phase 03 Polish

**Domain:** Terminal BBS over SSH — Raxol-based TUI polish (v1.0.1)
**Researched:** 2026-04-19
**Confidence:** HIGH (vendored code + project source read directly)

## Orientation

This is a **polish milestone**. The full app stack is locked and shipped:

| Slot | Tech | Version | Status |
|------|------|---------|--------|
| Runtime | Elixir / OTP | 1.19.5 / 28.3.1 | Locked |
| Web | Phoenix | 1.8.5 | Locked |
| DB | PostgreSQL (via postgrex / ecto_sql 3.13) | — | Locked |
| SSH | Erlang `:ssh` app (direct) | OTP 28 | Locked |
| TUI framework | Raxol (vendored at `vendor/raxol`) | **2.4.0** | Locked |
| Markdown parser | `mdex` | **0.12.1** | Locked (already in `mix.exs`) |
| Password hashing | `argon2_elixir` | 4.x | Locked |
| Background jobs | `oban` | 2.18 | Locked |

Stack research here is therefore narrow and pointed: **which existing Raxol primitives solve the polish milestone problems, and which non-Raxol libs we need to pull in (if any) for things Raxol does not provide.** The goal is a thin reusable-widget layer, not a new stack.

---

## Raxol 2.4.0 Widget Inventory

All widgets documented in `docs/raxol/getting-started/WIDGET_GALLERY.md`, verified against source in `vendor/raxol/lib/raxol/ui/components/`.

**Modern block-macro DSL only.** Layout containers (`column`, `row`, `box`) take a `do ... end` block that must evaluate to a **list** of child elements. Leaf elements (`text`, `divider`, `spacer`, `button`, `text_input`) are plain function calls. The legacy `panel/1` + `box(children: [...])` function-form is silently broken with the modern layout engine — see `memory/feedback_raxol_modern_dsl.md` and the note in the Raxol docs linked above. **Never recommend the legacy form.**

### Layout primitives — what we already use

| DSL | Block form | Modern usage | Polish-scope relevance |
|-----|-----------|--------------|------------------------|
| `column` | yes | `column style: %{gap: 1, padding: 1, align_items: :center} do [...] end` | Screen body stacking. Every screen. |
| `row` | yes | `row style: %{gap: 2} do [...] end` | StatusBar, KeyBar, thread-row columns. |
| `box` | yes | `box style: %{border: :single, padding: 1} do ... end` | Screen frame + modal frame. Borders: `:single`, `:double`, `:rounded`, `:bold`, `:ascii`. |
| `spacer` | no (leaf) | `spacer()` | Push-apart in rows (e.g. status-bar left/right). |
| `divider` | no (leaf) | `divider()` — optional `char:`, `style:` | Header separator beneath StatusBar. |
| `split_pane` | no (leaf) | `split_pane(direction: :horizontal, ratio: {1, 2}, min_size: 10, children: [left, right])` | Not needed for polish (chat will want it later). |

### Display widgets — the "do not reinvent" list

| Widget | DSL? | Component module | Use in polish |
|--------|------|------------------|---------------|
| `text/1` | yes | — | All text. Supports `fg:`, `bg:`, `style: [:bold, :dim, :italic, :underline, :strikethrough, :reverse]`. |
| `label/1` | yes | — | Alias for `text` with `content:`. |
| `list/1` | yes | — | Simple list with optional `selected:` index. Good candidate for boards/threads — currently we hand-roll `Enum.with_index` loops; `list/1` is simpler. |
| `table/1` | yes | `Display.Table` | **Strong candidate for ThreadList rows** — headers + rows + `column_widths: :auto`, `alignments`, `striped`, `selectable`. Handles keyboard navigation. |
| `status_bar` | **no** (component-only) | `Display.StatusBar` | Ready-made key/label pairs with `separator`. Renders bold keys + values. Our `Widgets.StatusBar` does roughly the same thing hand-rolled. **Wrap Raxol's, don't replace.** |
| `viewport` | **no** (component-only) | `Display.Viewport` | **Scrollable post body** for long posts. `visible_height`, `show_scrollbar`, `Viewport.update({:scroll_by, n}, vp)`. |
| `markdown_renderer` | no (component-only) | `Raxol.UI.Components.MarkdownRenderer` | Earmark-based MD → terminal styled text. See §"Markdown" below. |
| `code_block` | no | `Raxol.UI.Components.CodeBlock` | Makeup-powered for Elixir; plain text for others. Future if code snippets matter. |
| `progress` | yes | `Display.Progress` | Not needed for polish. |
| `tree` | no | `Display.Tree` | Not needed for polish. |
| `image` | yes | — | Not applicable — SSH terminal. |

### Input widgets

| Widget | DSL? | Component module | Use in polish |
|--------|------|------------------|---------------|
| `text_input/1` | yes | `Input.TextInput` | **Composer title field** (scope item #7). Single-line, `on_submit`, `max_length`, `validator`, `mask_char` (for passwords if we ever redo login). |
| `textarea/1` | yes | `Input.MultiLineInput` | Already used in Composer for body. |
| `button/1` | yes | `Input.Button` | Optional — we use text + key hints instead. |
| `checkbox/1` | yes | `Input.Checkbox` | Not in polish scope. |
| `radio_group/1` | yes | — | Not in polish scope. |
| `select/1` / `SelectList` | yes / no | `Input.SelectList` | **Candidate for NewThread board picker** — search + keyboard nav already implemented. We currently hand-roll j/k navigation. |
| `tabs/1` | yes | `Input.Tabs` | Not in polish scope. |
| `menu` | no | `Input.Menu` | Not in polish scope. |

### Overlay

| Widget | DSL? | Component module | Use in polish |
|--------|------|------------------|---------------|
| `modal/1` | yes | `Modal` | Already used. Types: `:alert`, `:prompt`, `:form`. Our `Widgets.Modal` is a custom body renderer that reuses the `box :double` frame in `App.render_modal_overlay/2` — keep as-is. |

### DSL call-site rules (re-assert, do not violate)

```elixir
# RIGHT — block-form layout, leaf calls inside the block returning a list
column style: %{gap: 1, padding: 1} do
  [
    text(" Header ", style: [:bold]),
    divider(),
    row style: %{gap: 2} do
      [text("left"), spacer(), text("right")]
    end
  ]
end

# WRONG — legacy function-form (silently renders empty)
panel(title: "Header", children: [text("left"), text("right")])
box(children: [text("a"), text("b")])
```

---

## Raxol Theming System (2.4.0)

Two layers:

### Layer 1 — Inline colors (the idiomatic, always-works layer)

`text/2` accepts `fg:` and `bg:` directly. Colors can be:

- Named ANSI: `:black`, `:red`, `:green`, `:yellow`, `:blue`, `:magenta`, `:cyan`, `:white`
- RGB tuple: `{255, 107, 174}`
- 256-color index: `198`
- Hex string: `"#ff6bae"`

Raxol auto-downsamples to terminal capability (`Raxol.Style.Colors.Adaptive.adapt_color_safe/1`). **Truecolor → 256 → 16 → mono** — handled transparently.

**Recommended pattern (from `docs/raxol/cookbook/THEMING.md`):** define a single module with semantic color helpers:

```elixir
defmodule Foglet.TUI.Theme do
  def accent, do: :cyan        # Titles, active selection
  def highlight, do: :magenta  # Borders, key hints
  def warn, do: :yellow
  def ok, do: :green
  def err, do: :red
  def dim, do: :white  # used with style: [:dim]

  # Component styles returned as keyword lists ready for spreading:
  def title_style, do: [fg: accent(), style: [:bold]]
  def selected_row_style, do: [fg: ok(), style: [:bold]]
  def row_style, do: [fg: ok()]
  def hint_style, do: [style: [:dim]]
end
```

Then in screens: `text("Foo", Foglet.TUI.Theme.title_style())`. This solves scope item #6 (theme inconsistency) without adopting the ThemeManager GenServer.

### Layer 2 — ThemeManager (the GenServer-backed runtime switcher)

`Raxol.UI.Theming.ThemeManager` is a GenServer with:

- `set_theme/1`, `get_theme/1`, `list_themes/0`
- Loads JSON from `priv/themes/` (only `Default.json` shipped — empty palette)
- Per-component styles via `Raxol.UI.Theming.Theme.component_style(theme, :button)`
- Pseudo-state: `:focus`, `:active`, `:disabled` resolved via `FocusHelper`

**Recommendation for polish:** **do not adopt ThemeManager yet.** Milestone 4 ("theme stub" in user preferences) and the roadmap's per-user theme preference are the right place for it. For v1.0.1, a static `Foglet.TUI.Theme` module (Layer 1) solves the inconsistency without taking on the runtime-switcher surface area.

---

## Markdown Rendering (fixes scope item #1 and #3)

### Current state (broken)

`lib/foglet_bbs/markdown.ex` parses markdown via **MDEx 0.12.1** (CommonMark + GFM + syntax highlighting via Rust NIF) → converts HTML → custom `{text, style}` tuples. `PostReader` and `PostComposer` walk the tuples and emit one `text/2` per tuple inside `column style: %{gap: 0}`. Tuple styles are `:bold`, `:italic`, `:dim`, `:underline`, `:plain`.

Problems (from hands-on use):
1. Posts show raw markdown — scope item #1. Likely causes: (a) MDEx not loaded in the runtime path the user tested; (b) seeds created posts with bodies that escape MDEx's regex round-trip; (c) the custom `transform_html_to_markers/1` regex pipeline swallows inputs when HTML contains attributes we don't match.
2. Seeded threads don't wrap — scope item #3. `text/1` itself does not wrap. `render_markdown_tuples/1` emits one `text/1` per styled span, **wrapping is not applied anywhere**. `MultiLineInput` in the composer wraps (`wrap: :word` available), but the reader does not.

### Options (comparison)

| Option | Wrap? | Headings/lists/code? | Deps | Effort | Verdict |
|--------|-------|---------------------|------|--------|---------|
| **A. Keep `Foglet.Markdown` + add word-wrap pass + debug the pipeline** | add manually | already supported | MDEx (have) | medium | Viable — keeps our canonical `{text, style}` shape. |
| **B. Swap to `Raxol.UI.Components.MarkdownRenderer`** | respects `width:` by splitting paragraph text into lines (but does not hard-wrap long lines; it just emits one `text` per paragraph) | yes: h1-h6, ul, ol, pre, blockquote, hr, inline code, links, bold, italic | EarmarkParser optional (has regex fallback) | low-medium | **Recommended** — native Raxol, no custom transform layer, fewer moving parts. Output is `%{type: :column, children: [text_elements]}` which the renderer understands natively. |
| C. Write a new minimal renderer from scratch | yes | subset | none | medium | Worst of both — throws away MDEx work and Raxol's component. |

**Recommendation: Option B.** Use `Raxol.UI.Components.MarkdownRenderer` — initialize with `markdown_text:` and `width:`, then call `render/2`. Adopt `earmark` as an explicit dep (it's currently only a `only: :dev` dep inside vendored Raxol; we want the regex fallback path to not be our primary path).

However, the existing `Foglet.Markdown` module has two properties the Raxol renderer does **not** replicate out of the box:

1. **ANSI-escape sanitization** of user input (see `strip_ansi/1`, T-2-03) — Raxol's renderer does not strip ESC from input text. We must run `strip_ansi` first, then hand to Raxol.
2. **Uppercased headings** (our house style per D-02) — Raxol's renderer leaves headings in source case. A simple post-process of the rendered column or a pre-process of the markdown can uppercase `# Heading` lines.

**Final recommendation — hybrid:**

```elixir
# lib/foglet_bbs/markdown.ex  (refactor target)
alias Raxol.UI.Components.MarkdownRenderer

def render(markdown, width \\ 80) when is_binary(markdown) do
  sanitized = strip_ansi(markdown)
  {:ok, state} = MarkdownRenderer.init(%{markdown_text: sanitized, width: width})
  MarkdownRenderer.render(state, %{})
  # returns %{type: :column, children: [text elements]} — caller inlines it
end
```

Then `PostReader.render_post_content/2` becomes:

```elixir
# inside box/column do block:
Foglet.Markdown.render(post.body, wrap_width(state))
```

and the `render_markdown_tuples/1` walker goes away.

**Word-wrap within rendered paragraphs** is still missing from `Raxol.UI.Components.MarkdownRenderer` — it splits on `\n` but does not break long paragraphs at word boundaries. For posts with long lines we need an additional wrap step. Our existing `Foglet.TUI.Widgets.Modal.word_wrap/2` is the right primitive to lift into a shared utility (`Foglet.TUI.Text.wrap/2`) and apply before or after markdown rendering.

### Makeup (syntax highlighting) — already available

Raxol's `code_block` component uses `makeup` (in `vendor/raxol/mix.exs` as a direct dep). Not needed for v1.0.1 but "free" when we want syntax-highlighted fenced blocks in posts.

---

## "Time Ago" / Relative-Time Formatting (fixes scope item #5)

Needed: short forms — `30s`, `5m`, `2h`, `3d`, `2w` — for thread-row `last_activity`.

### Options

| Option | Scope | Deps | Verdict |
|--------|-------|------|---------|
| **A. Custom module using `DateTime` + `System.os_time(:second)`** | Only what we need | none (stdlib) | **Recommended** — 30-line module, no new deps, exact formatting we want. |
| B. `Timex.from_now/1` | Full i18n duration library | `{:timex, "~> 3.7}"` (new dep) | Overkill — `from_now/1` returns verbose strings like "2 weeks ago". Would need post-processing to get short form. |
| C. `Cldr.DateTime.Relative` (ex_cldr_dates_times) | Locale-aware relative formatter | `{:ex_cldr_dates_times, ...}` | Way overkill. |

**Recommendation: Option A.** The CLAUDE.md project rules explicitly state: *"Elixir's standard library has everything necessary for date and time manipulation ... Never install additional dependencies unless asked."* And we only need short forms.

Reference implementation (for planner consumption):

```elixir
defmodule Foglet.TimeAgo do
  @moduledoc "Short-form relative time strings (30s, 5m, 2h, 3d, 2w, 6mo, 2y)."

  @spec format(DateTime.t() | NaiveDateTime.t(), DateTime.t()) :: String.t()
  def format(past, now \\ DateTime.utc_now())
  def format(%NaiveDateTime{} = nd, now), do: format(DateTime.from_naive!(nd, "Etc/UTC"), now)
  def format(%DateTime{} = past, %DateTime{} = now) do
    diff = DateTime.diff(now, past, :second)
    cond do
      diff < 0         -> "0s"  # clock skew — treat as "just now"
      diff < 60        -> "#{diff}s"
      diff < 3_600     -> "#{div(diff, 60)}m"
      diff < 86_400    -> "#{div(diff, 3_600)}h"
      diff < 7 * 86_400 -> "#{div(diff, 86_400)}d"
      diff < 30 * 86_400 -> "#{div(diff, 7 * 86_400)}w"
      diff < 365 * 86_400 -> "#{div(diff, 30 * 86_400)}mo"
      true             -> "#{div(diff, 365 * 86_400)}y"
    end
  end
end
```

---

## Terminal Capability / Size Detection (fixes scope item #9)

### What Raxol provides

1. **Initial size at startup** — `Raxol.Core.Runtime.Lifecycle.Initializer.detect_terminal_size/1` is called automatically. Passed into `init/1` via `%{width: w, height: h, options: [...]}`. We already handle this in `Foglet.TUI.App.extract_context/1`.
2. **Resize events** — Raxol dispatches a `%Raxol.Core.Events.Event{type: :window, data: %{width:, height:}}` struct to `update/2`. Already normalized to `{:window_change, w, h}` in `App.normalize_message/1`. Our `CLIHandler.handle_ssh_msg({:ssh_cm, _, {:window_change, _ch, w, h, _, _}}, state)` receives SSH PTY `window-change` messages and forwards them.
3. **Event subscription (alternative)** — `Subscription.events([:window_resize])` is documented but the `{:window_change, w, h}` message is already being delivered directly without explicit subscription.
4. **Defaults** — `Raxol.Core.Defaults.terminal_width/0` returns 80, `terminal_height/0` returns 24.

### "Terminal too small" gating pattern

Raxol does **not** provide a minimum-size gate component. We render one in the app's `view/1`.

Recommended pattern (new reusable widget — `Foglet.TUI.Widgets.TooSmall`):

```elixir
# In view/1:
def view(state) do
  {cols, rows} = state.terminal_size
  cond do
    state.modal              -> render_modal_overlay(...)
    cols < min_cols() or rows < min_rows() -> Widgets.TooSmall.render({cols, rows}, {min_cols(), min_rows()})
    true                     -> render_screen(state)
  end
end

defp min_cols, do: 60
defp min_rows, do: 20
```

The TooSmall widget itself is a single centered `column` with a `text/1` of `"Terminal too small (#{cols}×#{rows}) — need at least #{min_cols}×#{min_rows}."` The user resizes → window_change → re-render → gate passes.

---

## Recommended Polish-Milestone Stack Additions

**Zero new deps.** Everything needed is already in `mix.exs` or vendored.

| Addition | Lives In | Role |
|----------|----------|------|
| `Foglet.TUI.Theme` | new module | Single source of truth for semantic colors (scope #6). |
| `Foglet.TUI.Text` | new module | Word-wrap utility (lift from `Widgets.Modal.word_wrap/2`), grapheme-safe line clipping, maybe ANSI-strip. |
| `Foglet.TimeAgo` | new module | Short-form relative times (scope #5). |
| `Foglet.TUI.Widgets.TooSmall` | new widget | Terminal-size gate (scope #9). |
| `Foglet.TUI.Widgets.ScreenFrame` | new widget | Standardized box + header title + divider + StatusBar wrapper (scope #2). Wraps `Raxol.UI.Components.Display.StatusBar` component-call plus our header text; screens pass `title:` and `location:`, the frame does the rest. |
| Refactor `Foglet.Markdown` | existing module | Delegate to `Raxol.UI.Components.MarkdownRenderer` with pre-sanitize + optional uppercase-headings pass (scope #1, #3). |
| Use `Raxol.UI.Components.Display.Viewport` in `PostReader` | existing module | Scrollable post body when body exceeds available rows (scope #3). |

---

## Alternatives Considered

| Chosen | Alternative | When the alternative wins |
|--------|-------------|---------------------------|
| `Raxol.UI.Components.MarkdownRenderer` | Keep custom `Foglet.Markdown` tuple format + add wrap | If we outgrow Raxol's renderer (e.g. need custom nested-list rendering or tables-in-markdown). Revisit at Milestone 9 (search) or Milestone 14 (door games). |
| Inline `fg:`/`bg:` + `Foglet.TUI.Theme` helper module | Adopt `Raxol.UI.Theming.ThemeManager` (GenServer) | When per-user runtime theme switching is needed — **Milestone 4** roadmap item "theme stub." Right call then, not now. |
| Custom `Foglet.TimeAgo` | `timex` `from_now/1` | If we ever need full i18n relative times. Not until Milestone 9 earliest, and we'd reach for `ex_cldr_dates_times` over Timex then. |
| `Raxol.UI.Components.Display.Viewport` | Hand-roll pagination in `PostReader` | If posts become short-always and scroll is overkill — but we already know seeded threads don't fit on screen, so no. |
| `table/1` DSL | Hand-roll thread rows with `Enum.with_index` | When rows need custom per-cell layout that tables can't express — not the case for ThreadList. |

## What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| `panel(...)`, `box(children: [...])` legacy function-form | Silently renders empty with the modern layout engine. See `memory/feedback_raxol_modern_dsl.md`. | `box style: %{...} do ... end` block form. |
| `Heroicons` or any web icon library | N/A in terminal. | Unicode glyphs (`▸`, `•`, `★`) or ASCII. |
| `timex` for "time ago" | Overkill; new dep; verbose format needs post-processing anyway. | `Foglet.TimeAgo` (30 lines, stdlib only). |
| `httpoison` / `tesla` | Project rule: use `Req` only. | `Req` (already available for anything HTTP). |
| `earmark` as a separate direct dep | MDEx already does CommonMark+GFM faster; Raxol's renderer falls back to regex if Earmark isn't loaded, which is fine. | Let `Raxol.UI.Components.MarkdownRenderer` use its built-in regex parser, or run our markdown through `MDEx` first then hand HTML to a new rendering path. |
| `Phoenix.View` | Removed from Phoenix 1.8. | N/A — we're not rendering web templates in TUI code anyway. |

## Version Compatibility

| Component | Version in repo | Constraint / note |
|-----------|-----------------|-------------------|
| Elixir | 1.19.5 | Raxol 2.4.0 requires `~> 1.17 or ~> 1.18 or ~> 1.19` — OK. |
| Phoenix | 1.8.5 | Raxol 2.4.0 declares `~> 1.8.1` — OK. |
| `mdex` | 0.12.1 | `:mdex, "~> 0.2"` in our `mix.exs` — lockfile pulled 0.12.1; constraint may want tightening (`~> 0.12` would be more honest). **Minor hygiene item, not blocking.** |
| `raxol` | 2.4.0 (path dep: `vendor/raxol`) | Vendored. `Raxol.UI.Components.MarkdownRenderer.init/1` signature and `%{markdown_text:, width:}` confirmed from source. |
| `oban` | 2.18 | Not exercised in polish milestone. |
| `argon2_elixir` | 4.x | Not exercised in polish milestone. |

## Sources

- `vendor/raxol/mix.exs` — Raxol version 2.4.0 confirmed (HIGH)
- `vendor/raxol/lib/raxol/ui/components/markdown_renderer.ex` — Raxol renderer API, Earmark + regex fallback (HIGH)
- `vendor/raxol/lib/raxol/ui/components/display/status_bar.ex` — StatusBar component signature (HIGH)
- `vendor/raxol/lib/raxol/ui/theming/theme_manager.ex`, `theme.ex`, `priv/themes/Default.json` — ThemeManager shape (HIGH)
- `vendor/raxol/lib/raxol/core/runtime/subscription.ex` — `:window_resize` event subscription (HIGH)
- `vendor/raxol/lib/raxol/ssh/cli_handler.ex:81` + our `lib/foglet_bbs/ssh/cli_handler.ex:167` — SSH window-change wiring confirmed both sides (HIGH)
- `deps/raxol_core/lib/raxol/core/defaults.ex` — terminal default 80×24 (HIGH)
- `docs/raxol/getting-started/WIDGET_GALLERY.md` — canonical widget list and DSL forms (HIGH)
- `docs/raxol/getting-started/QUICKSTART.md` — TEA callback shape, `view/1` → block DSL (HIGH)
- `docs/raxol/cookbook/THEMING.md` — inline-color pattern vs. ThemeManager (HIGH)
- `mix.exs` + `mix.lock` — `mdex 0.12.1` confirmed locked (HIGH)
- `lib/foglet_bbs/tui/**` — existing screen/widget code read directly (HIGH)
- `memory/feedback_raxol_modern_dsl.md` — DSL discipline history (HIGH — this codebase's own post-mortem)
- `CLAUDE.md` — project rules (no new deps for date/time, Req-only for HTTP) (HIGH)

---
*Stack research for: Foglet BBS Phase 03 polish milestone (v1.0.1)*
*Researched: 2026-04-19*
