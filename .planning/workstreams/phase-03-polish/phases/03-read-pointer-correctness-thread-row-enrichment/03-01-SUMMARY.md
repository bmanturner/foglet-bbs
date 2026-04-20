---
phase: 3
plan: "01"
status: complete
started: "2026-04-20"
completed: "2026-04-20"
---

# Plan 01 — GREATEST Monotonicity Fix: Summary

## What was built

Fixed the LIST-01 root cause in `Foglet.Boards.advance_board_read_pointer/3` so the board read pointer only ever advances. Reading an older thread after a newer one no longer regresses the pointer.

## Key changes

- **`lib/foglet_bbs/boards.ex`**: Replaced unconditional `set:` in `on_conflict` with `GREATEST(existing, incoming)` SQL fragment using Ecto's `from(rp in ReadPointer, update: [...])` query form
- Added `returning: true` so callers get the actual stored value
- Added function-head guard `when is_integer(message_number) and message_number >= 0`
- **`test/foglet_bbs/boards/boards_test.exs`**: 3 new regression tests (no-regress, mixed sequence stays at max, same-number idempotence)

## Key decisions

- Used Ecto query form (`from(rp in ReadPointer, update: [...])`) instead of keyword-list `on_conflict: [set: [...]]` because the latter doesn't support `^` pin operators alongside `fragment/1`
- Used Ecto binding reference `rp.last_read_message_number` instead of raw table name `board_read_pointers.last_read_message_number` in fragment (Postgres aliases the table in INSERT..ON CONFLICT)

## Key files

- `lib/foglet_bbs/boards.ex` — GREATEST fragment, returning: true, guard clause
- `test/foglet_bbs/boards/boards_test.exs` — 3 new monotonicity tests

## Self-Check: PASSED
