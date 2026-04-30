---
phase: 44-postreader-and-content-query-hardening
reviewed: 2026-04-30T01:11:45Z
depth: standard
files_reviewed: 9
files_reviewed_list:
  - lib/foglet_bbs/posts.ex
  - lib/foglet_bbs/posts/reader_window.ex
  - lib/foglet_bbs/threads.ex
  - lib/foglet_bbs/tui/screens/post_reader.ex
  - lib/foglet_bbs/tui/screens/post_reader/state.ex
  - test/foglet_bbs/boards/boards_test.exs
  - test/foglet_bbs/posts/posts_test.exs
  - test/foglet_bbs/threads/threads_test.exs
  - test/foglet_bbs/tui/screens/post_reader_test.exs
findings:
  critical: 1
  warning: 0
  info: 0
  total: 1
status: issues_found
---

# Phase 44: Code Review Report

**Reviewed:** 2026-04-30T01:11:45Z
**Depth:** standard
**Files Reviewed:** 9
**Status:** issues_found

## Summary

Reviewed the bounded post reader/query changes and the thread read-pointer timestamp fix. The stale-conflict branch in `advance_thread_read_pointer/3` now preserves both `last_read_post_id` and `last_read_at`, and the winning-conflict branch updates both fields together. However, unread semantics still have a correctness bug because thread activity timestamps are generated separately from the winning post timestamp used for `last_read_at`.

## Critical Issues

### CR-01: Reading the latest post can still leave the thread marked unread

**File:** `lib/foglet_bbs/threads.ex:286`

**Issue:** `advance_thread_read_pointer/3` sets `last_read_at` to the winning post's `inserted_at`, and `list_threads/2` later decides unread state with `t.last_post_at > trp.last_read_at` at lines 132-134. But post creation sets `threads.last_post_at` with a separate `DateTime.utc_now()` after inserting the post (`Foglet.Threads.Thread.bump_counters/1` / `set_first_post/2`). That timestamp can be microseconds later than the post's `inserted_at`, so a user who advances the thread pointer to the actual latest post can still see `has_unread: true`. The current tests avoid this by manually setting `last_read_at` into the future, so they do not prove the real up-to-date path.

**Fix:**
Use one canonical activity timestamp for both the last post and the thread. For example, update thread counter helpers to accept the inserted post timestamp and persist that as `last_post_at`, then keep the pointer's `last_read_at` as the post timestamp:

```elixir
# lib/foglet_bbs/threads/thread.ex
def bump_counters(thread, %Foglet.Posts.Post{inserted_at: inserted_at}) do
  change(thread, %{
    post_count: thread.post_count + 1,
    last_post_at: inserted_at
  })
end

def set_first_post(thread, %Foglet.Posts.Post{id: post_id, inserted_at: inserted_at}) do
  change(thread, %{first_post_id: post_id, last_post_at: inserted_at})
end
```

Then call those helpers with the inserted `post` from `Foglet.Boards.Server`. Add a regression test that creates a real latest post, calls `Foglet.Threads.advance_thread_read_pointer(reader.id, thread.id, latest_post.id)`, and asserts `Foglet.Threads.list_threads(board.id, reader.id)` returns `has_unread: false` without manually altering timestamps.

---

_Reviewed: 2026-04-30T01:11:45Z_
_Reviewer: the agent (gsd-code-reviewer)_
_Depth: standard_
