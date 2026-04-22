---
phase: 06-threadlist
reviewed: 2026-04-22T13:16:14Z
depth: standard
files_reviewed: 3
files_reviewed_list:
  - lib/foglet_bbs/tui/screens/thread_list.ex
  - test/foglet_bbs/tui/screens/thread_list_test.exs
  - test/foglet_bbs/threads/threads_test.exs
findings:
  critical: 0
  warning: 1
  info: 0
  total: 1
status: issues_found
---

# Phase 06: Code Review Report

**Reviewed:** 2026-04-22T13:16:14Z
**Depth:** standard
**Files Reviewed:** 3
**Status:** issues_found

## Summary

Reviewed all listed source files at standard depth with focus on correctness, security, and maintainability. No security vulnerabilities were identified. One correctness issue was found in thread recency sorting logic in the thread list screen.

## Warnings

### WR-01: `nil` `last_post_at` is sorted first instead of last

**File:** `lib/foglet_bbs/tui/screens/thread_list.ex:191`
**Issue:** `sort_by_recency/1` builds sort keys so `nil` timestamps sort after dated threads in ascending order, but then reverses the whole list. The reverse moves `nil` rows to the front, contradicting the intended behavior ("nil sorts last") and surfacing brand-new/no-activity threads before active threads.
**Fix:**
```elixir
defp sort_by_recency(threads) do
  Enum.sort_by(
    threads,
    fn t ->
      case Map.get(t, :last_post_at) do
        %DateTime{} = dt -> {0, -DateTime.to_unix(dt, :microsecond)}
        _ -> {1, 0}
      end
    end,
    :asc
  )
end
```

---

_Reviewed: 2026-04-22T13:16:14Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
