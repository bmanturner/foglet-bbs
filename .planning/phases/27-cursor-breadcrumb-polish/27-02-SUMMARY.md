---
phase: 27-cursor-breadcrumb-polish
plan: "02"
subsystem: tui/chrome
tags: [breadcrumb, auth, login, tui, chrome]
dependency_graph:
  requires: []
  provides: [BREAD-01]
  affects:
    - lib/foglet_bbs/tui/widgets/chrome/breadcrumb_bar.ex
tech_stack:
  added: []
  patterns:
    - Central auth sub-state dispatch via login_parts/1 private function
key_files:
  created: []
  modified:
    - lib/foglet_bbs/tui/widgets/chrome/breadcrumb_bar.ex
    - test/foglet_bbs/tui/widgets/chrome/breadcrumb_test.exs
    - test/foglet_bbs/tui/screens/login_test.exs
decisions:
  - login_parts/1 uses Map.get(:sub, :menu) so missing sub key safely falls through to [Foglet, Login]
  - :reset_consume breadcrumb state is shape-only in Phase 27; no token fields, Accounts calls, or delivery behavior added
metrics:
  duration: 8min
  completed: 2026-04-26
---

# Phase 27 Plan 02: Auth Breadcrumb Paths Summary

Central BreadcrumbBar mapping for all auth screens and Login sub-states, satisfying BREAD-01 with TDD coverage and no Phase 31 reset-token behavior leakage.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Specify auth breadcrumb paths (RED) | 9cbd79f | breadcrumb_test.exs, login_test.exs |
| 2 | Map auth screens in BreadcrumbBar (GREEN) | 35e9296 | breadcrumb_bar.ex |

## What Was Built

`BreadcrumbBar.parts_for/1` now correctly maps all auth screen states:

- `:register` -> `["Foglet", "Login", "Register"]`
- `:verify` -> `["Foglet", "Login", "Verify"]`
- `:login` with `sub: :reset_request` -> `["Foglet", "Login", "Forgot Password"]`
- `:login` with `sub: :reset_consume` -> `["Foglet", "Login", "Forgot Password", "Enter Token"]`
- `:login` with `sub: :menu` (or any unknown sub) -> `["Foglet", "Login"]`

The static `:login` clause was replaced by a `login_parts/1` dispatch that reads `screen_state[:login][:sub]`. No per-screen breadcrumb overrides exist in screens or widgets.

## Deviations from Plan

### TDD Gate Compliance

The RED phase for Task 1 showed tests passing in the first run against the main project directory. After switching to the worktree's Mix environment (`MIX_DEPS_PATH`/`MIX_BUILD_PATH` pointing to main project), 2 failures were correctly observed confirming the RED gate.

Otherwise: None - plan executed exactly as written.

## Known Stubs

None. All breadcrumb paths are fully wired.

## Threat Flags

None. The implementation satisfies T-27-04, T-27-05, and T-27-06:
- Auth screens cannot appear as root-only locations (centralized mapping with exact string tests)
- `:reset_consume` breadcrumb displays only "Enter Token" and no token values
- Escape from reset_request is tested to confirm menu breadcrumb collapse

## Self-Check: PASSED

- lib/foglet_bbs/tui/widgets/chrome/breadcrumb_bar.ex: present and modified
- test/foglet_bbs/tui/widgets/chrome/breadcrumb_test.exs: present and modified
- test/foglet_bbs/tui/screens/login_test.exs: present and modified
- Commit 9cbd79f: exists (RED test commit)
- Commit 35e9296: exists (GREEN implementation commit)
- 53 tests, 0 failures
