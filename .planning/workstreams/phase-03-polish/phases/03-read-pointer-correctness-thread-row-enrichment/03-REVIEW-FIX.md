---
phase: 03-read-pointer-correctness-thread-row-enrichment
fixed_at: 2026-04-20T15:01:00Z
review_path: .planning/workstreams/phase-03-polish/phases/03-read-pointer-correctness-thread-row-enrichment/03-REVIEW.md
fix_scope: all
findings_in_scope: 7
fixed: 7
skipped: 0
status: all_fixed
iteration: 1
---

# Phase 03: Code Review Fix Report

**Fixed at:** 2026-04-20T15:01:00Z
**Source review:** `.planning/workstreams/phase-03-polish/phases/03-read-pointer-correctness-thread-row-enrichment/03-REVIEW.md`
**Iteration:** 1

**Summary:**
- Findings in scope: 7
- Fixed: 7
- Skipped: 0

## Fixed Issues

### CR-01: `nil` propagates to `advance_thread_read_pointer/3` causing Ecto error on flush

**Files modified:** `lib/foglet_bbs/tui/app.ex`, `lib/foglet_bbs/tui/screens/post_reader.ex`
**Commit:** `e3013c3`
**Applied fix:** Added `ctx[:last_read_post_id]` guard to both `maybe_flush_thread_pointer/3` in `app.ex` and `flush_thread_pointer/3` in `post_reader.ex`. The functions now only call `advance_thread_read_pointer/3` when all three of `thread_id`, `user_id`, and `last_read_post_id` are non-nil, preventing a changeset error when a user exits a thread before any posts have been loaded.

---

### WR-01: Row can exceed `width` when title truncation fires at a tight terminal

**Files modified:** `lib/foglet_bbs/tui/widgets/list/list_row.ex`
**Commit:** `fd3beaf`
**Applied fix:** Replaced `padding_len = max(width - title_part_len - metadata_len, min_gap)` with a width-capped expression: `(width - title_part_len - metadata_len) |> max(0) |> min(width)`. The `min_gap` floor is removed so that on very narrow terminals where metadata alone exceeds the available width, padding collapses to 0 rather than causing an overflow. Metadata visibility remains the priority contract.

---

### WR-02: Dead `cond` branch in `truncate_title/2` — the "below minimum" case is never reached

**Files modified:** `lib/foglet_bbs/tui/widgets/list/list_row.ex`
**Commit:** `fd3beaf`
**Applied fix:** Restored the distinct `max_len >= @min_title_length` and `max_len >= 2` branches so that the `2..19` range now emits `String.slice(title, 0, 1) <> @ellipsis` (1 char + ellipsis) instead of repeating the standard `max_len - 1` truncation formula. This also covers IN-02 (edge-case comment added at top of function).

---

### WR-03: Sticky threads with `nil` `last_post_at` sort below non-sticky threads within the sticky group

**Files modified:** `lib/foglet_bbs/tui/screens/thread_list.ex`
**Commit:** `9c2a6ba`
**Applied fix:** Replaced `last_post_sort_key/1` (which returned the arbitrary sentinel `-1` for nil `last_post_at`) with a new `sort_by_recency/1` private function. The new comparator uses a tuple key `{0, unix_microseconds}` for real `DateTime` values and `{1, 0}` for nil, giving unambiguous nil-last ordering within each sticky/regular group via `Enum.sort_by(..., :asc) |> Enum.reverse()`.

---

### IN-01: Nested `defmodule` inside test bodies creates stale-module risk in watch mode

**Files modified:** `test/foglet_bbs/tui/screens/thread_list_test.exs`, `test/foglet_bbs/tui/screens/post_reader_test.exs`
**Commit:** `8ea09f9`
**Applied fix:** Moved `HandlelessFakeThreads`, `NiltimeFakeThreads`, `AnnotatingFakeThreads`, and `OneArityOnly` to the top level of `ThreadListTest`. Moved `FakePostsForLoad` to the top level of `PostReaderTest` (removing the duplicate definition from inside the `describe` block). All 607 tests pass after the move.

---

### IN-02: `truncate_title/2` applies `String.slice/3` with `max_len - 1` when `max_len` is 0

**Files modified:** `lib/foglet_bbs/tui/widgets/list/list_row.ex`
**Commit:** `fd3beaf`
**Applied fix:** Added a four-line comment block at the top of `truncate_title/2` documenting the `max_len == 0`, `max_len == 1`, `max_len in 2..19`, and `max_len >= @min_title_length` paths. This was applied as part of the WR-01/WR-02 commit since all three changes were in the same function.

---

### IN-03: `subscribe_to_defaults/1` silently discards insert errors

**Files modified:** `lib/foglet_bbs/boards.ex`
**Commit:** `8018cca`
**Applied fix:** Wrapped `Repo.insert/2` result in a `case` expression inside the `Enum.each` lambda. `{:ok, _}` continues silently; `{:error, cs}` emits a `Logger.warning/1` with the user ID, board ID, and changeset errors. The `:ok` return contract for callers is unchanged. `require Logger` is called inline (matching the pattern used elsewhere in the module).

---

_Fixed: 2026-04-20T15:01:00Z_
_Fixer: Claude (gsd-code-fixer)_
_Iteration: 1_
