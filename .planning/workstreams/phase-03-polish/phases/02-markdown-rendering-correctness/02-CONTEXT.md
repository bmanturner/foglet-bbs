# Phase 2: Markdown rendering correctness — Context

**Gathered:** 2026-04-19
**Status:** Ready for planning

<domain>
## Phase Boundary

Fill in the `Post.MarkdownBody` and `Post.PostCard` widget stubs created in Phase 1 and fix the two confirmed bugs in the rendering pipeline. No new markdown features, no new deps, no database changes. Rendering happens at view time (not pre-rendered to DB).

**Known root-cause bugs to fix:**
1. `render_markdown_tuples/1` in `PostReader` maps every tuple (including `{"\n", :plain}` separators) to a `text/2` node, making newlines render as visible characters or layout artifacts instead of driving structure.
2. All `text/2` calls use `fg: :green` hardcode — Phase 1 fixes this globally, but `Post.MarkdownBody` must use theme slots from `session_context.theme`.

</domain>

<decisions>
## Implementation Decisions

### Widget pipeline ownership

- **D-01:** `Post.PostCard` owns the full per-post rendering pipeline. Call site: `PostCard.render(%{post: post, width: integer, theme: theme})`. PostCard assembles the author header (handle + timestamp), a divider, and the `Post.MarkdownBody` body section. PostReader calls PostCard once per displayed post — not MarkdownBody directly.
- **D-02:** The planner decides whether PostCard calls `Foglet.Markdown.render/1` internally or delegates that to `Post.MarkdownBody`. Both are valid; the key constraint is that `Post.MarkdownBody` receives enough information to lay out the rendered tuples with the correct theme and width.

### Newline-to-layout mapping

### Claude's Discretion
- **Newline layout strategy:** The planner should research and choose among: (A) filter `{"\n", :plain}` tuples and replace with `spacer()`, (B) group tuples between newline markers into line-groups and emit one styled `text/2` per physical line, or (C) change `Foglet.Markdown.render/1` contract to return `[[{text, style}]]` (list-of-lines). All three are viable. Constraint: the fix must eliminate visible `\n` artifacts in the PostReader without breaking existing `Foglet.Markdown` tests.
- **Wrapping strategy:** The planner must first verify whether Raxol's `text/2` inside a `column do` word-wraps at the terminal boundary automatically. If it does, trust it (zero implementation cost). If it clips or overflows, implement pre-wrapping in `Post.MarkdownBody` at `width` chars using grapheme-cluster-aware splitting. Code blocks (2-space indent) are the most likely overflow candidates — special-case them if needed.

### Within-post scrolling

- **D-03:** Add j/k within-post scroll to `PostReader`. `scroll_offset` lives in `state.screen_state[:post_reader]` alongside the existing `selected_post_index`.
- **D-04:** j scrolls down one line, k scrolls up one line. N/P keys navigate between posts (existing behavior) and always reset `scroll_offset` to 0.
- **D-05:** `Post.MarkdownBody` (or `PostCard`) accepts a `scroll_offset` prop and renders only the lines from `scroll_offset` to `scroll_offset + available_height`. The widget does NOT own the scroll offset — PostReader owns it in screen_state.

### Memoization

### Claude's Discretion
- **Memoization cache key:** Cache rendered output keyed on `{post.id, width}` (posts are immutable in v1.0.1 — no `updated_at` field). Cache lives in `state.screen_state[:post_reader][:render_cache]`. The planner decides whether memoization happens inside PostCard or in PostReader before calling PostCard.

### Theme

- **D-06:** `Post.MarkdownBody` maps style atoms to theme slots:
  - `:bold` → `theme.accent` (or `theme.primary` with `style: [:bold]` — planner decides which reads better)
  - `:italic` → `theme.primary` with `style: [:italic]`
  - `:dim` (inline code, code blocks) → `theme.dim`
  - `:underline` (headings) → `theme.title` with `style: [:underline]`
  - `:plain` → `theme.primary`
  No `fg: :green` anywhere in Phase 2 output.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Workstream Requirements and Roadmap
- `.planning/workstreams/phase-03-polish/REQUIREMENTS.md` — RENDER-01, RENDER-02 requirements; locked decisions (view-time rendering, no new deps, no `body_rendered` column)
- `.planning/workstreams/phase-03-polish/ROADMAP.md` — Phase 2 success criteria, dependency on Phase 1

### Phase 1 Context (read before planning Phase 2)
- `.planning/workstreams/phase-03-polish/phases/01-widget-foundation-theme-screen-chrome/01-CONTEXT.md` — Theme slots, widget namespace, `Post.MarkdownBody` + `Post.PostCard` stub decisions (D-10, D-11), SelectionList API

### Raxol DSL Constraint
- `memory/feedback_raxol_modern_dsl.md` — CRITICAL: function-form widget constraint. Use `column/row/box do...end` block macros only. No `use Raxol.UI.Components.Base.Component`, no `Raxol.UI.Components.MarkdownRenderer` (tuple-shape output — incompatible).

### Existing Code to Modify
- `lib/foglet_bbs/markdown.ex` — `Foglet.Markdown.render/1` source; `clean_tuples/1` newline deduplication logic. The planner should read this before deciding the newline layout approach.
- `lib/foglet_bbs/tui/screens/post_reader.ex` — `render_markdown_tuples/1` (to be replaced by PostCard call), `render_post_items/3`, `handle_key/2` (j/k scroll keys to add), `screen_state` shape for `:post_reader`.
- `lib/foglet_bbs/tui/widgets/` — location of existing flat widgets; `Post.MarkdownBody` + `Post.PostCard` stubs will be at `lib/foglet_bbs/tui/widgets/post/`.

### Research
- `.planning/workstreams/phase-03-polish/research/SUMMARY.md` §Key Findings — confirms MDEx already in mix.exs, `Raxol.UI.Components.MarkdownRenderer` incompatibility, and the specific `render_markdown_tuples` bug description.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `Foglet.Markdown.render/1` — already correct: parses CommonMark + GFM via MDEx, returns `[{text, style_atom}]`, strips ANSI injection, deduplicates consecutive newlines. No changes required unless newline contract is changed (Option C).
- `PostReader.render_post_items/3` — current integration point (lines 180–199 in `post_reader.ex`). Phase 2 replaces the `render_markdown_tuples/1` call here with `PostCard.render/1`.
- Theme struct from Phase 1 — available at `state.session_context.theme` (or default via `Foglet.TUI.Theme.default()`).

### Established Patterns
- All screens use `import Raxol.Core.Renderer.View` for `box/column/row/text/divider` macros — `Post.MarkdownBody` and `Post.PostCard` follow this same pattern.
- `MultiLineInput.render/2` is already NOT called in the codebase (composer uses its state struct but renders manually) — confirms the "use Raxol state machinery, render yourself" pattern.
- `state.screen_state[:post_reader]` already contains `%{selected_post_index: integer}` — extend this map with `scroll_offset: 0` and `render_cache: %{}`.

### Integration Points
- `PostReader.render_post_items/3` at `post_reader.ex:180` — replace `render_markdown_tuples(markdown_mod.render(body))` with `Post.PostCard.render(%{post: post, width: w, theme: theme, scroll_offset: scroll_offset})`
- `PostReader.handle_key/2` — add j/k clauses before the existing fallback `:no_match`
- `PostReader.advance_post/2` — reset `scroll_offset: 0` in screen_state when changing posts
- `state.terminal_size` — already tracked as `{w, h}`; pass `w` to PostCard, use `h - chrome_height` for available lines

</code_context>

<specifics>
## Specific Ideas

- User explicitly prefers `PostCard` as the integration unit — "a post card is a complete unit." This mirrors classic BBS post display where each post is a visually bounded block.
- j/k scroll was chosen specifically because long seeded posts (markdown-heavy threads in the General board) would be unreadable without it at typical terminal heights.
- Planner must verify Raxol `text/2` word-wrap behavior empirically (not assumed) before choosing wrapping strategy.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 02-markdown-rendering-correctness*
*Context gathered: 2026-04-19*
