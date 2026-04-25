# Phase 20: Rich Rows and Thread Flow — Research

**Researched:** 2026-04-25
**Domain:** Elixir/Raxol TUI widget composition, Unicode glyph rendering, terminal display-width math
**Confidence:** HIGH

## Summary

Phase 20 introduces `Foglet.TUI.Widgets.List.RichRow` as a stateless render-only widget alongside the existing `ListRow`. All architectural patterns, helper modules, theme slots, and test infrastructure are already in place from Phases 16-19. This is a well-scoped additive change with a clear reference implementation (`ListRow.render_with_metadata/6`) and a mature pattern to follow (`SelectionList`, `SmartList`).

The primary research findings are: (1) the full `ListRow.render_with_metadata/6` API and its private `compute_parts/4` and `styles_for/3` helpers are directly reusable as the width math blueprint; (2) all nine theme slots needed by Phase 20 (`accent`, `info`, `badge`, `warning`, `dim`, `selected`, `unselected`) exist in all nine themes and are fully confirmed; (3) the three locked-in glyphs (`◆` U+25C6, `◇` U+25C7, `●` U+25CF) are confirmed 1-cell wide via `Raxol.UI.TextMeasure`; (4) emoji glyphs `🔒` (U+1F512) and `🔐` (U+1F510) are confirmed 2-cell wide — they are forbidden; (5) `⚿` (U+26BF) and `⚑` (U+2691) are confirmed 1-cell wide; `⚑` is reserved by Phase 19 Moderation (19-CONTEXT.md D-08); (6) `Foglet.TUI.WidgetHelpers.assert_text_run/3` is the canonical style-assertion helper; (7) the cluster width of a 3-glyph + 2-space cluster is 5 display cells as a safe `@cluster_width` value.

**Primary recommendation:** Model `RichRow` directly on `ListRow.render_with_metadata/6` — same `row style: %{gap: 0}` with `text/2` segments, same `compute_parts` width math extended by a fixed `@cluster_width` offset, same `styles_for` dispatch logic extended by state-cluster atoms. Use `Foglet.TUI.WidgetHelpers.assert_text_run/3` for style assertions in tests.

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

**D-01:** `RichRow.render/1` accepts a keyword list. Required keys: `:title`, `:metadata`, `:state_cluster`, `:selected`, `:theme`. Optional: `:width` (default 80), `:focus_marker` (default `"▌ "`), `:emphasis` (`:bold` for unread).

**D-02:** `:state_cluster` is a list of state atoms (e.g. `[]`, `[:unread]`, `[:sticky, :locked]`). RichRow owns the atom-to-glyph-to-theme-slot mapping. Unknown atoms render as visual whitespace.

**D-03:** `@cluster_width` is a module attribute computed via `Foglet.TUI.TextWidth.display_width/1`. Fixed across all state combinations for column alignment.

**D-04:** `@moduledoc` documents public input contract, supported state atoms, size-contract priority. Follows `SelectionList` moduledoc style.

**D-05:** Glyph mapping: `unread` → `◆` (U+25C6), `read` → `◇` (U+25C7) or whitespace, `sticky` → `●` (U+25CF), `locked` → planner discretion within single-cell glyphs; `⚿` (U+26BF) recommended; `🔒` forbidden (2-cell).

**D-06:** Theme-slot routing: `unread` → `theme.accent.fg` + `:bold`; `read` glyph → `theme.dim.fg` (if rendered); `sticky` → `theme.info.fg` or `theme.badge.fg` (planner discretion); `locked` → `theme.warning.fg`.

**D-07:** No ASCII fallback. Single Unicode glyph set across all themes.

**D-08:** Focus marker `▌` (U+258C) replacing `> `. Canonical selection marker per `SelectionList` (line 100), `SmartList` (`@focused_marker` line 41), `Tabs` (line 43), `Modal` (line 82).

**D-09:** Focused row: `theme.selected.fg`, `theme.selected.bg`, `:bold`. Non-focused: two leading spaces, `theme.unselected.fg`, no `bg`.

**D-10:** Selection and state-cluster treatments are independent. Focused unread row shows both `▌` and `◆`.

**D-11:** Three test files. NEW: `test/foglet_bbs/tui/widgets/list/rich_row_test.exs`. EXTEND: `test/foglet_bbs/tui/screens/thread_list_test.exs` (LIST-03 describe block ~line 221). EXTEND: `test/foglet_bbs/tui/layout_smoke_test.exs` (new `thread_list — size contract` block).

**D-12 through D-15:** Test coverage matrix, `thread_list_test.exs` additions, layout smoke block, code-only coverage (no screenshot fixtures).

### Claude's Discretion

- Exact locked glyph for `:locked` within single-cell Unicode (`⚿` recommended over `⚑` which conflicts with Phase 19 Moderation glyph per 19-CONTEXT.md D-08).
- `sticky` routes to `theme.info.fg` or `theme.badge.fg` — pick based on contrast across all nine themes.
- Whether `read` state renders `◇` or whitespace.
- Exact `@cluster_width` value and spacing between cluster glyphs.
- Whether `RichRow.render/1` returns a single Raxol element or list of cells.
- Test fixture strategy (inline maps per sibling widget pattern).

### Deferred Ideas (OUT OF SCOPE)

- Migration of `BoardList`, `Sysop`, `Account`, invites to `RichRow` (Phase 21 / Phase 25).
- Focused-thread details strip below the list.
- Wide-terminal inspector pane.
- ASCII-only fallback glyph set.
- Row striping.
- Removing/rewriting `ListRow.render/3` or `ListRow.render_with_metadata/6`.
- Changes to `ThreadList` keyboard handling, navigation, or load orchestration.
- Schema, query, or context API changes.
- Theme palette retuning.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| RICHROW-01 | Reusable rich-row primitive with state glyphs, primary text, metadata, selection, theme routing | `ListRow.render_with_metadata/6` is the blueprint; `SelectionList` and `SmartList` provide the stateless render-only pattern; `WidgetHelpers.assert_text_run/3` provides the test assertion API |
| THREADS-01 | Thread list rows expose unread/read, sticky, locked via width-safe aligned rows | `ThreadEntry` fields `:has_unread`, `:sticky`, `:locked` confirmed; all glyphs confirmed 1-cell; `TextWidth.display_width/1` confirmed as the width helper |
| THREADS-02 | Thread list shows focused-thread details without disrupting navigation | Satisfied by selection clarity alone (D-08/D-09) — `▌` + `theme.selected.bg` distinguish focused row unambiguously |
</phase_requirements>

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| RichRow state-glyph rendering | TUI Widget | — | Pure render function over already-loaded state; no I/O |
| ThreadList row migration | TUI Screen | TUI Widget | Screen owns row construction; widget owns render logic |
| Width math (cluster + title + metadata) | TUI Widget (RichRow) | TextWidth helper | Width policy lives in the widget; `TextWidth` is the tool |
| Theme-slot lookup | TUI Widget (RichRow) | Theme module | Widget calls `theme.slot.fg`; no hardcoded atoms |
| ThreadEntry field access | TUI Screen (ThreadList) | — | Screen extracts `:has_unread`, `:sticky`, `:locked` from `ThreadEntry` and passes as state atoms to RichRow |
| Test assertions (style, glyph, width) | Test support | WidgetHelpers | `assert_text_run/3`, `flatten_text/1`, `color_atom_leaked?/2` |

## Standard Stack

### Core

| Module | Location | Purpose | Canonical Use |
|--------|----------|---------|---------------|
| `Foglet.TUI.TextWidth` | `lib/foglet_bbs/tui/text_width.ex` | Display-width measurement, truncation, padding | `display_width/1`, `truncate/2`, `pad_trailing/2` |
| `Foglet.TUI.Theme` | `lib/foglet_bbs/tui/theme.ex` | Theme slot struct and resolution | `theme.accent.fg`, `theme.selected.bg`, etc. |
| `Raxol.Core.Renderer.View` (DSL) | via `import` | View element constructors | `text/2`, `row/2`, `column/2` |
| `Foglet.TUI.Widgets.List.ListRow` | `lib/foglet_bbs/tui/widgets/list/list_row.ex` | Reference implementation for width math | Read for `compute_parts/4` and `styles_for/3` patterns |

### Supporting

| Module | Location | Purpose | When to Use |
|--------|----------|---------|-------------|
| `Foglet.TUI.WidgetHelpers` | `test/support/foglet/tui/widget_helpers.ex` | Test helpers: flatten text, assert style runs, check color leaks | All widget unit tests |
| `Raxol.UI.Layout.Engine` | via test import | Positioned-render engine for layout smoke tests | `layout_smoke_test.exs` size-contract blocks |
| `Foglet.Threads.ThreadEntry` | `lib/foglet_bbs/threads/thread_entry.ex` | Read-model for thread rows | `ThreadList` maps `:has_unread`, `:sticky`, `:locked` to state atoms |

### Version Verification

Raxol is vendored at `vendor/raxol/`. No npm/hex version concerns — the `Raxol.UI.TextMeasure` backend delegates to `Raxol.Terminal.CharacterHandling.get_string_width/1` when available (confirmed in `vendor/raxol/lib/raxol/ui/text_measure.ex`). [VERIFIED: read source]

## Architecture Patterns

### System Architecture Diagram

```
ThreadList.render/1
    │
    ├─► Theme.from_state/1 ──────────────────────────────► %Theme{...}
    │                                                              │
    ├─► sort_threads/1 ─────────────────────────────────► [%ThreadEntry{...}]
    │                                                              │
    └─► SelectionList.render/4 ─► (for each ThreadEntry):         │
                                   ├─ extract (:has_unread, :sticky, :locked)
                                   ├─ build state_cluster: [:unread, :sticky]
                                   └─► RichRow.render/1 ◄──────── width, theme
                                            │
                              ┌─────────────┼─────────────────────┐
                              │             │                     │
                     render_cluster/2  render_title/3    render_metadata/3
                              │             │                     │
                    (atom→glyph lookup) (truncate to    (right-align to
                    + theme-slot fg      remaining       remaining width)
                    + @cluster_width     title cells)
                    fixed padding
                              │             │                     │
                              └─────────────┴─────────────────────┘
                                            │
                                  row(style: %{gap: 0})
                                  [text(cluster, ...), text(padding, ...), text(metadata, ...)]
```

### Recommended Project Structure

```
lib/foglet_bbs/tui/widgets/list/
├── rich_row.ex          # NEW — Phase 20
├── list_row.ex          # UNCHANGED — existing callers keep using this
├── selection_list.ex    # UNCHANGED
└── smart_list.ex        # UNCHANGED

test/foglet_bbs/tui/widgets/list/
├── rich_row_test.exs    # NEW — Phase 20 widget unit tests
├── list_row_test.exs    # UNCHANGED
└── selection_list_test.exs # UNCHANGED

test/foglet_bbs/tui/screens/
└── thread_list_test.exs # EXTENDED — add to LIST-03 describe block ~line 221

test/foglet_bbs/tui/
└── layout_smoke_test.exs # EXTENDED — add thread_list size contract block
```

### Pattern 1: Stateless Render-Only Widget

RichRow follows the D-16 pattern: no `init/1`, no `handle_event/2`. Single public entry point is `render/1` with a keyword list.

```elixir
# Source: lib/foglet_bbs/tui/widgets/list/selection_list.ex (D-16 reference)
# Source: lib/foglet_bbs/tui/widgets/list/list_row.ex (render_with_metadata/6 reference)

defmodule Foglet.TUI.Widgets.List.RichRow do
  @moduledoc """
  Rich row renderer for Foglet BBS selection lists (RICHROW-01, THREADS-01).

  A stateless rendering widget — no internal state. Callers own all data.

  ## Public API

      RichRow.render(
        title: "Thread title",
        metadata: "@alice · 3 posts · 2h ago",
        state_cluster: [:unread, :sticky],
        selected: true,
        theme: theme,
        width: 80            # optional, default 80
      )

  ## Supported state atoms (Phase 20)

    * `:unread`  — ◆ (U+25C6) in theme.accent.fg + :bold
    * `:sticky`  — ● (U+25CF) in theme.info.fg (or theme.badge.fg)
    * `:locked`  — ⚿ (U+26BF) in theme.warning.fg (recommended)

  ## Reserved for Phase 21+

    * `:subscribed`, `:category`, `:required`

  ## Size-contract priority

  At any terminal width: cluster + metadata always render fully;
  title truncates first with "…"; minimum title attempt is 20 cells.

  Honours: D-02, D-03, D-07 (no ASCII fallback), D-08 (▌ marker),
           D-09 (selected/unselected theme slots), D-16 (stateless).
  """

  import Raxol.Core.Renderer.View

  alias Foglet.TUI.TextWidth
  alias Foglet.TUI.Theme

  @min_title_length 20
  @cluster_width 5         # 3 glyph cells + 2 space separators
  @focus_marker "▌ "
  @no_focus_marker "  "
  @ellipsis "…"

  @spec render(keyword()) :: any()
  def render(opts) when is_list(opts) do
    # ...
  end
end
```

### Pattern 2: Width Math — Extending compute_parts for a Cluster Prefix

The existing `ListRow.compute_parts/4` sets `marker_width = TextWidth.display_width(marker)`. `RichRow` extends this by adding `@cluster_width` to the left-side reservation:

```elixir
# Source: lib/foglet_bbs/tui/widgets/list/list_row.ex:121 (adapted)

defp compute_parts(focus_marker, cluster_str, title, metadata, width) do
  marker_width  = TextWidth.display_width(focus_marker)
  cluster_width = @cluster_width
  metadata_width = TextWidth.display_width(metadata)
  min_gap = 2

  max_title_body =
    max(width - marker_width - cluster_width - min_gap - metadata_width, 0)

  title_body = truncate_title(title, max_title_body)

  left_part = focus_marker <> cluster_str <> title_body
  left_width = TextWidth.display_width(left_part)

  padding_width = max(width - left_width - metadata_width, 0) |> min(width)
  padding_part  = TextWidth.pad_trailing("", padding_width)

  {left_part, padding_part, metadata}
end
```

Note: `cluster_str` is the already-rendered cluster string (padded to `@cluster_width` cells). The focus marker is separate from the cluster.

### Pattern 3: Atom-to-Glyph Mapping

```elixir
# Source: derived from ListRow.styles_for/3 and SelectionList.default_row/2 patterns

@glyph_map %{
  unread:  {"◆", :accent},
  sticky:  {"●", :info},
  locked:  {"⚿", :warning}
}

defp render_cluster(state_atoms, theme) do
  positions = [:unread, :sticky, :locked]  # fixed order

  positions
  |> Enum.map(fn atom ->
    case Map.get(@glyph_map, atom) do
      {glyph, slot} when atom in state_atoms ->
        {glyph, Map.get(theme, slot, %{})}
      {_glyph, _slot} ->
        # Not in state_atoms: render a space (same display width as glyph)
        {" ", %{}}
      nil ->
        {" ", %{}}
    end
  end)
  |> Enum.map(fn {glyph, style} ->
    text(glyph, style)
  end)
end
```

The cluster string is assembled with `Enum.intersperse(" ", glyph_cells)` or similar — the exact spacing strategy between cluster glyphs is planner discretion, subject to `@cluster_width` being fixed.

### Pattern 4: Test Assertion with assert_text_run

```elixir
# Source: test/support/foglet/tui/widget_helpers.ex, test/foglet_bbs/tui/widgets/list/smart_list_test.exs

import Foglet.TUI.WidgetHelpers, only: [flatten_text: 1, assert_text_run: 3, color_atom_leaked?: 2, color_names: 0]

# Verify focused row has selected theme styling
assert_text_run(result, "▌ ◆ ● Thread title", fg: theme.selected.fg, bg: theme.selected.bg, style: [:bold])

# Verify unread glyph in leading cluster
assert flatten_text(result) =~ "◆"

# Verify no hardcoded color atoms
for color <- color_names() do
  refute color_atom_leaked?(inspect(result, limit: :infinity), color)
end

# Verify metadata is right-aligned (ends with metadata string)
flat = flatten_text(result)
assert String.ends_with?(flat, "@alice · 3 posts · 2h ago")

# Verify total width does not exceed budget
assert TextWidth.display_width(flat) <= 64
```

### Anti-Patterns to Avoid

- **String.length for width**: Use `TextWidth.display_width/1`. `String.length("◆")` returns 1 grapheme, which happens to be correct for these glyphs — but this coincidence fails for combining marks and is policy-breaking.
- **Hardcoded color atoms**: No `:green`, `:cyan`, `:yellow`, `:red`, `:blue`, `:magenta`, `:white`, `:black` atoms anywhere in the module. Use `theme.slot.fg`.
- **Boolean unread? in public API**: `RichRow` takes `state_cluster: [:unread]`, not `unread?: true`. The `unread?` field exists only inside `ThreadList.render_thread_row/4` before translation to state atoms.
- **Cluster width as a runtime variable**: `@cluster_width` must be a compile-time module attribute. Computing it at runtime per call risks desync between glyph set and padding.
- **Adding `:locked` to `cast/3`**: Phase 20 reads `ThreadEntry.locked` — no schema change.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Display-width measurement | Custom `String.length` or `byte_size` check | `Foglet.TUI.TextWidth.display_width/1` | CJK is 2 cells; combining marks are 0 cells; Phase 16 established this |
| Title truncation with ellipsis | Custom `String.slice` | `Foglet.TUI.TextWidth.truncate/2` | Handles grapheme boundary splits and double-wide char avoidance |
| Right-padding to exact cell width | Manual space construction | `Foglet.TUI.TextWidth.pad_trailing/2` | Unicode-safe padding |
| Width-fit assertion in tests | Manual `TextWidth.display_width(flat) == width` guards | `assert_line_within_width!/3` from `layout_smoke_test.exs` | Already defined in the smoke test file |
| Style assertion in widget tests | `inspect(result) =~ "some color"` | `Foglet.TUI.WidgetHelpers.assert_text_run/3` | Finds the exact text node containing the content and checks its style properties structurally, not as string match |
| Theme color atom check | Manual `String.contains?` | `Foglet.TUI.WidgetHelpers.color_atom_leaked?/2` | Word-boundary regex avoids false positives (`:hovered_red` ≠ `:red`) |
| Emoji-based locked glyph | `🔒` or `🔐` | `⚿` (U+26BF) | Emoji glyphs are 2-cell wide on all SSH terminals — confirmed by `Raxol.UI.TextMeasure.display_width/1` |

**Key insight:** All width math primitives and test assertion helpers exist. `RichRow` needs only to call them at the right points, not reimplement them.

## Common Pitfalls

### Pitfall 1: Emoji Lock Glyph Double-Width

**What goes wrong:** Using `🔒` (U+1F512) or `🔐` (U+1F510) as the locked glyph breaks the cluster's fixed-width contract — the cluster renders 1 cell wider than `@cluster_width` on every SSH terminal.

**Why it happens:** Emoji are universally 2 display cells in terminal emulators. `Raxol.UI.TextMeasure.display_width("🔒")` returns 2 (confirmed in this research).

**How to avoid:** Use `⚿` (U+26BF, display_width=1) or another Miscellaneous Symbols block glyph. Verify any candidate glyph with `Raxol.UI.TextMeasure.display_width/1` before committing. The wave-1 task should run this check programmatically.

**Warning signs:** A test asserting `TextWidth.display_width(flat) <= width` fails with off-by-one at the cluster boundary.

### Pitfall 2: `⚑` Semantic Conflict with Phase 19 Moderation

**What goes wrong:** Using `⚑` (U+2691) as the locked glyph creates cross-screen semantic confusion — Phase 19 reserves `⚑` for the Moderation menu item in `MainMenu` (19-CONTEXT.md D-08, line 41).

**Why it happens:** `⚑` was documented as the Moderation glyph before Phase 20 was designed.

**How to avoid:** Use `⚿` (U+26BF) for locked. It is semantically a "squared key/lock" symbol, visually distinct from `⚑`, and not reserved by any prior phase.

**Warning signs:** `grep -r "⚑"` in `lib/` returns hits from both `main_menu.ex` and `rich_row.ex`.

### Pitfall 3: Cluster Width Drift Across State Combinations

**What goes wrong:** A row with all three glyphs is 1-2 cells wider than a row with no glyphs because padding was not added for absent glyphs.

**Why it happens:** Rendering only present glyphs without padding to the fixed `@cluster_width` breaks column alignment.

**How to avoid:** The `@glyph_map` must map every atom slot to either its glyph or a space of the same display width. The cluster string always has exactly `@cluster_width` display cells regardless of which atoms are present.

**Warning signs:** Acceptance criterion (d) from SPEC Requirement 2 fails — "a read+non-sticky+unlocked thread row's leading cluster pads to the same display-width as a fully-glyphed cluster."

### Pitfall 4: `assert_text_run/3` Content Match Is a Substring Search

**What goes wrong:** A test calls `assert_text_run(tree, "◆ ●", ...)` expecting an exact node match, but the tree has `"▌ ◆ ● Thread title..."` as one node — it matches. A separate test calls `assert_text_run(tree, "◆", ...)` and accidentally matches a text node that contains the unread glyph as part of a longer string.

**Why it happens:** `assert_text_run/3` uses `String.contains?/2` — it finds the first node whose content includes the search string.

**How to avoid:** Be specific about the content string passed to `assert_text_run/3`. For glyph-presence assertions, `flatten_text(tree) =~ "◆"` is simpler and correct.

### Pitfall 5: Row Struct vs Map Access in ThreadList

**What goes wrong:** `ThreadEntry` is a plain struct. Calling `Map.get(thread, :sticky, false)` works (structs support `Map.get/3`), but pattern-matching on `%{sticky: s}` is fragile if the struct adds fields.

**Why it happens:** The existing `render_thread_row/4` uses `Map.get(thread, :sticky, false)` — copy this pattern for consistency.

**How to avoid:** Access `ThreadEntry` fields via direct struct field access (`thread.sticky`, `thread.locked`, `thread.has_unread`) or `Map.get(thread, :sticky, false)` — match the pattern in the existing `render_thread_row/4` at `thread_list.ex:71-75`.

**Warning signs:** `KeyError` or `FunctionClauseError` when `ThreadEntry` fields are nil (they default to nil, not false).

### Pitfall 6: ThreadList `annotate_fallback/1` Populates `locked` from `Thread.locked`

**What goes wrong:** Tests using `FakeThreads` (which return plain maps) may not include `locked: true`. Asserting the locked glyph in `thread_list_test.exs` requires a fake thread fixture that has `locked: true`.

**Why it happens:** The existing fake adapters (e.g. `FakeThreads`) do not include `:locked`. They were written before Phase 20.

**How to avoid:** Add a `FakeLockedThreads` adapter to `thread_list_test.exs` that returns a thread with `locked: true`, or extend an existing fake. Match the `AnnotatingFakeThreads` pattern (defined at line 83 of `thread_list_test.exs`).

## Code Examples

### Minimal RichRow render skeleton

```elixir
# Source: adapted from lib/foglet_bbs/tui/widgets/list/list_row.ex:96-113

import Raxol.Core.Renderer.View
alias Foglet.TUI.TextWidth

@cluster_width 5  # computed via display_width of max cluster string, e.g. "◆ ● ⚿"

def render(opts) when is_list(opts) do
  title         = Keyword.fetch!(opts, :title)
  metadata      = Keyword.fetch!(opts, :metadata)
  state_cluster = Keyword.get(opts, :state_cluster, [])
  selected      = Keyword.get(opts, :selected, false)
  theme         = Keyword.fetch!(opts, :theme)
  width         = Keyword.get(opts, :width, 80)
  focus_marker  = Keyword.get(opts, :focus_marker, "▌ ")
  emphasis      = Keyword.get(opts, :emphasis, nil)

  marker   = if selected, do: focus_marker, else: "  "
  cluster  = render_cluster_string(state_cluster, theme)  # returns String.t, width = @cluster_width

  {left_part, padding, _meta} = compute_parts(marker, cluster, title, metadata, width)

  {title_style, meta_style, pad_style} = styles_for(selected, emphasis, theme)

  row style: %{gap: 0} do
    [
      text(left_part, title_style),
      text(padding, pad_style),
      text(metadata, meta_style)
    ]
  end
end
```

### Cluster string computation

```elixir
# Each position in the cluster maps to: glyph (1 cell) + trailing space (1 cell)
# Total for 3-slot cluster: 3 glyphs * 2 cells each = 6... but adjacent, see below.
# Strategy: "glyph space glyph space glyph" = 3 + 2 spaces = 5 cells → @cluster_width 5
# OR: "glyph glyph glyph " = 3 + 1 space = 4 cells → @cluster_width 4
# Planner chooses; the test validates via: TextWidth.display_width(cluster_str) == @cluster_width

@glyph_unread  "◆"
@glyph_sticky  "●"
@glyph_locked  "⚿"
@glyph_space   " "  # same display width as each glyph (1 cell)

defp render_cluster_string(state_atoms, _theme) do
  u = if :unread in state_atoms, do: @glyph_unread, else: @glyph_space
  s = if :sticky in state_atoms, do: @glyph_sticky, else: @glyph_space
  l = if :locked in state_atoms, do: @glyph_locked, else: @glyph_space
  # With single trailing space as separator: "usl " = 4 cells, @cluster_width = 4
  # Planner chooses exact format; TextWidth.display_width must equal @cluster_width
  u <> s <> l <> " "
end
```

### styles_for dispatch extended for RichRow

```elixir
# Source: adapted from lib/foglet_bbs/tui/widgets/list/list_row.ex:170-191

defp styles_for(true = _selected, _emphasis, theme) do
  selected_style = Map.get(theme.selected, :style, [:bold])
  sel_kw = [fg: theme.selected.fg, bg: theme.selected.bg, style: selected_style]
  {sel_kw, sel_kw, sel_kw}
end

defp styles_for(false = _selected, :bold = _emphasis, theme) do
  # unread, not selected
  {
    [fg: theme.accent.fg, style: [:bold]],
    [fg: theme.dim.fg],
    [fg: theme.dim.fg]
  }
end

defp styles_for(false = _selected, _emphasis, theme) do
  {
    [fg: theme.unselected.fg],
    [fg: theme.dim.fg],
    [fg: theme.dim.fg]
  }
end
```

### thread_list_test.exs LIST-03 extension (new assertions)

```elixir
# Source: test/foglet_bbs/tui/screens/thread_list_test.exs — extend describe block ~line 221

test "unread thread row contains ◆ in leading cluster", %{state: state} do
  {s, _} = ThreadList.load_threads(%{state | session_context: %{domain: %{threads: AnnotatingFakeThreads}}}, "b1")
  flat = flatten_text(ThreadList.render(s))
  assert flat =~ "◆"
end

test "sticky thread row contains ● in leading cluster", %{state: state} do
  {s, _} = ThreadList.load_threads(state, "b1")
  flat = flatten_text(ThreadList.render(s))
  assert flat =~ "●"
end

test "no row contains the literal string [S] ", %{state: state} do
  {s, _} = ThreadList.load_threads(state, "b1")
  flat = flatten_text(ThreadList.render(s))
  refute flat =~ "[S] "
end
```

### layout_smoke_test.exs size contract block

```elixir
# Source: test/foglet_bbs/tui/layout_smoke_test.exs — add new describe block

describe "thread_list — size contract" do
  setup do
    now = DateTime.utc_now()
    threads = [
      %Foglet.Threads.ThreadEntry{
        id: "t1",
        title: String.duplicate("x", 100),  # long title forces truncation
        sticky: true,
        locked: true,
        has_unread: true,
        post_count: 5,
        last_post_at: now,
        created_by: %{handle: "alice"}
      }
    ]
    user = %{id: "u1", handle: "alice", status: :active, role: :member}
    %{threads: threads, user: user}
  end

  for {width, height} <- [{64, 22}, {80, 24}, {132, 50}] do
    test "at #{width}x#{height}: cluster fully rendered, metadata visible, title truncated", ctx do
      # ... state setup, ThreadList.render/1, apply_at_size, assertions ...
      # (a) flat =~ "◆", flat =~ "●", flat =~ "⚿"  -- cluster glyphs present
      # (b) flat =~ "@alice"                         -- metadata present
      # (c) flat =~ "…"                              -- title truncated when forced
      # (d) TextWidth.display_width(flat) <= width   -- fits in budget
    end
  end
end
```

## State of the Art

| Old Approach | Current Approach | Changed | Impact |
|--------------|------------------|---------|--------|
| `> ` marker for selection | `▌` (U+258C) marker | Phase 14+ (SelectionList) | RichRow must use `▌`, not `> ` |
| `[S] ` text prefix for sticky | `●` (U+25CF) glyph in cluster | Phase 20 | Text prefix removal is a Phase 20 acceptance criterion |
| `unread?` boolean in render signature | `:state_cluster` atom list | Phase 20 (new) | Generic API enables Phase 21/25 reuse |
| `String.length` for width | `TextWidth.display_width/1` | Phase 16 | All layout code uses `TextWidth` |

**Deprecated/outdated:**
- `ListRow.render_with_metadata/6` with `unread?` boolean: stays intact for current callers (BoardList, NewThread, Sysop, Account). Do NOT modify it.
- `> ` selection marker: deprecated for list screens in favor of `▌`, but kept in `ListRow.render/3` for backwards compatibility.

## Glyph Cross-Terminal Compatibility

### Verified Display Widths (via `Raxol.UI.TextMeasure.display_width/1`)

[VERIFIED: ran `rtk mix run --no-start` in project context]

| Glyph | Codepoint | Display Width | Notes |
|-------|-----------|---------------|-------|
| `◆` | U+25C6 BLACK DIAMOND | **1** | Locked in as unread glyph (D-05) |
| `◇` | U+25C7 WHITE DIAMOND | **1** | Locked in as read glyph (D-05) |
| `●` | U+25CF BLACK CIRCLE | **1** | Locked in as sticky glyph (D-05) |
| `⚿` | U+26BF SQUARED KEY | **1** | Recommended locked glyph (D-05) |
| `⚑` | U+2691 BLACK FLAG | **1** | Forbidden for locked — reserved by Phase 19 Moderation (19-CONTEXT.md D-08) |
| `🔒` | U+1F512 LOCK | **2** | Forbidden — breaks cluster alignment |
| `🔐` | U+1F510 LOCK WITH KEY | **2** | Forbidden — breaks cluster alignment |
| `▌` | U+258C LEFT HALF BLOCK | **1** | Canonical selection marker — confirmed across all sibling widgets |
| `■` | U+25A0 BLACK SQUARE | **1** | Alternative fallback only; not recommended for this phase |

### Cross-Terminal Notes

[ASSUMED] for PuTTY/Windows Terminal rendering, based on Unicode standard + research findings:

- **Miscellaneous Symbols (U+2600-U+26FF):** Treated as East Asian Width "Ambiguous" by Unicode spec. `glibc wcwidth()` and the de-facto terminal standard report **1 cell** for these characters. Windows Terminal issue #2066 confirms this was standardized. SSH clients that use system `wcwidth()` (xterm, iTerm2, macOS Terminal, tmux, WezTerm, PuTTY via PuTTY's built-in wcwidth) will render these as 1 cell.

- **Emoji (U+1F000+):** Always 2 cells in modern terminals. Confirmed via `Raxol.UI.TextMeasure`.

- **Geometric Shapes (U+25A0-U+25FF):** Universally 1 cell (Narrow in Unicode EAW). No known terminal exceptions. `◆`, `◇`, `●`, `▌` all fall here.

- **Risk:** On very old PuTTY versions or misconfigured SSH clients, `⚿` (U+26BF) might render as a tofu box `□` if the font lacks it. The visual degradation is acceptable per D-07 (no ASCII fallback). If operator feedback indicates rendering issues, the response per D-07 is to swap `⚿` for another Geometric Shapes glyph (e.g. `■` U+25A0), not to add ASCII branching.

## Runtime State Inventory

Phase 20 is a TUI widget addition and screen migration. No rename/refactor of persistent data occurs.

| Category | Items Found | Action Required |
|----------|-------------|-----------------|
| Stored data | None — no schema or data change | None |
| Live service config | None | None |
| OS-registered state | None | None |
| Secrets/env vars | None | None |
| Build artifacts | None | None |

## Environment Availability

Phase 20 is purely code changes within the existing Elixir/Mix project.

| Dependency | Required By | Available | Version | Fallback |
|------------|------------|-----------|---------|----------|
| Elixir/Mix | All | ✓ | (project) | — |
| Raxol (vendored) | Widget DSL, TextMeasure | ✓ | vendor/raxol/ | — |
| `rtk mix test` | Test execution | ✓ | confirmed | — |

No missing dependencies.

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | ExUnit (Elixir standard) |
| Config file | `test/test_helper.exs` |
| Quick run command | `rtk mix test test/foglet_bbs/tui/widgets/list/rich_row_test.exs` |
| Full suite command | `rtk mix test test/foglet_bbs/tui/` |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| RICHROW-01 | RichRow renders with all input combos | unit | `rtk mix test test/foglet_bbs/tui/widgets/list/rich_row_test.exs` | ❌ Wave 0 |
| RICHROW-01 | No hardcoded color atoms | unit (theme hygiene) | `rtk mix test test/foglet_bbs/tui/widgets/list/rich_row_test.exs` | ❌ Wave 0 |
| THREADS-01 | ThreadList rows contain state glyphs | unit | `rtk mix test test/foglet_bbs/tui/screens/thread_list_test.exs` | ✅ |
| THREADS-01 | No `[S] ` in any rendered row | unit | `rtk mix test test/foglet_bbs/tui/screens/thread_list_test.exs` | ✅ (extend) |
| THREADS-02 | Focused row has unique styling property | unit | `rtk mix test test/foglet_bbs/tui/widgets/list/rich_row_test.exs` | ❌ Wave 0 |
| RICHROW-01 | 64-cell width: cluster+metadata fit, title truncates | unit + smoke | `rtk mix test test/foglet_bbs/tui/layout_smoke_test.exs` | ✅ (extend) |
| RICHROW-01 | RichRow accepts non-ThreadList state atoms | unit | `rtk mix test test/foglet_bbs/tui/widgets/list/rich_row_test.exs` | ❌ Wave 0 |

### Sampling Rate

- **Per task commit:** `rtk mix test test/foglet_bbs/tui/widgets/list/rich_row_test.exs`
- **Per wave merge:** `rtk mix test test/foglet_bbs/tui/`
- **Phase gate:** `rtk mix precommit` (compile + Credo + Sobelow + Dialyzer) before `/gsd-verify-work`

### Wave 0 Gaps

- [ ] `test/foglet_bbs/tui/widgets/list/rich_row_test.exs` — new file; covers RICHROW-01, THREADS-02, glyph/style/hygiene matrix
- [ ] Extend `test/foglet_bbs/tui/screens/thread_list_test.exs` LIST-03 describe block — glyph presence, `[S]` absence
- [ ] Extend `test/foglet_bbs/tui/layout_smoke_test.exs` — `thread_list — size contract` describe block

## Security Domain

Phase 20 introduces no authentication, session, authorization, or data persistence changes. No ASVS categories apply. `security_enforcement` is not explicitly set to false — but this phase is pure rendering logic with no input processing, credential handling, or data mutation.

| ASVS Category | Applies | Rationale |
|---------------|---------|-----------|
| V2 Authentication | No | No auth code touched |
| V3 Session Management | No | No session code touched |
| V4 Access Control | No | No authorization calls added |
| V5 Input Validation | No | No user input processed by RichRow |
| V6 Cryptography | No | No crypto |

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | `⚿` (U+26BF) renders as a visible glyph (not tofu `□`) across PuTTY and Windows Terminal | Glyph Cross-Terminal Notes | Locked glyph shows as box on some SSH clients; visual degradation only, no layout breakage (D-07 response: swap glyph, no ASCII branch) |
| A2 | Phase 19 `⚑` reservation in 19-CONTEXT.md D-08 means the Phase 19 implementation will ship `⚑` for Moderation | Pitfall 2 | If Phase 19 doesn't ship `⚑`, it is not yet reserved and could be used; verify when Phase 19 implementation lands |

**All other claims in this research are VERIFIED via codebase inspection or direct `rtk mix run` output.**

## Open Questions

1. **Exact `@cluster_width` value and glyph spacing**
   - What we know: 3 glyph positions, each 1 cell; separators add cells; total must be fixed.
   - What's unclear: Whether spaces between glyphs are 0 (glyphs adjacent: `◆●⚿ ` = 4 cells) or 1 (glyphs separated: `◆ ● ⚿` = 5 cells). Both are valid; wider gaps improve scanability.
   - Recommendation: Planner decides; verify `TextWidth.display_width(@cluster_string) == @cluster_width` as the Wave 0 assertion.

2. **`sticky` routes to `theme.info.fg` or `theme.badge.fg`**
   - What we know: Both slots exist in all 9 themes (confirmed in `theme.ex`). In gray theme: `info: %{fg: "#ffb000"}`, `badge: %{fg: "#000000", bg: "#aaaaaa"}`. In green theme: both are distinctively colored.
   - What's unclear: Visual contrast of `●` in `info.fg` vs `badge.fg` depends on terminal background.
   - Recommendation: Planner picks `theme.info.fg` — it is a straight foreground color without a `bg` override, making it safe to use on the row background. `badge.fg` has a `bg` key that would create a background block around the `●` glyph if applied naively.

3. **Whether `read` state renders `◇` explicitly or as whitespace**
   - What we know: SPEC explicitly allows either; whitespace simplifies the render path.
   - Recommendation: Planner uses whitespace — a single space per glyph position. Avoids one more theme-slot decision and reduces visual noise in read rows.

## Sources

### Primary (HIGH confidence)
- `lib/foglet_bbs/tui/widgets/list/list_row.ex` — Full API, width math, style dispatch
- `lib/foglet_bbs/tui/widgets/list/selection_list.ex` — Stateless widget pattern, `▌` selection marker
- `lib/foglet_bbs/tui/widgets/list/smart_list.ex` — `@focused_marker`, stateful/stateless distinction
- `lib/foglet_bbs/tui/theme.ex` — All 9 theme slot definitions (gray through mono)
- `lib/foglet_bbs/tui/text_width.ex` — Full TextWidth API
- `lib/foglet_bbs/tui/screens/thread_list.ex` — Current consumer, render_thread_row pattern
- `lib/foglet_bbs/threads/thread_entry.ex` — ThreadEntry struct with `:has_unread`, `:sticky`, `:locked`
- `lib/foglet_bbs/tui/widgets/README.md` — D-16 stateless widget contract
- `vendor/raxol/lib/raxol/ui/text_measure.ex` — Backend delegates to CharacterHandling
- `test/support/foglet/tui/widget_helpers.ex` — `flatten_text/1`, `assert_text_run/3`, `color_atom_leaked?/2`
- `test/foglet_bbs/tui/widgets/list/list_row_test.exs` — Canonical test patterns for metadata row widgets
- `test/foglet_bbs/tui/screens/thread_list_test.exs` — LIST-03 describe block to extend
- `test/foglet_bbs/tui/layout_smoke_test.exs` — Phase 18/19 size contract pattern
- `rtk mix run --no-start` — Direct glyph display_width measurements

### Secondary (MEDIUM confidence)
- [Windows Terminal issue #2066](https://github.com/microsoft/terminal/issues/2066) — Ambiguous-width character standardization (1 cell) in ConPTY/Windows Terminal
- `.planning/phases/20-rich-rows-and-thread-flow/20-CONTEXT.md` — All implementation decisions (D-01 through D-15)
- `.planning/phases/19-main-menu-dashboard/19-CONTEXT.md` — D-08 `⚑` Moderation glyph reservation

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — all modules read from source; function signatures confirmed
- Architecture: HIGH — direct pattern derivation from ListRow + SelectionList source
- Glyph widths: HIGH — confirmed via `Raxol.UI.TextMeasure.display_width/1` at runtime
- Cross-terminal glyph rendering: MEDIUM — Unicode standard + wcwidth de-facto standard; PuTTY specifics ASSUMED
- Pitfalls: HIGH — derived from source reading and accepted test patterns
- Test patterns: HIGH — all helpers read from source with function signatures confirmed

**Research date:** 2026-04-25
**Valid until:** 2026-05-25 (stable domain — no external API dependencies)
