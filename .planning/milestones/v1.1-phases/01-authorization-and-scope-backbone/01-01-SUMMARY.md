---
phase: 01-authorization-and-scope-backbone
plan: "01"
subsystem: authorization
tags:
  - authorization
  - bodyguard
  - policy-matrix
  - elixir
dependency_graph:
  requires: []
  provides:
    - Foglet.Authorization (Bodyguard.Policy implementation)
    - Bodyguard.permit/4 entry point for all domain guard callers
    - Foglet.Authorization.scopes_for/2 (data-visibility seam for Phase 8)
  affects:
    - Phase 2 (Sysop Config and Board Management) — consumes Bodyguard.permit/4 for :edit_config, :create_board, etc.
    - Phase 3 (Invite Persistence) — consumes Bodyguard.permit/4 for :generate_invite, :revoke_invite
    - Phase 8 (Moderation Workspace) — consumes scopes_for/2 for data-visibility filtering
tech_stack:
  added:
    - bodyguard 2.4.3 (~> 2.4)
  patterns:
    - Bodyguard.Policy behaviour — function-clause callback with @valid_actions allowlist
    - TDD RED/GREEN with matrix test comprehension (fixture-function pattern, no Macro.escape)
    - compile-time atom allowlists (@valid_actions, @mod_site_actions, @mod_board_actions)
key_files:
  created:
    - mix.exs (bodyguard dep added)
    - mix.lock (bodyguard 2.4.3 resolved)
    - lib/foglet_bbs/authorization.ex
    - test/foglet_bbs/authorization_test.exs
    - test/foglet_bbs/authorization/bodyguard_passthrough_test.exs
  modified: []
decisions:
  - "Board and category lifecycle actions (:create_board, :update_board, :archive_board, :create_category, :update_category, :archive_category) are sysop-only in v1.1 — mods are not granted these (SYSO-03)"
  - "Mod :edit_config deny clause placed BEFORE mod site-scope allowlist for defensive ordering — prevents future accidental promotion of :edit_config into mod actions"
  - "Used fixture-function pattern (defp actor/1 returning structs at runtime) instead of Macro.escape/1 in matrix comprehension — avoids compile-time struct-in-AST pitfall"
  - "AlwaysForbiddenPolicy defined as a top-level module (not nested) in the passthrough test file — two top-level defmodule blocks in one file, compliant with CLAUDE.md no-nesting rule"
metrics:
  duration: "~8 minutes"
  completed: "2026-04-23"
  tasks_completed: 3
  files_created: 5
  tests_added: 55
---

# Phase 1 Plan 01: Bodyguard Dependency + Foglet.Authorization Policy Module Summary

**One-liner:** Bodyguard 2.4.3 wired as @behaviour Bodyguard.Policy with an 18-atom @valid_actions allowlist, sysop/mod/user/nil policy matrix, scopes_for/2 list seam, and 55 TDD tests locking MODR-02 and MODR-03.

## What Was Built

### Task 1: Bodyguard dependency (commit c14d1a5)

Added `{:bodyguard, "~> 2.4"}` to `mix.exs` deps. `mix deps.get` resolved bodyguard 2.4.3 into `mix.lock`. `mix compile --warnings-as-errors` exits 0 — no new warnings in application code (all warnings are pre-existing in vendored raxol/yamerl deps).

### Task 2: Foglet.Authorization — RED then GREEN (commits 09a0f33, 7d383dd)

**RED:** Created two test files before any implementation:
- `test/foglet_bbs/authorization_test.exs` — 46 matrix cases + unknown-action Logger.warning test + permit?/4 boolean wrapper tests + 7 scopes_for/2 tests = 54 total tests, all failing with `UndefinedFunctionError`
- `test/foglet_bbs/authorization/bodyguard_passthrough_test.exs` — A4 smoke test using `AlwaysForbiddenPolicy` inline module, passing at RED (isolated from Foglet.Authorization)

**GREEN:** Created `lib/foglet_bbs/authorization.ex` with:
- `@behaviour Bodyguard.Policy` — implements `authorize/3` callback
- `@valid_actions` (18 atoms): all thread, post, oneliner, board/category lifecycle, config, and invite action atoms
- `@mod_site_actions` and `@mod_board_actions` compile-time lists separating mod-permitted actions from sysop-only ones
- Invalid actor guards (nil, deleted_at, suspended, pending) at top of `authorize/3` before any role dispatch (D-24)
- Unknown action clause with `Logger.warning` and `{:error, :forbidden}` return (D-13)
- Sysop clause permits all valid actions at any scope
- Explicit `:edit_config` deny for mod before site-scope allowlist (defensive ordering)
- `scopes_for/2` with `@spec` returning `[scope()]` — nil/deleted/suspended/pending → `[]`, sysop/mod → `[:site]`, others → `[]`

All 55 tests pass at GREEN.

### Task 3: mix precommit (commit 13b064a)

`mix precommit` ran `compile --warnings-as-errors`, `deps.unlock --unused`, `format`, `credo --strict`, `sobelow --exit Low`, and `dialyzer`. All gates passed. `mix format` reformatted atom lists to one-atom-per-line and reformatted one multi-line assert expression — 44 changed lines, behavior unchanged, tests still 55/0.

## Deviations from Plan

None — plan executed exactly as written.

The formatter reformatting after precommit was committed separately as `style(01-01)` per the task commit protocol — it is a format-only change, not a deviation.

## Known Stubs

None. All functions return concrete values for all input patterns. No placeholder text or TODO markers.

## Threat Surface Scan

No new network endpoints, auth paths, file access patterns, or schema changes introduced. `Foglet.Authorization` is a pure in-process function-clause module with no I/O. All STRIDE threats T-01-01 through T-01-06 from the plan's threat model are mitigated as designed.

## Self-Check: PASSED

| Item | Status |
|------|--------|
| mix.exs | FOUND |
| mix.lock | FOUND |
| lib/foglet_bbs/authorization.ex | FOUND |
| test/foglet_bbs/authorization_test.exs | FOUND |
| test/foglet_bbs/authorization/bodyguard_passthrough_test.exs | FOUND |
| c14d1a5 (Task 1 dep) | FOUND |
| 09a0f33 (Task 2 RED) | FOUND |
| 7d383dd (Task 2 GREEN) | FOUND |
| 13b064a (Task 3 format) | FOUND |
