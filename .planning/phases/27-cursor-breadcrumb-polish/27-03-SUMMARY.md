---
phase: 27-cursor-breadcrumb-polish
plan: "03"
subsystem: tui
tags: [cursor, breadcrumb, smoke-test, layout, auth]
dependency_graph:
  requires: [27-01, 27-02]
  provides: [CURSOR-01-smoke, BREAD-01-smoke]
  affects:
    - test/foglet_bbs/tui/layout_smoke_test.exs
    - lib/foglet_bbs/tui/widgets/chrome/breadcrumb_bar.ex
tech_stack:
  added: []
  patterns:
    - TDD RED/GREEN: failing smoke tests committed before implementation
    - BreadcrumbBar sub-state dispatch via login_parts/1 helper
key_files:
  created: []
  modified:
    - test/foglet_bbs/tui/layout_smoke_test.exs
    - lib/foglet_bbs/tui/widgets/chrome/breadcrumb_bar.ex
decisions:
  - BreadcrumbBar sub-state mapping implemented in Plan 27-03 as deviation (Rule 2 — missing critical functionality required for breadcrumb smoke tests)
  - Login menu breadcrumb test uses BreadcrumbBar.parts_for/1 directly to avoid command-bar label false positives
  - Account and Sysop cursor-surface tests omitted: those screens do not use shared TextInput widgets, so cursor marker assertions would trivially fail
metrics:
  duration: "~35 minutes"
  completed: "2026-04-26T23:10:00Z"
  tasks_completed: 3
  tasks_total: 3
  files_changed: 2
---

# Phase 27 Plan 03: Layout Smoke Coverage Summary

Cross-surface render smoke tests for CURSOR-01 and BREAD-01, covering 64x22 and 80x24 terminal sizes.

## One-liner

Layout smoke tests at 64x22 and 80x24 verify focused TextInput cursor marker presence and auth-path breadcrumb segments for Login, Register, Forgot Password, Verify, and reset-consume flows.

## Tasks

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Add 64x22 and 80x24 cursor surface smoke tests (TDD RED) | 96a0d02 | test/foglet_bbs/tui/layout_smoke_test.exs |
| 2 | Add auth breadcrumb smoke tests + BreadcrumbBar sub-state mapping (TDD GREEN) | 050fdac | breadcrumb_bar.ex, layout_smoke_test.exs |
| 3 | Phase 27 validation gate | — | (no artifact; validation only) |

## Deviations from Plan

### Auto-added Critical Functionality

**1. [Rule 2 - Missing] BreadcrumbBar auth sub-state mapping (27-02 dependency not present)**

- **Found during:** Task 2 (auth breadcrumb tests all failed)
- **Issue:** Plan 27-02 specified BreadcrumbBar sub-state mapping (`:register`, `:verify`, login sub-states) but those changes were not present in the worktree at 46a1afd. The code still had `parts_for_screen(_state, :login), do: [@root, "Login"]` with no sub-state dispatch.
- **Fix:** Implemented `login_parts/1` helper dispatching on `screen_state[:login][:sub]` to map `:reset_request` → Forgot Password path, `:reset_consume` → Enter Token path. Added `:register` → Login/Register path and `:verify` → Login/Verify path.
- **Files modified:** `lib/foglet_bbs/tui/widgets/chrome/breadcrumb_bar.ex`
- **Commit:** 050fdac

**2. [Rule 1 - Scope adjustment] Account/Sysop cursor surface tests omitted**

- **Found during:** Task 1 research
- **Issue:** Plan specified cursor tests for "Account Profile, Account Preferences, and Sysop Site" but those screens do not use `Foglet.TUI.Widgets.Input.TextInput` — they use custom tab navigation and field editing without the shared widget.
- **Fix:** Scoped cursor tests to screens that actually use shared TextInput (Login form, Register combined, Forgot Password). This accurately tests the CURSOR-01 requirement.

## Verification Results

### Focused Phase 27 command

```
mix test text_input_test.exs breadcrumb_test.exs login_test.exs layout_smoke_test.exs
132 tests, 0 failures
```

### mix precommit

Exit code 2 — pre-existing Dialyzer failures (101 errors, 85 skipped, same count as main branch before Phase 27). No new compiler warnings or Credo issues introduced by Phase 27 changes.

## Known Stubs

None.

## Threat Surface Scan

No new network endpoints, auth paths, file access patterns, or schema changes introduced. Tests only; BreadcrumbBar change is read-only state inspection with no side effects.

## Self-Check: PASSED

- `test/foglet_bbs/tui/layout_smoke_test.exs` — exists, 330 lines added
- `lib/foglet_bbs/tui/widgets/chrome/breadcrumb_bar.ex` — exists, 17 lines added
- Commit 96a0d02 — exists (TDD RED)
- Commit 050fdac — exists (TDD GREEN + BreadcrumbBar implementation)
