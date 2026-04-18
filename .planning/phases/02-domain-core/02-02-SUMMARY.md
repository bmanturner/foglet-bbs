---
plan: 02-02
phase: 02-domain-core
status: complete
completed: 2026-04-18
---

## Summary

Implemented the `Foglet.Boards.Server` GenServer and `Foglet.Boards.Supervisor` DynamicSupervisor, wired both into the application supervision tree, and replaced all BOARD-06 pending test stubs with passing tests.

## Key Results

### Board Server Architecture

`Foglet.Boards.Server` serializes message-number allocation per board via a single `GenServer.call`. Each call runs an `Ecto.Multi` that atomically:
1. Increments `boards.next_message_number`
2. Inserts the post with the allocated number
3. Bumps thread counters (`post_count`, `last_post_at`)
4. Increments `user.post_count`

The in-memory counter advances only on `{:ok, %{post: post}}` — any failure branch returns the original state and reuses the same number on the next attempt.

D-05 crash recovery: `init/1` queries `COALESCE(MAX(message_number), 0)` from posts for the board and resumes from `MAX + 1`, making the Server self-healing after mid-flight crashes.

### Supervision Tree

`lib/foglet_bbs/application.ex` now starts:
- `{Registry, keys: :unique, name: Foglet.BoardRegistry}` — before `Foglet.Boards.Supervisor`
- `Foglet.Boards.Supervisor` — DynamicSupervisor managing one Server per board

`Foglet.Boards.Supervisor.boot_board_servers/0` is called after `Supervisor.start_link` completes. The stub returns `:ok` until Plan 03 queries non-archived boards from the DB.

### Credo Issues Resolved

Two issues found and fixed:
1. Alias ordering in `server.ex`: `FogletBbs.Repo` placed after `Foglet.*` aliases alphabetically
2. Alias ordering in `board_server_test.exs`: same fix applied; also switched supervised IDs from string-interpolated atoms (credo binary_to_atom warning) to `{:board_server, board_id, extra_id}` tuples

### Test Results

All 6 Board Server tests pass (5 unit + 1 property):

- `starts and registers via Registry under board_id` — Registry lookup confirms PID
- `init loads next_message_number as MAX(message_number)+1 from DB (D-05)` — stop/restart sequence verified
- `allocates sequential message numbers for posts in a single board` — message_number 1, 2 confirmed
- `does not advance counter when transaction fails` — empty body fails validation; counter stays at 1; next valid post gets 1
- `message numbers are per-board (two boards have independent sequences)` — both boards independently start at 1
- Property: `message numbers are monotonically sequential under concurrent inserts` — 5 runs × 2–6 inserts, all numbers form a contiguous range

### Full Suite

```
1 property, 85 tests, 0 failures (37 excluded)
```

## Deviations from Plan

- Used tuple-based supervised IDs `{:board_server, board_id, extra_id}` instead of atom interpolation to satisfy `mix credo --strict` (binary_to_atom warning)
- Board Server test file uses direct `Repo.insert!` via schema changesets for board/category/user setup (contexts not yet implemented by Plan 03); `AccountsFixtures.user_fixture/0` used for users since Accounts context exists

## Self-Check: PASSED

- `mix compile --warnings-as-errors` exits 0
- `mix credo --strict` exits 0
- `mix test test/foglet_bbs/boards/board_server_test.exs` exits 0 (6 pass)
- `mix test` exits 0 (85 pass, 37 pending excluded)
- `mix precommit` exits 0
