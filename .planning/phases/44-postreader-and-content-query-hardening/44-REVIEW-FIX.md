---
phase: 44-postreader-and-content-query-hardening
fixed_at: 2026-04-29T20:20:00Z
review_path: .planning/phases/44-postreader-and-content-query-hardening/44-REVIEW.md
iteration: 1
findings_in_scope: 1
fixed: 1
skipped: 0
status: all_fixed
---

# Phase 44: Code Review Fix Report

**Fixed at:** 2026-04-29T20:20:00Z
**Source review:** .planning/phases/44-postreader-and-content-query-hardening/44-REVIEW.md
**Iteration:** 1

**Summary:**
- Findings in scope: 1
- Fixed: 1
- Skipped: 0

## Fixed Issues

### CR-01: Reading the latest post can still leave the thread marked unread

**Files modified:** `lib/foglet_bbs/threads/thread.ex`, `lib/foglet_bbs/boards/server.ex`, `test/foglet_bbs/threads/threads_test.exs`
**Commit:** dc21ecc8 (pre-existing — fix landed before this fixer run)
**Applied fix:** The remediation suggested by the reviewer was already implemented in commit `dc21ecc8` ("docs(45): add code review report"), which incidentally bundled the CR-01 source change alongside the 45-phase review docs. The change matches the reviewer's prescription exactly:

- `Foglet.Threads.Thread.bump_counters/2` now accepts the inserted `%Post{}` and persists `last_post_at: post.inserted_at` (replacing the previous `DateTime.utc_now()` call).
- `Foglet.Threads.Thread.set_first_post/2` now accepts the inserted `%Post{}` and persists both `first_post_id` and `last_post_at: post.inserted_at` together.
- `Foglet.Boards.Server` calls both helpers with the post struct returned from the Multi insert (`Thread.bump_counters(post)` at line 140; `Thread.set_first_post(thread, post)` at line 185).
- `advance_thread_read_pointer/3` continues to set `last_read_at = new_post.inserted_at` (line 286 of `threads.ex`), so pointer time and thread activity time now derive from the same canonical timestamp.
- A regression test `"thread read up-to-date is has_unread: false"` (test/foglet_bbs/threads/threads_test.exs:487-505) creates a real latest post, calls `advance_thread_read_pointer/3`, and asserts `has_unread == false` without manually altering timestamps. The test passes (`mix test test/foglet_bbs/threads/threads_test.exs:487` — 1 test, 0 failures).

No additional commits were required from this fixer run; the codebase already satisfies the review prescription. Marking this finding as `fixed` (not `skipped`) because the prescribed change is present and the regression test passes — this is the correctness state the reviewer requested.

---

_Fixed: 2026-04-29T20:20:00Z_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
