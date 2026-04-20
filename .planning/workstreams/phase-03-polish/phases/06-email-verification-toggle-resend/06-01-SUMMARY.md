---
phase: 6
plan: "01"
title: "Config seeds + Foglet.Accounts.post_login_screen/1"
subsystem: accounts
tags: [config, accounts, email-verification, seeds]
status: complete
completed_at: "2026-04-20T19:19:27Z"
duration_minutes: 15

dependency_graph:
  requires: []
  provides:
    - Foglet.Accounts.post_login_screen/1
    - config key require_email_verification (boolean, default true)
    - config key email_verify_resend_cooldown_seconds (integer, default 60)
  affects:
    - priv/repo/seeds.exs
    - lib/foglet_bbs/accounts.ex
    - test/foglet_bbs/accounts/accounts_test.exs

tech_stack:
  added: []
  patterns:
    - Foglet.Config.get/2 with safe default (missing seed -> secure posture)
    - cond branch for multi-clause boolean logic over nested if

key_files:
  modified:
    - priv/repo/seeds.exs
    - lib/foglet_bbs/accounts.ex
    - test/foglet_bbs/accounts/accounts_test.exs

decisions:
  - "Used Foglet.Config.get/2 (not get!/1) — missing seed defaults to true (verify required), not raise"
  - "on_exit only invalidates ETS cache; DB rollback handled by sandbox, avoiding cross-process ownership error"
  - "Used inline Ecto.Query.from/2 in test instead of file-wide import to keep test self-contained (Option 2 from plan)"

metrics:
  tasks_completed: 3
  tasks_total: 3
  commits: 3
  files_created: 0
  files_modified: 3
---

# Phase 6 Plan 01: Config Seeds + `Foglet.Accounts.post_login_screen/1` Summary

**One-liner:** Config seeds for `require_email_verification` (bool, default true) and `email_verify_resend_cooldown_seconds` (int, default 60), plus `Accounts.post_login_screen/1` returning `:main_menu | :verify` based on `confirmed_at` and the toggle flag.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Append two config seeds to seeds.exs | f07a2db | priv/repo/seeds.exs |
| 2 | Add Accounts.post_login_screen/1 | 3cffe61 | lib/foglet_bbs/accounts.ex |
| 3 | Unit tests for post_login_screen/1 | e9e827b | test/foglet_bbs/accounts/accounts_test.exs |

## Verification Results

- `mix run priv/repo/seeds.exs` (test env): Both keys inserted on first run, "already present" on re-run — idempotent.
- `mix compile --warnings-as-errors`: No errors or warnings on accounts.ex.
- Function order confirmed: `confirm_user` (line 151) → `post_login_screen` (line 173) → `build_verify_code` (line 192).
- `mix test test/foglet_bbs/accounts/accounts_test.exs`: 28 tests, 0 failures (24 existing + 4 new).
- `mix format --check-formatted`: All three files pass.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed DBConnection.OwnershipError in on_exit callback**

- **Found during:** Task 3 — first test run returned 4 failures with `DBConnection.OwnershipError` in `ExUnit.OnExitHandler`
- **Issue:** The plan's `on_exit` callback called `Foglet.Config.put!` to restore the config row. `put!/3` calls `Repo.get_by` internally, which requires a DB connection. The `on_exit` handler runs in a separate `ExUnit.OnExitHandler` process that does not own the sandbox connection in async mode.
- **Root cause:** Ecto sandbox in manual mode (used by `async: true` tests) requires every process that touches the DB to either check out a connection or be explicitly allowed. The on_exit process is neither.
- **Fix:** Replaced the DB-restoration logic in `on_exit` with just `Foglet.Config.invalidate/1` (ETS-only, no DB access). The DB row is already rolled back by the sandbox transaction at the end of each test — no explicit restoration is needed. The only cleanup needed is clearing the ETS cache so the next test doesn't read a stale value.
- **Files modified:** test/foglet_bbs/accounts/accounts_test.exs
- **Commit:** e9e827b (included in Task 3 commit)

## Known Stubs

None. `post_login_screen/1` is fully implemented with real config reads and returns real atoms. No placeholder data.

## Threat Flags

None. No new network endpoints, auth paths, file access patterns, or schema changes introduced. The new function reads from the existing `Foglet.Config` table (internal only).

## Self-Check: PASSED

- [x] `priv/repo/seeds.exs` contains `"require_email_verification"` and `"email_verify_resend_cooldown_seconds"`
- [x] `lib/foglet_bbs/accounts.ex` contains `def post_login_screen(%User{confirmed_at: confirmed_at})`
- [x] `test/foglet_bbs/accounts/accounts_test.exs` contains `describe "post_login_screen/1 (VERIFY-01)"`
- [x] Commits f07a2db, 3cffe61, e9e827b all present in git log
- [x] 28 tests pass, 0 failures
