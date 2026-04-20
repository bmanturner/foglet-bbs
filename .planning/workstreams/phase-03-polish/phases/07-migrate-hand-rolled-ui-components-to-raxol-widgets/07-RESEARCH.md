# Phase 7: Migrate Hand-Rolled UI Components to Raxol Widgets — Research

**Researched:** 2026-04-20
**Domain:** Raxol TUI component migration — theming gate analysis
**Confidence:** HIGH

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

- **D-01:** In scope — five surfaces: Modal, SelectionList base, SelectionList full/scrollable, PostReader scroll windowing, StatusBar.
- **D-02:** Kept hand-rolled — MarkdownBody (accent-color mapping), Verify code buffer (6-char mask).
- **D-03:** Not changed — KeyBar, ScreenFrame, PostCard, Compose translate_key plumbing.
- **D-04:** Theming gate applies to every migration. Full replacement if Raxol component accepts `Foglet.TUI.Theme`-derived hex `fg:`/`bg:`/`style:` props. Thin adapter if not.
- **D-05:** Gate applies to all five targets.
- **D-06:** Current modal types `:info`, `:error`, `:warning`, `:confirm` must map to Raxol's Modal API.
- **D-07:** If full replacement: `app.ex` `render_modal_overlay/2` + all `{:show_modal, spec}` dispatch sites updated; `widgets/modal.ex` deleted.
- **D-08:** If thin adapter: `Widgets.Modal.render/2` accepts `(modal_spec, theme)` and calls through to Raxol for overlay framing.
- **D-09:** Evaluate each SelectionList use site (board list, thread list) in a single pass.
- **D-10:** `List.ListRow`'s metadata variant (`@handle · N posts · Xh ago`) is NOT replaced.
- **D-11:** If full replacement: `Widgets.List.SelectionList` and base rendering in `Widgets.List.ListRow` deleted; callers updated.
- **D-12:** `Display.Viewport` replaces manual `scroll_offset` + `max_lines` slice.
- **D-13:** If full replacement: `post_reader.ex` manual offset tracking removed; `render_cache` keyed on `{post.id, width}` preserved.
- **D-14/D-15:** StatusBar reverse-video regression is accepted if migrating.
- **D-16:** If `Display.StatusBar` does NOT support theme injection, keep `Widgets.Chrome.StatusBar` hand-rolled.
- **D-17:** Every module deletion paired with caller updates in same plan. No orphan aliases.

### Claude's Discretion

- Thin adapter API shape (whether to pass `%Theme{}` or full `state`).
- Plan breakdown (one plan per target vs. related targets bundled).

### Deferred Ideas (OUT OF SCOPE)

None.

</user_constraints>

---

## Summary

This phase migrates five hand-rolled Foglet BBS widgets to Raxol primitives, gated on whether each Raxol component supports hex color injection from `Foglet.TUI.Theme`. After reading `docs/raxol/cookbook/THEMING.md` and examining each Raxol component's source in `.claude/worktrees/agent-a37a2a6e/vendor/raxol/`, the verdict is clear: **the View DSL primitives (`text`, `column`, `row`, `box`) accept `fg:` hex strings directly; the component-module targets (`Display.StatusBar`, `Input.SelectList`, `Display.Viewport`, `Raxol.UI.Components.Modal`) do NOT expose per-item hex color injection through their public API.**

The critical distinction: our current hand-rolled code threads `Foglet.TUI.Theme` hex slots into individual `text/2` calls via `fg:` keyword args. The Raxol component modules manage rendering internally — their theming hooks tie into `ThemeManager` (rejected, REQUIREMENTS.md locked decision), and `StyleHelper.merge_component_styles` reads from the Raxol theme system, not from our `Foglet.TUI.Theme` struct.

However, `Display.Viewport` is a special case: it accepts `children:` as a list of pre-rendered Raxol view elements, meaning our code can pre-render themed children and pass them in. This makes it viable as a scroll-windowing replacement without surrendering color control.

**Primary recommendation:** Four targets become thin adapters (Modal, SelectionList base, SelectionList full, StatusBar). Viewport gets a partial replacement — the scroll state management moves to Raxol, but children are pre-rendered with our theme colors.

---

## Per-Component Theming Verdict Table

This is the governing artifact for all plan decisions in Phase 7.

| Component | Raxol Target | Theming Support | Evidence | Strategy |
|-----------|-------------|-----------------|----------|----------|
| Modal | `modal/1` DSL + `Raxol.UI.Components.Modal` | NO — `modal/1` accepts `style: %{}` map only; `Modal` component uses `ThemeManager` via `StyleHelper`; no `type:`-aware color routing | `view/components.ex:237-248`; `modal/rendering.ex` — hardcoded `label` style maps, no fg/bg passthrough | **Thin adapter**: keep `Widgets.Modal`, replace overlay framing in `app.ex` with `box/column do` centering (already is — keep as-is) |
| SelectionList base | `list/1` DSL | NO — `list/1` accepts `items:`, `style:`, `selected:` only; no per-item fg/bg props | `view/components.ex:149-159`; `WIDGET_GALLERY.md` `list` section | **Thin adapter**: `Widgets.List.SelectionList` stays; its `column do` loop calling `row_renderer_fn` IS the right pattern |
| SelectionList full | `Input.SelectList` | NO — `selected_style` renders with `[:bold, :reverse]` atoms via `Raxol.Core.Defaults.selected_style()`; no hex color support | `select_list/renderer.ex:83-100`; `SelectList.init` defaults `selected_style: Raxol.Core.Defaults.selected_style()` | **Thin adapter**: `Input.SelectList` cannot reproduce `theme.selected.bg` hex; keep `Widgets.List.SelectionList` |
| PostReader windowing | `Display.Viewport` | PARTIAL — accepts `children:` as pre-rendered Raxol elements; our themed elements pass through unmodified; scroll state fully managed by Viewport | `display/viewport.ex:175-213` — `render/2` slices `state.children` by `scroll_top`/`visible_height`; children are passed in as-is | **Partial replacement**: scroll state (`scroll_offset`, bounds clamping) moves to `Viewport.update/2`; children are pre-rendered with theme colors by existing `PostCard` pipeline |
| StatusBar | `Display.StatusBar` | NO — renders `key: value` pairs using `StyleHelper.merge_component_styles(state, context, :status_bar)` which reads from `ThemeManager`; no `fg:`/`bg:` per text node; layout is `key-value` pairs, not left/right split | `display/status_bar.ex:46-56`; `build_children/1` generates bold key + plain label pairs only | **Keep hand-rolled** (D-16): `Display.StatusBar` cannot reproduce our left=`"Foglet BBS — {title}"` / right=`"@handle"` layout with hex `fg:`/`bg:` from `theme.status_bar`. Dropping both reverse-video AND hex colors is not acceptable per D-16. |

---

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| Modal overlay centering | `app.ex` view layer | `Widgets.Modal` body | `app.ex` already owns the centering via `column justify: :center`; Modal module owns body content only |
| Selection highlight rendering | `Widgets.List.ListRow` | None | Theme-aware `fg:`/`bg:` at item level requires our code; Raxol `list/1` and `SelectList` cannot carry hex colors |
| Post scroll windowing | `Display.Viewport` (state) + `PostCard` (rendering) | `post_reader.ex` key handlers | Viewport owns `scroll_top`/clamp; PostCard continues to render themed children; PostReader key handlers call `Viewport.update/2` |
| Status bar chrome | `Widgets.Chrome.StatusBar` | `ScreenFrame` | Stays hand-rolled; `Display.StatusBar` API mismatch (key-value pairs only, ThemeManager dependency) |

---

## Standard Stack

### Core (in scope for this phase)

| Module | Type | Purpose | Constraint |
|--------|------|---------|------------|
| `Raxol.UI.Components.Display.Viewport` | Component module | Scroll state management (scroll_top, clamp, visible_height) | Must call via `Viewport.init/1`, `Viewport.update/2`, `Viewport.render/2`; no DSL shortcut |
| `Raxol.Core.Renderer.View` macros | DSL import | `column`, `row`, `box`, `text`, `divider` | Function-form only — `column do`, `row do`, `box do` block macros; no `use Raxol.UI.Components.Base.Component` |

### Kept Hand-Rolled (confirmed by theming gate)

| Module | Why Kept |
|--------|----------|
| `Widgets.Modal` | `Raxol.UI.Components.Modal` theming via `ThemeManager`; `modal/1` DSL has no type-aware color routing |
| `Widgets.List.SelectionList` | `list/1` and `Input.SelectList` cannot carry hex fg/bg per item |
| `Widgets.List.ListRow` (base + metadata) | Base render unchanged; metadata variant always stayed per D-10 |
| `Widgets.Chrome.StatusBar` | `Display.StatusBar` incompatible layout + ThemeManager dependency |

### NOT Needed (rejected)

| Rejected | Why |
|----------|-----|
| `Raxol.UI.Theming.ThemeManager` | Locked decision — rejected for v1.0.1 (REQUIREMENTS.md) |
| `Raxol.UI.Components.Modal` component module | Would require ThemeManager; also uses `use Raxol.UI.Components.Base.Component` (locked out) |
| `Raxol.UI.Components.Input.SelectList` | `selected_style` hardcoded to reverse/bold atoms; no hex injection |
| `Raxol.UI.Components.Display.StatusBar` | Key-value pair layout only; `StyleHelper.merge_component_styles` reads ThemeManager |

---

## Architecture Patterns

### System Architecture Diagram

```
PostReader.render(state)
  └─ get_screen_state(state)
       ├─ render_cache[{post.id, width}]          ← preserved unchanged
       └─ Viewport state (scroll_top, visible_height)
            └─ Viewport.update({:scroll_by, +/-1}) ← replaces manual scroll_offset math
            └─ Viewport.render(vp_state, %{})
                 └─ Enum.slice(children, scroll_top, visible_height)
                      └─ PostCard.render_from_tuples/5 ← children pre-rendered with theme hex
```

```
App.view(state) when state.modal
  └─ render_modal_overlay(modal, terminal_size)
       └─ column justify: :center, align: :center do
            └─ box style: %{border: :double, padding: 1} do
                 └─ Widgets.Modal.render(modal, theme)  ← thin adapter; theme passed explicitly
                      └─ column do
                           ├─ text(title, fg: theme.title.fg, style: [:bold])
                           ├─ divider()
                           ├─ text(message, fg: type_color(theme, type))
                           └─ text(key_hint, fg: theme.dim.fg)
```

### Recommended Viewport Integration Pattern

```elixir
# In post_reader.ex screen state — AFTER migration
defp default_screen_state do
  {:ok, vp} = Viewport.init(%{
    id: "post_reader_vp",
    children: [],
    visible_height: 10,
    show_scrollbar: false
  })

  %{
    selected_post_index: 0,
    viewport: vp,
    render_cache: %{}
  }
end

# scroll j/k — replaces manual offset math
defp scroll_post(state, delta) do
  ss = get_screen_state(state)
  {new_vp, []} = Viewport.update({:scroll_by, delta}, ss.viewport)
  new_ss = %{ss | viewport: new_vp}
  new_screen_state = Map.put(state.screen_state, :post_reader, new_ss)
  {:update, %{state | screen_state: new_screen_state}, []}
end

# Render — pass pre-themed children into Viewport
defp render_post_content(state, ss, theme, w, _h) do
  post = Enum.at(state.posts, ss.selected_post_index)
  tuples = ss.render_cache[{post.id, w}] || parse_body(state, post)

  # Pre-render themed children — Viewport passes these through unmodified
  themed_children = PostCard.render_from_tuples(post, tuples, w, theme, ...)

  vp = %{ss.viewport | children: [themed_children], visible_height: available_height}
  Viewport.render(vp, %{})
end
```

### Thin Adapter API Shape

Follow `ScreenFrame.render/4` pattern (accepts explicit args, not full state) for consistency. The thin adapter's only change from current signature is adding `theme` as a second argument:

```elixir
# Current (no theme):
Widgets.Modal.render(modal_spec)

# After thin adapter update:
Widgets.Modal.render(modal_spec, theme)
# Caller in app.ex:
# theme = (Map.get(state, :session_context) || %{}) |> Map.get(:theme) || Theme.default()
# render_modal_overlay(state.modal, theme, state.terminal_size)
```

`SelectionList.render/3` and `StatusBar.render/2` already accept theme-containing `state` or explicit `theme` — no API change needed.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Scroll position clamping and bounds math | Custom `max(0, min(offset, total - visible))` | `Viewport.update({:scroll_by, delta}, vp)` | Viewport's `clamp_scroll/3` handles all edge cases including empty content, single-item content, visible > total |
| Scroll state representation | `scroll_offset` integer in screen_state | `%{viewport: vp_state}` with `Viewport.init/1` | Viewport state bundles `scroll_top`, `content_height`, `visible_height` coherently |
| Modal overlay centering | Custom flex column/centering logic | `column justify: :center, align: :center do` (already exists in `app.ex`) | The centering in `render_modal_overlay/2` is already correct — don't change it |

**Key insight:** Only the Viewport scroll-state management is genuinely redundant. The other four targets cannot be replaced because their rendering APIs are incompatible with hex color injection.

---

## Common Pitfalls

### Pitfall 1: Assuming `Input.SelectList` supports hex theme colors

**What goes wrong:** Attempting to pass `fg: theme.selected.fg` to `Input.SelectList` init props or expecting its `selected_style` to accept hex strings. `selected_style` is `Raxol.Core.Defaults.selected_style()` which returns `%{bold: true, reverse: true}` atoms only. The renderer converts these to `[:bold, :reverse]` style atoms, not fg/bg hex pairs.

**Why it happens:** `Input.SelectList` accepts a `theme:` map in its props, but that map feeds into `FocusHelper.focus_style/2` for focus-ring only — not into item-level color rendering.

**How to avoid:** Do not migrate `SelectionList` to `Input.SelectList`. The current `Widgets.List.SelectionList` + `Widgets.List.ListRow` pattern (explicit `row_renderer_fn` with themed `text/2` calls) is the correct pattern for this codebase.

**Warning signs:** Any PR that touches `lib/foglet_bbs/tui/widgets/list/selection_list.ex` to call `Input.SelectList.init/1`.

### Pitfall 2: Passing Viewport children as raw post bodies

**What goes wrong:** Passing unrendered post body strings as `children:` to `Viewport.init/1`. The Viewport expects children to be pre-rendered Raxol view elements (maps with `type:` key), not strings or raw tuples.

**Why it happens:** `Viewport.render/2` calls `Enum.slice(state.children, scroll_top, visible_height)` and passes results directly as children of a `:column` node. Raw strings will cause renderer errors.

**How to avoid:** Always pre-render children through `PostCard.render_from_tuples/5` (which returns a Raxol view element) before passing to Viewport. The Viewport gets ONE child element per "line" of logical content.

**Warning signs:** Passing `post.body` string or `[{text, style}]` tuples as Viewport children.

### Pitfall 3: Removing `render_cache` during Viewport migration

**What goes wrong:** The `render_cache` in `screen_state[:post_reader]` (keyed on `{post.id, width}`) is for memoizing `Foglet.Markdown.render/1` output — an expensive parse step. Viewport migration only replaces the scroll state management, not the cache.

**Why it happens:** The `render_cache` is stored alongside `scroll_offset` in screen_state, making it tempting to restructure the whole screen_state shape in one pass.

**How to avoid:** Preserve `render_cache` verbatim in the new screen_state shape. Only `scroll_offset` (integer) is replaced by `viewport` (Viewport state struct). D-13 explicitly calls this out.

**Warning signs:** Any screen_state shape that drops `render_cache` from the `:post_reader` map.

### Pitfall 4: Using `use Raxol.UI.Components.Base.Component` in thin adapters

**What goes wrong:** A thin adapter or migration helper that adds `use Raxol.UI.Components.Base.Component` to a Foglet module. This introduces the full component lifecycle (init/2, mount/1, handle_event/3) and is the forbidden pattern per REQUIREMENTS.md locked decision.

**Why it happens:** The Raxol component module docs show this pattern prominently. Easy to copy-paste when adapting existing Raxol component code.

**How to avoid:** All Foglet widget modules use `import Raxol.Core.Renderer.View` and expose plain `render/N` functions. No `use` macros from Raxol's component system.

**Warning signs:** Any Foglet widget file containing `use Raxol.UI.Components.Base.Component` or `@behaviour Raxol.UI.Components.Base.Component`.

### Pitfall 5: Misidentifying the Viewport `visible_height` source

**What goes wrong:** Hardcoding `visible_height` in the Viewport init state. The available content height depends on runtime terminal size minus chrome overhead (border + StatusBar + divider + KeyBar ≈ 10 rows).

**Why it happens:** `Viewport.init/1` requires `visible_height` as a prop. It's tempting to set it once at init time.

**How to avoid:** Calculate `available_height = max(h - 10, 5)` at render time (already done in `render_post_content/4`) and call `Viewport.update({:set_visible_height, available_height}, vp)` before rendering, or pass a fresh `visible_height` via `Viewport.update({:update_props, %{visible_height: available_height}}, vp)`.

---

## Code Examples

### Viewport init (verified from source)

```elixir
# Source: vendor/raxol/lib/raxol/ui/components/display/viewport.ex:36-62
alias Raxol.UI.Components.Display.Viewport

{:ok, vp} = Viewport.init(%{
  id: "post_reader_vp",
  children: [],            # pre-rendered Raxol elements go here
  visible_height: 10,      # updated at render time via {:set_visible_height, h}
  show_scrollbar: false,   # BBS aesthetic — no scrollbar chrome
  scroll_top: 0
})
```

### Viewport scroll control (verified from source)

```elixir
# Source: vendor/raxol/lib/raxol/ui/components/display/viewport.ex:85-99
{new_vp, []} = Viewport.update({:scroll_by, +1}, vp)    # scroll down one line
{new_vp, []} = Viewport.update({:scroll_by, -1}, vp)    # scroll up one line
{new_vp, []} = Viewport.update({:scroll_to, 0}, vp)     # reset to top (on N/P)
{new_vp, []} = Viewport.update({:set_visible_height, h}, vp)  # resize
```

### Viewport render (verified from source)

```elixir
# Source: vendor/raxol/lib/raxol/ui/components/display/viewport.ex:175-213
# Viewport.render/2 slices children[scroll_top, visible_height] and wraps in :row
rendered = Viewport.render(vp_state, %{})
# rendered is a %{type: :row, children: [content_column, optional_scrollbar]}
```

### Modal thin adapter — updated signature

```elixir
# Current signature in widgets/modal.ex:40 — BEFORE
def render(%{message: msg} = spec) do
  # uses hardcoded color_for/1 with :red, :yellow, :green atoms

# AFTER — accept theme, route colors through theme slots
def render(%{message: msg} = spec, theme) do
  type = Map.get(spec, :type, :info)
  title = Map.get(spec, :title, title_for(type))
  msg_fg = color_for_type(type, theme)   # reads theme.error.fg, theme.warning.fg, etc.

  column [] do
    [text(" #{title} ", fg: theme.title.fg, style: [:bold]), divider()] ++
      wrapped_lines(msg, msg_fg) ++
      [text(key_hint_for(type), fg: theme.dim.fg)]
  end
end

defp color_for_type(:error, theme), do: theme.error.fg
defp color_for_type(:warning, theme), do: theme.warning.fg
defp color_for_type(:confirm, theme), do: theme.warning.fg
defp color_for_type(_info, theme), do: theme.primary.fg
```

### Caller update in app.ex for modal thin adapter

```elixir
# Current render_modal_overlay/2 in app.ex:173 — calls Widgets.Modal.render(modal)
defp render_modal_overlay(modal, _terminal_size) do
  column justify: :center, align: :center do
    [
      box style: %{border: :double, padding: 1} do
        Widgets.Modal.render(modal)   # <- no theme
      end
    ]
  end
end

# AFTER — extract theme and pass explicitly
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
# app.ex view/1 call site: render_modal_overlay(state.modal, state)
# (terminal_size arg removed — centering is pure Raxol flex, no size math needed)
```

---

## Current Implementation Details (caller counts and signatures)

### Modal

- **File:** `lib/foglet_bbs/tui/widgets/modal.ex`
- **Current signature:** `render/1` — accepts `modal_spec` map only (no theme)
- **Color handling:** Hardcoded `color_for/1` returns `:red`, `:yellow`, `:green` atoms (NOT theme-derived)
- **Callers:** 1 — `app.ex:render_modal_overlay/2` via `Widgets.Modal.render(modal)`
- **Migration:** Add `theme` arg, replace hardcoded color atoms with theme slot lookups

### SelectionList

- **File:** `lib/foglet_bbs/tui/widgets/list/selection_list.ex`
- **Current signature:** `render/3` — `(items, selected_index, row_renderer_fn)` — pure rendering, no internal state
- **Callers:** 3 — `board_list.ex:42`, `thread_list.ex:48`, `new_thread.ex:97`
- **Migration:** NO CHANGE — this is already the correct thin-adapter pattern. The `column do` loop + `row_renderer_fn` is equivalent to what any Raxol `list/1` would do, with full theme color control via the row_renderer.

### ListRow base

- **File:** `lib/foglet_bbs/tui/widgets/list/list_row.ex`
- **Current signature:** `render/3` — `(label, selected, theme)` returns themed `text/2`
- **Current signature (metadata):** `render_with_metadata/6` — `(title, metadata, selected, unread?, theme, opts)`
- **Migration:** NO CHANGE — both variants are genuinely custom and correctly themed.

### StatusBar

- **File:** `lib/foglet_bbs/tui/widgets/chrome/status_bar.ex`
- **Current signature:** `render/2` — `(state, title)` — reads `state.session_context.theme` and `state.current_user`
- **Callers:** 1 — `screen_frame.ex:41` via `StatusBar.render(state, title)`
- **Migration:** NO CHANGE — `Display.StatusBar` is incompatible per theming verdict.

### PostReader scroll windowing

- **File:** `lib/foglet_bbs/tui/screens/post_reader.ex`
- **Current state:** `screen_state[:post_reader]` = `%{selected_post_index, scroll_offset, render_cache}`
- **Manual scroll math:** `scroll_post/2` lines 278-306 — computes `max_offset`, clamps `new_offset`
- **Render slicing:** `PostCard.render_from_tuples/5` receives `scroll_offset:` and `max_lines:` opts
- **Migration target:** Replace `scroll_offset` integer + manual clamp with `Viewport` state; `render_cache` preserved unchanged.

---

## DSL Constraint Confirmation

[VERIFIED: REQUIREMENTS.md locked decisions + vendor source inspection]

The function-form only constraint applies to ALL Foglet widget modules:
- Use `import Raxol.Core.Renderer.View` and call `column do`, `row do`, `box do`, `text/2`, `divider/1` block macros
- Never `use Raxol.UI.Components.Base.Component`
- Never `@behaviour Raxol.UI.Components.Base.Component`
- `Viewport` is used as a plain module (`Viewport.init/1`, `Viewport.update/2`, `Viewport.render/2`) — this is the "component module only" pattern from WIDGET_GALLERY.md, which does NOT require `use Raxol.UI.Components.Base.Component` in the caller

---

## Runtime State Inventory

Step 2.5 SKIPPED (not a rename/refactor/migration phase — this is a code-level widget replacement with no string renaming).

---

## Environment Availability

Step 2.6 SKIPPED — no new external dependencies. Phase uses only Raxol vendor code already present in the repository.

---

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | ExUnit (built-in) |
| Config file | `test/test_helper.exs` |
| Quick run command | `mix test test/foglet_bbs/tui/` |
| Full suite command | `mix test` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| WIDGET-01 | Function-form widgets use Raxol block-macro DSL | unit | `mix test test/foglet_bbs/tui/widgets/` | Existing files |
| FRAME-02 | StatusBar shows title + handle | unit | `mix test test/foglet_bbs/tui/widgets/chrome/status_bar_test.exs` | Verify exists |
| (Modal thin adapter) | Modal renders with theme slot colors (not hardcoded atoms) | unit | `mix test test/foglet_bbs/tui/widgets/modal_test.exs` | Wave 0 check |
| (Viewport integration) | PostReader scroll via Viewport — j/k advances scroll_top | unit | `mix test test/foglet_bbs/tui/screens/post_reader_test.exs` | Existing |

### Sampling Rate

- **Per task commit:** `mix test test/foglet_bbs/tui/`
- **Per wave merge:** `mix test`
- **Phase gate:** Full suite green before `/gsd-verify-work`

### Wave 0 Gaps

- [ ] `test/foglet_bbs/tui/widgets/modal_test.exs` — verify Modal renders theme slot fg values, not hardcoded atoms (`:red`, `:green`, `:yellow`)
- [ ] Confirm `test/foglet_bbs/tui/screens/post_reader_test.exs` covers scroll state shape after Viewport integration

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `Raxol.Core.Defaults.selected_style()` returns atoms (`%{bold: true, reverse: true}`), not hex values | Theming Verdict — SelectionList | If it somehow allows hex passthrough, full SelectionList replacement becomes viable |
| A2 | `StyleHelper.merge_component_styles/3` in `Display.StatusBar` reads from `ThemeManager`, not from caller-passed theme | Theming Verdict — StatusBar | If StatusBar accepts a caller-provided style map that overrides its internal theming, thin-adapter becomes unnecessary |

**Both A1 and A2 are based on direct vendor source inspection** (`select_list/renderer.ex` line 83-100; `display/status_bar.ex` lines 47-48). Confidence is HIGH.

---

## Open Questions

1. **Viewport children granularity for PostReader**
   - What we know: `PostCard.render_from_tuples/5` currently returns a single Raxol element (a `column` wrapping all post content with scroll slicing inside)
   - What's unclear: Should the Viewport receive one child (the full post card element) and rely on its internal height for scrolling, OR should it receive individual lines as separate children for line-by-line scrolling?
   - Recommendation: Pass one child per **post line tuple** (i.e., expand the inner `column do` of `PostCard` into individual line elements as Viewport children) for correct line-by-line j/k behavior matching the current UX. The planner should decide this API boundary.

2. **Modal `render_modal_overlay/2` signature change**
   - The current call is `render_modal_overlay(state.modal, state.terminal_size)`. After the thin adapter update, `terminal_size` is no longer needed (centering is Raxol flex). The signature should become `render_modal_overlay(state.modal, state)`.
   - This is a minor internal refactor; no external impact but worth noting in the plan.

---

## Sources

### Primary (HIGH confidence — direct source inspection)

- `vendor/raxol/lib/raxol/ui/components/display/viewport.ex` — `Viewport.init/1`, `update/2`, `render/2` API verified
- `vendor/raxol/lib/raxol/ui/components/display/status_bar.ex` — `StyleHelper.merge_component_styles` call verified
- `vendor/raxol/lib/raxol/ui/components/input/select_list/renderer.ex` — `selected_style` atoms rendering verified
- `vendor/raxol/lib/raxol/ui/components/modal/rendering.ex` — no fg/bg passthrough verified
- `vendor/raxol/lib/raxol/view/components.ex` — `list/1` and `modal/1` DSL function signatures verified
- `docs/raxol/cookbook/THEMING.md` — hex `fg:` support in base `text/2` DSL confirmed
- `docs/raxol/getting-started/WIDGET_GALLERY.md` — component API shapes, DSL availability table
- `lib/foglet_bbs/tui/widgets/modal.ex` — current implementation and callers
- `lib/foglet_bbs/tui/widgets/list/selection_list.ex` — current API
- `lib/foglet_bbs/tui/widgets/list/list_row.ex` — metadata variant scope confirmed
- `lib/foglet_bbs/tui/widgets/chrome/status_bar.ex` — current implementation
- `lib/foglet_bbs/tui/screens/post_reader.ex` — scroll windowing full implementation
- `lib/foglet_bbs/tui/app.ex` — `render_modal_overlay/2` and all `{:show_modal}` sites

### Secondary (MEDIUM confidence — doc cross-reference)

- `docs/raxol/cookbook/BUILDING_APPS.md` — scrollable list pattern (manual offset math, validating current approach)

---

## Metadata

**Confidence breakdown:**
- Theming verdicts: HIGH — based on direct vendor source inspection, not docs alone
- Viewport integration pattern: HIGH — `init/1`, `update/2`, `render/2` API verified from source
- Modal thin adapter API: HIGH — 1 caller in `app.ex`, straightforward signature change
- SelectionList / StatusBar keep hand-rolled: HIGH — source inspection confirms no hex injection path

**Research date:** 2026-04-20
**Valid until:** 2026-05-20 (Raxol is vendored; source won't change without explicit update)
