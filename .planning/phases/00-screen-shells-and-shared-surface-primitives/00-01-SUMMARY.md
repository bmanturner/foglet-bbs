---
phase: 00
plan: 01
subsystem: tui-tests
tags: [tui, tests, tdd, screens, phase-00, wave-0]
dependency_graph:
  requires: []
  provides:
    - test/foglet_bbs/tui/screens/account_test.exs
    - test/foglet_bbs/tui/screens/moderation_test.exs
    - test/foglet_bbs/tui/screens/sysop_test.exs
    - test/foglet_bbs/tui/screens/shared/invites_surface_test.exs
  affects:
    - test/foglet_bbs/tui/screens/main_menu_test.exs
    - test/foglet_bbs/tui/app_test.exs
    - test/foglet_bbs/tui/layout_smoke_test.exs
tech_stack:
  added: []
  patterns:
    - TDD RED phase — test files reference not-yet-existent production modules
    - ExUnit async: true throughout for safe parallel test execution
    - collect_text_values/1 helper for flattening Raxol render trees in test assertions
    - role-gated visibility assertions using Foglet.Accounts.User role field
key_files:
  created:
    - test/foglet_bbs/tui/screens/account_test.exs
    - test/foglet_bbs/tui/screens/moderation_test.exs
    - test/foglet_bbs/tui/screens/sysop_test.exs
    - test/foglet_bbs/tui/screens/shared/invites_surface_test.exs
  modified:
    - test/foglet_bbs/tui/screens/main_menu_test.exs
    - test/foglet_bbs/tui/app_test.exs
    - test/foglet_bbs/tui/layout_smoke_test.exs
decisions:
  - Wave 0 contracts locked via failing test assertions before any production code
  - collect_text_values/1 helper duplicated per file (not extracted to test/support/) to keep each test file self-contained and async-safe
  - Forbidden-substring assertions use String.contains?/2 rather than exact match to remain robust to whitespace formatting changes
  - Role :user with default invite policy always has INVITES hidden; :sysop always sees it (per D-07)
metrics:
  duration: "~75 minutes"
  completed: "2026-04-23T18:17:03Z"
  tasks_completed: 2
  files_created: 4
  files_modified: 3
---

# Phase 0 Plan 01: Wave 0 Failing Test Bed Summary

**One-liner:** Failing TDD test bed locking tab contracts, role-gate semantics, forbidden-action guards, and InvitesSurface visibility matrix for Account, Moderation, Sysop, and shared INVITES shells.

## What Was Built

Four new test files and three extended test files establishing the Wave 0 contract for Phase 0. All new assertions are in RED (failing) state — production modules do not yet exist. Existing tests are unaffected.

### Test Files Created

| File | Module | Tests | Coverage |
|------|--------|-------|----------|
| `test/foglet_bbs/tui/screens/account_test.exs` | `Foglet.TUI.Screens.AccountTest` | 11 | ACCT-01: tabs, INVITES visibility, key nav, forbidden commands |
| `test/foglet_bbs/tui/screens/moderation_test.exs` | `Foglet.TUI.Screens.ModerationTest` | 10 | MODR-01: 5-tab set, placeholder guards, key nav |
| `test/foglet_bbs/tui/screens/sysop_test.exs` | `Foglet.TUI.Screens.SysopTest` | 9 | SYSO-01: 5-tab set, key nav, no fake config writes |
| `test/foglet_bbs/tui/screens/shared/invites_surface_test.exs` | `Foglet.TUI.Screens.Shared.InvitesSurfaceTest` | 12 | T-00-04: title/default_state/visible?/render/no-fake-functions |

### Test Files Extended

| File | New Tests | Describe Block Added |
|------|-----------|---------------------|
| `test/foglet_bbs/tui/screens/main_menu_test.exs` | 10 | "Phase 0 shell entry points" |
| `test/foglet_bbs/tui/app_test.exs` | 5 | "Phase 0 screen routing" |
| `test/foglet_bbs/tui/layout_smoke_test.exs` | 3 | Account/Moderation/Sysop shell smoke tests |

## Decision-to-Test Mapping

| Decision | Test Assertion(s) |
|----------|------------------|
| D-01: Account is standard main-menu destination | main_menu_test "authenticated user with role :user sees Account menu entry" |
| D-02: Moderation/Sysop gated to :mod/:sysop | main_menu_test "role :user does NOT see Moderation/Sysop", "'M'/'m' returns :no_match for role :user" |
| D-03: New screens are Screen behaviour modules | account_test/moderation_test/sysop_test "render/1 does not crash with default screen state" |
| D-04: Each shell owns screen-local state | account_test/moderation_test/sysop_test "init_screen_state/1 returns struct with active_tab: 0" |
| D-05: Tabs use Foglet.TUI.Widgets.Input.Tabs | account_test "returns a struct with ... a Tabs wrapper state" (asserts %Tabs{} struct) |
| D-06: INVITES is Phase 0 scaffold only | invites_surface_test "default_state/0 returns struct with items: []" |
| D-07: INVITES conditionally shown | account_test "includes INVITES when role :sysop", "omits INVITES when visible?/2 returns false" |
| D-08: Account has PROFILE and PREFS | account_test "shows PROFILE and PREFS tab labels by default" |
| D-09: Account carries INVITES scaffold | account_test "includes INVITES when InvitesSurface.visible?/2 returns true" |
| D-10: Moderation has QUEUE/LOG/USERS/SANCTIONS/BOARDS | moderation_test "shows all five tab labels ... in that order" |
| D-11: Sysop has SITE/BOARDS/LIMITS/SYSTEM/USERS | sysop_test "shows all five tab labels in order: SITE, BOARDS, LIMITS, SYSTEM, USERS" |
| D-12: nil=loading, []=placeholder semantics | invites_surface_test "with %{items: nil} renders loading branch", "with %{items: []} renders placeholder copy" |
| D-13: Phase 0 placeholder must stay non-operational | account_test/moderation_test/sysop_test "renders scaffold-only placeholder copy (no fake ...)" |

## Security Threat Guards Encoded

| Threat ID | Guard Tests |
|-----------|-------------|
| T-00-01 (Info Disclosure) | account_test "renders scaffold-only placeholder copy (no fake save buttons)", "does NOT dispatch any fake operator commands" |
| T-00-02 (Elevation of Privilege) | main_menu_test "'M'/'m' returns :no_match for role :user", moderation_test "does NOT dispatch fake moderation commands" |
| T-00-03 (Elevation of Privilege) | main_menu_test "'S'/'s' returns :no_match for role :mod and :user", sysop_test "does NOT dispatch fake config-write commands" |
| T-00-04 (Tampering) | invites_surface_test "InvitesSurface defines no fake generate/revoke functions" (refute function_exported?) |

## RED State Verification

After plan completion, all four new test files fail with `UndefinedFunctionError` — the production modules (`Foglet.TUI.Screens.Account`, `Foglet.TUI.Screens.Moderation`, `Foglet.TUI.Screens.Sysop`, `Foglet.TUI.Screens.Shared.InvitesSurface`) do not yet exist. This is the expected Wave 0 outcome.

Extended test files (main_menu_test, app_test, layout_smoke_test) have existing tests passing and new Phase 0 assertions failing — regression safety is preserved.

## Commits

| Task | Commit | Files |
|------|--------|-------|
| Task 1: Four new failing test files | `39ce632` | account_test.exs, moderation_test.exs, sysop_test.exs, shared/invites_surface_test.exs |
| Task 2: Three extended test files | `aac6dbc` | main_menu_test.exs, app_test.exs, layout_smoke_test.exs |

## Deviations from Plan

None — plan executed exactly as written. The `collect_text_values/1` helper was duplicated per file (executor judgment per plan guidance) rather than extracted to `test/support/` to keep async-safe test isolation.

## Known Stubs

None — this plan contains only test files. No production stubs exist in this plan's output.

## Threat Flags

None — this plan creates test files only. No new network endpoints, auth paths, or schema changes introduced.

## Self-Check: PASSED

Files confirmed present:
- `test/foglet_bbs/tui/screens/account_test.exs` — FOUND
- `test/foglet_bbs/tui/screens/moderation_test.exs` — FOUND
- `test/foglet_bbs/tui/screens/sysop_test.exs` — FOUND
- `test/foglet_bbs/tui/screens/shared/invites_surface_test.exs` — FOUND

Commits confirmed:
- `39ce632` — FOUND (test(00-01): add failing test bed for Account, Moderation, Sysop shells and InvitesSurface)
- `aac6dbc` — FOUND (test(00-01): extend main_menu, app, and layout_smoke tests with Phase 0 shell assertions)
