---
phase: 01-authorization-and-scope-backbone
plan: "04"
subsystem: authorization
tags:
  - authorization
  - scope-for
  - threads
  - posts
  - elixir
  - tdd

dependency_graph:
  requires:
    - "01-01"  # Foglet.Authorization policy module (provides @valid_actions allowlist)
  provides:
    - "Foglet.Threads.scope_for/1 — {:board, board_id} scope helper"
    - "Foglet.Posts.scope_for/1 — {:board, board_id} scope helper"
  affects:
    - "Phase 8 — moderation operation call sites consume these helpers via Bodyguard.permit/4"

tech_stack:
  added: []
  patterns:
    - "Pattern-matched struct destructuring for compile-time field presence guarantee"
    - "TDD RED/GREEN cycle for pure-function plumbing"

key_files:
  created: []
  modified:
    - lib/foglet_bbs/threads.ex
    - lib/foglet_bbs/posts.ex
    - test/foglet_bbs/threads/threads_test.exs
    - test/foglet_bbs/posts/posts_test.exs

decisions:
  - "Pattern-match on %Thread{board_id: board_id} (not thread.board_id) — destructuring gives compile-time field-presence verification; a future schema refactor removing :board_id would fail to compile rather than silently return {:board, nil}"
  - "No operator function signature changes in this plan — D-20 explicitly defers lock_thread, unlock_thread, sticky_thread, unsticky_thread, move_thread, delete_thread, delete_post, edit_post actor-aware signatures to Phase 8"

metrics:
  duration: "~8 minutes"
  completed: "2026-04-23T21:10:58Z"
  tasks_completed: 2
  files_modified: 4
---

# Phase 01 Plan 04: Threads and Posts scope_for/1 Helpers Summary

**One-liner:** Added `Foglet.Threads.scope_for/1` and `Foglet.Posts.scope_for/1` returning `{:board, board_id}` scope tuples for Phase 8 Bodyguard call sites (D-08).

## What Was Built

Two single-line pure functions completing the Phase 1 authorization seam:

- `Foglet.Threads.scope_for(%Thread{board_id: board_id})` — returns `{:board, board_id}`
- `Foglet.Posts.scope_for(%Post{board_id: board_id})` — returns `{:board, board_id}`

Each has a `@doc` string explaining its Phase 8 consumer relationship and a `@spec` typed to `{:board, Ecto.UUID.t()}`. Both follow the `Foglet.Boards.scope_for/1` precedent established in Plan 02.

Unit tests cover two variants per domain: plain-struct (no DB, proves the pattern-match) and persisted-fixture (round-trip with a real board_id from the test database).

## TDD Gate Compliance

| Gate | Commit | Status |
|------|--------|--------|
| RED  | 5a40a3e | `test(01-04): add failing scope_for/1 tests for Threads and Posts` |
| GREEN | cc70a0c | `feat(01-04): add Threads.scope_for/1 and Posts.scope_for/1 helpers (D-08)` |
| REFACTOR | N/A — single-line functions need no refactoring | Skipped (not needed) |

## Commits

| Hash | Type | Description |
|------|------|-------------|
| 5a40a3e | test | Add failing scope_for/1 tests for Threads and Posts (RED) |
| cc70a0c | feat | Add Threads.scope_for/1 and Posts.scope_for/1 helpers (D-08) (GREEN) |

## Verification Results

- `mix test test/foglet_bbs/threads/threads_test.exs test/foglet_bbs/posts/posts_test.exs` — 31 tests, 0 failures
- `mix test` (full suite) — 1016 tests + 1 property, 0 failures
- `mix precommit` — compile, format, credo, sobelow, dialyzer all pass
- D-20 compliance — negative greps on `lock_thread(actor`, `delete_post(actor` etc. all return 0

## Deviations from Plan

None — plan executed exactly as written. The persisted-fixture test for threads reused `setup_board_with_server` from the existing describe block rather than duplicating the board server allow pattern, which keeps the test idiomatic with the existing file conventions.

## Known Stubs

None. Both functions are complete — they return real struct field values and have no hardcoded placeholders.

## Threat Surface Scan

No new network endpoints, auth paths, file access patterns, or schema changes introduced. Both functions are pure (no side effects, no I/O). Threat model items T-01-19 and T-01-20 are mitigated as planned:

- T-01-19: Pattern-match destructuring causes `FunctionClauseError` if called on a struct without `:board_id` — fails loudly rather than returning `{:board, nil}`
- T-01-20: Done-criteria negative greps confirmed 0 operator signature changes (D-20 compliance)

## Self-Check: PASSED

All files confirmed present. Both task commits verified in git log.
