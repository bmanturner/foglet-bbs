# Phase 21: Board Directory Facelift — Research

**Researched:** 2026-04-25
**Domain:** Raxol TUI — multi-column tree row rendering inside an SSH-served Elixir TUI app
**Confidence:** HIGH (codebase grounding); MEDIUM-HIGH (Phase 20 contract not yet shipped — verified against locked Phase 20 CONTEXT/SPEC/PLAN, not against running code)

## Summary

Phase 21 is a Raxol TUI redesign that replaces a single-label `Display.Tree` with a custom `BoardTree` wrapper that walks the tree itself and dispatches each visible board node into Phase 20's `RichRow` for multi-column rendering. Two architectural directions exist on paper — extend `Display.Tree` with a row-callback hook, OR build a dedicated `BoardTree` wrapper — but the evidence in the codebase, the vendored Raxol source, and the locked CONTEXT.md/SPEC.md all converge on one answer: **build `BoardTree` as a new wrapper that owns a `Display.Tree` for cursor/expand state and emits each row through `RichRow`**. The "extend Display.Tree" option is structurally rejected (Display.Tree's `build_children/2` is private and column-string-only; CONTEXT.md explicitly bans contract changes to it), and the SCREENS.md primitive-gap note already proposed the wrapper path.

The key implementation risks are not architectural — they are layout-correctness and data-shape risks: width-math of the cluster + glyph prefix + name + composite metadata column at 64-cell content width; the `:last_post_at` aggregate avoiding N+1 across both subscribed and unsubscribed boards; the `⚿` (U+26BF) Unicode East-Asian-Width "Ambiguous" property creating a 1-vs-2-cell terminal-rendering mismatch; and `Foglet.TimeAgo.format/1` returning `"?"` (not the em-dash `—`) on `nil`, which means `BoardTree` MUST branch on `nil` BEFORE delegating to `TimeAgo`.

**Primary recommendation:** Build `Foglet.TUI.Widgets.List.BoardTree` as a stateful facade (`init/1` + `handle_event/2` + `render/2`) that internally holds a `Display.Tree` struct and walks `RaxolTree.visible_nodes/1` itself, emitting category rows inline (themed `text/2`) and board rows through `RichRow.render/1` per CONTEXT D-01/D-02/D-04. Compose the subscription glyph (`⚿`/`✓`/`+`) as a fixed 2-cell title prefix (D-02). Compose the unread-count + age column as a single right-aligned composite string in `RichRow`'s `:metadata` slot, separator = two spaces (D-04). For the `last_post_at` aggregate, mirror `Foglet.Boards.unread_counts/1`'s structural pattern but join from `Board` (not `Subscription`) so unsubscribed boards are populated identically (D-09 + a correction documented below).

## User Constraints (from CONTEXT.md)

### Locked Decisions

**SPEC override (precedence note):** CONTEXT.md modifies the locked SPEC. Where SPEC.md and CONTEXT.md disagree, CONTEXT wins. The planner reconciles. (`<spec_lock>` and `<acceptance_overrides>` blocks in CONTEXT carry the canonical contract.)

**Preserved from SPEC:**
- Requirement 1: `BoardTree` wrapper with `▾`/`▸` category glyphs, board rows through `RichRow`.
- Requirement 2 (modified): glyph-only subscription column — `⚿` required, `✓` subscribed, `+` available; no `[required]`/`[subscribed]`/`[unsubscribed]` literal text.
- Requirement 3: `directory_board` exposes `:last_post_at` (max of non-deleted thread `last_post_at`, or `nil`); identical for subscribed/unsubscribed actors; no N+1.
- Requirement 6: workflows preserved (j/k/↑/↓/←/→/Enter/s/u/q/Q).

**Overridden by CONTEXT:**
- ❌ Requirement 4 (details strip) **REMOVED**. No details strip below the tree. Per-row age column replaces it.
- ✏️ Requirement 5 (64x22 priority contract) extended. Now covers four trailing-priority segments: read-state cluster + subscription-glyph prefix + unread column + age column all render fully; only the board name truncates with `…`. The 20-cell minimum name attempt is preserved.

**Implementation Decisions (D-01 … D-11):**
- D-01: `BoardTree` mirrors `Display.Tree`'s stateful facade (`init/1`/`handle_event/2`/`render/2`). Owns a `Display.Tree` struct internally; walks `RaxolTree.visible_nodes/1` itself; dispatches each visible node to either an inline category row (rendered by `BoardTree`) or `RichRow.render/1` for a board row. `BoardList` no longer imports `Display.Tree` directly in its row render path.
- D-02: `RichRow`'s `:state_cluster` carries **read-state only** (`[:unread]` or `[]`). Subscription glyph is composed as a fixed 2-cell **title prefix** (e.g. `"⚿ announcements"`). Unread + age ride together in `:metadata` with two-space separator.
- D-03: ⚠️ **RichRow has not yet shipped.** Phase 21 plans against `20-CONTEXT.md` D-01/D-02. Planner re-validates D-02 against the actual signature before plan 21-01.
- D-04: Row segments in order: indent (4), read-state cluster (Phase 20 `@cluster_width = 4`), subscription glyph + name (`:title`), unread + age (`:metadata`).
- D-05: Width math at 64x22 — body 60 cells, fixed segments 22, gap 2, **name budget 36 cells** (well above the 20-cell Phase 20 minimum).
- D-06: Age via `Foglet.TimeAgo.format/1` short form (`12m`/`2h`/`3d`); em-dash `—` (U+2014) for `nil` `last_post_at`.
- D-07: Category rows render only `{▾|▸} {category.name}` — no trailing summary, no age column, no subscription glyph.
- D-08: Details strip REMOVED. Only the tree (and existing top-of-tree feedback flash line) renders inside `Chrome.ScreenFrame`.
- D-09: `:last_post_at` added via single-pass `LEFT JOIN` aggregate query, structurally similar to `Foglet.Boards.unread_counts/1`. **Correction (see Pitfall 4 below):** the aggregate must source from `Board`, not `Subscription`, since unsubscribed boards must also be populated.
- D-10: Subscription feedback preserves the existing top-of-tree flash via `BoardList.maybe_feedback/2`. Strings preserved verbatim.
- D-10b: Subscription glyph theme slots — `⚿` → `theme.warning.fg`, `✓` → `theme.info.fg`, `+` → `theme.dim.fg` (planner discretion within these recommendations).
- D-11: Tests — NEW `board_tree_test.exs`; EXTEND `board_list_test.exs` (replace bracketed-text assertions with glyph assertions); EXTEND `layout_smoke_test.exs` (add `board_list — size contract` block at `[{64,22},{80,24},{132,50}]`); EXTEND `boards_test.exs` `board_directory_for/1` block with `:last_post_at` cases.

### Claude's Discretion

- Final theme-slot picks for the subscription glyphs (D-10b recommends `theme.warning.fg` / `theme.info.fg` / `theme.dim.fg`).
- Exact whitespace/separator strategy between row segments — single space, double space, or `TextWidth.pad_to_width`-based fixed columns.
- Read-state cluster width — recommended: reuse Phase 20's `@cluster_width = 4` verbatim.
- Whether age column right-padding is fixed at 3 cells or trims trailing whitespace.
- Whether the `last_post_at` aggregation query is a sibling private function to `unread_counts/1` or merged into a single multi-aggregate query.
- Whether the em-dash `—` for nil age renders through `theme.dim.fg` or default foreground.
- Whether to substitute a different 1-cell BMP glyph for `⚿` if visual testing reveals rendering issues; planner should flag any substitution in plan output for review.

### Deferred Ideas (OUT OF SCOPE)

- Wide-terminal inspector pane on the right.
- Category-row summary text (board count, unread total).
- ASCII-only fallback glyph set.
- Adoption of `BoardTree` by Sysop screens (Phase 25 territory).
- New keyboard binding for `+ subscribe` — `+` is visual state only.
- Theme palette retuning (UI-03 v2 territory).
- Schema, query, or context API changes beyond `:last_post_at` on `directory_board`.
- Changes to `Foglet.TUI.Widgets.Display.Tree` public contract.
- Changes to `Foglet.TUI.Widgets.List.RichRow` public API.

## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| BOARDS-01 | Distinguish expanded/collapsed categories (`▾`/`▸`), read/unread boards (`◆`/`◇`), and subscription state (`⚿`/`✓`/`+`) via semantic columns and glyphs. | RichRow contract from Phase 20 (D-01/D-02/D-05) supports the read-state cluster; Pattern 1 below maps each visual element to either a `RichRow` slot or a `BoardTree`-owned category-row branch. Glyph width tables verified against Raxol `CharacterHandling.wide_char?/1`. |
| BOARDS-02 | Focused board/category details visible — ORIGINALLY a 64x22 details strip, **fulfilled differently in this phase** (per CONTEXT D-08): each board row carries a trailing age column instead. | CONTEXT supersedes SPEC. The 60-cell body width math (D-05) shows the four trailing segments fit at 64x22 with 36 cells for the name. The wide inspector remains deferred. |
| BOARDS-03 | Existing open / expand-collapse / subscribe / unsubscribe / back workflows preserved. | `BoardList.handle_key/2` keeps its surface (j/k/↑/↓/←/→/Enter/s/u/q/Q). Internally events forward to `BoardTree.handle_event/2` instead of `Display.Tree.handle_event/2`. The `:load_threads` command emission on Enter for board nodes is preserved. Required-subscription guard preserved verbatim. |
| BOARDS-04 | Single-label tree limitation solved through `Tree.render_row/3`-style row callbacks OR a dedicated `BoardTree` wrapper. | **Wrapper wins.** Raxol's `Display.Tree` does not expose a row-callback hook (verified against `vendor/raxol/lib/raxol/ui/components/display/tree.ex`). The Foglet `Display.Tree` wrapper at `lib/foglet_bbs/tui/widgets/display/tree.ex` already walks `visible_nodes/1` itself, but its render path is column-of-text-rows-only. CONTEXT D-01 explicitly bans modifying `Display.Tree`'s contract. The `BoardTree` wrapper is the locked path. |

## Project Constraints (from CLAUDE.md / AGENTS.md)

These are absolute — RESEARCH.md does not recommend approaches that contradict them.

- **`Foglet.TUI.*` is the TUI namespace.** New modules live under `Foglet.TUI.Widgets.List.BoardTree`, mirrored at `lib/foglet_bbs/tui/widgets/list/board_tree.ex`.
- **Pure render functions over already-loaded state.** `BoardTree.render/2` performs no DB queries, no side effects, no PubSub. All state arrives via `init/1` (the directory) and `render/2` opts (theme, width).
- **Theme routing is mandatory.** No hardcoded color atoms — fg/bg/style come from `Foglet.TUI.Theme` slots only.
- **Width-sensitive layout uses `Foglet.TUI.TextWidth`.** Never `String.length/1` or grapheme counts for layout decisions.
- **Stateful widgets expose `init/1` + `handle_event/2` + `render/2`.** Mandatory for `BoardTree` per CONTEXT D-01.
- **Widget moduledoc cites decision IDs** (D-07, D-09, D-13, D-14 from earlier phases — see `lib/foglet_bbs/tui/widgets/README.md` for canonical guidance).
- **Tests use `start_supervised!/1`** for any supervised processes; no `Process.sleep/1` or `Process.alive?/1`.
- **`mix precommit` runs at completion** — compile (warnings as errors), formatter, Credo, Sobelow, Dialyzer.
- **`rtk` shell prefix** for `mix`/`git` invocations.
- **No N+1 queries** in `board_directory_for/1` extension (CONTEXT D-09; explicit constraint per SPEC line 91).

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|--------------|----------------|-----------|
| Tree visible-node walk + cursor + expanded set | `BoardTree` (wraps `Display.Tree`) | `Raxol.UI.Components.Display.Tree.visible_nodes/1` | `Display.Tree` already provides the canonical visible-node algorithm and cursor/expanded state; reusing it avoids reimplementing tree mutation. |
| Category row rendering (`▾`/`▸` + name) | `BoardTree` (inline `text/2`) | `Foglet.TUI.Theme` (slot lookup) | Category rows are simple — no multi-column layout — so an inline themed `text/2` is more readable than routing through `RichRow`. |
| Board row rendering (cluster + title + metadata) | `Foglet.TUI.Widgets.List.RichRow.render/1` (Phase 20) | `Foglet.TUI.TextWidth` for width math | RichRow is the locked Phase 20 primitive; reusing it keeps the row contract consistent with ThreadList. |
| Subscription glyph mapping | `BoardTree` (composes title prefix) | `Foglet.TUI.Theme` slots | RichRow's `:state_cluster` doesn't accept `+`/`⚿`/`✓` reliably (mixing reserved + unreserved atoms is brittle per CONTEXT D-02), so glyph-as-title-prefix is the safer integration. |
| Read-state glyph (`◆`/`◇`/space) | `RichRow` (`:state_cluster: [:unread]` or `[]`) | — | `:unread` is a Phase 20 reserved cluster atom; route through the existing slot. |
| Age column formatting | `Foglet.TimeAgo.format/1` | `BoardTree` (handles `nil` → `—` em-dash branch) | Existing helper produces `"12m"`/`"2h"`/`"3d"` magnitudes verbatim; nil branch belongs to BoardTree because TimeAgo returns `"?"` on nil (NOT em-dash). |
| `:last_post_at` aggregation | `Foglet.Boards.board_directory_for/1` | `Repo` LEFT JOIN aggregate | Domain context owns the query per AGENTS.md ("contexts own preload choices and queries"); structurally mirrors `unread_counts/1`. |
| Width truncation (name only) | `RichRow.truncate_title/2` | `Foglet.TUI.TextWidth.truncate/3` | Phase 20 already handles right-truncation with `…`; the title prefix `"⚿ "` is preserved by the right-truncation contract. |
| Subscription feedback flash | `BoardList.maybe_feedback/2` (existing) | `Foglet.TUI.Theme.accent.fg` | Preserved verbatim — no migration to inline-row treatment per CONTEXT D-10. |

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| `raxol` | 2.4.0 (vendored at `vendor/raxol`) | Terminal UI rendering primitives + tree component | Project's TUI runtime; `Display.Tree` wrapped by `Foglet.TUI.Widgets.Display.Tree`. `[VERIFIED: vendor/raxol/mix.exs @version 2.4.0]` |
| `raxol_terminal` | from `deps/raxol_terminal` | Display-width measurement (`CharacterHandling.wide_char?/1`) | Source of truth for terminal cell width; used through `Raxol.UI.TextMeasure`. `[VERIFIED: deps/raxol_terminal/lib/raxol/terminal/character_handling.ex]` |

### Foglet-internal building blocks (all required, in scope)

| Module | Purpose | Why Used |
|--------|---------|----------|
| `Foglet.TUI.Widgets.List.RichRow` (Phase 20, NEW from sibling phase) | Multi-column row primitive: state-cluster + title + metadata + selection treatment | The locked Phase 20 contract that Phase 21 consumes. `[VERIFIED: 20-CONTEXT.md D-01..D-04, 20-04-PLAN.md @cluster_width=4 + module skeleton]` |
| `Foglet.TUI.Widgets.Display.Tree` (existing) | Owns Raxol tree state (cursor, expanded set, `visible_nodes`) | `BoardTree` holds one internally per CONTEXT D-01; no public-contract change. `[VERIFIED: lib/foglet_bbs/tui/widgets/display/tree.ex]` |
| `Foglet.Boards.board_directory_for/1` (existing, +`:last_post_at` field) | Source of `[%{category, boards: […]}]` directory shape | Already populates the directory; D-09 adds `:last_post_at` via aggregate join. `[VERIFIED: lib/foglet_bbs/boards.ex:243-271]` |
| `Foglet.Boards.unread_counts/1` (existing, structural reference) | Single-pass batch unread aggregate (group_by + count) | Canonical aggregate-query pattern in this codebase. NOTE — joins from `Subscription`, not `Board`, so the new `last_post_ats/1` aggregate must NOT copy this exact pattern (see Pitfall 4). `[VERIFIED: lib/foglet_bbs/boards.ex:511-526]` |
| `Foglet.TimeAgo.format/1` (existing) | Compact relative-time formatter (`"12m"`/`"2h"`/`"3d"`) | Already produces the magnitudes Phase 21 wants verbatim; consumed identically by `PostCard.get_time_ago/1` at `post_card.ex:163-198`. `[VERIFIED: lib/foglet_bbs/time_ago.ex]` |
| `Foglet.TUI.TextWidth` (existing) | Display-width helpers: `display_width/1`, `slice_to_width/2`, `truncate/3`, `pad_trailing/2`, `pad_leading/2` | Mandatory for column width math; `String.length` is forbidden for layout per project conventions. `[VERIFIED: lib/foglet_bbs/tui/text_width.ex]` |
| `Foglet.TUI.Theme` (existing) | Theme slot vocabulary (`accent`, `info`, `badge`, `warning`, `dim`, `selected`, `unselected`, `primary`) | All glyph colors route through these slots; no new slots in Phase 21. `[VERIFIED: lib/foglet_bbs/tui/theme.ex:69-97]` |

### Supporting (test-only)

| Module | Purpose | When to Use |
|--------|---------|-------------|
| `Foglet.TUI.WidgetHelpers` (test support) | `flatten_text/1`, `assert_text_run/3`, `text_runs/1`, `color_atom_leaked?/2`, `color_names/0` | Every widget test imports this. `[VERIFIED: test/support/foglet/tui/widget_helpers.ex]` |
| `FogletBbs.DataCase` | Async-disabled DB-backed test case for `boards_test.exs` extensions | Required for the `:last_post_at` data-layer tests. `[VERIFIED: test/foglet_bbs/tui/layout_smoke_test.exs:1 uses it]` |
| `Raxol.UI.Layout.Engine.apply_layout/2` (via `layout_smoke_test.exs`) | Positioned-render harness for size-contract assertions | Phase 18/19/20 use the same triple `[{64,22},{80,24},{132,50}]`. Phase 21 follows. `[VERIFIED: test/foglet_bbs/tui/layout_smoke_test.exs]` |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| `BoardTree` wrapper | Extending `Display.Tree` with a row-callback hook (`render_row/3`) | **Rejected.** (1) Raxol's `Display.Tree.build_children/2` is private and emits a single themed `text/2` per node; there's no extension seam. (2) Foglet's `Display.Tree` wrapper does walk `visible_nodes/1` itself, but a row-callback addition would change its public contract — explicitly OUT OF SCOPE per CONTEXT.md "Deferred Ideas." (3) Wrapping doesn't preclude future generalization; if Phase 25 needs the same shape, it lifts the row-dispatch logic. YAGNI: a single-consumer wrapper today, generalize later. |
| `RichRow :state_cluster: [:subscribed, :required, :available]` for the subscription glyph | Title-prefix approach (CONTEXT D-02) | **Rejected.** Phase 20's cluster is fixed-width 4 cells with three reserved slots (`:unread`/`:sticky`/`:locked`); the `+` available-to-subscribe glyph is not in Phase 20's reserved atom vocabulary. Mixing reserved + ad-hoc atoms in a single cluster breaks the fixed-width invariant Phase 20 enforces via property tests. Title-prefix sidesteps the contract entirely. |
| `Display.Table` (`lib/foglet_bbs/tui/widgets/display/table.ex`) | Flat tabular widget | **Rejected.** Table is flat — no expand/collapse parent rows. Categories require a tree-shaped data flow. |
| New domain helper `Foglet.Boards.last_post_ats/1` (separate query) | Inline merge into `board_directory_for/1` | **Both viable per D-09 Discretion.** Recommendation: extract a sibling private function `last_post_ats/0` (no actor parameter — the value is actor-independent per D-09) called once from `board_directory_for/1`. Mirrors `unread_counts/1`'s shape. Single Repo round-trip. |
| `Foglet.TimeAgo.format/1` returning `"?"` on nil → swallow at row level | Branch on `nil` BEFORE calling TimeAgo | **Branch first.** TimeAgo returns `"?"` for nil; CONTEXT D-06 wants `—` (U+2014). Calling `TimeAgo.format(nil)` and string-replacing `"?"` is fragile. Branch on `last_post_at == nil` in `BoardTree` (or a private `format_age/1` helper) and emit em-dash directly. |

### No Installation Required

This is an internal-module phase. No `mix.exs` deps change.

**Version verification:** `raxol 2.4.0` is vendored at `vendor/raxol`, not pulled from hex. Vendored source is the authoritative version. `[VERIFIED: vendor/raxol/mix.exs lines 4 and 53; mix.lock line 178 confirms hex-published version 2.4.0 for `raxol_core`/`raxol_liveview`/`raxol_mcp`/`raxol_plugin`/`raxol_sensor` siblings]`

## Architecture Patterns

### System Architecture Diagram

```
                     ┌────────────────────────────────────────────────┐
                     │  Foglet.TUI.Screens.BoardList.render/1         │
                     │  (existing screen — no public-contract change) │
                     └────────────────────────┬───────────────────────┘
                                              │ produces content_element
                                              ▼
                     ┌────────────────────────────────────────────────┐
                     │  Chrome.ScreenFrame.render/4                   │
                     │  (existing — passive, applies border + padding)│
                     │  Reserves 4 cells: 60-cell body at 64-wide TTY │
                     └────────────────────────┬───────────────────────┘
                                              │ inner content body
                                              │
                                  ┌───────────┴───────────┐
                                  │                       │
                       ┌──────────▼──────────┐  ┌─────────▼──────────┐
                       │ maybe_feedback/2    │  │ BoardTree.render/2 │
                       │ (existing flash     │  │ (NEW)              │
                       │  line, preserved)   │  └─────────┬──────────┘
                       └─────────────────────┘            │
                                                          │ owns one
                                                          │ Display.Tree struct
                                                          ▼
                                            ┌───────────────────────┐
                                            │ RaxolTree.visible_    │
                                            │ nodes/1 (existing)    │
                                            └─────────┬─────────────┘
                                                      │ [{node, depth}, …]
                                                      │ for each node:
                                              ┌───────┴────────┐
                                              │                │
                                  ┌───────────▼─────┐  ┌───────▼──────────────┐
                                  │ category branch │  │ board branch         │
                                  │ inline text/2:  │  │ compose:             │
                                  │ "▾ Public" or   │  │   :state_cluster =   │
                                  │ "▸ Public"      │  │       [:unread]/[]   │
                                  │ themed via      │  │   :title = "⚿ name"  │
                                  │ theme.primary/  │  │     (or "✓ "/"+ ")   │
                                  │   .accent       │  │   :metadata =        │
                                  └─────────────────┘  │     "N unread  12m"  │
                                                       │     (composite)      │
                                                       └───────┬──────────────┘
                                                               │
                                                  ┌────────────▼─────────────┐
                                                  │ RichRow.render/1 (NEW    │
                                                  │   from Phase 20)         │
                                                  │ - leading focus marker   │
                                                  │ - 4-cell state cluster   │
                                                  │ - truncated title        │
                                                  │ - right-aligned metadata │
                                                  └──────────────────────────┘

Data sources (read-only, loaded ahead of render — D-01 purity):
  ┌────────────────────────────────────────────┐
  │ Foglet.Boards.board_directory_for/1        │
  │ returns [%{category, boards: [%{...}]}]    │
  │ where each board entry now includes:       │
  │   :board, :subscribed?, :required_subs?,   │
  │   :unread_count, :last_post_at  ← NEW      │
  └─────────────────────────┬──────────────────┘
                            │ aggregate population
              ┌─────────────┼──────────────┐
              ▼             ▼              ▼
        list_boards/0  unread_counts/1  last_post_ats/0  ← NEW
        (existing)     (existing,        (NEW private,
                       Subscription      LEFT JOIN from
                       JOIN — only       Board, populates
                       subscribed)       all boards)
```

### Recommended Project Structure

```
lib/foglet_bbs/
├── boards.ex                              # +:last_post_at on directory_board, +last_post_ats/0 helper
├── tui/
│   ├── screens/
│   │   ├── board_list.ex                  # alias swap: Display.Tree → BoardTree (in row render path)
│   │   └── board_list/
│   │       └── state.ex                   # State.tree → State.board_tree (or keep field name, change type)
│   └── widgets/
│       └── list/
│           ├── board_tree.ex              # NEW: stateful facade per D-01
│           ├── list_row.ex                # unchanged
│           ├── rich_row.ex                # NEW from Phase 20 (consumed)
│           ├── selection_list.ex          # unchanged
│           └── smart_list.ex              # unchanged

test/
├── foglet_bbs/
│   ├── boards/
│   │   └── boards_test.exs                # EXTEND describe "board_directory_for/1 (SUBS-01)" with :last_post_at
│   └── tui/
│       ├── layout_smoke_test.exs          # ADD describe "board_list — size contract" at the standard triple
│       ├── screens/
│       │   └── board_list_test.exs        # REPLACE [subscribed]/[required]/[unsubscribed] assertions
│       └── widgets/
│           └── list/
│               └── board_tree_test.exs    # NEW
```

### Pattern 1: BoardTree as Stateful Facade

**What:** A new widget that mirrors `Display.Tree`'s public shape (`init/1`/`handle_event/2`/`render/2`) and internally owns a `Display.Tree` struct for cursor/expanded state. It walks `Raxol.UI.Components.Display.Tree.visible_nodes/1` and dispatches each node through one of two branches: an inline category renderer or `RichRow.render/1` for board rows.

**When to use:** Phase 21 specifically. The pattern generalizes — Phase 25's Sysop boards screen could adopt the same shape — but keep `BoardTree`'s atom vocabulary tight (`:category`/`:board` data discriminator only; do not anticipate Sysop-specific shapes).

**Why this pattern:**
- Mirrors the existing `Foglet.TUI.Widgets.Display.Tree` facade, so screen-side migration in `BoardList` is a small alias swap (per CONTEXT D-01).
- `Display.Tree` already provides everything needed for cursor/expanded behavior; reusing it via composition (not inheritance) keeps a clean boundary.
- Render-purity is preserved: `BoardTree.render/2` reads only from already-loaded state (the directory list at `init/1` time and the held `Display.Tree`'s cursor/expanded set).
- `BoardList.handle_key/2` keeps its current surface — only the alias of which struct it forwards to changes.

**Example (sketched skeleton, illustrative not prescriptive):**
```elixir
# Source: this research, grounding from
#   lib/foglet_bbs/tui/widgets/display/tree.ex
#   .planning/phases/20-rich-rows-and-thread-flow/20-04-PLAN.md
defmodule Foglet.TUI.Widgets.List.BoardTree do
  @moduledoc """
  Themed board-directory tree (BOARDS-01..04). Stateful facade.

  Owns a `Foglet.TUI.Widgets.Display.Tree` for cursor/expanded state and
  routes board rows through `Foglet.TUI.Widgets.List.RichRow` per
  21-CONTEXT.md D-01/D-02/D-04.

  Honours D-07/D-09 (theme slots) and D-13/D-14 (init/handle_event/render).
  """

  import Raxol.Core.Renderer.View

  alias Foglet.TimeAgo
  alias Foglet.TUI.TextWidth
  alias Foglet.TUI.Theme
  alias Foglet.TUI.Widgets.Display.Tree
  alias Foglet.TUI.Widgets.List.RichRow
  alias Raxol.UI.Components.Display.Tree, as: RaxolTree

  @category_glyph_expanded "▾"
  @category_glyph_collapsed "▸"
  @glyph_required "⚿"          # U+26BF — see Pitfall 1 (Ambiguous EAW)
  @glyph_subscribed "✓"
  @glyph_available "+"
  @glyph_no_age "—"             # U+2014

  defstruct [:tree, :directory, last_action: nil]

  @type t :: %__MODULE__{
          tree: Tree.t(),
          directory: [Foglet.Boards.directory_category()],
          last_action: Tree.action() | nil
        }

  @spec init(keyword()) :: t()
  def init(opts) do
    directory = Keyword.fetch!(opts, :directory)
    id = Keyword.get(opts, :id, "board-tree-#{:erlang.unique_integer([:positive])}")
    nodes = directory_to_nodes(directory)
    tree = Tree.init(id: id, nodes: nodes)
    expanded = nodes |> Enum.map(& &1.id) |> MapSet.new()
    tree = put_in(tree.raxol_state.expanded, expanded)
    %__MODULE__{tree: tree, directory: directory}
  end

  @spec handle_event(map(), t()) :: {t(), Tree.action()}
  def handle_event(event, %__MODULE__{tree: t} = st) do
    {new_t, action} = Tree.handle_event(event, t)
    {%{st | tree: new_t, last_action: action}, action}
  end

  @spec render(t(), keyword()) :: any()
  def render(%__MODULE__{tree: %Tree{raxol_state: rs}}, opts) do
    %Theme{} = theme = Keyword.fetch!(opts, :theme)
    width = Keyword.get(opts, :width, 80)
    cursor = Map.get(rs, :cursor)
    expanded = Map.get(rs, :expanded, MapSet.new())
    visible = RaxolTree.visible_nodes(rs)

    rows =
      Enum.map(visible, fn {node, depth} ->
        case Map.get(node, :data) do
          %{kind: :category, category: cat} ->
            render_category(cat, depth, expanded, node.id == cursor, theme)

          %{kind: :board} = data ->
            render_board(data, depth, node.id == cursor, theme, width)
        end
      end)

    column style: %{gap: 0} do
      rows
    end
  end

  # ---- private ----

  defp render_category(cat, depth, expanded, selected?, theme) do
    indent = TextWidth.pad_trailing("", depth * 2)
    glyph =
      if MapSet.member?(expanded, {:category, cat.id}),
        do: @category_glyph_expanded,
        else: @category_glyph_collapsed
    label = "#{indent}#{glyph} #{cat.name}"

    if selected? do
      text(label, fg: theme.selected.fg, bg: theme.selected.bg, style: [:bold])
    else
      text(label, fg: theme.primary.fg, style: [:bold])
    end
  end

  defp render_board(data, depth, selected?, theme, width) do
    indent = depth * 2  # absorbed into title prefix below; RichRow has its own marker

    %{board: board,
      subscribed?: subscribed?,
      required_subscription?: required?,
      unread_count: unread,
      last_post_at: last_post_at} = data

    state_cluster = if is_integer(unread) and unread >= 1, do: [:unread], else: []

    sub_glyph =
      cond do
        required? -> @glyph_required
        subscribed? -> @glyph_subscribed
        true -> @glyph_available
      end

    title_prefix = TextWidth.pad_trailing("", indent) <> sub_glyph <> " "
    title = title_prefix <> board.name

    metadata = compose_metadata(unread, last_post_at)

    RichRow.render(
      title: title,
      metadata: metadata,
      state_cluster: state_cluster,
      selected: selected?,
      theme: theme,
      width: width,
      emphasis: if(state_cluster == [:unread], do: :bold, else: nil)
    )
  end

  defp compose_metadata(nil, last_post_at),
    do: format_age(last_post_at)

  defp compose_metadata(0, last_post_at),
    do: "all read  " <> format_age(last_post_at)

  defp compose_metadata(n, last_post_at) when is_integer(n) and n >= 1,
    do: "#{n} unread  " <> format_age(last_post_at)

  defp format_age(nil), do: @glyph_no_age
  defp format_age(%DateTime{} = dt), do: TimeAgo.format(dt)

  defp directory_to_nodes(directory) do
    Enum.map(directory, fn %{category: cat, boards: boards} ->
      %{
        id: {:category, cat.id},
        label: cat.name,
        children:
          Enum.map(boards, fn b ->
            %{
              id: {:board, b.board.id},
              label: b.board.name,
              children: [],
              data: Map.put(b, :kind, :board)
            }
          end),
        data: %{kind: :category, category: cat}
      }
    end)
  end
end
```

### Pattern 2: Aggregate `last_post_at` via single LEFT JOIN

**What:** Add `:last_post_at` to `directory_board` in `Foglet.Boards.board_directory_for/1`. Source the value from a single `Repo.all` query that LEFT-JOINs `Foglet.Threads.Thread` against `Foglet.Boards.Board`, filters non-deleted threads, groups by `board.id`, and returns max `t.last_post_at`. Materialize as a `%{board_id => DateTime.t() | nil}` map. Merge alongside `subscribed_board_ids/1` and `unread_counts/1` results when assembling each `directory_board` entry.

**When to use:** Specifically for Phase 21 (the only consumer). Domain-context-owned data shaping per AGENTS.md.

**Example (illustrative):**
```elixir
# Source: this research, grounding from lib/foglet_bbs/boards.ex:511-526 (unread_counts/1 precedent)
@spec last_post_ats() :: %{String.t() => DateTime.t() | nil}
defp last_post_ats do
  Repo.all(
    from b in Board,
      left_join: t in Foglet.Threads.Thread,
      on: t.board_id == b.id and is_nil(t.deleted_at),
      group_by: b.id,
      select: {b.id, max(t.last_post_at)}
  )
  |> Map.new()
end
```

**Notes:**
- The LEFT JOIN ensures every board id appears, even ones with zero non-deleted threads (max → `nil`).
- The result is actor-independent per CONTEXT D-09 + SPEC line 140 (boards are public-readable).
- If the planner consolidates with `unread_counts/1` into a single multi-aggregate query, the JOIN root must remain `Board` (not `Subscription`) so unsubscribed boards appear.

### Pattern 3: Composite metadata column (right-aligned, fixed-format)

**What:** The trailing metadata column is a single right-aligned string that bakes both the unread count and the age into one field, separated by two spaces. RichRow's right-alignment contract handles the gap between title and metadata.

**Composition table (D-04):**

| `unread_count` | `last_post_at` | metadata string |
|---|---|---|
| `nil` | `nil` | `"—"` |
| `nil` | `~U[…]` | `"12m"` |
| `0` | `nil` | `"all read  —"` |
| `0` | `~U[…]` | `"all read  12m"` |
| `>= 1` | `nil` | `"3 unread  —"` |
| `>= 1` | `~U[…]` | `"3 unread  12m"` |

**Maximum width pre-truncation (D-05):**
- `99 unread  ` = 11 cells + age. With age max `"99mo"` or `"99y"` (4 cells), the metadata never exceeds **15 cells**. CONTEXT D-05 assumes 14 — slight over-budget but still inside the 60-cell body with 36 cells for the name (down from 36 to 35 in the worst case, still well above the 20-cell minimum).

### Anti-Patterns to Avoid

- **Don't try to pass the subscription glyph as a `RichRow :state_cluster` atom.** The cluster width is fixed at 4 cells with three reserved slots; mixing reserved (`:unread`) and ad-hoc (`:available`) atoms breaks Phase 20's property invariant. Use the title prefix per CONTEXT D-02.
- **Don't pre-truncate the title in `BoardTree`.** RichRow does width math itself; pre-truncating would either double-truncate or break the 20-cell minimum logic. Compose the full prefixed title and pass through.
- **Don't call `TimeAgo.format/1` with `nil`.** It returns `"?"`, not the em-dash CONTEXT D-06 specifies. Branch on `nil` first.
- **Don't add side effects to `BoardTree.render/2`.** No DB queries, no PubSub, no logging. Render is pure over already-loaded state.
- **Don't hardcode color atoms.** Every `fg`/`bg` must come from a `theme.<slot>.fg|bg` lookup. Tests assert this via `color_atom_leaked?/2` regex.
- **Don't assert on `inspect(tree) =~ "..."` for style.** Use `assert_text_run/3` from `WidgetHelpers` for style-property assertions; use `flatten_text/1` + `=~` for content presence.
- **Don't merge `last_post_ats/0` into `unread_counts/1` blindly.** `unread_counts/1` joins from `Subscription` and only returns subscribed boards. Copying that pattern for `last_post_ats` would silently miss unsubscribed boards.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Cursor / expand-collapse / Up/Down/Left/Right key dispatch | A custom navigation handler | `Foglet.TUI.Widgets.Display.Tree` (held inside `BoardTree`) → `Raxol.UI.Components.Display.Tree.handle_event/3` | Already handles up/down/left/right/enter/space/home/end with leaf-vs-parent semantics. Reimplementing `next_in_list` / `prev_in_list` for visible nodes is non-trivial and error-prone. |
| Visible-node walk (skipping collapsed children) | A recursive walker | `Raxol.UI.Components.Display.Tree.visible_nodes/1` | Returns `[{node, depth}, …]` already filtered by the expanded set. |
| Multi-column row layout (cluster + title + right-aligned metadata) | A custom `text/2` + padding implementation | `Foglet.TUI.Widgets.List.RichRow.render/1` (Phase 20) | Cluster width invariant, focus-marker treatment, title truncation, right-alignment, theme routing all already designed. |
| Display-width measurement (cells, not bytes/graphemes) | `String.length/1` or `byte_size/1` | `Foglet.TUI.TextWidth.display_width/1` (delegates to `Raxol.UI.TextMeasure`) | Cells, CJK width, combining marks. Project conventions explicitly forbid `String.length` for layout. |
| Right-truncation with ellipsis | Custom `String.slice` + concat | `Foglet.TUI.TextWidth.truncate/2,3` | Handles edge cases (text shorter than max, ellipsis wider than max, sub-grapheme boundaries). RichRow already wires this in. |
| Right-padding to a fixed width | Custom space-concat | `Foglet.TUI.TextWidth.pad_trailing/2` | Same edge-case handling. |
| Relative-time formatting (seconds/minutes/hours/days/weeks) | Custom helper | `Foglet.TimeAgo.format/1` | Already returns the exact magnitudes Phase 21 wants. **Caveat: branch on `nil` BEFORE calling.** |
| Subscription feedback flash above the tree | A new flash mechanism | `Foglet.TUI.Screens.BoardList.maybe_feedback/2` (existing) | Already in use; preserved verbatim per CONTEXT D-10. |
| Aggregate query to find "max thread last_post_at per board" | Per-board `Repo.aggregate` calls | A single `Repo.all` LEFT JOIN with `group_by` | Per-board calls would introduce N+1 (forbidden by SPEC line 91). The codebase already canonicalizes the aggregate pattern at `boards.ex:511-526` for `unread_counts/1`. |
| Theme-routed text rendering | Hardcoded `:red`/`:green`/`:cyan` atoms | `text(content, fg: theme.<slot>.fg, bg: theme.<slot>.bg, style: theme.<slot>.style)` | Universal Foglet convention; tests audit for atom leaks. |

**Key insight:** Phase 21 is almost entirely a composition phase. Every primitive it needs already exists in the codebase or in Phase 20's about-to-ship `RichRow`. The core risk isn't writing custom primitives — it's correctly orchestrating the existing ones.

## Common Pitfalls

### Pitfall 1: U+26BF `⚿` Ambiguous-Width Drift Between Test and Real Terminals

**What goes wrong:** `⚿` (SQUARED KEY, U+26BF) has Unicode East_Asian_Width property "Ambiguous." On East-Asian-locale terminals (CJK fonts, ambiguous=wide), it renders as 2 cells. On Western terminals, it renders as 1 cell. Raxol's width measurement (`CharacterHandling.wide_char?/1`) treats it as 1 cell — verified against the wide_ranges table at `deps/raxol_terminal/lib/raxol/terminal/character_handling.ex:18-51`. Tests pass on the developer machine; users with ambiguous=wide terminals see misaligned rows.

**Why it happens:** Raxol's wide table covers CJK ranges, fullwidth forms, and Misc Symbols/Pictographs (`0x1F300..0x1FAFF`) — but NOT the Misc Symbols block (`0x2600..0x26FF`) where `⚿` lives. The `◆` (U+25C6), `◇` (U+25C7), `▾` (U+25BE), `▸` (U+25B8) glyphs Phase 21 uses are also outside Raxol's wide table.

**How to avoid:**
1. Use `Foglet.TUI.TextWidth.display_width("⚿") == 1` as the layout-truth source. Tests assert against this measurement.
2. Reserve a fixed prefix width: `subscription_glyph` + ` ` = always 2 cells.
3. Document the terminal-rendering caveat in `BoardTree`'s `@moduledoc` (it's a known property of Ambiguous-EAW characters, not a bug).
4. CONTEXT D-04 / Specifics already grants the planner authority to substitute a different 1-cell BMP glyph if visual testing reveals issues. Candidates: `*` (U+002A asterisk — too generic), `※` (U+203B reference mark — has its own ambiguity), or staying with `⚿` and accepting the caveat for the 2026 ship.
5. When substituting, flag the substitution in the plan output for review.

**Warning signs:** Layout-smoke tests pass at `{64,22}` on dev but a real user reports "subscription column overlaps name." Trace the user's `LANG`/`LC_CTYPE` for an East-Asian locale.

`[VERIFIED: deps/raxol_terminal/lib/raxol/terminal/character_handling.ex:18-51]`
`[CITED: codepoints.net/U+26BF — East_Asian_Width: Ambiguous]`

### Pitfall 2: Width Math at 64x22 — The Margin Is Real, Not Marginal

**What goes wrong:** Implementer assumes the row is 64 cells wide. ScreenFrame applies border (1 cell each side) + padding (1 cell each side) = 4 cells overhead. Available body is 60 cells. Phase 21's fixed segments consume:

```
indent (4) + cluster (4 = Phase 20 @cluster_width) + sub-glyph prefix in title (2)
  + min gap (2) + max metadata (15: "99 unread  99mo")
= 27 cells fixed
```

Wait — CONTEXT D-05 says 22 cells fixed. The discrepancy: D-05 assumes the indent (4 cells for boards under a category) is part of `RichRow`'s focus-marker math, not added by `BoardTree`. **Verify which side owns the indent before plan finalization.** RichRow's focus marker is fixed at 2 cells (`"▌ "` or `"  "`). The cluster is 4 cells fixed. If `BoardTree` adds 2 more cells of indent for boards-under-categories on top of RichRow's marker, total left-side overhead becomes `2 (marker) + 2 (indent) + 4 (cluster) + 2 (sub-glyph prefix) = 10` left + `2 (gap) + 15 (metadata) = 17` right = 27 fixed; **name budget at 64x22 = 60 − 27 = 33 cells.** Still well above the 20-cell Phase 20 minimum. CONTEXT D-05's number (36) is roughly correct but slightly optimistic; document the actual computed budget in plan tasks.

**Why it happens:** Confusion over which layer owns the indent. Phase 20's RichRow is screen-agnostic and assumes the caller has already done any indent. Phase 21 specifically wants 2-or-4-cell indent under a category — a `BoardTree` concern.

**How to avoid:**
1. Decide explicitly: indent lives in the title prefix (composed by `BoardTree`), not in a separate `:indent` keyword on `RichRow`.
2. Use `TextWidth.pad_trailing("", depth * 2)` to build the indent.
3. The full title becomes: `"  ⚿ announcements"` (2 cells indent + 2 cells sub-glyph prefix + name).
4. Add a `layout_smoke` assertion that measures total row width ≤ 64 cells AND that name length ≥ 20 cells when the input name is shorter than the budget.

**Warning signs:** Layout-smoke tests fail with "row.x reaches column 64" or RichRow's truncation kicks in for short names because the budget was misallocated.

### Pitfall 3: `TimeAgo.format(nil) == "?"` (NOT em-dash)

**What goes wrong:** Implementer writes `format_age(last_post_at) = TimeAgo.format(last_post_at)` and ships. CONTEXT D-06 demands `—` (U+2014 EM DASH) for nil. `TimeAgo.format(nil)` returns the literal string `"?"` — verified at `lib/foglet_bbs/time_ago.ex:28`. The test for "nil last_post_at renders em-dash" fails.

**Why it happens:** TimeAgo was designed to be defensive and never crash. Its nil branch was a fallback for `PostCard`'s case where `:inserted_at` may be missing on a malformed map; it was not designed to communicate a meaningful "no posts" state.

**How to avoid:**
1. Branch on `nil` in `BoardTree` BEFORE calling `TimeAgo.format/1`:

   ```elixir
   defp format_age(nil), do: "—"   # U+2014
   defp format_age(%DateTime{} = dt), do: TimeAgo.format(dt)
   ```

2. Add a test in `board_tree_test.exs` that asserts `format_age(nil) == "—"` and `flatten_text(...) =~ "—"` for an entry with `last_post_at: nil`.
3. Do NOT extend `TimeAgo.format/1` to return em-dash — it has multiple consumers (`PostCard`) that may rely on `"?"`.

**Warning signs:** Test output `"expected '—', got '?'"` in board_tree_test.exs's nil-age branch.

`[VERIFIED: lib/foglet_bbs/time_ago.ex:28]`

### Pitfall 4: `unread_counts/1` Joins Subscription, Not Board

**What goes wrong:** Implementer reads CONTEXT D-09's "structurally identical to `Foglet.Boards.unread_counts/1` precedent" and writes a `last_post_ats/1` that joins from `Subscription`. Result: unsubscribed boards never appear in the result map; their `last_post_at` is `nil` even when the board has posts. Tests at `board_directory_for/1` covering "subscribed and unsubscribed actors see the same last_post_at" fail.

**Why it happens:** `unread_counts/1` is keyed on `Subscription` because unread state is intrinsically per-user-per-board. `last_post_at` is a board-level attribute (actor-independent per CONTEXT D-09 + SPEC line 140). The two queries have similar shapes (LEFT JOIN, group_by, aggregate) but different roots.

**How to avoid:**
1. Root the new aggregate from `Foglet.Boards.Board` (or `Foglet.Threads.Thread` — same result, just a different scan plan).
2. The aggregate takes no `user_id` parameter — it's `last_post_ats/0`, not `last_post_ats/1`.
3. Test cases must explicitly cover an unsubscribed actor seeing a non-nil `:last_post_at` for a board with posts.

**Example (correct shape):**
```elixir
# Source: this research, plus the LEFT-JOIN-from-Board correction.
defp last_post_ats do
  Repo.all(
    from b in Board,
      left_join: t in Foglet.Threads.Thread,
      on: t.board_id == b.id and is_nil(t.deleted_at),
      group_by: b.id,
      select: {b.id, max(t.last_post_at)}
  )
  |> Map.new()
end
```

**Warning signs:** Test "value identical for subscribed and unsubscribed actors on the same board" fails with subscribed → datetime, unsubscribed → nil.

`[VERIFIED: lib/foglet_bbs/boards.ex:511-526 — unread_counts/1 joins Subscription]`

### Pitfall 5: BoardList.State.tree Field Shape Drift

**What goes wrong:** `BoardList.State` currently holds `tree: Tree.t() | nil` where `Tree` aliases `Foglet.TUI.Widgets.Display.Tree`. CONTEXT D-01 says "BoardTree internally **owns** a `Display.Tree` struct." If `State.tree` is repurposed to hold a `BoardTree.t()`, the alias must change AND the test fixture in `layout_smoke_test.exs:556-614` (which builds `screen_state: %{board_list: %{selected_index: 0}}` — a bare map, not a `%State{}`) breaks because `BoardList.render/1` constructs the tree on-demand from `state.board_list` when `screen_state.board_list` doesn't have a `%State{}` struct.

**Why it happens:** Inconsistent state shape between code paths (production path uses `%State{}`, smoke-test path uses bare map). `BoardList.screen_state/1` falls back to `init_screen_state()` when the map shape isn't `%State{}` — but the fixture's bare map causes the tree to be rebuilt on every render call, which is intentional but means smoke tests don't exercise the held tree's cursor/expand state.

**How to avoid:**
1. Rename `State.tree` → `State.board_tree` per CONTEXT canonical_refs (`board_list.ex:252-256`'s feedback path is preserved; tree-state field can move).
2. Update the `Foglet.TUI.Widgets.Display.Tree` alias to `Foglet.TUI.Widgets.List.BoardTree` in `state.ex`.
3. Update the smoke-test fixture path: either pass a `%State{}` struct OR keep the bare-map fallback path working by ensuring `BoardList.render_board_content/3`'s `tree = ss.board_tree || build_tree(state.board_list)` works for both shapes.
4. Add a test asserting the fixture path: a fresh state (no `%State{}` in `screen_state`) renders correctly.

**Warning signs:** Existing test at `layout_smoke_test.exs:556` ("board_list renders board rows at distinct y positions") fails after the rename because the ad-hoc fixture map didn't get updated.

### Pitfall 6: SCREENS.md Mock Includes the Details Strip

**What goes wrong:** Implementer reads `SCREENS.md` lines 309-350 (which mocks the details strip) and uses it as the visual target. CONTEXT D-08 explicitly removes the strip. Result: extra row composed below the tree, wasted vertical space, no test coverage for it (the assertions were removed).

**Why it happens:** Multiple sources of truth. The locked CONTEXT.md is canonical; the SCREENS.md mock predates the CONTEXT-level override.

**How to avoid:**
1. Treat `21-CONTEXT.md` as canonical for Phase 21 visual scope. SCREENS.md is illustrative only when it agrees with CONTEXT.
2. Ensure `BoardList.render_board_content/3` does NOT add a strip below the tree.
3. Acceptance criteria check: render `BoardList` at 64x22 and assert no row contains `"•"` (the SCREENS.md separator) on a non-feedback line.

**Warning signs:** Plan task action says "render details strip below tree" — should never appear.

### Pitfall 7: `RichRow` Doesn't Exist Yet

**What goes wrong:** Plan tasks refer to `RichRow.render/1` but `lib/foglet_bbs/tui/widgets/list/rich_row.ex` is not yet committed at the time Phase 21 starts. Plans treat it as a hard dependency.

**Why it happens:** Phase 20 is "in flight on a parallel track" per SPEC line 17. The roadmap shows Phase 21 as dependent on Phase 20. STATE.md confirms Phase 20 is currently executing.

**How to avoid:**
1. **Phase 21 plan execution must wait until Phase 20 ships RichRow.** Verify `lib/foglet_bbs/tui/widgets/list/rich_row.ex` exists and `Foglet.TUI.Widgets.List.RichRow.render/1` is callable before Wave 1 of Phase 21 begins.
2. Per CONTEXT D-03, the planner re-validates D-02's title-prefix approach against the actual RichRow signature once it lands. If RichRow's title-truncation behavior diverges from "right-truncate with `…`", D-02 must be re-examined.
3. Phase 21 tasks against the locked Phase 20 contract from `20-CONTEXT.md` D-01/D-02 + the module skeleton in `20-04-PLAN.md` lines 245-538 — both referenced verbatim in this RESEARCH.

**Warning signs:** Phase 21 Wave 1 fails with `(UndefinedFunctionError) Foglet.TUI.Widgets.List.RichRow.render/1 is undefined` — Phase 20 hasn't shipped yet.

`[VERIFIED: ls of lib/foglet_bbs/tui/widgets/list/ — only list_row.ex, selection_list.ex, smart_list.ex present]`
`[VERIFIED: STATE.md status: "Phase 20 — rich-rows-and-thread-flow" executing]`

### Pitfall 8: Bracketed-Text Test Assertions Must Be Replaced AND Their Negations Added

**What goes wrong:** Implementer updates `board_list_test.exs:87-89` to assert glyphs (`⚿`, `✓`, `+`) but leaves the existing bracketed-text assertions (`"[required]"`, `"[subscribed]"`, `"[unsubscribed]"`) lurking elsewhere. Tests pass because both assertions can't be true simultaneously — but the brackets DO appear if a regression brings them back, and the test that should catch the regression is gone.

**Why it happens:** The CONTEXT D-11 instruction is "replace existing literal-string assertions … with glyph-only assertions" but doesn't make explicit that NEGATIVE assertions (`refute text =~ "[required]"`) must be added.

**How to avoid:**
1. Per CONTEXT D-11 explicitly: "Add an explicit absence assertion: no row contains the literal substrings `"required"`, `"subscribed"`, or `"subscribe"` as words (other than within the board's own name)."
2. Use `refute flatten_text(tree) =~ "[required]"` etc. for each affected line.
3. Preserve the required-subscription feedback test at `board_list_test.exs:154` — feedback strings still contain the word `"required"`, but they appear in the flash line above the tree, NOT in row text.
4. Distinguish row text from flash text in assertions (the flash has the leading flash class; the rows do not).

**Warning signs:** Refactor lands, glyph tests pass, then a future regression slips bracketed-text back into row labels and no test catches it.

## Code Examples

Verified patterns from official sources / project codebase:

### Walking Visible Tree Nodes (Raxol-Owned)

```elixir
# Source: lib/foglet_bbs/tui/widgets/display/tree.ex:88-111
@spec render(t(), keyword()) :: any()
def render(%__MODULE__{raxol_state: rs}, opts) do
  %Theme{} = theme = Keyword.fetch!(opts, :theme)
  indent = Map.get(rs, :indent_size, @default_indent_size)
  cursor = Map.get(rs, :cursor)
  visible = RaxolTree.visible_nodes(rs)

  rows =
    Enum.map(visible, fn {node, depth} ->
      indent_str = String.duplicate(" ", depth * indent)
      icon = node_icon(node, rs)
      label = "#{indent_str}#{icon} #{node.label}"
      # ... themed text/2 emit
    end)

  column style: %{gap: 0} do
    rows
  end
end
```

This is the precise pattern `BoardTree.render/2` mirrors. The only difference: `BoardTree` discriminates `node.data.kind` to dispatch to either `text/2` (categories) or `RichRow.render/1` (boards).

### Calling RichRow with State-Cluster + Metadata

```elixir
# Source: .planning/phases/20-rich-rows-and-thread-flow/20-04-PLAN.md (RichRow public contract)
RichRow.render(
  title: "⚿ announcements",       # subscription-glyph prefix + name (D-02)
  metadata: "3 unread  12m",       # composite right-aligned (D-04)
  state_cluster: [:unread],        # read-state only (D-02)
  selected: cursor_on_this_row?,
  theme: theme,
  width: width,                     # passed through from BoardTree.render/2 opts
  emphasis: :bold                   # bold the title for unread rows
)
```

### Themed Category Row (Inline `text/2`)

```elixir
# Source: this research, mirroring lib/foglet_bbs/tui/widgets/display/tree.ex pattern
defp render_category(cat, depth, expanded, selected?, theme) do
  indent = TextWidth.pad_trailing("", depth * 2)
  glyph =
    if MapSet.member?(expanded, {:category, cat.id}),
      do: "▾",
      else: "▸"
  label = "#{indent}#{glyph} #{cat.name}"

  if selected? do
    text(label, fg: theme.selected.fg, bg: theme.selected.bg, style: [:bold])
  else
    text(label, fg: theme.primary.fg, style: [:bold])
  end
end
```

### Aggregate Query (LEFT JOIN, no N+1)

```elixir
# Source: this research, structural reference lib/foglet_bbs/boards.ex:511-526
defp last_post_ats do
  Repo.all(
    from b in Board,
      left_join: t in Foglet.Threads.Thread,
      on: t.board_id == b.id and is_nil(t.deleted_at),
      group_by: b.id,
      select: {b.id, max(t.last_post_at)}
  )
  |> Map.new()
end
```

### Test: Glyph Presence in Rendered Row

```elixir
# Source: this research, conventions from test/foglet_bbs/tui/widgets/list/list_row_test.exs
test "required board row title prefix contains ⚿", %{theme: theme} do
  state =
    BoardTree.init(
      directory: [
        %{
          category: %{id: "c1", name: "Public"},
          boards: [
            %{
              board: %{id: "b1", name: "announcements"},
              subscribed?: true,
              required_subscription?: true,
              unread_count: 3,
              last_post_at: DateTime.add(DateTime.utc_now(), -720, :second)
            }
          ]
        }
      ],
      id: "board-tree-test"
    )

  text = BoardTree.render(state, theme: theme, width: 60) |> flatten_text()

  assert text =~ "⚿ announcements"
  assert text =~ "◆"             # unread cluster glyph (Phase 20 D-05)
  assert text =~ "3 unread"
  assert text =~ "12m"           # TimeAgo short form
  refute text =~ "[required]"    # bracketed text removed (CONTEXT D-11)
  refute text =~ "[subscribed]"
end
```

### Test: Theme-Routing Hygiene (No Color Atom Leaks)

```elixir
# Source: test/foglet_bbs/tui/widgets/list/smart_list_test.exs pattern
test "no hardcoded color atoms leak", %{theme: theme} do
  tree = BoardTree.render(state, theme: theme, width: 80)
  serialized = inspect(tree, limit: :infinity)

  for color <- color_names() do
    refute color_atom_leaked?(serialized, color),
           "found hardcoded :#{color} atom in BoardTree render"
  end
end
```

### Test: 64-Cell Width Contract

```elixir
# Source: this research, Phase 20 plan-04 acceptance precedent
test "at 64-cell width with long name, name truncates and all four trailing segments render in full" do
  long_name = String.duplicate("a", 80)
  state = BoardTree.init(directory: [
    %{
      category: %{id: "c1", name: "Cat"},
      boards: [%{
        board: %{id: "b1", name: long_name},
        subscribed?: true,
        required_subscription?: true,
        unread_count: 5,
        last_post_at: DateTime.add(DateTime.utc_now(), -3600, :second)
      }]
    }
  ])

  text = BoardTree.render(state, theme: Theme.default(), width: 60) |> flatten_text()

  assert text =~ "⚿"           # subscription glyph fully rendered
  assert text =~ "◆"            # cluster glyph fully rendered
  assert text =~ "5 unread"     # unread fully rendered
  assert text =~ "1h"           # age fully rendered (~3600 sec ago)
  assert text =~ "…"            # name truncated
  # Total row width assertion (over the row line, not the whole tree):
  # extract via text_runs/1 or similar
end
```

## Runtime State Inventory

This phase has no rename/refactor/migration character. New module + new directory_board field + alias swap. **No external runtime state to update.**

| Category | Items Found | Action Required |
|----------|-------------|-----------------|
| Stored data | None — verified by grep for `:tree`/`board_directory` in `.planning/`. The directory shape extension (`:last_post_at`) is additive; existing serialized state (none — this is in-process state only) is unaffected. | None. |
| Live service config | None — verified by absence of n8n / Datadog / Tailscale config in this repository. | None. |
| OS-registered state | None — Foglet is not registered with OS task schedulers; the SSH daemon runs inside the Elixir release. | None. |
| Secrets / env vars | None — Phase 21 introduces no new env vars or secrets. The `:last_post_at` field reads from the existing `Foglet.Threads.Thread` schema. | None. |
| Build artifacts / installed packages | None — vendored Raxol at `vendor/raxol` is unchanged. No `mix.exs` deps change. | None. |

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|-------------|-----------|---------|----------|
| Elixir | Phase 21 module | ✓ | `~> 1.17 or ~> 1.18 or ~> 1.19` per `vendor/raxol/mix.exs:11` | — |
| `raxol` (vendored) | `Display.Tree`, `Renderer.View` DSL, `TextMeasure` | ✓ | 2.4.0 | — |
| `raxol_terminal` (deps) | `CharacterHandling.wide_char?/1` | ✓ | bundled with raxol_core | — |
| Postgres | `Foglet.Boards.board_directory_for/1` aggregate query | ✓ (assumed available in test env via `FogletBbs.DataCase`) | matches `Foglet.Repo` config | — |

**Missing dependencies:** None. This is an internal-module phase — no new external dependencies.

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | ExUnit (Elixir built-in) |
| Config file | `test/test_helper.exs` (existing) |
| Quick run command | `rtk mix test test/foglet_bbs/tui/widgets/list/board_tree_test.exs` |
| Full suite command | `rtk mix test` |
| Pre-commit | `rtk mix precommit` (compile -W as errors, format, Credo, Sobelow, Dialyzer) |

### Phase Requirements → Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|--------------|
| BOARDS-01 | Category `▾`/`▸` glyphs and read-state `◆`/`◇` cluster glyphs render correctly | unit | `rtk mix test test/foglet_bbs/tui/widgets/list/board_tree_test.exs --only describe:"category glyphs"` | ❌ (Wave 0 / D-11) |
| BOARDS-01 | Subscription glyphs `⚿`/`✓`/`+` render in title prefix per state | unit | `rtk mix test test/foglet_bbs/tui/widgets/list/board_tree_test.exs --only describe:"subscription glyphs"` | ❌ (Wave 0 / D-11) |
| BOARDS-01 | Bracketed-text strings absent from rendered rows | unit (refute) | `rtk mix test test/foglet_bbs/tui/screens/board_list_test.exs:80` (extended) | ✓ (extends existing) |
| BOARDS-02 | Per-row age column renders `TimeAgo.format/1` short form OR em-dash on nil | unit | `rtk mix test test/foglet_bbs/tui/widgets/list/board_tree_test.exs --only describe:"age column"` | ❌ (Wave 0 / D-11) |
| BOARDS-02 | Width-contract: at 64-cell content, all four trailing segments render fully; only name truncates | size-contract | `rtk mix test test/foglet_bbs/tui/layout_smoke_test.exs --only describe:"board_list — size contract"` | ❌ (Wave 0 / D-11; layout_smoke_test exists) |
| BOARDS-03 | All keys (j/k/↑/↓/←/→/Enter/s/u/q/Q) preserved | integration | `rtk mix test test/foglet_bbs/tui/screens/board_list_test.exs` (existing tests) | ✓ |
| BOARDS-03 | `:load_threads` command emission on Enter for board node preserved | integration | `rtk mix test test/foglet_bbs/tui/screens/board_list_test.exs:104` | ✓ |
| BOARDS-03 | Required-subscription guard preserved (no unsubscribe command emitted) | integration | `rtk mix test test/foglet_bbs/tui/screens/board_list_test.exs:144` | ✓ |
| BOARDS-04 | `BoardList` source contains no direct `Foglet.TUI.Widgets.Display.Tree` reference in row render path | static (grep) | `rtk grep -F "Display.Tree" lib/foglet_bbs/tui/screens/board_list.ex` (expect 0 matches in `defp render_board_content`) | static check at acceptance time |
| BOARDS-04 | `Foglet.TUI.Widgets.List.BoardTree` module exists with public render entry point | unit | `Foglet.TUI.Widgets.List.BoardTree.__info__(:functions)` includes `:render` | ❌ (Wave 0) |
| Constraint | `:last_post_at` aggregate is single-pass (no N+1) | data-layer | `rtk mix test test/foglet_bbs/boards/boards_test.exs --only describe:"board_directory_for/1 (SUBS-01)"` (extended with `:last_post_at` cases + log-counting) | ✓ (extends existing) |
| Constraint | No hardcoded color atoms in `BoardTree` source | hygiene | Inside board_tree_test: `color_atom_leaked?/2` audit | ❌ (Wave 0) |
| Constraint | Subscription feedback flash preserved | integration | `rtk mix test test/foglet_bbs/tui/screens/board_list_test.exs:144` | ✓ |

### Sampling Rate

- **Per task commit:** `rtk mix test test/foglet_bbs/tui/widgets/list/board_tree_test.exs test/foglet_bbs/tui/screens/board_list_test.exs --max-failures 1`
- **Per wave merge:** `rtk mix test --include integration --max-failures 1` (full TUI + boards-context coverage)
- **Phase gate:** `rtk mix precommit && rtk mix test` — full suite green before `/gsd-verify-work`

### Wave 0 Gaps

- [ ] `test/foglet_bbs/tui/widgets/list/board_tree_test.exs` — covers BOARDS-01, BOARDS-02 (age column), BOARDS-04 (module exists), and theme-routing hygiene
- [ ] `test/foglet_bbs/tui/layout_smoke_test.exs` — ADD `describe "board_list — size contract"` block at `[{64,22},{80,24},{132,50}]` (file exists; describe block does not)
- [ ] `test/foglet_bbs/tui/screens/board_list_test.exs` — REPLACE bracketed-text assertions at lines 87-101, 155 with glyph + absence assertions; ADD age-column assertions; ADD read-state cluster glyph assertions
- [ ] `test/foglet_bbs/boards/boards_test.exs` — EXTEND `describe "board_directory_for/1 (SUBS-01)"` (line 464 onward) with `:last_post_at` cases (max of non-deleted threads, nil when no threads, identical for subscribed/unsubscribed actors)
- [ ] No framework install required — ExUnit is built-in; existing `FogletBbs.DataCase` and `Foglet.TUI.WidgetHelpers` cover support

## Security Domain

Per `.planning/config.json` `workflow.ai_integration_phase: true` (default), security is enabled. This phase is a TUI rendering refactor + an additive read-only field on a directory map. Security exposure is minimal but non-zero.

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|------------------|
| V2 Authentication | no | Phase 21 does not change auth flows. SSH session and `state.current_user` are inputs. |
| V3 Session Management | no | No session changes. |
| V4 Access Control | yes (advisory) | `board_directory_for/1` already filters via `actor` for subscription state. `:last_post_at` is actor-independent per CONTEXT D-09 + SPEC line 140 (boards are public-readable). Confirm this matches the project's `Foglet.Authorization` policy for board listing. |
| V5 Input Validation | no | Phase 21 has no user input new. Existing key handlers validate at the screen level; inputs to `BoardTree.handle_event/2` are constrained Raxol `:key` events. |
| V6 Cryptography | no | No crypto. |

### Known Threat Patterns for {Elixir + Phoenix + Raxol TUI}

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| SQL injection in `last_post_ats/0` LEFT JOIN | Tampering | Ecto query DSL (parameterized); never string-concat user input into queries. The aggregate has no user-supplied filter. |
| Information disclosure: `:last_post_at` reveals activity to unsubscribed users | Information Disclosure | Per CONTEXT D-09 + SPEC line 140, this is by design — boards are public-readable. The `last_post_at` value is no more sensitive than the board's existence. Confirmed against the project's "boards are public-readable" invariant. |
| Render-time DoS via giant directory | Denial of Service | `board_directory_for/1` returns all active boards in active categories — finite, bounded by category/board population. RichRow's truncation prevents single-row width blowups. |
| Theme-slot bypass via hardcoded color atom | Tampering (cross-user theme leakage) | All color atoms route through `theme.<slot>.fg/bg`; tests audit via `color_atom_leaked?/2`. |

**No new ASVS controls or threat-model changes** are introduced by Phase 21 beyond the existing project posture.

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Single embedded label string `"name [subscribed] (3 unread)"` rendered through `Display.Tree`'s built-in row composer | Multi-column row via `RichRow` (state cluster + title + metadata) with `BoardTree` orchestrating tree state | Phase 21 (this phase) | Semantic columns, glyph language, width-aware truncation, theme-routed styling. |
| Per-board `Repo.aggregate` for unread count | Single-pass `LEFT JOIN` + `group_by` aggregate at `boards.ex:511-526` | Earlier phase (predates Phase 21) | Pattern is now canonical; Phase 21 reuses for `:last_post_at`. |
| `> ` selection marker in row | `▌` (U+258C) selection marker | Phase 20 (sibling) | Cross-screen consistency with SelectionList, SmartList, Tabs, Modal. |
| `▼`/`▶` category-state glyphs (Display.Tree default) | `▾`/`▸` category-state glyphs (BoardTree-owned in Phase 21; matches SCREENS.md §Board Directory) | Phase 21 | Visual: lighter, less heavy than the default block triangles. |
| Details strip below tree (was the SCREENS.md plan) | Per-row age column (CONTEXT D-04 / D-08) | This CONTEXT (overrides SPEC) | Saves a screen line at 64x22; richer information density per row. |

**Deprecated/outdated within this phase:**

- The SCREENS.md mock at lines 309-350 includes a `Board details` strip — superseded by CONTEXT D-08.
- SPEC.md Requirement 4 (details strip) — superseded by CONTEXT `<spec_lock>` and `<acceptance_overrides>`.
- SPEC.md Requirement 2's `✓ required` / `✓ subscribed` / `+ subscribe` text labels — superseded by glyph-only mapping per CONTEXT D-02.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | RichRow's title-truncation behavior is right-truncate with `…` (per Phase 20 plan-04 implementation) — preserved in shipped RichRow. | Pattern 1 / D-02 (Title Prefix Approach) | If RichRow's truncation strategy changes (left-truncate, middle-truncate, no-ellipsis), the title-prefix approach for subscription glyphs breaks — the glyph could be eaten on long names. CONTEXT D-03 already flags this; planner re-validates against shipped RichRow before plan 21-01. `[ASSUMED based on 20-04-PLAN.md skeleton lines 476-493]` |
| A2 | Phase 20 ships `RichRow` before Phase 21 plan execution begins. | Pitfall 7 | Phase 21 Wave 1 fails if RichRow is undefined. STATE.md confirms Phase 20 is currently executing; absent confirmation that Phase 20 is complete, treat plan execution as gated on Phase 20 ship. `[ASSUMED based on STATE.md status + ROADMAP.md sequence]` |
| A3 | `Foglet.Boards.Board.id` is a string (UUID). | Pattern 2 / Pitfall 4 | Aggregate query result map keys are typed as `%{String.t() => ...}` per `unread_counts/1`'s spec at `boards.ex:510`. Confirmed for Subscription path; assumed for Board path. If `Board.id` is integer-typed, the spec annotations need adjustment (no behavioral change). `[ASSUMED based on unread_counts/1 spec at boards.ex:510 typing %{String.t() => count}]` |
| A4 | `Foglet.Threads.Thread.deleted_at` is the canonical soft-delete sentinel; `is_nil(t.deleted_at)` filter is sufficient. | Pattern 2 (last_post_ats query) | If a different soft-delete column or table-level partial index exists, the filter could miss rows. `[VERIFIED: lib/foglet_bbs/threads/thread.ex:9 — `field :deleted_at, :utc_datetime_usec`]` Verified, demoting from ASSUMED. |
| A5 | The `unread_count` field stays `nil` for unsubscribed boards (per existing `boards.ex:266` ternary), and `BoardTree` handles `nil` as "no unread column at all" while `:last_post_at` still renders. | Pattern 3 (composite metadata table) | If a future change makes `unread_count` always-an-integer, the metadata composition table's first row (`nil`/`nil` → `"—"`) becomes unreachable but still correct. Low impact. `[VERIFIED: lib/foglet_bbs/boards.ex:266]` Verified, demoting from ASSUMED. |
| A6 | Substituting a different 1-cell BMP glyph for `⚿` if rendering issues are found is acceptable scope per CONTEXT D-04 / Discretion (and "should flag the substitution in plan output for review"). | Pitfall 1 | If user interprets "lock-shaped" strictly as `⚿` only, substitution requires a re-discuss. CONTEXT D-04 / Discretion explicitly grants this authority — confirmed verbatim. `[CITED: 21-CONTEXT.md D-04 / Discretion final bullet]` Verified-by-citation, demoting from ASSUMED. |
| A7 | Rendering the em-dash `—` (U+2014) for nil `last_post_at` requires no theme slot beyond `theme.dim.fg` (planner discretion per CONTEXT D-10b final bullet) — and that this slot exists across all nine themes. | Pitfall 3 / D-06 | If a theme omits `:dim`, em-dash renders without color routing — minor visual issue, no crash (the slot lookup falls through gracefully in current code). `[VERIFIED: lib/foglet_bbs/tui/theme.ex:69-81 — :dim is in @slot_keys and every shipped theme defines it]` Verified, demoting from ASSUMED. |
| A8 | The 64-cell width math (CONTEXT D-05) does not double-count the 4-cell indent from the existing `Display.Tree` `indent_size: 2 * depth_1`. | Pitfall 2 | If indent is double-counted (once in BoardTree, once via RichRow's marker logic), name budget shrinks below 20-cell minimum on deep trees. The directory tree is at most depth 1 (categories → boards), so the indent is 2 cells, not 4 — re-validate the math in plan tasks. `[ASSUMED — needs explicit measurement during plan-task scaffolding]` |

**Net result:** Two genuine assumptions remain (A1, A2, A3, A8). A4–A7 are verified or cited. A1 (RichRow truncation) and A8 (indent double-count) are the highest-risk and should be re-validated against shipped Phase 20 code before Phase 21 plan execution.

## Open Questions

1. **Should the `last_post_at` aggregate be sibling to `unread_counts/1` or merged?**
   - What we know: CONTEXT D-09 Discretion explicitly allows either. Both satisfy the no-N+1 constraint.
   - What's unclear: Whether the planner prefers two clean queries (one Repo.all per concern) or one multi-aggregate query (one Repo round-trip).
   - Recommendation: Sibling private function `last_post_ats/0` (no `user_id` arg). Reads cleanly; matches the unread_counts pattern; one Repo round-trip per concern is acceptable for the directory's small cardinality.

2. **Whether to right-pad the metadata column to a fixed width or trim trailing whitespace.**
   - What we know: CONTEXT D-04/D-05 final bullet flags as planner discretion.
   - What's unclear: Whether visual tests at the size-contract triple show alignment drift between rows of different age magnitudes (`12m` vs `1mo`).
   - Recommendation: Fixed-width metadata column at 15 cells (`pad_leading` to 15 — the worst case `"99 unread  99mo"`). RichRow then right-aligns the padded string against the title gap.

3. **Whether `BoardList.State.tree` field should be renamed to `:board_tree` or keep `:tree` with new type.**
   - What we know: CONTEXT canonical_refs notes `State.tree` "may evolve to State.board_tree."
   - What's unclear: Whether the rename causes test-fixture rewrites in `layout_smoke_test.exs` and `board_list_test.exs` that the CONTEXT didn't anticipate.
   - Recommendation: Rename to `:board_tree`. The fields' types diverge enough (`Display.Tree.t()` vs `BoardTree.t()`) that name divergence is helpful for grep-ability, and the test fixtures already use bare maps via the `screen_state/1` fallback.

4. **At depth 1 (boards under a category), what is the actual indent in cells?**
   - What we know: `Display.Tree`'s default `indent_size = 2`. CONTEXT D-04 says "Indent — 4 cells for boards under a category."
   - What's unclear: Whether the 4 in CONTEXT was a typo for 2 (the default), or whether `BoardTree` should override `indent_size` to 4.
   - Recommendation: Use `indent_size: 2` (Display.Tree default) → boards under a category are indented 2 cells. This adjusts CONTEXT D-05's math: name budget at 64x22 becomes 60 − (2 indent + 4 cluster + 2 sub-glyph + 2 gap + 15 metadata) = **35 cells**, still well above the 20-cell floor. Document the indent choice explicitly in plan task acceptance.

## Sources

### Primary (HIGH confidence)

- **Foglet codebase (verified):**
  - `lib/foglet_bbs/tui/widgets/display/tree.ex` — Foglet's Display.Tree wrapper, current rendering path
  - `lib/foglet_bbs/tui/screens/board_list.ex` — BoardList screen, current implementation
  - `lib/foglet_bbs/tui/screens/board_list/state.ex` — State struct
  - `lib/foglet_bbs/tui/widgets/list/list_row.ex` — sibling list-row renderer (precedent for `compute_parts`)
  - `lib/foglet_bbs/tui/widgets/list/selection_list.ex` — `▌` canonical marker
  - `lib/foglet_bbs/tui/text_width.ex` — `display_width/1`, `truncate/3`, `pad_trailing/2`, `slice_to_width/2`
  - `lib/foglet_bbs/tui/theme.ex` — slot vocabulary (`accent`/`info`/`badge`/`warning`/`dim`/`selected`/`unselected`/`primary`)
  - `lib/foglet_bbs/time_ago.ex` — `format/1` with `nil` → `"?"` branch (Pitfall 3 source)
  - `lib/foglet_bbs/boards.ex` — `board_directory_for/1` (lines 243-271), `unread_counts/1` precedent (lines 511-526), `directory_board` typespec (lines 224-229)
  - `lib/foglet_bbs/threads/thread.ex` — `:last_post_at`, `:deleted_at` schema fields
  - `lib/foglet_bbs/tui/widgets/chrome/screen_frame.ex` — `inner_width/1` reserves 4 cells (border + padding)
  - `lib/foglet_bbs/tui/widgets/post/post_card.ex:163-198` — `get_time_ago/1` consumer precedent for TimeAgo

- **Vendored Raxol source (verified):**
  - `vendor/raxol/lib/raxol/ui/components/display/tree.ex` — Raxol Display.Tree component, full source
  - `vendor/raxol/lib/raxol/ui/text_measure.ex` — TextMeasure delegates to CharacterHandling
  - `deps/raxol_terminal/lib/raxol/terminal/character_handling.ex` — `wide_char?/1` Pitfall 1 source
  - `vendor/raxol/lib/raxol/core/renderer/view.ex` — `row`/`column`/`text`/`box` DSL macros
  - `vendor/raxol/mix.exs:4` — `@version "2.4.0"`

- **Foglet planning artifacts (verified):**
  - `.planning/REQUIREMENTS.md` — BOARDS-01..04
  - `.planning/phases/21-board-directory-facelift/21-CONTEXT.md` — locked decisions D-01..D-11
  - `.planning/phases/21-board-directory-facelift/21-SPEC.md` — original spec
  - `.planning/phases/20-rich-rows-and-thread-flow/20-CONTEXT.md` — RichRow contract D-01..D-04
  - `.planning/phases/20-rich-rows-and-thread-flow/20-04-PLAN.md` lines 220-538 — RichRow module skeleton + width math
  - `.planning/STATE.md` — Phase 20 currently executing
  - `SCREENS.md` lines 309-350 — Board Directory mock + `RichRow primitive` guidance
  - `lib/foglet_bbs/tui/widgets/README.md` — widget conventions D-07/D-09/D-13/D-14/D-16

### Secondary (MEDIUM confidence)

- **Web-confirmed Unicode property:**
  - codepoints.net / compart.com U+26BF SQUARED KEY East_Asian_Width: Ambiguous — informs Pitfall 1 risk articulation, but the layout-truth source is Raxol's `wide_char?/1` (which is the verified primary source).

### Tertiary (LOW confidence)

- None. Every claim in this research traces to a primary or secondary source.

## Metadata

**Confidence breakdown:**

- **Standard stack:** HIGH — every module verified against codebase or vendored source. Versions confirmed in `mix.exs` / `mix.lock`.
- **Architecture (BoardTree wrapper):** HIGH — pattern verified against the existing `Display.Tree` wrapper and Foglet widget conventions. CONTEXT D-01 locks the shape.
- **Architecture (`:last_post_at` query strategy):** HIGH — structural precedent at `boards.ex:511-526`, with one corrected nuance (Pitfall 4: join from Board, not Subscription).
- **Width math at 64x22:** MEDIUM — D-05 figures hold within ±2 cells depending on indent decision (Open Question 4); name budget is well above the 20-cell floor under any reasonable interpretation. Re-validate in plan tasks.
- **RichRow contract dependency:** MEDIUM-HIGH — Phase 20 hasn't shipped, so the RichRow signature is "assumed-from-locked-CONTEXT-and-plan-04-skeleton." CONTEXT D-03 mandates a re-validation gate before Phase 21 plan execution.
- **Glyph rendering on user terminals:** MEDIUM — Raxol's TextMeasure treats `⚿`/`◆`/`◇`/`▾`/`▸` as 1-cell. Real terminal+font combinations may differ for `⚿` (Ambiguous EAW). CONTEXT grants substitution authority (Pitfall 1).
- **Pitfalls coverage:** HIGH — eight distinct pitfalls identified with codebase line references; the highest-risk three (Pitfalls 3, 4, 7) have explicit mitigations.

**Research date:** 2026-04-25
**Valid until:** 2026-05-25 (30-day estimate; the codebase is stable and the planning artifacts are locked. Re-check Phase 20 ship status weekly until it lands.)

---

*Phase: 21-board-directory-facelift*
*Research date: 2026-04-25*
*Next step: `/gsd-plan-phase 21` — produce per-task plans against the RichRow contract once Phase 20 ships*
