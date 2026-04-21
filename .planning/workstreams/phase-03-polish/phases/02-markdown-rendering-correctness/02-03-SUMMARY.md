---
phase: 2-markdown-rendering-correctness
plan: 03
subsystem: [ui, rendering, navigation]
tags: [raxol, post-reader, scroll, cache, theme, tui]

requires:
  - phase: 2-markdown-rendering-correctness
    provides: Post.MarkdownBody (Plan 01), Post.PostCard (Plan 02)
provides:
  - PostReader integration via PostCard.render_from_tuples/5
  - j/k within-post scroll with bounded scroll_offset
  - Per-screen render cache keyed on {post.id, width}
  - Legacy state migration via get_screen_state/1
affects: [terminal-size-gate, thread-list]

tech-stack:
  added: []
  patterns:
    - "Per-screen render cache: %{{post_id, width} => tuples} in screen_state"
    - "available_height = max(h - 10, 5) for scroll bounds"
    - "get_screen_state/1 merges defaults over existing keys for backward compat"

key-files:
  created: []
  modified:
    - lib/foglet_bbs/tui/screens/post_reader.ex
    - test/foglet_bbs/tui/screens/post_reader_test.exs

key-decisions:
  - "Cache keyed on {post.id, width} — resize evicts stale entries by lookup miss (RENDER-02)"
  - "Posts immutable in v1.0.1 so no updated_at in cache key"
  - "D-04: N/P resets scroll_offset to 0; no Space/b page-scroll in Phase 2"
  - "available_height = max(h - 10, 5) — Phase 5 introduces proper too-small gate"

patterns-established:
  - "Screen-state default merging for backward compatibility across deploys"
  - "warm_cache/4 pattern: lazy population on key handlers, read-through on render"

requirements-completed: [RENDER-01, RENDER-02]

duration: 25min
completed: 2026-04-20
---

# Plan 02-03: PostReader Integration Summary

**PostCard + j/k within-post scroll + per-screen render cache — replaces legacy inline markdown rendering with widget pipeline, adds bounded scroll navigation**

## Performance

- **Duration:** ~25 min
- **Started:** 2026-04-20T12:15:00Z
- **Completed:** 2026-04-20T12:40:00Z
- **Tasks:** 3
- **Files modified:** 2

## Accomplishments
- PostReader now delegates all per-post rendering to PostCard.render_from_tuples/5
- j/k scroll keys advance/decrement scroll_offset bounded by max(total_lines - available_height, 0)
- N/P navigation resets scroll_offset to 0 (D-04)
- Per-screen render cache keyed on {post.id, width} — terminal resize evicts stale entries
- get_screen_state/1 merges defaults for backward compat with pre-Phase-2 state shapes
- Legacy render_markdown_tuples/2, render_post_items/4, get_post_author/1 deleted
- 16 new tests: RENDER-01 (no \n artifacts), RENDER-02 (resize), j/k scroll, cache, legacy migration, seed-fixture UAT smoke

## Task Commits

1. **Task 1: Rewrite post_reader.ex** — `24c5cc6` (feat)
2. **Task 2+3: Extend post_reader_test.exs** — `24c5cc6` (test, same commit)

## Files Created/Modified
- `lib/foglet_bbs/tui/screens/post_reader.ex` — Rewrote: render/1 now passes {w,h}, render_post_content/5 uses PostCard + cache, j/k scroll handlers, warm_cache, scroll_post, get_screen_state, default_screen_state. Deleted: render_markdown_tuples/2, render_post_items/4, get_post_author/1
- `test/foglet_bbs/tui/screens/post_reader_test.exs` — Added 16 new tests in 6 describe blocks while preserving all 9 original tests

## Decisions Made
- Followed plan for cache key shape, scroll bounds formula, and state migration strategy
- Test fixtures adjusted: used smaller terminal height (12 rows) for scroll tests since default 24 rows shows all content without scrolling

## Deviations from Plan

### Auto-fixed Issues

**1. Test fixture adjustment for scroll tests**
- **Found during:** Task 2 (post_reader_test.exs)
- **Issue:** Plan's test bodies (5-10 lines) fit within default available_height of 14 (from 24-row terminal), so j/k had no scroll range
- **Fix:** Used `terminal_size: {80, 12}` in scroll tests → available_height = max(12-10, 5) = 5, making 8-line bodies scrollable
- **Files modified:** test/foglet_bbs/tui/screens/post_reader_test.exs
- **Verification:** All 25 tests pass including scroll offset assertions
- **Committed in:** 24c5cc6 (Task 2+3 commit)

---

**Total deviations:** 1 auto-fixed (test fixture sizing)
**Impact on plan:** None — plan's scroll logic is correct, just needed appropriate test data

## Issues Encountered
- None beyond the test fixture sizing noted above

## User Setup Required
None

## Next Phase Readiness
- Phase 2 (Markdown rendering correctness) is complete
- Phase 3 (Read-pointer correctness + thread-row enrichment) depends on Phase 2 via readable posts — ready to execute
- PostReader's cache and scroll infrastructure can be reused by future screens

---
*Phase: 2-markdown-rendering-correctness*
*Completed: 2026-04-20*
