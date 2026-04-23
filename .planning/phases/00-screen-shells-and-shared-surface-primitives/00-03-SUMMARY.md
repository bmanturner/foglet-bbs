---
phase: "00"
plan: "03"
subsystem: "tui-routing"
tags: [tui, app, routing, visibility, phase-00, shell-visibility]
dependency_graph:
  requires:
    - "00-01 (app routing infrastructure, test scaffolding)"
    - "00-02 (InvitesSurface.visible?/2 interface)"
  provides:
    - "App routing seams for :account, :moderation, :sysop screens"
    - "ShellVisibility helper with 4 predicates for Plan 07 (MainMenu wiring) and Plans 04-06 (shells)"
  affects:
    - "Plans 04-06 (shell implementations can plug into routing with one-line change)"
    - "Plan 07 (MainMenu consumes ShellVisibility predicates directly)"
tech_stack:
  added: []
  patterns:
    - "Centralized visibility predicate module (ShellVisibility)"
    - "Compile-time stub modules to satisfy Elixir's --warnings-as-errors without real implementations"
key_files:
  created:
    - "lib/foglet_bbs/tui/screens/shell_visibility.ex"
    - "lib/foglet_bbs/tui/screens/shared/invites_surface.ex (stub — Plan 02 replaces)"
    - "lib/foglet_bbs/tui/screens/account.ex (stub — Plan 04 replaces)"
    - "lib/foglet_bbs/tui/screens/moderation.ex (stub — Plan 05 replaces)"
    - "lib/foglet_bbs/tui/screens/sysop.ex (stub — Plan 06 replaces)"
    - "test/foglet_bbs/tui/screens/shell_visibility_test.exs"
  modified:
    - "lib/foglet_bbs/tui/app.ex (@type screen union extended, 3 screen_module_for/1 clauses added)"
decisions:
  - "Created compile-time stub modules for missing dependencies (Plans 02, 04-06) rather than using @compile {:nowarn_undefined_function} or apply/3, keeping the real dispatch path clean"
  - "ShellVisibility invites_visible?/2 delegates entirely to InvitesSurface.visible?/2 rather than duplicating the policy/role matrix"
metrics:
  duration: "8 minutes"
  completed_date: "2026-04-23"
  tasks_completed: 2
  files_created: 6
  files_modified: 1
---

# Phase 00 Plan 03: App Routing Seams and Shell Visibility Helper Summary

App routing seams for :account/:moderation/:sysop added to `Foglet.TUI.App` and a centralized `ShellVisibility` helper created with four role/config predicates, satisfying the Security Domain mitigation against visibility drift (Pitfall 3).

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Create Foglet.TUI.Screens.ShellVisibility helper module | 223718c | shell_visibility.ex, invites_surface.ex (stub), shell_visibility_test.exs |
| 2 | Extend App @type screen union and screen_module_for/1 | 997912e | app.ex, account.ex (stub), moderation.ex (stub), sysop.ex (stub) |

## What Was Built

### Task 1: ShellVisibility Helper

Created `lib/foglet_bbs/tui/screens/shell_visibility.ex` with four predicates:

- `account_visible?/1` — `true` for any non-nil user (D-01)
- `moderation_visible?/1` — `true` for `:mod` and `:sysop` roles (D-02)
- `sysop_visible?/1` — `true` only for `:sysop` role (D-02)
- `invites_visible?/2` — resolves policy from `session_context[:invite_code_generators]` with fallback to `Foglet.Config.invite_code_generators/0`, delegates to `InvitesSurface.visible?/2`

All predicates handle `nil` user and maps without a `:role` key safely. The `config_policy_or_nil/0` helper wraps the Config read in `rescue` and `catch :exit` to handle ETS-not-seeded and DB-unavailable scenarios — returns `nil` (hides for non-sysops, safe default).

TDD cycle: 15 unit tests written (RED: all fail on missing module), then module implemented (GREEN: all 15 pass).

### Task 2: App Routing Extension

Two targeted edits to `lib/foglet_bbs/tui/app.ex`:

1. `@type screen` union extended to append `| :account | :moderation | :sysop`
2. Three `screen_module_for/1` clauses added after the existing nine (total: 12)

The diff:

```elixir
# @type screen union — added at end:
          | :account
          | :moderation
          | :sysop

# screen_module_for/1 — appended before closing `end`:
  defp screen_module_for(:account), do: Screens.Account
  defp screen_module_for(:moderation), do: Screens.Moderation
  defp screen_module_for(:sysop), do: Screens.Sysop
```

## Navigation Tests

The existing app_test.exs has no `describe "Phase 0 screen routing"` block yet — Plan 01's agent adds those in its worktree. The existing test at line 77-80 (`:navigate changes current_screen`) tests `:board_list`; it confirms the navigation mechanism works. All 85 existing tests pass.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Created InvitesSurface stub to resolve compile-time warning**
- **Found during:** Task 1 compile with `--warnings-as-errors`
- **Issue:** `ShellVisibility` aliases `Foglet.TUI.Screens.Shared.InvitesSurface` and calls `visible?/2`. Since Plan 02 creates the real module in a parallel worktree not yet merged, Elixir raises `warning: Foglet.TUI.Screens.Shared.InvitesSurface.visible?/2 is undefined`, which becomes an error under `--warnings-as-errors`.
- **Fix:** Created `lib/foglet_bbs/tui/screens/shared/invites_surface.ex` as a minimal stub (`def visible?(_user, _policy), do: false`). Plan 02's worktree creates the real module; when worktrees are merged, the real implementation replaces this stub.
- **Files created:** `lib/foglet_bbs/tui/screens/shared/invites_surface.ex`
- **Commit:** 223718c

**2. [Rule 3 - Blocking] Created Account/Moderation/Sysop screen stubs to resolve compile-time warnings**
- **Found during:** Task 2 compile with `--warnings-as-errors`
- **Issue:** `App.view` calls `screen_module_for(state.current_screen).render(state)` and `screen_module_for/1` now returns `Screens.Account`, `Screens.Moderation`, `Screens.Sysop`. Elixir warns about undefined `render/1` and `handle_key/2` on these modules, which fails under `--warnings-as-errors`.
- **Fix:** Created minimal stubs for each (`render/1` returns `nil`, `handle_key/2` returns `{state, []}`). Plans 04-06 replace these with real implementations.
- **Files created:** `lib/foglet_bbs/tui/screens/account.ex`, `lib/foglet_bbs/tui/screens/moderation.ex`, `lib/foglet_bbs/tui/screens/sysop.ex`
- **Commit:** 997912e

## Tests Status

| Test File | Status | Count |
|-----------|--------|-------|
| test/foglet_bbs/tui/screens/shell_visibility_test.exs | GREEN | 15/15 |
| test/foglet_bbs/tui/app_test.exs | GREEN | 85/85 |

### Render-Invoking Tests (Still RED)

The `App.view` routing for `:account`, `:moderation`, `:sysop` returns stub module output until Plans 04-06 replace the stubs. However, the stubs return `nil` from `render/1` rather than crashing, so view calls don't raise — they return `nil`. Any test that asserts meaningful rendered output for these screens must wait for Plans 04-06.

The `describe "view/1 routing"` block in `app_test.exs` tests only the screens that existed before Plan 03 (`:login` through `:new_thread`). No tests assert on the new screen renders yet.

## Threat Model Compliance

All four STRIDE items mitigated:

- **T-00-02/T-00-03**: `moderation_visible?/1` and `sysop_visible?/1` are the single source of truth — Plans 07 and 04-06 consume them rather than reimplementing.
- **T-00-04**: `invites_visible?/2` delegates to `InvitesSurface.visible?/2` (stub now, real in Plan 02). Policy resolution catches config read failures and returns `nil` → hides for non-sysops.
- **T-00-ROUTE**: `:account | :moderation | :sysop` added to the closed `@type screen` union; `screen_module_for/1` is exhaustive over the union (no `_` catch-all).

## Known Stubs

| Stub | File | Reason |
|------|------|--------|
| `InvitesSurface.visible?/2` always returns `false` | `lib/foglet_bbs/tui/screens/shared/invites_surface.ex` | Real implementation from Plan 02 worktree — replaces on merge |
| `Account.render/1` returns `nil` | `lib/foglet_bbs/tui/screens/account.ex` | Real implementation from Plan 04 — replaces on merge |
| `Moderation.render/1` returns `nil` | `lib/foglet_bbs/tui/screens/moderation.ex` | Real implementation from Plan 05 — replaces on merge |
| `Sysop.render/1` returns `nil` | `lib/foglet_bbs/tui/screens/sysop.ex` | Real implementation from Plan 06 — replaces on merge |

## Self-Check: PASSED

All created files exist on disk. Both task commits (223718c, 997912e) verified in git log. No missing items.
