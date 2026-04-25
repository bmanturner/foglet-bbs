# Phase 21: board-directory-facelift - Context

**Gathered:** 2026-04-25 (assumptions mode)
**Status:** Ready for planning

<domain>
## Phase Boundary

Phase 21 introduces a new `Foglet.TUI.Widgets.List.BoardTree` widget under `lib/foglet_bbs/tui/widgets/list/` and migrates `Foglet.TUI.Screens.BoardList` from direct `Display.Tree` rendering to `BoardTree`. Categories render with `▾`/`▸` glyphs. Board rows route through Phase 20's `Foglet.TUI.Widgets.List.RichRow` with semantic columns: leading read-state cluster (`◆` unread / `◇` read), board name, subscription column (`✓ required` / `✓ subscribed` / `+ subscribe`), trailing unread column (`N unread` / `all read` / absent), and a new trailing **age column** (`12m` / `2h` / `3d` / `—`). `Foglet.Boards.board_directory_for/1` gains `:last_post_at` on every directory entry, derived from the max `Foglet.Threads.Thread.last_post_at` across non-deleted threads.

Phase 21 does NOT ship a details strip below the tree, a wide-terminal inspector pane, ASCII-only fallback glyphs, or any modification to `Foglet.TUI.Widgets.Display.Tree`, `Foglet.TUI.Widgets.List.RichRow`'s public API, or persistence schemas. No new database query, schema field, or context API is introduced beyond the additive `:last_post_at` field on `directory_board`.

</domain>

<spec_lock>
## Locked Requirements (from 21-SPEC.md)

⚠️ **SPEC override:** This phase modifies the locked SPEC at the user's direction during discussion. CONTEXT.md decisions take precedence over SPEC where they conflict. The planner reconciles. The SPEC will not be re-derived; this CONTEXT carries the canonical row contract.

**Preserved from SPEC.md (unchanged):**
- Requirement 1 — `BoardTree` wrapper lands with `▾`/`▸` category glyphs and routes board rows through `RichRow`.
- Requirement 2 — Board row state glyphs (`◆`/`◇`, `✓ required`/`✓ subscribed`/`+ subscribe`); no `[required]`/`[subscribed]`/`[unsubscribed]` literal text.
- Requirement 3 — `directory_board` exposes `:last_post_at` (max of non-deleted thread `last_post_at`, or `nil`); identical for subscribed/unsubscribed actors; no N+1.
- Requirement 6 — Workflows functionally preserved (j/k/↑/↓/←/→/Enter/s/u/q/Q).

**Overridden by this CONTEXT:**
- ❌ **Requirement 4 (details strip) is REMOVED.** No focused-row details line below the tree. Per-row age column replaces it (see D-04, D-06 below).
- ✏️ **Requirement 5 (64x22 priority contract) extended.** Now covers four trailing-priority segments: read-state cluster + subscription-glyph prefix + unread column + **age column** all render fully; only the board name truncates with `…`. The 20-cell minimum name attempt is preserved.
- ✏️ **Requirement 2 substantially modified.** Subscription state renders as a **single glyph only** — no text labels. Mapping: `⚿` (U+26BF Squared Key) for required, `✓` (U+2713 Check Mark) for subscribed, `+` (U+002B Plus Sign) for available-to-subscribe. The literal words `required`, `subscribed`, `subscribe` no longer appear in row text. Each board row also carries a trailing age column (see D-04, D-06). Affected acceptance criteria from SPEC.md lines 99–116 are restated in `<acceptance_overrides>` below.

</spec_lock>

<acceptance_overrides>
## Acceptance Criteria Overrides (CONTEXT-level)

These supersede the corresponding lines in 21-SPEC.md when read by the planner.

- ❌ Removed: "A focused board row renders a details strip line `{name} • {state} • {unread} • {last post age}` at 64x22…" (SPEC.md:110)
- ❌ Removed: "A focused category row renders a details strip line `{name} • {N boards} • {M unread total}` at 64x22." (SPEC.md:111)
- ❌ Removed: "A required board row's subscription column reads `✓ required`; a subscribed (non-required) row's reads `✓ subscribed`; an unsubscribed row's reads `+ subscribe`." (SPEC.md:103) — replaced with glyph-only mapping below.
- ✅ Added: A required board row renders the single glyph `⚿` (U+26BF Squared Key) as the subscription affordance; a subscribed (non-required) row renders `✓` (U+2713 Check Mark); an unsubscribed row renders `+` (U+002B Plus Sign). No subscription state is rendered as multi-character text.
- ✅ Added: An `unread_count >= 1` board row's age column renders the result of `Foglet.TimeAgo.format/1` over `:last_post_at` (e.g. `12m`, `2h`, `3d`); a board row with `last_post_at == nil` renders `—` (U+2014) in the age column.
- ✅ Added: At 64-cell content width with a long board name, the leading read-state cluster, subscription glyph, unread column, AND age column all render in full; the board name is the only segment that truncates with `…`.
- ✅ Added: Category rows render only `{▾|▸} {category.name}` — no trailing summary text, no age column, no subscription glyph. The subscription glyph and age column appear on board rows only.

</acceptance_overrides>

<decisions>
## Implementation Decisions

### BoardTree Public API Surface

- **D-01:** `Foglet.TUI.Widgets.List.BoardTree` mirrors `Display.Tree`'s stateful facade. Public functions are `init/1`, `handle_event/2`, and `render/2`. `init/1` accepts `:directory` (the `[%{category, boards: [%{board, subscribed?, required_subscription?, unread_count, last_post_at}]}]` shape from `Foglet.Boards.board_directory_for/1` at `lib/foglet_bbs/boards.ex:243-271`) and `:id`. `render/2` accepts `:theme` (required) and `:width` (optional, defaults to 80). `BoardTree` internally **owns** a `Display.Tree` struct for cursor/expanded/collapse state, walks `RaxolTree.visible_nodes/1` itself, and dispatches each visible node to either an inline category row (rendered by `BoardTree`) or `RichRow.render/1` for a board row. `BoardList` no longer imports `Display.Tree` directly in its row render path.

### RichRow State-Cluster Shape for Board Rows

- **D-02:** `RichRow`'s `:state_cluster` carries **read-state only** (`[:unread]` or `[]`). The subscription glyph (`⚿` / `✓` / `+`) is composed by `BoardTree` as a fixed 2-cell **prefix on `RichRow`'s `:title`** (e.g. `:title => "⚿ announcements"` or `"+ marketplace"`). The trailing unread column (`N unread` / `all read` / absent) and the new trailing age column (`12m` / `2h` / `3d` / `—`) ride together in `RichRow`'s `:metadata` slot as a right-aligned composite string with whitespace separation (e.g. `"3 unread  12m"`, `"all read  2h"`, or `"3 unread  —"`).
  - The cluster's fixed-width contract (Phase 20 D-03) is intact: `:unread` is a single-glyph atom; the subscription glyph lives in the title prefix, not the cluster.
  - Phase 20 reserved cluster atoms `:subscribed`, `:category`, `:required` for Phase 21 — but this phase does NOT use them, because the subscription glyph set includes `+` (available) which Phase 20 did not reserve, and shipping mixed reserved + unreserved atoms in the cluster is brittle. Title-prefix approach sidesteps Phase 20's atom vocabulary entirely.
  - Title truncation behavior preserves the prefix: `RichRow` truncates from the right with `…` (Phase 20 contract), so `"⚿ announcements with a very long n…"` keeps `⚿` and the leading name characters intact. `BoardTree` does not pre-truncate; it composes the full prefixed string and lets `RichRow` apply width math.

- **D-03:** ⚠️ **Phase 20 RichRow has not yet shipped.** `lib/foglet_bbs/tui/widgets/list/rich_row.ex` does not exist as of this CONTEXT. Phase 21 plans against `20-CONTEXT.md` D-01/D-02 (the locked Phase 20 contract). When `RichRow` lands, the planner re-validates D-02 against the actual signature before plan 21-01 begins. If RichRow's title-truncation behavior diverges from "right-truncate with `…`", D-02's title-prefix approach must be re-examined.

### Row Layout (Glyph-Heavy Contract, 64x22-Safe)

- **D-04:** Each board row is composed of these segments, in order, with the corresponding mapping to `RichRow.render/1` inputs:
  1. **Indent** — 4 cells for boards under a category. Preserve current `Display.Tree` indentation.
  2. **Read-state cluster** (`RichRow :state_cluster`) — `[:unread]` → `◆ ` (2 cells) or `[]` → `◇ ` or whitespace, padded to Phase 20's `@cluster_width`.
  3. **Subscription glyph + name** (`RichRow :title`) — composed string `"{glyph} {board.name}"`:
     - `⚿` (U+26BF Squared Key) when `required_subscription?: true`
     - `✓` (U+2713 Check Mark) when `subscribed?: true and required_subscription?: false`
     - `+` (U+002B Plus Sign) when `subscribed?: false`
     The 2-cell prefix (1 glyph + 1 space) is followed by the board name. RichRow truncates the title from the right with `…` when forced; the prefix is preserved by the right-truncation contract.
  4. **Unread + age metadata** (`RichRow :metadata`) — right-aligned composite string:
     - `"N unread  {age}"` when `unread_count >= 1`
     - `"all read  {age}"` when `unread_count == 0`
     - `"{age}"` (age column only) when `unread_count == nil`
     - `{age}` is `Foglet.TimeAgo.format(last_post_at)` (`12m` / `2h` / `3d`) or `—` (U+2014) when `last_post_at == nil`.

  Separator within metadata is two spaces. Gap between title and metadata is RichRow's standard right-alignment behavior.

- **D-05:** Width math at 64x22 (assume 60-cell body width after `ScreenFrame` overhead):
  - Fixed: indent (4) + cluster (2) + subscription prefix (2) + max metadata (14, e.g. `"99 unread  12m"`) = **22 cells**.
  - Title↔metadata gap (RichRow internal): ≥ 2 cells.
  - Name budget: 60 − 22 − 2 = **36 cells** ≥ 20-cell minimum (Phase 20 contract preserved with comfortable headroom).
  - The age column uses the **short** form from `Foglet.TimeAgo.format/1` exclusively. The long form (`"12m ago"`, `"no posts yet"`) remains rejected — even though headroom now permits it, short form keeps the metadata column visually compact and aligned with how `Foglet.TUI.Widgets.Post.PostCard` already consumes the helper.

### Age Column Format

- **D-06:** Age is rendered via `Foglet.TimeAgo.format/1` (`lib/foglet_bbs/time_ago.ex:22-29`) — the same helper already consumed by `Foglet.TUI.Widgets.Post.PostCard.get_time_ago/1` (`lib/foglet_bbs/tui/widgets/post/post_card.ex:163-198`). Output magnitudes are `"7m"`, `"3h"`, `"2d"` — no `" ago"` suffix appended; no new helper module added. When `last_post_at == nil`, the age column renders the literal em-dash `—` (U+2014, 1 cell). No long-form fallback (`"no posts yet"`, `"new"`, `"never"`) is rendered.

### Category Row Treatment

- **D-07:** Category rows render only `{▾|▸} {category.name}`. No trailing board count, no unread total, no age column. The age column belongs to board rows only. This is a deliberate simplification — the deferred wide-terminal inspector pane is the future home for richer category context if needed.

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

- **D-10b:** Subscription glyphs route through `Foglet.TUI.Theme` slots (no hardcoded color atoms). Recommended slot mapping, mirroring Phase 20's semantic alignment:
  - `⚿` (required) → `theme.warning.fg` — same slot Phase 20 D-06 maps to `:locked`. Both atoms communicate "this state is fixed; you can't change it." Cross-screen consistency is intentional.
  - `✓` (subscribed) → `theme.info.fg` — affirmative status; Phase 20 also routes `:sticky` here (or to `theme.badge.fg`).
  - `+` (available) → `theme.dim.fg` — unobtrusive affordance; should fade visually so the eye lands on `⚿`/`✓` first.
  - Final slot picks are planner discretion within these recommendations after a quick visual pass across all nine themes.

### Test Placement

- **D-11:** Tests follow Phase 20 D-11 precedent exactly:
  - **NEW** `test/foglet_bbs/tui/widgets/list/board_tree_test.exs` — widget-level unit tests sibling to `list_row_test.exs`, `selection_list_test.exs`, `smart_list_test.exs`. Coverage includes (a) expanded vs collapsed category glyphs (`▾`/`▸`), (b) board row composition with each `(read/unread, subscribed/required/unsubscribed, has_unread/no_unread/nil_unread, posted/no_posts)` shape, (c) `RichRow :state_cluster` carries read-state only, (d) `RichRow :title` carries the subscription glyph prefix (`⚿ `/`✓ `/`+ `) followed by the board name, (e) age column renders `TimeAgo.format/1` output or `—`, (f) 64-cell long-name truncation: cluster + subscription glyph + unread + age all present in full, name contains `…`, total row width ≤ 64 cells, name ≥ 20 cells, (g) theme-routing audit (no hardcoded color atoms in `BoardTree` source).
  - **EXTEND** `test/foglet_bbs/tui/screens/board_list_test.exs` — replace existing `[subscribed]` / `[required]` / `[unsubscribed]` literal-string assertions at lines 87–101, 155 with **glyph-only** assertions: `⚿` (required), `✓` (subscribed), `+` (available). Add an explicit absence assertion: no row contains the literal substrings `"required"`, `"subscribed"`, or `"subscribe"` as words (other than within the board's own name). Add read-state cluster glyph assertions (`◆` / `◇`). Add age-column assertions for at least one populated and one `nil` `last_post_at` case. Preserve the existing required-subscription feedback test at line 154 verbatim — feedback strings still contain the word `"required"`, but they appear in the flash line, not in row text.
  - **EXTEND** `test/foglet_bbs/tui/layout_smoke_test.exs` — add `describe "board_list — size contract"` block at the standard `[{64,22}, {80,24}, {132,50}]` triple Phase 18/19/20 use. The existing `board_list renders board rows at distinct y positions` test at line 384 is absorbed or preserved as appropriate; the new block asserts (a) all four trailing columns fully rendered, (b) name truncates only when forced, (c) no two text elements share `{x, y}` coordinates such that they overlap.
  - **EXTEND** `test/foglet_bbs/boards/boards_test.exs` `describe "board_directory_for/1 (SUBS-01)"` block at line 464 with `:last_post_at` cases: (a) board with three non-deleted threads of known `last_post_at` returns max in `:last_post_at`, (b) board with no non-deleted threads returns `nil`, (c) value identical for subscribed and unsubscribed actors on the same board, (d) deleted threads are excluded from the max computation.

### Claude's Discretion

- Final theme-slot picks for the subscription glyphs (D-10b recommends `theme.warning.fg` / `theme.info.fg` / `theme.dim.fg` for `⚿` / `✓` / `+`; planner validates after a quick visual pass across all nine themes).
- Exact whitespace/separator strategy between row segments — single space, double space, or `TextWidth.pad_to_width/2`-based fixed columns. The constraint is column alignment across all rows in the visible viewport; planner picks based on what reads cleanest in the layout-smoke triple.
- Exact value of the read-state cluster width in `BoardTree` if it differs from Phase 20's `RichRow.@cluster_width` (sticky/locked atoms don't apply to BoardList, so a 1-glyph + 1-space cluster is sufficient). Recommended: reuse Phase 20's value verbatim for cross-screen consistency.
- Whether age column right-padding is fixed at 3 cells or trims trailing whitespace. Both satisfy the size contract.
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
- `lib/foglet_bbs/tui/widgets/list/rich_row.ex` — **NEW from Phase 20** (not yet shipped at time of this CONTEXT). Phase 21 consumes its public API; planner validates the actual signature against `20-CONTEXT.md` D-01/D-02 before plan 21-01.
- `lib/foglet_bbs/tui/screens/board_list.ex` — Migrate from direct `Display.Tree` rendering to `BoardTree`. Preserve `BoardList.State.feedback`, `maybe_feedback/2`, key handlers (j/k/↑/↓/←/→/Enter/s/u/q/Q), and `load_threads` orchestration.
- `lib/foglet_bbs/tui/screens/board_list/state.ex` — `State.feedback` field preserved; `State.tree` may evolve to `State.board_tree` if BoardTree owns the prior `Display.Tree` struct internally.
- `lib/foglet_bbs/tui/widgets/display/tree.ex` — **No changes.** Display.Tree retains its current contract for any other future consumers.
- `lib/foglet_bbs/boards.ex` — `directory_board` typespec at lines 224–229 gains `:last_post_at`. `board_directory_for/1` at lines 243–271 gains a single LEFT-JOIN aggregate alongside existing `subscribed_board_ids/1` and `unread_counts/1` calls. `unread_counts/1` at lines 511–526 is the structural precedent for the new aggregate.
- `lib/foglet_bbs/threads/thread.ex` — Schema fields `:last_post_at` (line 11) and `:deleted_at` (line 9) consumed by the new aggregate query. **No schema changes.**
- `lib/foglet_bbs/tui/widgets/list/list_row.ex` — Sibling reference; keeps current contract for non-BoardList callers.
- `lib/foglet_bbs/tui/widgets/list/selection_list.ex` — Sibling render pattern; canonical `▌` selection-marker reference.
- `lib/foglet_bbs/tui/widgets/list/smart_list.ex` — Sibling keyword-driven render pattern.
- `lib/foglet_bbs/tui/text_width.ex` — `display_width/1`, `slice_to_width/2`, `pad_to_width/2`. Mandatory for column width math, name truncation, and age-column right-alignment.
- `lib/foglet_bbs/time_ago.ex` (lines 22–29) — `Foglet.TimeAgo.format/1` consumed verbatim for the age column. No adapter, no new helper.
- `lib/foglet_bbs/tui/widgets/post/post_card.ex` (lines 163–198) — Existing TimeAgo consumer; reference precedent for how the helper is integrated.
- `lib/foglet_bbs/tui/theme.ex` (lines 106–241) — Theme slots `accent`, `info`, `badge`, `warning`, `dim`, `selected`, `unselected`. No new slots introduced.
- `lib/foglet_bbs/tui/widgets/chrome/screen_frame.ex` — `ScreenFrame.render/4` stays passive; `BoardList.render/1` continues calling it.

### Test Anchors
- `test/foglet_bbs/tui/widgets/list/board_tree_test.exs` — **NEW** widget-level test file (D-11).
- `test/foglet_bbs/tui/widgets/list/list_row_test.exs` — Sibling test pattern reference.
- `test/foglet_bbs/tui/widgets/list/selection_list_test.exs` — Sibling test pattern reference.
- `test/foglet_bbs/tui/widgets/list/smart_list_test.exs` — Sibling test pattern reference (state input shapes).
- `test/foglet_bbs/tui/screens/board_list_test.exs` — Existing screen tests; replace `[subscribed]`/`[required]`/`[unsubscribed]` assertions at lines 87–101, 155 with column-text + glyph assertions; add age-column assertions; preserve required-subscription feedback test at line 154.
- `test/foglet_bbs/tui/layout_smoke_test.exs` — Existing positioned-render harness. Add `describe "board_list — size contract"` block at `[{64,22},{80,24},{132,50}]`. Existing line 384 stub absorbed or preserved.
- `test/foglet_bbs/boards/boards_test.exs` (line 464 onward) — Existing `describe "board_directory_for/1 (SUBS-01)"` block; extend with `:last_post_at` cases.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `Foglet.TUI.Widgets.Display.Tree.{init/1, handle_event/2, render/2}` — Current stateful facade. BoardTree mirrors this shape, owning a Display.Tree internally for cursor/expand state (D-01).
- `Foglet.Boards.board_directory_for/1` (`boards.ex:243-271`) — Existing entry point; gains `:last_post_at` per D-09.
- `Foglet.Boards.unread_counts/1` (`boards.ex:511-526`) — Structural precedent for the new `last_post_ats/1` aggregate query. Single Repo.all, group_by, MAX/COUNT aggregate.
- `Foglet.TimeAgo.format/1` (`time_ago.ex:22-29`) — Already produces `"7m"`/`"3h"`/`"2d"` magnitudes. Consumed verbatim for the age column (D-06).
- `Foglet.TUI.TextWidth.display_width/1`, `slice_to_width/2`, `pad_to_width/2` — Width helpers for column alignment, name truncation, age-column padding.
- `Foglet.TUI.Theme` slots `accent`, `info`, `badge`, `warning`, `dim`, `selected`, `unselected` — No new slots.
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
- `BoardList.handle_key/2` is unchanged in surface — j/k/↑/↓/←/→/Enter/s/u/q/Q each route to the same outcome. Internally, key handlers may forward events to `BoardTree.handle_event/2` instead of `Display.Tree.handle_event/2`. The `:load_threads` command emission on Enter for board nodes is preserved.
- `App` routing and Phase 17 `:bbs` mode metadata for BoardList are unchanged.
- `Foglet.Boards.board_directory_for/1` callers (BoardList, Sysop boards screen, any future TUI consumer) all receive the new `:last_post_at` field. BoardList consumes it via D-09; Sysop boards screen (`lib/foglet_bbs/tui/screens/sysop/boards_view.ex`) is unaffected — it can ignore the new field until Phase 25 chooses to consume it.
- `Foglet.Threads.Thread.bump_counters/1` (`thread.ex:33-38`) keeps `:last_post_at` accurate on post inserts; no changes required to the bump path.

</code_context>

<specifics>
## Specific Ideas

- "Get rid of the details strip and show the age on each board row" — locked into D-04, D-06, D-07, D-08. SPEC.md requirement 4 is removed by this CONTEXT; the row gains an age column via `Foglet.TimeAgo.format/1` short form (`12m`/`2h`/`3d`/`—`).
- "Instead of subscribed, subscribe, and required, just use icons. lock unicode for required, checkmark unicode for subscribed, and plus sign for subscribe" — locked into D-02, D-04, D-10b, D-11, and `<acceptance_overrides>`. The subscription column is glyph-only; no text labels remain in row content.
- **Lock-glyph constraint:** No 1-cell padlock glyph exists in widely-supported BMP Unicode. The actual lock emoji `🔒` (U+1F512) renders as 2 cells on most terminals, breaking Phase 20's fixed-width cluster contract. The closest 1-cell BMP "locked / mandatory" glyph is `⚿` (U+26BF Squared Key) — locked here in D-04. Phase 20's locked-thread atom is also recommended to use `⚿` (per `20-CONTEXT.md` D-05 / Discretion); the cross-screen overlap ("you can't change this state") is intentional and consistent.
- The em-dash `—` (U+2014) is the explicit no-posts sentinel — chosen over empty cell or the word `new` to avoid ambiguity with unread state.
- `Foglet.TimeAgo.format/1` short form (`"7m"` etc.) is the exact format used — no `" ago"` suffix appended, no new helper module added. The existing `PostCard.get_time_ago/1` consumer (`post_card.ex:163-198`) is the integration precedent.
- Subscription feedback stays as the top-of-tree flash line via existing `maybe_feedback/2` — no migration to inline-row treatment, no migration to a row-level icon flash.
- 64x22 width math (D-05) leaves comfortable headroom: 60 (body) − 22 (fixed segments) − 2 (gap) = 36 cells available for the board name (vs. 20-cell minimum from Phase 20). The text-label form (`✓ subscribed` etc.) would have left only 24 cells; glyph-only frees ~12 cells.

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

*Phase: 21-board-directory-facelift*
*Context gathered: 2026-04-25*
