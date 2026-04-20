---
phase: 3
plan: "02"
status: complete
started: "2026-04-20"
completed: "2026-04-20"
---

# Plan 02 — list_threads/2 Unread Annotation: Summary

## What was built

Added `Foglet.Threads.list_threads/2` that returns threads annotated with a virtual `:has_unread` boolean per the current user's thread read pointers. Also fixed pre-existing bug where threads had `nil` `last_post_at` on creation.

## Key changes

- **`lib/foglet_bbs/threads.ex`**: New 2-arity `list_threads(board_id, user_id)` with LEFT JOIN on `thread_read_pointers`, `coalesce(trp.last_read_at, fragment("to_timestamp(0)"))` for epoch fallback, batch preload of `created_by`
- **`lib/foglet_bbs/threads/thread.ex`**: Fixed `set_first_post/2` to also set `last_post_at: DateTime.utc_now()` on thread creation
- **`test/foglet_bbs/threads/threads_test.exs`**: 9 new tests (empty list, new user all-unread, unread-after-reply, up-to-date reader, sticky order, preload, nil-user branch, soft-delete, nil last_post_at)

## Key decisions

- Used `fragment("to_timestamp(0)")` for epoch instead of pinned `~U[1970-01-01 00:00:00.000000Z]` — Postgrex can't encode DateTime as parameter in certain SQL contexts
- Returns plain maps (not Thread structs) via explicit field selection + batch preload, avoiding Ecto `select` + `preload` interaction issues
- Preserved `list_threads/1` unchanged for backwards compatibility

## Key files

- `lib/foglet_bbs/threads.ex` — list_threads/2, annotate_no_user/1, preload_created_by/1
- `lib/foglet_bbs/threads/thread.ex` — set_first_post/2 now sets last_post_at
- `test/foglet_bbs/threads/threads_test.exs` — 9 new tests

## Self-Check: PASSED
