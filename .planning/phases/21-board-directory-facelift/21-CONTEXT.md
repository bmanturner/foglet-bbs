# Phase 21: board-directory-facelift - Context

**Gathered:** 2026-04-25 (assumptions mode)
**Revised:** 2026-04-25 (`/gsd-plan-phase 21 --reviews` revision; see "Revision Note" at bottom)
**Status:** Ready for planning

<domain>
## Phase Boundary

Phase 21 introduces a new `Foglet.TUI.Widgets.List.BoardTree` widget under `lib/foglet_bbs/tui/widgets/list/` and migrates `Foglet.TUI.Screens.BoardList` from direct `Display.Tree` rendering to `BoardTree`. Categories render with `▾`/`▸` glyphs. Board rows route through Phase 20's `Foglet.TUI.Widgets.List.RichRow` with semantic columns: `RichRow :state_cluster` carries BOTH the read-state cell (`◆` for unread / whitespace for read) AND the subscription-state cell (`⚿` required / `✓` subscribed / `+` available); `RichRow :title` carries the indented board name only; `RichRow :metadata` carries a right-aligned composite of unread + age (`12m` / `2h` / `3d` / `—`). `Foglet.Boards.board_directory_for/1` gains `:last_post_at` on every directory entry, derived from the max `Foglet.Threads.Thread.last_post_at` across non-deleted threads.

Phase 21 does NOT ship a details strip below the tree, a wide-terminal inspector pane, ASCII-only fallback glyphs, or any modification to `Foglet.TUI.Widgets.Display.Tree`, `Foglet.TUI.Widgets.List.RichRow`'s public API, or persistence schemas. No new database query, schema field, or context API is introduced beyond the additive `:last_post_at` field on `directory_board`.

</domain>

<spec_lock>
## Locked Requirements (from 21-SPEC.md)

⚠️ **SPEC override:** This phase modifies the locked SPEC at the user's direction during discussion. CONTEXT.md decisions take precedence over SPEC where they conflict. The planner reconciles. The SPEC will not be re-derived; this CONTEXT carries the canonical row contract.

**Preserved from SPEC.md (unchanged):**
- Requirement 1 — `BoardTree` wrapper lands with `▾`/`▸` category glyphs and routes board rows through `RichRow`.
- Requirement 2 — Board row state glyphs (`◆`/whitespace, `⚿`/`✓`/`+`); no `[required]`/`[subscribed]`/`[unsubscribed]` literal text.
- Requirement 3 — `directory_board` exposes `:last_post_at` (max of non-deleted thread `last_post_at`, or `nil`); identical for subscribed/unsubscribed actors; no N+1.
- Requirement 6 — Workflows functionally preserved (j/k/↑/↓/←/→/Enter/s/u/q/Q).

**Overridden by this CONTEXT:**
- ❌ **Requirement 4 (details strip) is REMOVED.** No focused-row details line below the tree. Per-row age column replaces it (see D-04, D-06 below).
- ✏️ **Requirement 5 (64x22 priority contract) extended.** Now covers four trailing-priority elements: read-state cluster cell + subscription cluster cell + unread metadata + **age metadata** all render fully; only the board name truncates with `…`. The 20-cell minimum name attempt is preserved.
- ✏️ **Requirement 2 substantially modified.** Subscription state renders as a **single glyph only** — no text labels. Mapping: `⚿` (U+26BF Squared Key) for required, `✓` (U+2713 Check Mark) for subscribed, `+` (U+002B Plus Sign) for available-to-subscribe. The literal words `required`, `subscribed`, `subscribe` no longer appear in row text. Each board row also carries a trailing age column (see D-04, D-06). Affected acceptance criteria from SPEC.md lines 99–116 are restated in `<acceptance_overrides>` below.

</spec_lock>

<acceptance_overrides>
## Acceptance Criteria Overrides (CONTEXT-level)

These supersede the corresponding lines in 21-SPEC.md when read by the planner.

- ❌ Removed: "A focused board row renders a details strip line `{name} • {state} • {unread} • {last post age}` at 64x22…" (SPEC.md:110)
- ❌ Removed: "A focused category row renders a details strip line `{name} • {N boards} • {M unread total}` at 64x22." (SPEC.md:111)
- ❌ Removed: "A required board row's subscription column reads `✓ required`; a subscribed (non-required) row's reads `✓ subscribed`; an unsubscribed row's reads `+ subscribe`." (SPEC.md:103) — replaced with cluster-cell glyph mapping below.
- ✅ Added: A required board row carries `⚿` (U+26BF Squared Key) as a `RichRow` state-cluster cell themed via `theme.warning`; a subscribed (non-required) row carries `✓` (U+2713 Check Mark) themed via `theme.info`; an unsubscribed row carries `+` (U+002B Plus Sign) themed via `theme.dim`. No subscription state is rendered as multi-character text. No subscription glyph appears in `RichRow :title`.
- ✅ Added: An `unread_count >= 1` board row's metadata renders the result of `Foglet.TimeAgo.format/1` over `:last_post_at` (e.g. `12m`, `2h`, `3d`); a board row with `last_post_at == nil` renders `—` (U+2014) in the age portion of metadata.
- ✅ Added: At 64-cell content width with a long board name, the read-state cluster cell, subscription cluster cell, unread metadata, AND age metadata all render in full; the board name (the only segment in `:title`) is the only segment that truncates with `…`.
- ✅ Added: Category rows render only `{▾|▸} {category.name}` — no trailing summary text, no age column, no subscription glyph. The subscription cluster cell and age metadata appear on board rows only.
- ✅ Added: Read board rows (`unread_count == 0` or `unread_count == nil`) render the read-state cluster slot as **whitespace** via `RichRow`'s absent-glyph contract (`rich_row.ex:137-138` — `glyph_node(nil, ...)` emits ` ` themed via `theme.dim`). No `◇` glyph is rendered. The cluster cell for read-state is simply absent from the cluster list, NOT a `:read` atom or a `◇` cell.

</acceptance_overrides>

<decisions>
## Implementation Decisions

### BoardTree Public API Surface

- **D-01:** `Foglet.TUI.Widgets.List.BoardTree` mirrors `Display.Tree`'s stateful facade. Public functions are `init/1`, `handle_event/2`, `render/2`, AND `focused_board_entry/1` (added in this revision — see D-13). `init/1` accepts `:directory` (the `[%{category, boards: [%{board, subscribed?, required_subscription?, unread_count, last_post_at}]}]` shape from `Foglet.Boards.board_directory_for/1` at `lib/foglet_bbs/boards.ex:243-271`) and `:id`. `render/2` accepts `:theme` (required) and `:width` (optional, defaults to 80). `BoardTree` internally **owns** a `Display.Tree` struct for cursor/expanded/collapse state, walks `RaxolTree.visible_nodes/1` itself, and dispatches each visible node to either an inline category row (rendered by `BoardTree`) or `RichRow.render/1` for a board row. `BoardList` no longer imports `Display.Tree` directly in its row render path and no longer pattern-matches on `Display.Tree.t()` internals — it calls `BoardTree.focused_board_entry/1` instead.

### RichRow State-Cluster Shape for Board Rows

- **D-02 (REVISED):** `RichRow`'s `:state_cluster` carries TWO caller-owned cells (in this order):

  1. **Read-state cell** — `:unread` built-in atom when `unread_count >= 1` (RichRow renders `◆` themed via `theme.accent`; emphasis derives `:bold` automatically per rich_row.ex:101-102). When `unread_count` is `0` or `nil`, the read-state cell is **absent from the cluster list** — RichRow's `glyph_node(nil, ...)` at `rich_row.ex:137-138` renders that slot as whitespace through `absent_glyph_style/2` (theme.dim). No `◇` glyph is rendered.
  2. **Subscription-state cell** — exactly one of:
     - `:locked` built-in atom when `required_subscription?: true` — RichRow already maps this to `⚿` themed via `theme.warning` (rich_row.ex:128).
     - `%{key: :subscribed_board, glyph: "✓", slot: :info}` when `subscribed?: true and required_subscription?: false` — caller-owned cell shape per rich_row.ex:130-132.
     - `%{key: :available_board, glyph: "+", slot: :dim}` when `subscribed?: false` — caller-owned cell shape per rich_row.ex:130-132.

  `RichRow.@cluster_slots = 3` (rich_row.ex:15) — the cluster has three slots; read-state + subscription-state fit comfortably in two. The third slot stays empty and renders whitespace via `glyph_node(nil, ...)`. Total cluster width is `RichRow.@cluster_width = 4` (rich_row.ex:16; 3 slots + trailing space).

  `RichRow :title` carries the indented board name ONLY: `"{indent}{board.name}"` where `indent = TextWidth.pad_trailing("", depth * @indent_per_depth)`. No subscription-glyph prefix. RichRow truncates the title from the right with `…` when the title exceeds the width budget.

  `RichRow :metadata` carries the composite trailing string: `"N unread  AGE"` / `"all read  AGE"` / `"AGE"` only.

  This encoding is the natural shape RichRow already supports — verified directly against rich_row.ex:128-132 — and resolves the theme-routing concern raised in 21-REVIEWS.md: each glyph in the cluster routes through its declared theme slot via RichRow's existing `glyph_style/3` path (rich_row.ex:232-255). No extra styling layer is needed.

- **D-03:** ✅ **Phase 20 RichRow has shipped.** `lib/foglet_bbs/tui/widgets/list/rich_row.ex` exists; this CONTEXT was updated against the actual shipped contract. RichRow's `:state_cluster` accepts both built-in atoms (`:unread`, `:sticky`, `:locked`) and caller-owned cell maps (`%{key: atom(), glyph: String.t(), slot: Theme.slot()}`). Title truncation is right-truncate with `…` per `compute_parts/4` and `truncate_title/2` (rich_row.ex:149-195). Plan 21-02 Task 1 includes a 5-minute preflight to re-confirm these constants before locking the test contract.

### Row Layout (Glyph-Heavy Contract, 64x22-Safe)

- **D-04 (REVISED):** Each board row is composed of these elements, in order, with the corresponding mapping to `RichRow.render/1` inputs:
  1. **Indent** — built into `RichRow :title` as a leading whitespace prefix (`depth * @indent_per_depth` cells; for boards under a category at depth 1, this is 2 cells using `@indent_per_depth = 2`).
  2. **Read-state + subscription cluster** (`RichRow :state_cluster`) — list of caller-owned cells (see D-02):
     - When `unread_count >= 1`: `[:unread, sub_cell]` → first slot renders `◆` (`theme.accent`), second slot renders the subscription glyph at its slot, third slot whitespace.
     - When `unread_count` is `0` or `nil`: `[sub_cell]` → first slot whitespace (absent read-state), second slot renders the subscription glyph, third slot whitespace.
     The subscription cell is exactly one of:
     - `:locked` (renders `⚿` via `theme.warning`) when `required_subscription?: true`
     - `%{key: :subscribed_board, glyph: "✓", slot: :info}` when `subscribed?: true and required_subscription?: false`
     - `%{key: :available_board, glyph: "+", slot: :dim}` when `subscribed?: false`
  3. **Board name** (`RichRow :title`) — `"{indent}{board.name}"`; RichRow right-truncates with `…` when forced.
  4. **Unread + age metadata** (`RichRow :metadata`) — right-aligned composite string:
     - `"N unread  {age}"` when `unread_count >= 1`
     - `"all read  {age}"` when `unread_count == 0`
     - `"{age}"` (age only) when `unread_count == nil`
     - `{age}` is `Foglet.TimeAgo.format(last_post_at)` (`12m` / `2h` / `3d`) or `—` (U+2014) when `last_post_at == nil`.

  Separator within metadata is two spaces. Gap between title and metadata is RichRow's standard right-alignment behavior (`compute_parts/4` at rich_row.ex:149-176 reserves at least 2 cells of padding).

- **D-05 (REVISED):** Width math at 64x22 (assume 60-cell body width after `ScreenFrame` overhead):
  - Indent at depth 1: `1 * @indent_per_depth = 2` cells.
  - Cluster: `RichRow.@cluster_width = 4` cells (rich_row.ex:16). The cluster occupies the same fixed width whether all three slots have glyphs or only one — RichRow always renders three slots + trailing space.
  - Max metadata: `"99 unread  12m" = 14` cells (worst-case populated unread + 3-digit age).
  - Sum of fixed elements: `2 + 4 + 14 = 20` cells.
  - Title↔metadata gap (RichRow internal min): 2 cells.
  - Title (= indent + name) budget at 60-cell body width: `60 − 4 (cluster) − 14 (metadata) − 2 (gap) = 40` cells. Subtract the 2-cell indent: `name budget = 38` cells, ≥ 20-cell minimum (Phase 20 contract preserved with comfortable headroom).
  - The age column uses the **short** form from `Foglet.TimeAgo.format/1` exclusively. The long form (`"12m ago"`, `"no posts yet"`) remains rejected — short form keeps the metadata column visually compact and aligned with how `Foglet.TUI.Widgets.Post.PostCard` already consumes the helper.

  Reference constants in code: `RichRow.@cluster_width` (rich_row.ex:16), `RichRow.@cluster_slots` (rich_row.ex:15), `RichRow.@min_title_length` (rich_row.ex:20), `BoardTree.@indent_per_depth` (defined in Plan 21-03).

### Age Column Format

- **D-06:** Age is rendered via `Foglet.TimeAgo.format/1` (`lib/foglet_bbs/time_ago.ex:22-29`) — the same helper already consumed by `Foglet.TUI.Widgets.Post.PostCard.get_time_ago/1` (`lib/foglet_bbs/tui/widgets/post/post_card.ex:163-198`). Output magnitudes are `"7m"`, `"3h"`, `"2d"` — no `" ago"` suffix appended; no new helper module added. When `last_post_at == nil`, the age portion of metadata renders the literal em-dash `—` (U+2014, 1 cell). No long-form fallback (`"no posts yet"`, `"new"`, `"never"`) is rendered. **`TimeAgo.format(nil)` returns `"?"` (time_ago.ex:28) — `BoardTree` MUST branch on `nil` BEFORE calling `TimeAgo.format/1`.**

### Category Row Treatment

- **D-07:** Category rows render only `{▾|▸} {category.name}`. No trailing board count, no unread total, no age column, no subscription cluster. The cluster, age, and subscription glyphs belong to board rows only. This is a deliberate simplification — the deferred wide-terminal inspector pane is the future home for richer category context if needed. Category rows render via inline themed `text/2` (BoardTree's own renderer), NOT through RichRow.

### Details Strip — REMOVED

- **D-08:** No details strip is rendered below the tree. The `BoardList.render_board_content/3` body composes only the tree (and the existing top-of-tree feedback flash line, see D-12) inside `Chrome.ScreenFrame`. SPEC.md requirement 4 and its associated acceptance criteria are removed by this CONTEXT (see `<spec_lock>` and `<acceptance_overrides>` above).

### `last_post_at` Query Strategy

- **D-09:** `:last_post_at` is added to `Foglet.Boards.board_directory_for/1` via a single-pass `LEFT JOIN` aggregation query. Structurally identical to the existing `Foglet.Boards.unread_counts/1` precedent at `lib/foglet_bbs/boards.ex:511-526`:

  ```elixir
  # New private helper, called once per board_directory_for/1 invocation:
  # SELECT b.id, MAX(t.last_post_at)
  # FROM boards b
  # LEFT JOIN threads t ON t.board_id = b.id AND t.deleted_at IS NULL
  # GROUP BY b.id
  ```

  The result materializes into a `%{board_id => DateTime.t() | nil}` map and merges alongside the existing `subscribed_board_ids/1` and `unread_counts/1` results when assembling `directory_board` entries. Computed actor-independently (boards are public-readable per SPEC.md:37 and interview decision SPEC.md:140). The same map populates subscribed and unsubscribed entries identically.

  - The existing per-board `Repo.aggregate` pattern at `boards.ex:486-504` is **rejected** as it would introduce N+1 (forbidden by SPEC.md:91).
  - Soft-delete column on `Foglet.Threads.Thread` is `:deleted_at` (`lib/foglet_bbs/threads/thread.ex:9`), matching the sentinel used by `unread_counts/1` for posts.

### Subscription Feedback Mechanism

- **D-10:** Subscription feedback **preserves the existing top-of-tree flash mechanism** via `BoardList.maybe_feedback/2` (`lib/foglet_bbs/tui/screens/board_list.ex:252-256`) and the `BoardList.State.feedback` field. The strings (`"Already subscribed."`, `"Not subscribed."`, `"This board is a required subscription."` at `board_list.ex:144,158,165`) are preserved verbatim. The new row layout does not absorb feedback, and since the details strip is removed (D-08), feedback has no alternative surface. This is the lowest-churn path and preserves the existing feedback acceptance test at `board_list_test.exs:154`.

### Subscription Glyph Theme Routing

- **D-10b (REVISED):** Subscription glyphs route through `Foglet.TUI.Theme` slots via `RichRow`'s existing cluster-cell `:slot` field. RichRow's `glyph_style/3` (rich_row.ex:232-255) takes the cell's `:slot` atom, looks up `theme.<slot>.fg` and `theme.<slot>.style`, and emits a styled `text/2` node. No separate styling layer is needed — the theme routing happens inside RichRow at the cluster-render path. Slot mapping:
  - `⚿` (required) → `:locked` built-in atom in `:state_cluster` → RichRow renders via `theme.warning` (rich_row.ex:128).
  - `✓` (subscribed) → `%{key: :subscribed_board, glyph: "✓", slot: :info}` → RichRow renders via `theme.info`.
  - `+` (available) → `%{key: :available_board, glyph: "+", slot: :dim}` → RichRow renders via `theme.dim`.

  Cross-screen consistency note: `:locked` is also Phase 20's reserved atom for locked threads (rich_row.ex:128); both phases mapping to `theme.warning` is intentional — both communicate "this state is fixed; you can't change it."

### Test Placement

- **D-11 (REVISED):** Tests follow Phase 20 D-11 precedent exactly:
  - **NEW** `test/foglet_bbs/tui/widgets/list/board_tree_test.exs` — widget-level unit tests sibling to `list_row_test.exs`, `selection_list_test.exs`, `smart_list_test.exs`. Coverage includes (a) expanded vs collapsed category glyphs (`▾`/`▸`), (b) board row composition with each `(read/unread, subscribed/required/unsubscribed, has_unread/no_unread/nil_unread, posted/no_posts)` shape, (c) `RichRow :state_cluster` carries the read-state cell + subscription cluster cell (two cells max), (d) `RichRow :title` carries the indented board name only (NO subscription glyph prefix), (e) age portion of metadata renders `TimeAgo.format/1` output or `—` (em-dash; no `?`), (f) 64-cell long-name truncation: cluster cells (read + subscription) + unread + age all present in full, name contains `…`, total row width ≤ 64 cells, name ≥ 20 cells, (g) theme-routing verification via `text_runs/1` (`⚿` text run carries `fg: theme.warning.fg`; `✓` carries `theme.info.fg`; `+` carries `theme.dim.fg`), (h) theme-routing source audit (no hardcoded color atoms in `BoardTree` source), (i) `BoardTree.focused_board_entry/1` returns the focused board entry map after navigation, and `nil` when the cursor is on a category or out of range, (j) category long-name truncation (≤ 60 cells with `…`).
  - **EXTEND** `test/foglet_bbs/tui/screens/board_list_test.exs` — replace existing `[subscribed]` / `[required]` / `[unsubscribed]` literal-string assertions at lines 87–101, 155 with **glyph-only** assertions: `⚿` (required), `✓` (subscribed), `+` (available). Add explicit absence assertions: word-boundary regex refutes for `\brequired\b/i`, `\bsubscribed\b/i`, `\bsubscribe\b/i` against row text. Add read-state cluster glyph assertions (`◆` for unread; refute `◇` always). Add age-metadata regex assertions (e.g. `~r/\d+(s|m|h|d|w|mo|y)\b/`) for at least one populated and one `nil` `last_post_at` case. Preserve the existing required-subscription feedback test at line 154 verbatim — feedback strings still contain the words `"required subscription"` legitimately, but they appear in the flash line, not in row text.
  - **EXTEND** `test/foglet_bbs/tui/layout_smoke_test.exs` — add `describe "board_list — size contract"` block at the standard `[{64,22}, {80,24}, {132,50}]` triple Phase 18/19/20 use. The existing `board_list renders board rows at distinct y positions` test at line 741 is preserved (extended only with `:last_post_at` on each fixture entry); the new block asserts (a) all four trailing elements (read cluster + subscription cluster + unread + age) fully rendered, (b) name truncates only when forced, (c) interval-based per-row collision detection: for every row, sort elements by `x` and assert each `prev.x + display_width(prev.text) <= next.x` (no overlap). The fixture seam is `state.board_list = directory` set directly on the App (matching the existing line-741 pattern); no `load_boards/1` call, no FakeBoards module needed in layout-smoke.
  - **EXTEND** `test/foglet_bbs/boards/boards_test.exs` `describe "board_directory_for/1 (SUBS-01)"` block at line 464 with `:last_post_at` cases: (a) board with three non-deleted threads of known `last_post_at` returns max in `:last_post_at`, (b) board with no non-deleted threads returns `nil`, (c) value identical for subscribed and unsubscribed actors on the same board, (d) deleted threads are excluded from the max computation. Lookups locate the board entry by `board.id`, NOT by destructuring the entire directory shape (`[%{boards: [entry]}] = directory` is brittle to fixture growth).

### BoardTree Public API (encapsulation)

- **D-13 (NEW in this revision):** `Foglet.TUI.Widgets.List.BoardTree` exports `focused_board_entry/1 :: t() -> board_entry() | nil`. This function walks the internal `Display.Tree`'s `raxol_state.cursor` and `raxol_state.nodes` to locate the focused board entry map (with `:kind => :board` removed before return). `BoardList` consumes this API and never pattern-matches on `BoardTree`'s internal `:tree` field or `Display.Tree.raxol_state` shape — preserving encapsulation and resolving the Pitfall 5 fragility called out in 21-REVIEWS.md MED 3.

### Claude's Discretion

- Whether the read-state cluster cell uses `:unread` (built-in atom) or an equivalent `%{key: :unread, glyph: "◆", slot: :accent}` cell map. Both produce identical rendering (rich_row.ex:126); built-in atom is preferred for brevity.
- Exact whitespace/separator strategy between metadata segments — single space, double space. The constraint is column alignment across all rows in the visible viewport; planner picks based on what reads cleanest in the layout-smoke triple. Recommendation: two spaces, matching CONTEXT D-04.
- Whether age metadata right-padding is fixed at 3 cells or trims trailing whitespace. Both satisfy the size contract.
- Whether the `last_post_at` aggregation query is a sibling private function to `unread_counts/1` or merged into a single multi-aggregate query that returns both `unread_count` and `last_post_at` per board. Both satisfy D-09 and the no-N+1 constraint; planner picks based on readability and Repo round-trip count.
- Whether the em-dash `—` for nil age renders through `theme.dim.fg` or the row's default foreground. Subtle visual choice; either is acceptable.
- Whether `BoardTree` substitutes a different 1-cell BMP glyph for `⚿` if visual testing reveals rendering issues on common SSH terminal/font combos. The user's intent is "lock-shaped"; planner has authority to substitute (within 1-cell BMP) if `⚿` proves problematic, but should flag the substitution in plan output for review.

### Folded Todos

None — `gsd-sdk query todo.match-phase 21` not run because no todos are flagged against Phase 21 in current STATE.md.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Locked Phase Scope
- `.planning/phases/21-board-directory-facelift/21-SPEC.md` — Original Phase 21 SPEC. **Read alongside `<spec_lock>` and `<acceptance_overrides>` in this CONTEXT — they override SPEC requirement 4 and modify requirements 2/5.**
- `.planning/ROADMAP.md` §Phase 21 — Milestone position, dependency on Phase 20, requirements `BOARDS-01`–`BOARDS-04`, success criteria.
- `.planning/REQUIREMENTS.md` — Requirement IDs `BOARDS-01`, `BOARDS-02`, `BOARDS-03`, `BOARDS-04`. Note: BOARDS-02 ("Focused board or category details are visible through a 64x22-safe compact details strip") is **fulfilled differently** in this phase — per-row age column instead of a strip. Reflect this in REQUIREMENTS.md if the planner amends requirement language.
- `SCREENS.md` §Board Directory (lines 309–350) — Visual target sketch and glyph language. **Note:** the SCREENS.md mock includes the details strip; this phase deviates per D-08.
- `SCREENS.md` §Design Principles and §Chosen Direction — Classic Modern BBS rhythm, single-Unicode-set guidance.

### Dependency Contracts
- `.planning/phases/20-rich-rows-and-thread-flow/20-CONTEXT.md` — **MUST READ FIRST.** RichRow public API (D-01), state-cluster contract (D-02, D-03), theme-slot mapping (D-06), 20-cell minimum title attempt. Phase 21 consumes this contract.
- `.planning/phases/20-rich-rows-and-thread-flow/20-SPEC.md` — RichRow shipped contract; pairs with 20-CONTEXT.md.
- `.planning/phases/16-unicode-width-foundation/16-CONTEXT.md` — `Foglet.TUI.TextWidth` width-helper contract used for cluster fixed-width math, column padding, and row truncation.
- `.planning/phases/17-theme-and-mode-metadata/17-CONTEXT.md` — Theme-slot vocabulary; BoardList screen mode metadata (`:bbs`).
- `.planning/phases/18-chrome-v2/18-CONTEXT.md` — `Chrome.ScreenFrame` composition boundary; `[{64,22},{80,24},{132,50}]` size-contract triple.
- `.planning/phases/19-main-menu-dashboard/19-CONTEXT.md` — Glyph/theme-slot precedent and the "extend existing test files; do not create new size-contract files" rule.

### Existing Code Touch Points
- `lib/foglet_bbs/tui/widgets/list/board_tree.ex` — **NEW** module to create.
- `lib/foglet_bbs/tui/widgets/list/rich_row.ex` — **SHIPPED** Phase 20. Phase 21 consumes its public API; cluster-cell shape verified at rich_row.ex:128-132; cluster constants at rich_row.ex:15-16.
- `lib/foglet_bbs/tui/screens/board_list.ex` — Migrate from direct `Display.Tree` rendering to `BoardTree`. Preserve `BoardList.State.feedback`, `maybe_feedback/2`, key handlers (j/k/↑/↓/←/→/Enter/s/u/q/Q), and `load_threads` orchestration. Switch `focused_board_entry/1` from inline `Display.Tree` pattern match to `BoardTree.focused_board_entry/1` API call (D-13).
- `lib/foglet_bbs/tui/screens/board_list/state.ex` — `State.feedback` field preserved; `State.tree` renames to `State.board_tree` to hold `BoardTree.t()` instead of `Display.Tree.t()`.
- `lib/foglet_bbs/tui/widgets/display/tree.ex` — **No changes.** Display.Tree retains its current contract for any other future consumers.
- `lib/foglet_bbs/boards.ex` — `directory_board` typespec at lines 224–229 gains `:last_post_at`. `board_directory_for/1` at lines 243–271 gains a single LEFT-JOIN aggregate alongside existing `subscribed_board_ids/1` and `unread_counts/1` calls. `unread_counts/1` at lines 511–526 is the structural precedent for the new aggregate.
- `lib/foglet_bbs/threads/thread.ex` — Schema fields `:last_post_at` (line 11) and `:deleted_at` (line 9) consumed by the new aggregate query. **No schema changes.**
- `lib/foglet_bbs/tui/widgets/list/list_row.ex` — Sibling reference; keeps current contract for non-BoardList callers.
- `lib/foglet_bbs/tui/widgets/list/selection_list.ex` — Sibling render pattern; canonical `▌` selection-marker reference.
- `lib/foglet_bbs/tui/widgets/list/smart_list.ex` — Sibling keyword-driven render pattern.
- `lib/foglet_bbs/tui/text_width.ex` — `display_width/1`, `slice_to_width/2`, `pad_trailing/2`. Mandatory for column width math, name truncation, and age-column right-alignment.
- `lib/foglet_bbs/time_ago.ex` (lines 22–29) — `Foglet.TimeAgo.format/1` consumed verbatim for the age column. No adapter, no new helper. **`format(nil) == "?"` (line 28) — caller MUST branch on nil first.**
- `lib/foglet_bbs/tui/widgets/post/post_card.ex` (lines 163–198) — Existing TimeAgo consumer; reference precedent for how the helper is integrated.
- `lib/foglet_bbs/tui/theme.ex` (lines 106–241) — Theme slots `accent`, `info`, `badge`, `warning`, `dim`, `selected`, `unselected`. No new slots introduced.
- `lib/foglet_bbs/tui/widgets/chrome/screen_frame.ex` — `ScreenFrame.render/4` stays passive; `BoardList.render/1` continues calling it.

### Test Anchors
- `test/foglet_bbs/tui/widgets/list/board_tree_test.exs` — **NEW** widget-level test file (D-11).
- `test/foglet_bbs/tui/widgets/list/list_row_test.exs` — Sibling test pattern reference.
- `test/foglet_bbs/tui/widgets/list/selection_list_test.exs` — Sibling test pattern reference.
- `test/foglet_bbs/tui/widgets/list/smart_list_test.exs` — Sibling test pattern reference (state input shapes).
- `test/foglet_bbs/tui/widgets/list/rich_row_test.exs` — Direct sibling for cluster-cell assertions; `text_runs/1` style checks pattern.
- `test/foglet_bbs/tui/screens/board_list_test.exs` — Existing screen tests; replace `[subscribed]`/`[required]`/`[unsubscribed]` assertions at lines 87–101, 155 with column-text + glyph assertions; add age-metadata assertions; preserve required-subscription feedback test at line 154.
- `test/foglet_bbs/tui/layout_smoke_test.exs` — Existing positioned-render harness. Add `describe "board_list — size contract"` block at `[{64,22},{80,24},{132,50}]`. Existing line-741 test extended with `:last_post_at` on fixture; uses `state.board_list = directory` directly on the App (no `load_boards/1`, no FakeBoards in this file).
- `test/foglet_bbs/boards/boards_test.exs` (line 464 onward) — Existing `describe "board_directory_for/1 (SUBS-01)"` block; extend with `:last_post_at` cases. Use `find_board_entry(directory, board.id)` helper for entry lookup, not full-directory destructuring.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `Foglet.TUI.Widgets.Display.Tree.{init/1, handle_event/2, render/2}` — Current stateful facade. BoardTree mirrors this shape, owning a Display.Tree internally for cursor/expand state (D-01).
- `Foglet.TUI.Widgets.List.RichRow.render/1` — Phase 20 stateless rich-row renderer. Cluster accepts caller-owned cells (`%{key: atom, glyph: String, slot: atom}`) at rich_row.ex:130-132. `:locked` built-in atom at rich_row.ex:128 maps to `⚿` themed via `theme.warning`. Absent slot renders whitespace via `glyph_node(nil, ...)` at rich_row.ex:137-138.
- `Foglet.Boards.board_directory_for/1` (`boards.ex:243-271`) — Existing entry point; gains `:last_post_at` per D-09.
- `Foglet.Boards.unread_counts/1` (`boards.ex:511-526`) — Structural precedent for the new `last_post_ats/1` aggregate query. Single Repo.all, group_by, MAX/COUNT aggregate.
- `Foglet.TimeAgo.format/1` (`time_ago.ex:22-29`) — Already produces `"7m"`/`"3h"`/`"2d"` magnitudes. Consumed verbatim for the age column (D-06). `format(nil) == "?"`.
- `Foglet.TUI.TextWidth.display_width/1`, `slice_to_width/2`, `pad_trailing/2` — Width helpers for column alignment, name truncation, age-metadata padding.
- `Foglet.TUI.Theme` slots `accent`, `info`, `badge`, `warning`, `dim`, `selected`, `unselected`, `primary` — No new slots.
- `Foglet.Threads.Thread.last_post_at` (`thread.ex:11`) — Already maintained by `Thread.bump_counters/1` on post inserts.
- `Foglet.Threads.Thread.deleted_at` (`thread.ex:9`) — Soft-delete sentinel, used by the new aggregate's `is_nil(t.deleted_at)` filter.
- `Foglet.TUI.Screens.BoardList.maybe_feedback/2` (`board_list.ex:252-256`) — Existing top-of-tree feedback mechanism preserved verbatim per D-10.

### Established Patterns
- TUI widget facades follow `init/1` + `handle_event/2` + `render/2` (Display.Tree, SmartList, SelectionList).
- Sibling list widgets each have their own dedicated test file at `test/foglet_bbs/tui/widgets/list/<widget>_test.exs`.
- Size contracts live inside `layout_smoke_test.exs` at the `[{64,22},{80,24},{132,50}]` triple — Phase 18 set this; Phase 19 and Phase 20 reinforced it.
- Width-sensitive layout uses `TextWidth`; `String.length/1` and grapheme counts are not allowed for layout decisions.
- Widget styling routes through `Foglet.TUI.Theme` slots; no hardcoded color atoms anywhere in `lib/`.
- Aggregate queries that touch every row in a context group use a single `Repo.all` with `group_by`, not per-row `Repo.aggregate` calls (`boards.ex:511-526` is the canonical pattern).
- Tests use `start_supervised!/1` for supervised processes; no `Process.sleep/1` or `Process.alive?/1`.

### Integration Points
- `Foglet.TUI.Screens.BoardList.render/1` keeps calling `Chrome.ScreenFrame.render(state, breadcrumb, content, keys)`. The `content` body changes: tree is now produced by `BoardTree.render(state.board_tree, opts)` instead of `Display.Tree.render(state.tree, opts)`. The feedback flash line above the tree is preserved.
- `BoardList.handle_key/2` is unchanged in surface — j/k/↑/↓/←/→/Enter/s/u/q/Q each route to the same outcome. Internally, key handlers may forward events to `BoardTree.handle_event/2` instead of `Display.Tree.handle_event/2`. The `:load_threads` command emission on Enter for board nodes is preserved. `focused_board_entry/1` is now `BoardTree.focused_board_entry/1` (D-13).
- `App` routing and Phase 17 `:bbs` mode metadata for BoardList are unchanged.
- `Foglet.Boards.board_directory_for/1` callers (BoardList, Sysop boards screen, any future TUI consumer) all receive the new `:last_post_at` field. BoardList consumes it via D-09; Sysop boards screen (`lib/foglet_bbs/tui/screens/sysop/boards_view.ex`) is unaffected — it can ignore the new field until Phase 25 chooses to consume it.
- `Foglet.Threads.Thread.bump_counters/1` (`thread.ex:33-38`) keeps `:last_post_at` accurate on post inserts; no changes required to the bump path.

</code_context>

<specifics>
## Specific Ideas

- "Get rid of the details strip and show the age on each board row" — locked into D-04, D-06, D-07, D-08. SPEC.md requirement 4 is removed by this CONTEXT; the row gains an age portion in metadata via `Foglet.TimeAgo.format/1` short form (`12m`/`2h`/`3d`/`—`).
- "Instead of subscribed, subscribe, and required, just use icons. lock unicode for required, checkmark unicode for subscribed, and plus sign for subscribe" — locked into D-02, D-04, D-10b, D-11, and `<acceptance_overrides>`. The subscription column is glyph-only; no text labels remain in row content. The glyph rides as a `:state_cluster` cell (NOT a title prefix), routed through `theme.warning` / `theme.info` / `theme.dim` via RichRow's existing slot machinery.
- **Lock-glyph constraint:** No 1-cell padlock glyph exists in widely-supported BMP Unicode. The actual lock emoji `🔒` (U+1F512) renders as 2 cells on most terminals, breaking Phase 20's fixed-width cluster contract. The closest 1-cell BMP "locked / mandatory" glyph is `⚿` (U+26BF Squared Key) — locked here in D-04. Phase 20's `:locked` atom (rich_row.ex:128) already uses `⚿` themed via `theme.warning`; Phase 21 reuses that built-in atom for the required-board case.
- The em-dash `—` (U+2014) is the explicit no-posts sentinel — chosen over empty cell or the word `new` to avoid ambiguity with unread state.
- `Foglet.TimeAgo.format/1` short form (`"7m"` etc.) is the exact format used — no `" ago"` suffix appended, no new helper module added. The existing `PostCard.get_time_ago/1` consumer (`post_card.ex:163-198`) is the integration precedent. Caller MUST branch on nil before calling.
- Subscription feedback stays as the top-of-tree flash line via existing `maybe_feedback/2` — no migration to inline-row treatment, no migration to a row-level icon flash.
- 64x22 width math (D-05) leaves comfortable headroom: 60 (body) − 4 (cluster) − 14 (max metadata) − 2 (gap) = 40 cells available for indent + name; minus 2-cell indent = 38 cells for the name (vs. 20-cell minimum from Phase 20).

</specifics>

<deferred>
## Deferred Ideas

- Wide-terminal inspector pane on the right with full board description, posting policy, full subscription/unread detail — matches Phase 20's deferral pattern; can be added in a later phase as progressive enhancement when terminal width permits.
- Category-row summary text (board count, unread total) — could land on the category row itself or in a future inspector pane. Phase 21 ships category rows as `{▾|▸} {category.name}` only (D-07).
- ASCII-only fallback glyph set — Phase 20 locked single-Unicode-set across themes; Phase 21 inherits.
- Adoption of `BoardTree` by the Sysop board management screen (`lib/foglet_bbs/tui/screens/sysop/boards_view.ex`) — Phase 25 territory per ROADMAP.md.
- Adoption of `BoardTree` by any future operator surface — Phase 25 or beyond.
- New keyboard binding for "+ subscribe" — `+` is visual state only; subscription remains on `s`.
- Theme palette retuning to improve glyph contrast on real SSH terminals — `UI-03` v2 territory; Phase 21 uses slots Phase 17 shipped.
- Schema, query, or context API changes beyond `:last_post_at` on `directory_board` — out of scope.
- Changes to `Foglet.TUI.Widgets.Display.Tree`'s public contract — out of scope.
- Changes to `Foglet.TUI.Widgets.List.RichRow`'s public API — out of scope (Phase 21 consumes the API Phase 20 ships and does not modify it).

### Reviewed Todos (not folded)
None — no Phase 21 todo matches in current STATE.md.

</deferred>

---

## Revision Note (2026-04-25)

This CONTEXT was revised by `/gsd-plan-phase 21 --reviews` after Codex review surfaced a critical architectural mismatch with the original D-02 design.

**What changed:**

The original D-02 placed the subscription glyph (`⚿` / `✓` / `+`) as a 2-cell prefix on `RichRow :title` (`"⚿ announcements"`, `"+ marketplace"`). Codex correctly identified that this approach **cannot independently theme the glyph vs. the name** — a single text run carries one style, so `⚿` would inherit the title's default fg, defeating D-10b's per-glyph theme routing.

After reading the actual shipped `lib/foglet_bbs/tui/widgets/list/rich_row.ex`:
- rich_row.ex:130-132 confirms `:state_cluster` accepts caller-owned `%{glyph: String, slot: atom}` cells.
- rich_row.ex:128 confirms `:locked` built-in atom already maps to `⚿` themed via `theme.warning`.
- rich_row.ex:15-16 confirms `@cluster_slots = 3` and `@cluster_width = 4` — comfortable room for read-state + subscription + one empty slot.
- rich_row.ex:137-138 confirms the absent-slot whitespace contract.

**The revision moves the subscription glyph from `:title` prefix into `:state_cluster` as a caller-owned cell.** `RichRow.glyph_style/3` (rich_row.ex:232-255) already routes each cluster cell's `:slot` field through the theme — so per-glyph theme routing is achieved natively without any modification to RichRow.

**Cascading benefits:**
- D-10b becomes a thin restatement of RichRow's existing slot routing.
- D-04 becomes simpler — title is just `"{indent}{name}"`, no prefix composition.
- D-05 width math collapses cleanly: indent (2) + cluster (4) + metadata (14) = 20 cells; name budget at 60-cell body = 38 cells.
- The `◇` read-state question (Codex concern HIGH 2) resolves automatically: read board = empty cluster slot = whitespace via `glyph_node(nil, ...)`. No `◇` glyph needed, no test ambiguity.

**Other revisions made in the same pass:**
- D-13 added: `BoardTree.focused_board_entry/1` is now public, replacing BoardList's inline pattern match on `Display.Tree.t()` internals (Codex MED 3 / Pitfall 5).
- D-11 amended: layout_smoke_test seam pinned to `state.board_list = directory` direct assignment (Codex MED 4).
- D-11 amended: layout overlap detection uses interval math, not duplicate-`{x,y}` (Codex MED 5).
- D-11 amended: time-based assertions use regex (`~r/\d+(s|m|h|d|w|mo|y)\b/`) instead of exact magnitudes (Codex MED 6).
- D-05 math reconciled with shipped RichRow constants (Codex MED 7).
- D-11 amended: data-layer tests look up entries by `board.id`, not full-directory destructuring (Codex MED 8).
- D-11 amended: word-boundary regex refutes for `"required"` / `"subscribed"` / `"subscribe"` in row text (Codex LOW 10).
- D-11 amended: category long-name truncation coverage (Codex LOW 11).

The downstream plans (21-01, 21-02, 21-03, 21-04) were re-edited in place to consume this revised contract.

---

*Phase: 21-board-directory-facelift*
*Context gathered: 2026-04-25*
*Context revised: 2026-04-25 (--reviews)*
