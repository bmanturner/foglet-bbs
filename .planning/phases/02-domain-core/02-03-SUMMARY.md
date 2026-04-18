---
plan: 02-03
phase: 02-domain-core
status: complete
completed: 2026-04-18
---

## Summary

Implemented the three domain contexts — `Foglet.Boards`, `Foglet.Threads`, `Foglet.Posts` — wired D-06 into `Foglet.Accounts.register_user/1`, replaced the Plan 02 boot stub, added seed data, and replaced all pending test stubs with 29 passing tests.

## Key Results

### Contexts Implemented

**Foglet.Boards** (`lib/foglet_bbs/boards.ex`):
- `boot_board_servers/0` — queries non-archived boards, starts a Board Server for each; replaces the Plan 02 Supervisor stub
- `create_category/1`, `get_category!/1`, `list_categories/0`
- `create_board/2` — inserts board, immediately starts Board Server via BoardSupervisor (D-04)
- `get_board!/1`, `get_board_by_slug!/1`, `list_boards/0` (preloads :category)
- `subscribe/2`, `subscribe_to_defaults/1` (idempotent via `on_conflict: :nothing`), `list_subscriptions/1`
- `advance_board_read_pointer/3` (upsert), `get_board_read_pointer/2`
- `unread_count/2` — single-board unread count with soft-delete filter
- `unread_counts/1` — batch map `%{board_id => count}` via single SQL GROUP BY query

**Foglet.Threads** (`lib/foglet_bbs/threads.ex`):
- `create_thread/3` — delegates to Board Server for atomic allocation
- `get_thread!/1` (preloads :board, :created_by, :first_post), `list_threads/1`
- `lock_thread/1`, `unlock_thread/1`, `sticky_thread/1`, `unsticky_thread/1`, `delete_thread/1`
- `move_thread/2` — Ecto.Multi updates both `threads.board_id` and all `posts.board_id` atomically
- `advance_thread_read_pointer/3` (upsert), `get_thread_read_pointer/2`

**Foglet.Posts** (`lib/foglet_bbs/posts.ex`):
- `create_reply/4` — delegates to Board Server
- `get_post!/1` (preloads :user, :reply_to), `list_posts/1` (soft-delete filtered)
- `edit_post/3` — Ecto.Multi: inserts post_edits record with previous_body, then updates post
- `list_edits/1` (newest first, preloads :edited_by)
- `delete_post/2` — soft-delete with optional reason; message_number preserved

### D-06 Wired

`Foglet.Accounts.register_user/1` now calls `Foglet.Boards.subscribe_to_defaults/1` post-commit. Subscription failure does not roll back user creation.

### Application.ex Updated

`Foglet.Boards.Supervisor.boot_board_servers()` replaced with `Foglet.Boards.boot_board_servers()`.

### Seeds Applied

First run: inserted "General" category and "general" board (`default_subscription: true`).
Second run: idempotent — no duplicate inserts.

### Test Results

29 new tests across 3 files, all passing:
- BOARD-01: category creation + validation, board creation + validation (5 tests)
- BOARD-07: subscribe_to_defaults idempotency (2 tests)
- BOARD-08: board read pointer upsert (2 tests)
- BOARD-10: unread counts with soft-delete filter (3 tests)
- BOARD-02: thread creation, post_count, message_number (3 tests)
- BOARD-09: thread read pointer upsert (2 tests)
- BOARD-12: lock, sticky, move_thread (3 tests)
- BOARD-03: create_reply, thread/user counter bumps, reply_to_id (4 tests)
- BOARD-04: edit_post with history (3 tests)
- BOARD-11: soft-delete with list_posts filter (2 tests)

Full suite: 114 tests pass, 8 pending (markdown stubs for Plan 04), 0 failures.

## Deviations from Plan

- `allow_board_server!/1` pattern used in all test files instead of `start_supervised!` for Board Servers: `create_board/2` already starts the Server via `BoardSupervisor`, so tests look up the PID from the Registry with `Registry.lookup/2` and call `Sandbox.allow/3`. This avoids `:already_started` errors from `start_supervised!`.
- Registry `start_supervised!` calls removed from test setups — the Registry is part of the application supervision tree, already running.

## Self-Check: PASSED

- `mix compile --warnings-as-errors` exits 0
- `mix credo --strict` exits 0
- `mix test` exits 0 (114 pass, 8 pending excluded)
- `mix run priv/repo/seeds.exs` exits 0 (idempotent on second run)
- `mix precommit` exits 0
