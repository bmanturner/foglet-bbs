---
phase: 07-oneliners-and-main-menu-social-strip
plan: 01
subsystem: oneliners
tags:
  - ecto
  - postgres
  - domain
requirements:
  - ONEL-01
  - ONEL-03
dependency_graph:
  requires:
    - Foglet.Schema
    - Foglet.Accounts.User
    - FogletBbs.Repo
  provides:
    - Foglet.Oneliners
    - Foglet.Oneliners.Entry
    - oneliners table
  affects:
    - main-menu oneliner loading in later Phase 07 plans
tech_stack:
  added:
    - Ecto schema and migration
  patterns:
    - context-owned actor assignment
    - bounded visible recents query
key_files:
  created:
    - lib/foglet_bbs/oneliners.ex
    - lib/foglet_bbs/oneliners/entry.ex
    - priv/repo/migrations/20260424024644_create_oneliners.exs
    - test/foglet_bbs/oneliners/oneliners_test.exs
  modified: []
decisions:
  - User ownership is set on %Entry{} before changeset construction and never cast from caller attrs.
  - Recent visible listing is capped at 20 rows and preloads :user for TUI handle rendering.
metrics:
  completed_at: 2026-04-24T02:53:46Z
  tasks_completed: 2
  files_changed: 4
---

# Phase 07 Plan 01: Oneliner Domain Foundation Summary

Postgres-backed oneliner persistence with actor-owned creation, body validation, bounded visible recents, and database-backed tests.

## Completed Tasks

| Task | Name | Commit | Files |
| ---- | ---- | ------ | ----- |
| 1 RED | Add failing oneliner schema tests | 74ea38e | `test/foglet_bbs/oneliners/oneliners_test.exs` |
| 1 GREEN | Add oneliner migration and schema | 40112ed | `lib/foglet_bbs/oneliners/entry.ex`, `priv/repo/migrations/20260424024644_create_oneliners.exs`, `test/foglet_bbs/oneliners/oneliners_test.exs` |
| 2 RED | Add failing oneliner context tests | f00339b | `test/foglet_bbs/oneliners/oneliners_test.exs` |
| 2 GREEN | Add Oneliners context APIs | 50d5856 | `lib/foglet_bbs/oneliners.ex` |

## What Changed

- Added `Foglet.Oneliners.Entry` with the locked schema shape: `body`, `hidden`, `hidden_reason`, `user_id`, `hidden_by_id`, and `timestamps(updated_at: false)`.
- Added `oneliners` migration with UUID primary key, user foreign keys, hidden default, no `updated_at`, and a partial visible-recents index on `inserted_at`.
- Added `Foglet.Oneliners.create_entry/2` and `list_recent_visible/1`.
- Added database-backed tests for trimming, length validation, hidden default behavior, actor-owned inserts, spoofed `user_id` rejection, visible-only newest-first listing, user preload, limit clamping, and same-user latest-visible rejection.

## Verification

- `mix test test/foglet_bbs/oneliners/oneliners_test.exs` passed with 9 tests, 0 failures.
- `mix precommit` passed. Dialyzer reported 84 ignored existing warnings and completed successfully.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Installed missing Mix dependencies in isolated worktree**
- **Found during:** Task 1 RED verification
- **Issue:** The isolated worktree had no fetched dependencies, so `mix test` could not run.
- **Fix:** Ran `mix deps.get` for this worktree.
- **Files modified:** dependency/build artifacts only, no tracked source files.
- **Commit:** None

**2. [Rule 1 - Bug] Simplified redundant `with` in `create_entry/2`**
- **Found during:** Final `mix precommit`
- **Issue:** Credo flagged the transaction flow as a redundant `with`.
- **Fix:** Rewrote it as a `case` while preserving the same tagged-tuple behavior.
- **Files modified:** `lib/foglet_bbs/oneliners.ex`
- **Commit:** 50d5856

## Known Stubs

None. The scanner found only test assertions for empty list behavior, not UI-facing empty stubs.

## Threat Flags

None beyond the plan's threat model. The new trust-boundary surfaces are the planned `Foglet.Oneliners` context, schema, and migration, with mitigations implemented.

## Self-Check: PASSED

- Found `lib/foglet_bbs/oneliners.ex`
- Found `lib/foglet_bbs/oneliners/entry.ex`
- Found `priv/repo/migrations/20260424024644_create_oneliners.exs`
- Found `test/foglet_bbs/oneliners/oneliners_test.exs`
- Found commits `74ea38e`, `40112ed`, `f00339b`, and `50d5856`
