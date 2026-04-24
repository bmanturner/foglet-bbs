---
phase: 07-oneliners-and-main-menu-social-strip
plan: 03
subsystem: tui
tags:
  - oneliners
  - main-menu
  - modal
  - app-state
requirements:
  - ONEL-01
  - ONEL-02
  - ONEL-03
dependency_graph:
  requires:
    - 07-01
    - 07-02
  provides:
    - App-owned oneliner loading and composer submit lifecycle
    - Focused oneliner modal validation error routing
  affects:
    - Foglet.TUI.App
    - Foglet.TUI.Modal
    - Foglet.TUI.Widgets.Modal
    - Foglet.TUI.Widgets.Modal.Form
    - Foglet.TUI.Widgets.Chrome.StatusBar
tech_stack:
  added: []
  patterns:
    - Raxol Command.task for app-owned I/O
    - Modal.Form callback payload stash consumed by App
key_files:
  created:
    - test/support/fake_oneliners.ex
  modified:
    - lib/foglet_bbs/tui/app.ex
    - lib/foglet_bbs/tui/modal.ex
    - lib/foglet_bbs/tui/screens/domain.ex
    - lib/foglet_bbs/tui/widgets/modal.ex
    - lib/foglet_bbs/tui/widgets/modal/form.ex
    - lib/foglet_bbs/tui/widgets/chrome/status_bar.ex
    - test/foglet_bbs/tui/app_test.exs
decisions:
  - Kept MainMenu pure; App owns load, modal, submit, refresh, and error state.
  - Preserved existing App.init/1 two-tuple contract and used explicit/App update load commands instead of returning init commands unsupported by Raxol lifecycle.
  - Reused the existing Modal.Form submit-stash pattern rather than changing the shared form widget contract.
metrics:
  completed_at: 2026-04-24T03:26:26Z
  duration: approximately 1h10m
  tasks_completed: 3
  commits: 4
---

# Phase 07 Plan 03: App-Owned Oneliner Composer Summary

App-owned oneliner loading, focused composer modal, submit/refresh lifecycle, and validation error display are wired into `Foglet.TUI.App`.

## Completed Tasks

| Task | Name | Commit | Result |
| ---- | ---- | ------ | ------ |
| 1 | Add App tests for load and composer lifecycle | 8e79d18 | Added RED coverage for oneliner load, composer open/cancel/submit, invalid error handling, and no hide UI exposure. |
| 2 | Implement App-owned oneliner load, modal submit, and refresh | 3c78d12 | Added `recent_oneliners`, `@oneliner_limit 5`, oneliner domain injection, command tasks, focused `Modal.Form`, submit result handling, and refresh after success. |
| 3 | Run final phase quality gate | a33a69e | Ran Phase 7 targeted tests and `mix precommit`; committed formatter/Credo cleanup. |

## Verification

| Command | Result |
| ------- | ------ |
| `mix test test/foglet_bbs/tui/app_test.exs` | Passed: 101 tests, 0 failures |
| `mix test test/foglet_bbs/tui/app_test.exs test/foglet_bbs/tui/screens/main_menu_test.exs test/foglet_bbs/oneliners/oneliners_test.exs` | Passed: 136 tests, 0 failures |
| `mix test test/foglet_bbs/oneliners/oneliners_test.exs test/foglet_bbs/tui/screens/main_menu_test.exs test/foglet_bbs/tui/app_test.exs test/foglet_bbs/tui/layout_smoke_test.exs` | Passed: 154 tests, 0 failures |
| `mix precommit` | Passed successfully |
| `rg "hide_oneliner\|Hide oneliner\|hidden_reason" lib/foglet_bbs/tui test/foglet_bbs/tui` | Only negative assertions in `app_test.exs`; no TUI hide action implementation found. |

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed struct Access in main-menu status clock**
- **Found during:** Task 2 verification
- **Issue:** Rendering `App.view/1` for main menu after oneliner success crashed because `StatusBar.clock_instant/1` used `get_in(state, [:session_context, :clock_now])` on `%Foglet.TUI.App{}`.
- **Fix:** Switched to `Map.get(state, :session_context)` followed by `Map.get(session_context, :clock_now)`.
- **Files modified:** `lib/foglet_bbs/tui/widgets/chrome/status_bar.ex`
- **Commit:** 3c78d12

**2. [Rule 2 - Missing Critical Functionality] Rendered base-level modal form errors**
- **Found during:** Task 2 verification
- **Issue:** Same-user latest-visible errors were stored as `:base` errors but `Modal.Form.render/2` only rendered field-specific errors.
- **Fix:** Added base error rendering below field rows so domain-level submit errors remain visible while the modal stays focused.
- **Files modified:** `lib/foglet_bbs/tui/widgets/modal/form.ex`
- **Commit:** 3c78d12

**3. [Rule 3 - Blocking Issue] Installed missing worktree dependencies**
- **Found during:** Task 1 RED verification
- **Issue:** The isolated worktree lacked Mix dependencies, so tests could not compile.
- **Fix:** Ran `mix deps.get` in `/tmp/foglet-bbs-phase-07-03` after approval.
- **Files modified:** None
- **Commit:** N/A

## Known Stubs

None. The fake oneliners module is test support only and the production path is wired to `Foglet.Oneliners` through `default_domain_module(:oneliners)`.

## Threat Flags

None. The plan's threat register already covered modal input, App-to-domain submit, domain-error display, and bounded load/refresh behavior.

## Notes

- Shared tracking files were intentionally not updated or committed from this worktree per parallel execution instructions.
- The main worktree was restored after an accidental early patch application; no tracked main-worktree changes remain from this executor.

## Self-Check: PASSED

- Found summary file: `.planning/phases/07-oneliners-and-main-menu-social-strip/07-03-SUMMARY.md`
- Found test support file: `test/support/fake_oneliners.ex`
- Found task commits: `8e79d18`, `3c78d12`, `a33a69e`
