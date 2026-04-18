---
plan: 02-01
phase: 02-domain-core
status: complete
completed: 2026-04-18
---

## Summary

Laid the database and schema foundation for Phase 2: added MDEx dependency, created 8 migrations for Phase 2 tables, implemented 9 Ecto schema modules, and scaffolded Wave 0 test stubs.

## Key Results

### MDEx Version
- MDEx **0.12.1** installed (resolved from `~> 0.2` constraint)
- Pre-compiled NIF binary downloaded for `aarch64-apple-darwin` — no Rust toolchain required
- Transitive deps: lumis, nimble_options, nimble_parsec, rustler_precompiled

### Migration Timestamps
- Used stable timestamps `20260418000006` through `20260418000013` as specified
- All 8 migrations applied cleanly on top of Phase 1's 5 existing migrations

### Migration Round-Trip
- `mix ecto.migrate` — 13/13 migrations applied (including Phase 1)
- `mix ecto.rollback --step 8` — Phase 2 migrations reversed cleanly
- `mix ecto.migrate` — round-trip confirmed successful

### Schema Modules Created
1. `Foglet.Boards.Category` — categories table
2. `Foglet.Boards.Board` — boards table with Ecto.Enum for readable_by/postable_by
3. `Foglet.Boards.Subscription` — board_subscriptions table
4. `Foglet.Boards.ReadPointer` — board_read_pointers table
5. `Foglet.Threads.Thread` — threads table with bump_counters/set_first_post/lock/sticky/delete changesets
6. `Foglet.Threads.ReadPointer` — thread_read_pointers table
7. `Foglet.Posts.Post` — posts table; body_tsv intentionally omitted from schema
8. `Foglet.Posts.Edit` — post_edits table
9. `Foglet.Posts.Upvote` — upvotes table

All schemas use `use Foglet.Schema`. FK fields (user_id, board_id, thread_id, message_number) excluded from cast calls.

### Test Scaffold
- `test/support/boards_fixtures.ex` — stub helpers (raise until Plan 03)
- 5 test files with `@tag :pending` stubs covering all 12 BOARD requirements
- `test/test_helper.exs` updated with `exclude: [:pending]` so stubs don't fail
- `mix test` exits 0: 80 tests pass, 43 pending excluded

## Deviations from Plan
- Added `exclude: [:pending]` to `test/test_helper.exs` — the plan says stubs should not fail; this is the correct ExUnit mechanism for `@tag :pending` to skip rather than fail

## Self-Check: PASSED
- `mix compile --warnings-as-errors` exits 0
- `mix credo --strict` exits 0 (added @moduledoc to all 8 new schemas)
- `mix ecto.migrate` exits 0
- Rollback round-trip verified
- `mix test` exits 0 (80 pass, 43 pending excluded)
