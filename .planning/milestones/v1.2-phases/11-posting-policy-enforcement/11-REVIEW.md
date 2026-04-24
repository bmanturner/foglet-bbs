---
phase: 11-posting-policy-enforcement
reviewed: 2026-04-24T20:35:30Z
depth: standard
files_reviewed: 10
files_reviewed_list:
  - lib/foglet_bbs/boards/board.ex
  - lib/foglet_bbs/posting_policy.ex
  - lib/foglet_bbs/threads.ex
  - lib/foglet_bbs/posts.ex
  - lib/foglet_bbs/tui/screens/new_thread.ex
  - lib/foglet_bbs/tui/screens/post_composer.ex
  - test/foglet_bbs/threads/threads_test.exs
  - test/foglet_bbs/posts/posts_test.exs
  - test/foglet_bbs/tui/screens/new_thread_test.exs
  - test/foglet_bbs/tui/screens/post_composer_test.exs
findings:
  critical: 0
  warning: 2
  info: 0
  total: 2
status: issues_found
---

# Phase 11: Code Review Report

**Reviewed:** 2026-04-24T20:35:30Z
**Depth:** standard
**Files Reviewed:** 10
**Status:** issues_found

## Summary

Reviewed the Phase 11 posting-policy enforcement changes across board schema policy fields, shared posting policy, thread/reply context preflights, TUI structured-error formatting, and targeted tests. The targeted Phase 11 test command passes with `111 tests, 0 failures`.

The main issue is that the new context preflights still call `Repo.get/2` directly on caller-supplied binary IDs. Malformed UUID strings can raise before reaching the intended `{:error, :posting_not_allowed}` denial path. I also found a test coverage gap for the reply preflight edge cases required by Plan 11-02.

## Warnings

### WR-01: Malformed Caller-Supplied IDs Can Raise Before Posting Denial

**File:** `lib/foglet_bbs/threads.ex:45`
**Issue:** `Foglet.Threads.create_thread/3` treats any binary `user_id` or `board_id` as safe for `Repo.get/2`. For UUID primary keys, malformed binary IDs can raise an Ecto cast error instead of returning `{:error, :posting_not_allowed}`. Phase 11's threat model identifies `user_id` and `board_id` as untrusted TUI/SSH inputs and expects disallowed, missing, or unknown users to be rejected without side effects.
**Fix:**
```elixir
defp safe_get(schema, id) when is_binary(id) do
  case Ecto.UUID.cast(id) do
    {:ok, uuid} -> Repo.get(schema, uuid)
    :error -> nil
  end
end

defp safe_get(_schema, _id), do: nil
```

Use `safe_get(User, user_id)` and `safe_get(Board, board_id)` in `create_thread/3`, then add tests for malformed user and board IDs returning `{:error, :posting_not_allowed}` without board-server side effects.

### WR-02: Reply Preflight Has The Same Malformed-ID Crash Path And Missing Edge Tests

**File:** `lib/foglet_bbs/posts.ex:46`
**Issue:** `Foglet.Posts.create_reply/4` directly calls `Repo.get/2` for caller-supplied `user_id`, `board_id`, and `thread_id`. Malformed UUID strings can raise before the function reaches the intended policy, mismatch, or lock preflight results. The POST-02/POST-03 tests cover role matrix, lock bypass, and side-effect-free policy denial, but they do not cover missing/malformed board IDs, missing/malformed thread IDs, or thread/board mismatch even though Plan 11-02 requires those cases to return `{:error, :posting_not_allowed}` before board-server delegation.
**Fix:** Reuse the same `safe_get/2` pattern from WR-01 in `create_reply/4`, and add tests that assert malformed `user_id`, `board_id`, and `thread_id`, plus a persisted thread/board mismatch, all return `{:error, :posting_not_allowed}` and leave post/thread/user/board counters unchanged.

---

_Reviewed: 2026-04-24T20:35:30Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
