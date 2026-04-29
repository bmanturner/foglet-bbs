# Phase 44: PostReader And Content Query Hardening - Context

**Gathered:** 2026-04-29 (assumptions mode)
**Status:** Ready for planning

<domain>
## Phase Boundary

Phase 44 hardens PostReader and content query invariants so users can read a
1000-post thread without eager-loading every post, while maintainers have
automated protection for resize-cache, render-purity, and soft-delete
list-query behavior.

Locked requirements come from `44-SPEC.md`: PostReader must store only a
bounded active window plus navigation metadata, preserve next/previous and
`jump_last` reader navigation, evict stale terminal-width render-cache entries,
keep render helpers pure, and protect the split where reader/history queries
may include tombstones while list/summary paths hide soft-deleted content.
</domain>

<decisions>
## Implementation Decisions

### Bounded PostReader Loading
- **D-01:** Add a context-owned bounded post query for PostReader instead of
  making the screen slice a full `list_posts/1` result locally. The query
  boundary should be cursor/window based, preload `:user`, preserve
  tombstone-capable reader/history rows, and return navigation metadata such as
  direction and whether previous/next windows exist.
- **D-02:** Keep `Foglet.Posts.list_posts/1` tombstone-capable for the existing
  reader/history contract unless planning identifies a clearer name split such
  as keeping `list_posts/1` as history and adding an explicitly bounded reader
  variant. Do not make list/summary hiding depend on PostReader filtering.

### PostReader State Shape
- **D-03:** Keep `%Foglet.TUI.Screens.PostReader.State{}.posts` as the active
  bounded window for compatibility with existing render, pending-read,
  reply-navigation, and viewport helpers. Add explicit navigation/window
  metadata alongside it rather than replacing `posts` with an unrelated
  collection abstraction.
- **D-04:** The acceptance proof for the 1000-post target must verify both the
  domain call contract and state shape: the fake posts domain should observe
  bounded window/page requests, and `%PostReader.State{}.posts` must never
  contain all 1000 posts.

### Reader Navigation
- **D-05:** Preserve current reader key semantics: `n`, `space`, and
  `page_down` advance one post; `p` and `page_up` move one post backward; `j`
  and `k` scroll inside the selected post.
- **D-06:** Crossing the active window boundary should request the adjacent
  bounded window and land on the correct boundary post, preserving pending read
  pointer seeding for the post the user actually reaches.
- **D-07:** `load_intent: :jump_last` should request the newest bounded window
  from the domain and select the newest available post without first loading
  the full thread.
- **D-08:** Matching `:thread_activity` reloads must use the bounded loading
  contract and preserve the current reader position as well as practical,
  rather than resetting through a full-list reload.

### Resize Cache Eviction
- **D-09:** Evict stale-width `render_cache` entries in reducer/state plumbing
  when warming at the current terminal width. Render paths must remain
  read-only and must not mutate `%PostReader.State{}`.
- **D-10:** Keep the cache keyed by `{post_id, terminal_width}` unless planning
  proves a narrower key is simpler and still preserves correct wrapping. The
  required outcome is that active state contains no stale-width cache keys
  after resize-driven warming.

### Render-Purity Guard
- **D-11:** Preserve or strengthen the automated source/static guard that
  rejects state-write operations inside PostReader render helpers.
- **D-12:** If Phase 43 has already moved PostReader rendering into
  `Foglet.TUI.Screens.PostReader.Render`, move or expand the guard so it covers
  the active render boundary there. If render helpers still live in
  `post_reader.ex`, keep the guard focused on that file.

### Soft-Delete Query Policy
- **D-13:** Treat reader/history queries as tombstone-capable: soft-deleted
  posts remain available to PostReader so historical message numbers and gaps
  remain visible.
- **D-14:** Add explicit list/summary coverage or a shared helper proving that
  soft-deleted content is excluded from user-visible list surfaces that should
  hide it, especially `Threads.list_threads/1`, `Threads.list_threads/2`, board
  directory unread/last-post summaries, and existing `QueryHelpers.not_deleted/1`
  paths.
- **D-15:** Prefer `Foglet.QueryHelpers` or context-owned query helpers over new
  ad hoc `is_nil(deleted_at)` predicates in screens.

### the agent's Discretion
- Downstream agents may choose exact function names, option names, window size,
  cursor metadata shape, and test fake module names, provided the behavior is
  explicit, grep-friendly, and structurally tested.
- Downstream agents may choose whether bounded loading is implemented as
  `list_posts_window/2`, `list_posts_after/3`, `list_posts_before/3`, or a
  single option-driven reader function, as long as PostReader does not perform
  full-list loading for the large-thread path.
- Downstream agents may decide whether the render-purity guard remains a
  source-level ExUnit check or becomes a stronger shared/static helper.

### Folded Todos
No matching todos were folded into this phase.
</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

- `.planning/phases/44-postreader-and-content-query-hardening/44-SPEC.md`
- `.planning/phases/43-large-screen-decomposition/43-CONTEXT.md`
- `.planning/phases/42-app-runtime-helper-extraction/42-CONTEXT.md`
- `.planning/phases/41-tui-contract-and-modal-effects/41-CONTEXT.md`
- `.planning/ROADMAP.md`
- `.planning/REQUIREMENTS.md`
- `.planning/PROJECT.md`
- `.planning/codebase/CONCERNS.md`
- `.planning/codebase/CONVENTIONS.md`
- `.planning/codebase/TESTING.md`
- `docs/DATA_MODEL.md`
- `docs/raxol/getting-started/WIDGET_GALLERY.md`
- `lib/foglet_bbs/tui/widgets/README.md`
- `lib/foglet_bbs/tui/SCREEN_CONTRACT.md`
- `lib/foglet_bbs/tui/app.ex`
- `lib/foglet_bbs/tui/app/routing.ex`
- `lib/foglet_bbs/tui/context.ex`
- `lib/foglet_bbs/tui/effect.ex`
- `lib/foglet_bbs/posts.ex`
- `lib/foglet_bbs/posts/post.ex`
- `lib/foglet_bbs/threads.ex`
- `lib/foglet_bbs/boards.ex`
- `lib/foglet_bbs/query_helpers.ex`
- `lib/foglet_bbs/tui/screens/post_reader.ex`
- `lib/foglet_bbs/tui/screens/post_reader/state.ex`
- `lib/foglet_bbs/tui/widgets/post/post_card.ex`
- `lib/foglet_bbs/tui/widgets/post/markdown_body.ex`
- `test/foglet_bbs/tui/screens/post_reader_test.exs`
- `test/foglet_bbs/posts/posts_test.exs`
- `test/foglet_bbs/threads/threads_test.exs`
- `test/foglet_bbs/boards/boards_test.exs`
</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `Foglet.TUI.Context` carries route params, terminal size, current user, and
  domain overrides; PostReader tests already use domain override fakes for
  posts, boards, threads, and markdown.
- `Foglet.TUI.Effect.task/3` is the existing reducer-to-App path for async
  domain work and returns `{:task_result, op, result}` to the screen.
- `Foglet.TUI.Screens.PostReader.State` already owns loaded posts,
  `selected_post_index`, pending read positions, viewport state, render cache,
  load status, and `load_intent`.
- `Foglet.QueryHelpers.not_deleted/1` is the existing shared helper for
  hiding soft-deleted rows from list-style queries.
- `PostCard.reader_parts/6` and `MarkdownBody` are the existing render assets
  for reader body wrapping; this phase should preserve them rather than
  redesigning PostReader visuals.

### Established Patterns
- Screens own local reducer state and request domain work through effects;
  durable query and mutation rules belong in `Foglet.*` contexts.
- App forwards `{:thread_activity, thread_id, event}` to the active screen
  reducer; PostReader currently responds by reloading posts.
- PostReader currently warms render cache and viewport outside render helpers;
  render helpers read cache and may parse as fallback but do not write state.
- Existing tests favor reducer/effect/state assertions for PostReader, with a
  source-level render-purity guard already present.
- Domain tests use real context functions and Board Server setup so message
  number invariants remain realistic.

### Integration Points
- `PostReader.update(:load, ...)` and matching `:thread_activity` handling
  currently call `posts_mod.list_posts(thread_id)` through task effects.
- `PostReader.update({:task_result, :load_posts, {:ok, posts}}, ...)` currently
  assigns the full returned list into `%State{}.posts` and selects index `0` or
  the final index for `load_intent: :jump_last`.
- `advance_local_post/3`, `scroll_local_post/3`, `seed_pending_read_position/1`,
  `warm_selected_post/2`, and reply navigation all consume `%State{}.posts` and
  `selected_post_index`.
- App resize handling updates `state.terminal_size`; PostReader cache eviction
  will need to occur when reducer/cache warming receives the new size through
  `Context`.
- `Threads.list_threads/1,2` already apply `QueryHelpers.not_deleted/1`.
  `Boards.board_directory_for/1` derives unread counts and last-post timestamps
  through board/thread/post summary queries that should be protected by tests
  for deleted-content exclusion.
</code_context>

<specifics>
## Specific Ideas

- The 1000-post proof should use a fake posts domain that fails or records a
  violation if PostReader asks for the old unbounded `list_posts/1` path.
- Keep the reader experience as a post-by-post reader, not a redesigned feed or
  table.
- Treat Phase 44 as a hardening phase: no new browser UI, no visual redesign,
  no changed message-number semantics, and no broad context rewrite.
</specifics>

<deferred>
## Deferred Ideas

None - analysis stayed within phase scope.

### Reviewed Todos (not folded)
No matching todos were found for this phase.
</deferred>

---

*Phase: 44-postreader-and-content-query-hardening*
*Context gathered: 2026-04-29*
