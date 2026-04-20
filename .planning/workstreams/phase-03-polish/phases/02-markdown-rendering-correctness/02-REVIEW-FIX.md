---
phase: 02-markdown-rendering-correctness
fixed_at: 2026-04-20T00:00:00Z
review_path: .planning/workstreams/phase-03-polish/phases/02-markdown-rendering-correctness/02-REVIEW.md
iteration: 1
fix_scope: all
findings_in_scope: 5
fixed: 5
skipped: 0
status: all_fixed
---

# Phase 02: Code Review Fix Report

**Fixed at:** 2026-04-20T00:00:00Z
**Source review:** .planning/workstreams/phase-03-polish/phases/02-markdown-rendering-correctness/02-REVIEW.md
**Iteration:** 1

**Summary:**
- Findings in scope: 5
- Fixed: 5
- Skipped: 0

## Fixed Issues

### WR-01: Render cache never warmed via render/1

**Files modified:** `lib/foglet_bbs/tui/screens/post_reader.ex`
**Commit:** 9941d94
**Applied fix:** Added `warm_cache_for_index/5` private helper and called it from `load_posts/2` after fetching posts. This warms the render cache for the first post (index 0) at load time, so `render_post_content/5` finds a cache hit on the very first frame rather than calling `parse_body/2` on every terminal refresh before any keypress. The `render/1` function remains pure — the cache population happens in the stateful `load_posts/2` path which already returns updated state.

---

### WR-02: post.body accessed via dot syntax on potentially struct-typed value

**Files modified:** `lib/foglet_bbs/tui/screens/post_reader.ex`
**Commit:** e3013c3
**Applied fix:** Replaced `post.body` with `Map.get(post, :body)` at the `body_line_count` call in `scroll_post/2`. This fix was applied as part of a prior phase-03 fix commit (e3013c3 — CR-01 guard nil last_read_post_id) which touched the same file; the change was present in the repository when this fixer ran and is confirmed in the source at line 307. No additional commit was needed.

---

### WR-03: defmodule EmptyPosts defined inside a test block

**Files modified:** `test/foglet_bbs/tui/screens/post_reader_test.exs`
**Commit:** a1ba5be
**Applied fix:** Moved `defmodule EmptyPosts` from inside the `test "empty posts list..."` block to module level alongside `FakePosts`, `FakeBoards`, `FakeThreads`, and `FakeMarkdown`. The test body now references the module-level definition. All 30 post_reader tests pass.

---

### IN-01: Redundant max(scroll_offset, 0) in window_lines/3

**Files modified:** `lib/foglet_bbs/tui/widgets/post/markdown_body.ex`
**Commit:** 6207b5e
**Applied fix:** Added `and scroll_offset >= 0` to the guard of the `is_integer(max_lines)` clause of `window_lines/3`, and removed the now-redundant `max(scroll_offset, 0)` clamp from the `Enum.drop` call. The guard makes the caller contract explicit — callers are responsible for clamping — rather than silently coercing negative values. All 20 markdown_body tests pass.

---

### IN-02: "By @unknown" fallback is misleading

**Files modified:** `lib/foglet_bbs/tui/widgets/post/post_card.ex`
**Commit:** 2e25340
**Applied fix:** Replaced the wildcard arm `_ -> "By @unknown"` in `author_line/1` with `_ -> "(post details unavailable)"`. The original string falsely implied an author with the handle "unknown"; the new string neutrally conveys that the data is absent. All 18 post_card tests pass.

---

_Fixed: 2026-04-20T00:00:00Z_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
