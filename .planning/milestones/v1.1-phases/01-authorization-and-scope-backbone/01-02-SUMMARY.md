---
phase: 01-authorization-and-scope-backbone
plan: "02"
subsystem: authorization
tags:
  - authorization
  - boards
  - actor-first
  - bodyguard
  - elixir
dependency_graph:
  requires:
    - 01-01 (Foglet.Authorization Bodyguard.Policy + Bodyguard dep)
  provides:
    - Foglet.Boards.create_board/3 (actor-first, :create_board guard)
    - Foglet.Boards.update_board/3 (actor-first, :update_board guard)
    - Foglet.Boards.archive_board/2 (actor-first, :archive_board guard)
    - Foglet.Boards.scope_for/1 ({:board, id} scope synthesis per D-08)
    - Foglet.Boards.Board.archive_changeset/1 (defensive single-field changeset)
  affects:
    - Phase 2 (Sysop Config and Board Management) — all board lifecycle callers must pass actor
    - test/support/boards_fixtures.ex — board_fixture now internally passes sysop actor
    - Downstream tests using board_fixture (threads, posts) — shielded, no source changes needed
tech_stack:
  added: []
  patterns:
    - actor-first domain function signature with Bodyguard.permit/4 before side effects (D-17)
    - with :ok <- Bodyguard.permit(...) do ... end — short-circuit before Repo (Pitfall 2 safe)
    - Separate archive_changeset/1 — defensive single-field changeset (defense in depth T-01-09)
    - scope_for/1 helper per D-08 — consistent {:board, id} synthesis at domain boundary
    - board_fixture sysop shield — existing callers work without source changes
    - TDD RED/GREEN — forbidden-path tests written before implementation
key_files:
  created: []
  modified:
    - lib/foglet_bbs/boards.ex
    - lib/foglet_bbs/boards/board.ex
    - test/foglet_bbs/boards/boards_test.exs
    - test/support/boards_fixtures.ex
decisions:
  - "create_board/3, update_board/3, archive_board/2 all guard at :site scope — mods are forbidden for all three (Plan 01 Open Question 1 resolution: SYSO-03)"
  - "Bodyguard.permit/4 called outside any Repo.transact — Pitfall 2 pattern respected (T-01-11 mitigated)"
  - "board_fixture internally synthesizes %User{role: :sysop, status: :active, deleted_at: nil} — all three fields set explicitly to prevent accidental rejection"
  - "archive_changeset/1 only casts :archived — defense in depth even if guard were bypassed (T-01-09)"
metrics:
  duration: "~7 minutes"
  completed: "2026-04-23"
  tasks_completed: 3
  files_created: 0
  files_modified: 4
  tests_added: 14
---

# Phase 1 Plan 02: Actor-First Boards Boundary Summary

**One-liner:** Bodyguard.permit/4 guards wired into create_board/3, update_board/3, archive_board/2 with archive_changeset/1 and scope_for/1, backed by 14 new TDD tests covering forbidden paths for regular user, nil, and mod actors.

## What Was Built

### Task 1: Board.archive_changeset/1 and Boards.scope_for/1 (commit 82559d8)

Added `archive_changeset/1` to `Foglet.Boards.Board` — a defensive changeset that only casts `:archived: true`, preventing any other field mutation through the archive path. Added `scope_for/1` to `Foglet.Boards` returning `{:board, id}` per D-08, giving callers a consistent scope synthesis point.

Tests: 3 new tests confirming changeset validity, field isolation, and scope tuple shape. All 18 board tests green.

### Task 2: Actor-first function signatures + forbidden-path tests (commits 476dc27, c94fffb)

**RED (476dc27):** Added `alias Foglet.Accounts.User`, `sysop_actor/0`, `mod_actor/0` helpers to the test module. Renamed `describe "create_board/2"` to `describe "create_board/3"` and migrated all direct `create_board` calls in both describe blocks. Added 11 new forbidden-path and happy-path test cases across `create_board/3 authorization (D-27)`, `update_board/3`, and `archive_board/2` describe blocks. Migrated `board_fixture/2` to pass `%User{role: :sysop, status: :active, deleted_at: nil}` internally. Tests failed with `UndefinedFunctionError` for `create_board/3` — correct RED state.

**GREEN (c94fffb):** Replaced `create_board/2` with actor-first `create_board/3`. Added `update_board/3` and `archive_board/2`. Each function follows the pattern:

```elixir
with :ok <- Bodyguard.permit(Foglet.Authorization, :action, actor, :site) do
  # Repo side effect only after authorization
end
```

All 29 board tests green. Full suite: 1026 tests, 0 failures. Threads/posts regression: 27 tests, 0 failures.

### Task 3: Full precommit gate (no additional commit)

`mix precommit` ran `compile --warnings-as-errors`, `format`, `credo --strict`, `sobelow`, and `dialyzer`. All gates passed. No formatting delta (code was already compliant). Dialyzer: 76 pre-existing skips, 0 new errors from application code.

## Deviations from Plan

None — plan executed exactly as written.

## Known Stubs

None. All functions return concrete values for all input patterns. No placeholder text or TODO markers. The `board_fixture` sysop actor is explicitly constructed with all three fields set (`role`, `status`, `deleted_at`), not a stub.

## Threat Surface Scan

No new network endpoints, auth paths, or schema changes introduced beyond what the threat model anticipated. All five STRIDE threats from the plan's register (T-01-07 through T-01-12, minus T-01-13 which was accepted) are mitigated as designed:

- T-01-07: regular user forbidden for create_board — asserted with DB count == 0
- T-01-08: regular user forbidden for update_board — board row unchanged on DB reload
- T-01-09: regular user forbidden for archive_board — archived stays false on DB reload; archive_changeset/1 additionally restricts cast fields
- T-01-10: mod forbidden for all three operations — explicit mod_actor() tests
- T-01-11: Bodyguard.permit/4 called outside Repo.transact — no transaction wrapper used
- T-01-12: board_fixture sysop actor has all three fields set; any regression would fail all downstream board/thread/post tests

## Self-Check: PASSED

| Item | Status |
|------|--------|
| lib/foglet_bbs/boards.ex | FOUND |
| lib/foglet_bbs/boards/board.ex | FOUND |
| test/foglet_bbs/boards/boards_test.exs | FOUND |
| test/support/boards_fixtures.ex | FOUND |
| 82559d8 (Task 1) | FOUND |
| 476dc27 (Task 2 RED) | FOUND |
| c94fffb (Task 2 GREEN) | FOUND |
| mix precommit | PASSED |
| mix test (full suite) | 1026 tests, 0 failures |
