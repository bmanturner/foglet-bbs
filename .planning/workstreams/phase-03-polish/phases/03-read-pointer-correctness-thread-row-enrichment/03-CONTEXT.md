# Phase 3: Read-pointer correctness + thread-row enrichment — Context

**Gathered:** 2026-04-19
**Status:** Ready for planning

<domain>
## Phase Boundary

Fix two categories of bugs in the board/thread list layer:
1. Board unread counts drift backward and go stale (LIST-01, LIST-02) — pure correctness work in the domain layer and App command dispatch
2. Thread rows show only title+unread count; enrich them with creator handle, post count, and last-activity time-ago (LIST-03)

No new domain features. No new runtime deps. Rendering happens in the existing `List.ListRow` / `List.SelectionList` widget layer from Phase 1.

</domain>

<decisions>
## Implementation Decisions

### Thread row layout

- **D-01:** Thread rows use a single line with right-aligned, variable-width metadata. Title occupies the left; metadata is right-aligned in a column whose width adapts to its content.
- **D-02:** Metadata format: `@handle · N posts · Xh ago` (all three pieces, separated by `·`). Width is content-driven — no fixed metadata column. Handle is the `created_by.handle` value from the preloaded association.
- **D-03:** When title + gap + metadata exceeds terminal width, the **title truncates** (with `…`) to preserve the full metadata. Metadata must always be fully visible. Minimum title display: ~20 chars before the `…` kicks in.
- **D-04:** Threads with unread posts display their **title in bold**. No numeric unread count appears on thread rows. Threads fully read (or with no unread) show normal-weight title.

### Read-on-entry behavior

- **D-05:** When a user opens a thread (enters PostReader), the read position for that thread is **immediately initialized** to post 0's `{post_id, message_number}` — even before any navigation. This means pressing Q immediately after entry still advances the board read pointer past the first post. Subsequent j/k navigation updates the pointer normally.

### Board refresh timing (LIST-02)

- **D-06:** Two-phase refresh strategy:
  1. Dispatch `{:load_boards}` immediately when the user presses Q in `ThreadList` (before navigating to board_list). This triggers a board data reload with the pre-flush DB state so the board list isn't stale on arrival.
  2. `do_update({:read_pointers_flushed, thread_id}, state)` also dispatches `{:load_boards}` when `state.current_screen == :board_list`, so counts update again after the async flush completes. This second refresh ensures counts are accurate once the DB write lands.

### Board read pointer monotonicity (LIST-01)

### Claude's Discretion
- **GREATEST fix:** `Foglet.Boards.advance_board_read_pointer/3` must use `GREATEST` in the upsert conflict resolution so the pointer only ever advances: `on_conflict: [set: [last_read_message_number: fragment("GREATEST(board_read_pointers.last_read_message_number, ?)", ^message_number)]]`. Current code overwrites unconditionally, which allows reading thread B (msg 1) after thread A (msg 3) to regress the pointer.
- **Thread unread detection:** To apply the bold-on-unread treatment (D-04), `list_threads/1` or a sibling function needs to annotate each thread with whether it has unread posts for the current user. The planner should choose among: (A) add `user_id` param to `list_threads` and JOIN with `thread_read_pointers`, (B) separate query for the user's thread pointers and merge in Elixir, (C) compare `thread.last_post_at > thread_read_pointer.last_read_at`. Approach A is cleanest; approaches B/C avoid changing the `list_threads/1` signature. Constraint: the resulting thread structs need a virtual field (e.g. `has_unread: boolean`) that `ListRow` can read.
- **TimeAgo format:** Exactly as specified in REQUIREMENTS.md: `30s`, `5m`, `2h`, `3d`, `2w`, `6mo`, `2y`. Module `Foglet.TimeAgo` is delivered by Phase 1 (WIDGET-02). Phase 3 only calls it.
- **Thread row rendering:** Use `List.ListRow` / `List.SelectionList` from Phase 1. The `row_renderer` prop receives a thread struct and must produce a single-line element with right-aligned metadata. Terminal width is available via `state.terminal_size` — pass it through to the row renderer.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Workstream Requirements and Roadmap
- `.planning/workstreams/phase-03-polish/REQUIREMENTS.md` — LIST-01, LIST-02, LIST-03 requirements; locked decisions; explicit "no new deps" constraint
- `.planning/workstreams/phase-03-polish/ROADMAP.md` — Phase 3 success criteria, dependency on Phase 1 + Phase 2

### Prior Phase Context
- `.planning/workstreams/phase-03-polish/phases/01-widget-foundation-theme-screen-chrome/01-CONTEXT.md` — Widget namespace (`List.SelectionList`, `List.ListRow`), theme slots, `Foglet.TimeAgo` stub (WIDGET-02), SelectionList API (row_renderer prop)
- `.planning/workstreams/phase-03-polish/phases/02-markdown-rendering-correctness/02-CONTEXT.md` — PostCard pipeline (not in Phase 3 scope, but don't break it)

### Raxol DSL Constraint
- `memory/feedback_raxol_modern_dsl.md` — CRITICAL: function-form widget constraint. Use `column/row/box do...end` block macros only.

### Code to Modify
- `lib/foglet_bbs/tui/screens/thread_list.ex` — Q handler (add `{:load_boards}`), `render_thread_row/3` (enrich with metadata), `load_threads/2` (pass user for unread detection)
- `lib/foglet_bbs/tui/screens/post_reader.ex` — `handle_key("q")` and `load_posts/2` (initialize read_position on entry per D-05)
- `lib/foglet_bbs/tui/app.ex` — `do_update({:read_pointers_flushed, ...})` (add `{:load_boards}` when on board_list), `do_update({:load_threads, ...})`
- `lib/foglet_bbs/boards.ex` — `advance_board_read_pointer/3` (GREATEST fix for LIST-01 monotonicity)
- `lib/foglet_bbs/threads.ex` — `list_threads/1` or new sibling (add user_id for unread annotation)
- `lib/foglet_bbs/tui/widgets/list/` — `ListRow` row_renderer must support metadata right-alignment and bold-on-unread

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `Foglet.Boards.unread_counts/1` — batch query; already correct. Phase 3 relies on it; the fix is in `advance_board_read_pointer/3` not in `unread_counts`.
- `Thread` schema already has `post_count: integer` (default 1) and `belongs_to :created_by`. `list_threads/1` already preloads `[:created_by]`. No schema changes needed for LIST-03.
- `Foglet.TimeAgo` — provided by Phase 1. Phase 3 calls `Foglet.TimeAgo.format(thread.last_post_at)`.

### Established Patterns
- `state.terminal_size` is `{cols, rows}` — available for row width calculations
- Thread row rendering uses `Raxol.Core.Renderer.View` macros. Right-alignment within a fixed terminal width requires computing padding manually (no flexbox).
- `state.screen_state[:thread_list]` holds `%{selected_index: integer}` — already the SelectionList ownership pattern from Phase 1.

### Integration Points
- `ThreadList.handle_key("q")` at `thread_list.ex:100` — add `{:load_boards}` to the commands list
- `App.do_update({:read_pointers_flushed, ...})` at `app.ex:427` — add conditional `{:load_boards}` dispatch
- `PostReader.load_posts/2` at `post_reader.ex:101` — after loading posts, initialize read_position for post 0
- `Boards.advance_board_read_pointer/3` at `boards.ex:186` — GREATEST fix in upsert conflict

### Known Stubs (from Phase 1 planning)
- `Post.MarkdownBody.render/3` and `Post.PostCard.render/3` currently have `none()` Dialyzer success typing — they are Phase 1 stubs awaiting Phase 2 implementation. Phase 3 must not touch them.

</code_context>

<specifics>
## Specific Ideas

- Thread row example at 80 cols (selected row): `"> Thread title that may be lon…   @alice · 5 posts · 2h ago"`
- Thread row example at 80 cols (unread, unselected): bold title, dim metadata
- "mark first post as seen on entry" — user's language for D-05. It's a UX expectation: if you saw it, you read it.
- Two-phase board refresh is intentional UX design, not a workaround: the immediate refresh prevents jarring stale counts on landing, the post-flush refresh corrects them accurately.

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 03-read-pointer-correctness-thread-row-enrichment*
*Context gathered: 2026-04-19*
