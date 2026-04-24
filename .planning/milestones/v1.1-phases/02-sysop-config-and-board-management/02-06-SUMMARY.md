---
phase: 02-sysop-config-and-board-management
plan: 02-06
subsystem: ui
tags: [tui, sysop, boards, limits, error-handling, regression-tests]
requires:
  - phase: 02-sysop-config-and-board-management
    provides: "Existing SITE/LIMITS/BOARDS/SYSTEM sysop TUI surfaces and actor-aware board mutations"
provides:
  - "BOARDS Modal.Form submit atom errors route to the shared error modal"
  - "Board creation startup failures are normalized to {:error, :board_server_unavailable}"
  - "LIMITS ordinary character input is nil-safe and does not raise BadBooleanError"
  - "Category display-order submit errors remain inline instead of silently saving as 0"
  - "Regression coverage for Phase 02 verification and review gaps"
affects: [sysop-tui, board-management, runtime-config]
tech-stack:
  added: []
  patterns:
    - "TUI submit handlers reset local modal state before emitting parent error modal events"
    - "Plain Raxol char handlers use nil-safe || modifier checks"
key-files:
  created:
    - ".planning/phases/02-sysop-config-and-board-management/02-06-SUMMARY.md"
  modified:
    - "lib/foglet_bbs/boards.ex"
    - "lib/foglet_bbs/tui/screens/sysop/boards_view.ex"
    - "lib/foglet_bbs/tui/screens/sysop/limits_form.ex"
    - "test/foglet_bbs/tui/screens/sysop_test.exs"
key-decisions:
  - "Board supervisor startup exits are normalized inside Foglet.Boards.create_board/3 so the existing documented atom error contract is reliable for callers."
  - "BOARDS atom submit errors use a specific message for :board_server_unavailable and a generic atom fallback that includes inspect(reason)."
patterns-established:
  - "Board form atom errors reset the active Modal.Form state and route through {:error_modal, message, :main_menu}."
requirements-completed: [SYSO-02, SYSO-03]
duration: 8 min
completed: 2026-04-24
---

# Phase 02 Plan 06: Sysop Gap Closure Summary

**Crash-safe sysop BOARDS atom-error routing and LIMITS plain-character handling with focused TUI regressions**

## Performance

- **Duration:** 8 min
- **Started:** 2026-04-24T14:22:00Z
- **Completed:** 2026-04-24T14:30:17Z
- **Tasks:** 2
- **Files modified:** 4

## Accomplishments

- BOARDS Modal.Form submit now handles `{:error, reason}` atom tuples without `CaseClauseError`.
- `Foglet.Boards.create_board/3` now catches board-supervisor startup exits and returns the documented `{:error, :board_server_unavailable}` tuple.
- LIMITS ordinary character input now uses a nil-safe modifier guard and ignores non-digit input without raising.
- Category Modal.Form display-order submit now keeps invalid input inline instead of normalizing it to `0`.
- Added regression tests for the failure paths through `Sysop.handle_key/2`.

## Task Commits

1. **Task 1: Route BOARDS Modal.Form atom errors to safe error modal** - `76f6821` (fix)
2. **Task 2: Fix LIMITS plain char BadBooleanError and run phase gate** - `76f6821` (fix)
3. **Review follow-up: Preserve category display-order validation** - `80f42e5` (fix)

## Files Created/Modified

- `lib/foglet_bbs/boards.ex` - Widened `create_board/3` spec and normalized board-supervisor startup exits.
- `lib/foglet_bbs/tui/screens/sysop/boards_view.ex` - Added generic atom-error submit handling and user-facing board-server-unavailable message.
- `lib/foglet_bbs/tui/screens/sysop/limits_form.ex` - Replaced strict boolean `or` with nil-safe `||` for char-event modifier checks.
- `test/foglet_bbs/tui/screens/sysop_test.exs` - Added BOARDS atom-error and LIMITS plain-character regressions.

## Decisions Made

- Normalize `DynamicSupervisor.start_child/2` exits in the Boards context instead of letting a missing supervisor crash callers. This keeps the context's documented return shape true and gives the TUI a safe, testable error contract.
- Use one atomic code commit for both tightly coupled gap fixes because both were part of the same verification-gap closure plan and shared the same regression test file.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 2 - Missing Critical] Normalized board supervisor startup exits**
- **Found during:** Task 1 (BOARDS atom-error regression)
- **Issue:** Stopping `Foglet.Boards.Supervisor` can make `DynamicSupervisor.start_child/2` exit with `:noproc` instead of returning an error tuple.
- **Fix:** Wrapped `BoardSupervisor.start_board/1` in `start_board_server/1` and converted exits into `{:error, reason}` for the existing rollback path.
- **Files modified:** `lib/foglet_bbs/boards.ex`
- **Verification:** `rtk mix test test/foglet_bbs/tui/screens/sysop_test.exs --trace`
- **Committed in:** `76f6821`

---

**Total deviations:** 1 auto-fixed (missing critical).
**Impact on plan:** The fix stayed inside the planned context boundary and made the planned UI error handling reachable through the real domain contract.

## Issues Encountered

Advisory code review found that invalid category display-order input was silently normalized to `0`. Fixed in `80f42e5` by preserving invalid payloads as inline Modal.Form errors.

## Verification

- PASS: `rtk mix test test/foglet_bbs/tui/screens/sysop_test.exs --trace` — 35 tests, 0 failures.
- PASS: `rtk mix test test/foglet_bbs/config_test.exs test/foglet_bbs/boards/boards_test.exs test/foglet_bbs/tui/screens/sysop_test.exs` — 119 tests, 0 failures.
- PASS: `rtk mix compile --warnings-as-errors`.
- PASS: `rtk mix precommit`.
- PASS: Acceptance greps for `board_server_unavailable`, `{:error, reason} when is_atom(reason)`, nil-safe LIMITS modifier checks, and the plain-character regression.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

Phase 02 gap-closure implementation is ready for re-verification. The remaining phase-level decision is whether human SSH/TUI UAT is required after automated verification passes.

---
*Phase: 02-sysop-config-and-board-management*
*Completed: 2026-04-24*
