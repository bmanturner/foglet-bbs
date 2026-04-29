# Phase 44: PostReader And Content Query Hardening - Specification

**Created:** 2026-04-29
**Ambiguity score:** 0.152 (gate: <= 0.20)
**Requirements:** 5 locked

## Goal

Users can read a 1000-post thread through PostReader without eager-loading every post, while maintainers have automated protection for resize-cache, render-purity, and soft-delete list-query invariants.

## Background

The v2.1 concerns audit identifies four related risks around PostReader and content queries. `Foglet.Posts.list_posts/1` currently returns every post for a thread in one query, ordered by `inserted_at` and preloaded with `:user`; `Foglet.TUI.Screens.PostReader` calls that API on route entry and thread activity, then stores the full returned list in `%PostReader.State{}.posts`. The same screen stores parsed Markdown in `%PostReader.State{}.render_cache` keyed by `{post.id, terminal_width}`, so resizing from one width to another leaves stale-width entries alive until the reader exits. The PostReader moduledoc documents that `defp render_*` helpers must not mutate state, and tests already contain a source-level purity guard, but Phase 44 should preserve or strengthen that invariant as part of the hardened contract. Soft deletion is intentionally historical inside a thread: current tests assert that `Posts.list_posts/1` includes deleted posts so PostReader can preserve message-number continuity. Other list and summary paths use `Foglet.QueryHelpers.not_deleted/1` or equivalent filters and need explicit protection against accidentally showing deleted content.

## Requirements

1. **Bounded large-thread loading**: PostReader must read a 1000-post thread without storing all 1000 posts in screen-local state.
   - Current: `PostReader.update(:load, ...)` and thread-activity reload paths call the posts domain module's full `list_posts(thread_id)` API, and loaded task results assign the entire returned list to `%PostReader.State{}.posts`.
   - Target: The PostReader large-thread path stores only a bounded active window of posts plus the navigation metadata needed to continue reading.
   - Acceptance: A focused PostReader test using a fake posts domain for a 1000-post thread proves the screen asks for bounded windows/pages and never populates `%PostReader.State{}.posts` with all 1000 posts.

2. **Reader navigation preserved**: Bounded loading must preserve required reader navigation for next post, previous post, and jump-to-last route entry.
   - Current: PostReader supports next/previous navigation through local list indexes, and `load_intent: :jump_last` selects the final post after a full-list load.
   - Target: Users can move to the next and previous post across loaded-window boundaries, and opening PostReader with jump-last intent lands on the newest available post without requiring a full-thread list in state.
   - Acceptance: Focused reducer tests cover next, previous, and jump-last behavior across a bounded-window boundary without asserting only for static rendered text.

3. **Resize cache eviction**: PostReader must not retain stale-width render-cache entries after terminal resize during a session.
   - Current: `render_cache` entries are keyed by `{post.id, width}`; tests currently prove that warming at width 80 and then width 40 leaves both widths in the cache until the screen exits.
   - Target: After resize-driven warming at a new terminal width, PostReader keeps cache entries for the current width and removes entries for stale widths from the active screen state.
   - Acceptance: A PostReader cache test warms a post at one width, changes terminal width, warms again, and verifies the resulting `render_cache` has current-width entries and no stale-width keys.

4. **Render-path purity protected**: Automated protection must prevent PostReader render helpers from mutating screen state.
   - Current: The moduledoc says `defp render_*` helpers must not write state, and a source-level test scans render helper bodies for forbidden write patterns.
   - Target: The render-purity protection remains automated and covers the active PostReader render boundary after this phase's loading/cache changes, whether render helpers stay in `post_reader.ex` or move to a sibling render module first.
   - Acceptance: A test or static check fails if a PostReader render helper performs screen-state writes such as `put_in`, `Map.put`, or `%{state | ...}` inside the render path.

5. **Soft-delete list policy protected**: Soft-deleted posts must remain visible only in the reader path that preserves thread history, while list/summary paths that should hide deleted content must have explicit coverage or a shared helper.
   - Current: `Posts.list_posts/1` includes deleted posts, and tests assert that behavior; thread and board list-style queries rely on `QueryHelpers.not_deleted/1` or local `is_nil(deleted_at)` predicates.
   - Target: The codebase has an explicit query boundary or focused tests proving that reader/history queries may include tombstones while list/summary queries hide soft-deleted posts.
   - Acceptance: Tests demonstrate that a deleted post is still available to the PostReader/history path as a tombstone-capable row, and that at least the affected list/summary query paths exclude deleted posts.

## Boundaries

**In scope:**
- Define and enforce a bounded PostReader loading contract for 1000-post threads.
- Preserve required PostReader next, previous, and jump-last reading behavior under bounded loading.
- Evict or prevent stale terminal-width render-cache entries in active PostReader state.
- Preserve or strengthen automated render-path purity protection for PostReader.
- Add query coverage or a shared helper that protects the soft-delete visibility split between reader/history paths and list/summary paths.
- Add focused tests that verify behavior structurally rather than by static text presence.

**Out of scope:**
- New end-user browser workflows - Foglet remains SSH-first and terminal-native.
- Changing thread message-number semantics - message numbers remain stable and historical.
- Hiding soft-deleted posts from PostReader/history views entirely - tombstone-capable reader history remains intentional.
- Reworking unrelated TUI screens - Phase 44 is scoped to PostReader and content query invariants.
- Replacing Raxol, changing shared widget contracts, or redesigning PostReader visuals - this phase hardens behavior, not presentation.
- Broad domain context rewrites - any query helper changes must stay focused on the listed invariants.
- Pure text-presence tests - project testing rules reject tests that only assert text exists or does not exist.

## Constraints

- Post creation and message-number allocation must continue routing through `Foglet.Boards.Server`; Phase 44 must not alter allocation semantics.
- Read pointers remain monotonic persisted user state and must continue advancing through the owning contexts.
- PostReader render functions remain pure over already-loaded state and context-derived render data.
- Route colors and display styling through `Foglet.TUI.Theme` and existing widgets if render code is touched.
- Soft-deleted posts preserve message numbers; reader/history behavior should support tombstones rather than compacting gaps.
- Prefer existing `Foglet.QueryHelpers` or context-owned query boundaries over ad hoc deleted-content predicates scattered through screens.

## Acceptance Criteria

- [ ] A fake-domain PostReader test proves a 1000-post thread is read through bounded windows/pages and `%PostReader.State{}.posts` never contains all 1000 posts.
- [ ] Next-post and previous-post navigation work across a bounded-window boundary.
- [ ] `load_intent: :jump_last` opens the newest available post without requiring all posts to be loaded into screen state.
- [ ] PostReader resize/cache coverage proves stale terminal-width cache keys are removed or impossible after warming at the new width.
- [ ] Automated render-path purity protection covers the active PostReader render boundary and fails on state writes inside render helpers.
- [ ] Reader/history query coverage proves deleted posts remain available where tombstone history is required.
- [ ] List/summary query coverage or a shared query helper proves soft-deleted posts are excluded from paths that should hide them.
- [ ] Focused tests avoid pure text-presence assertions.
- [ ] `rtk mix precommit` passes after implementation.

## Ambiguity Report

| Dimension           | Score | Min   | Status | Notes |
|---------------------|-------|-------|--------|-------|
| Goal Clarity        | 0.91  | 0.75  | met    | 1000-post target and invariant categories are named. |
| Boundary Clarity    | 0.84  | 0.70  | met    | Reader/history tombstones and list/summary hiding are separated. |
| Constraint Clarity  | 0.78  | 0.65  | met    | Resize cache, render purity, read pointers, and message-number constraints are explicit. |
| Acceptance Criteria | 0.82  | 0.70  | met    | Bounded loading, navigation, cache, purity, and soft-delete checks are pass/fail. |
| **Ambiguity**       | 0.152 | <=0.20| met    | Gate passed after round 2. |

Status: met = meets minimum, below = planner treats as assumption

## Interview Log

| Round | Perspective | Question summary | Decision locked |
|-------|-------------|------------------|-----------------|
| 1 | Researcher | What concrete large-thread target should Phase 44 protect for PostReader? | Use a 1000-post thread target. |
| 1 | Researcher | Should PostReader continue showing soft-deleted posts as tombstones while other list paths hide them? | Yes. Reader/history paths keep tombstone-capable rows; list/summary paths hide deleted content. |
| 1 | Researcher | What should be true after terminal resize? | After resize-driven warming, `render_cache` contains no entries for stale terminal widths. |
| 2 | Researcher + Simplifier | What is the irreducible loading outcome for a 1000-post thread? | PostReader state holds only a bounded active window plus navigation metadata, never all 1000 posts. |
| 2 | Researcher + Simplifier | Which navigation remains required? | Next, previous, and jump-last route entry remain required. |
| 2 | Researcher + Simplifier | What proof should acceptance require for avoiding eager loads? | Use a fake domain call contract proving bounded window/page requests and no full-list state population. |

---

*Phase: 44-postreader-and-content-query-hardening*
*Spec created: 2026-04-29*
*Next step: $gsd-discuss-phase 44 - implementation decisions (how to build what is specified above)*
