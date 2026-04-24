---
phase: 06-chrome-clock-and-main-menu-wiring
plan: 03
subsystem: tui
tags: [elixir, exunit, raxol, tui, chrome, main-menu]

requires:
  - phase: 06-chrome-clock-and-main-menu-wiring
    provides: deterministic RED tests for main-menu clock subscription and tick handling
provides:
  - Main-menu-only Raxol interval subscription for clock refresh
  - Explicit no-op App.update/2 handler for main-menu clock ticks
  - Heartbeat-separated refresh path for MENU-02
affects: [phase-06, tui-app, main-menu-clock]

tech-stack:
  added: []
  patterns:
    - Screen-scoped Raxol interval subscriptions via App.subscribe/1
    - No-op update handlers for render-only refresh ticks

key-files:
  created:
    - .planning/phases/06-chrome-clock-and-main-menu-wiring/06-03-SUMMARY.md
  modified:
    - lib/foglet_bbs/tui/app.ex

key-decisions:
  - "Main-menu clock refresh uses a dedicated :main_menu_clock_tick subscription instead of reusing :heartbeat_tick."
  - "The clock tick handler returns {state, []} so refresh messages trigger rerender without mutating navigation, modal, or domain-loaded state."

patterns-established:
  - "App.subscribe/1 builds heartbeat, clock, and PubSub subscription lists separately before concatenation."
  - "Render-only timer messages should have explicit no-op update clauses near related lifecycle handlers."

requirements-completed: [MENU-02]

duration: 18min
completed: 2026-04-24
---

# Phase 06 Plan 03: Main-Menu Clock Refresh Summary

**Main-menu-only Raxol clock refresh subscription with explicit no-op tick handling**

## Performance

- **Duration:** 18 min
- **Started:** 2026-04-24T02:49:00Z
- **Completed:** 2026-04-24T03:07:40Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments

- Added `subscribe_interval(60_000, :main_menu_clock_tick)` only when `state.current_screen == :main_menu`.
- Preserved the existing 10-second `:heartbeat_tick` subscription and PubSub custom subscriptions as separate paths.
- Added an explicit `do_update(:main_menu_clock_tick, state), do: {state, []}` handler so clock ticks rerender without state mutation or commands.

## Task Commits

Each task was committed atomically:

1. **Task 1: Add main-menu-only interval subscription** - `fc0693e` (feat)
2. **Task 2: Add no-op clock tick update handler** - `fe60cc1` (feat)

**Plan metadata:** pending in final docs commit.

## Files Created/Modified

- `lib/foglet_bbs/tui/app.ex` - Adds main-menu clock interval subscription and explicit no-op tick handler.
- `.planning/phases/06-chrome-clock-and-main-menu-wiring/06-03-SUMMARY.md` - Records execution results for this plan.

## Decisions Made

Followed Phase 6 decisions D-08 through D-10: the clock refresh path is distinct from heartbeat, scoped to the main menu, and handled as a no-op state update.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Used worktree-local dependency/build symlinks for verification**
- **Found during:** Task 1 RED verification
- **Issue:** The isolated worktree did not have `deps/` or `_build/`, so `mix test test/foglet_bbs/tui/app_test.exs` stopped before running tests.
- **Fix:** Created temporary worktree-local symlinks to the main checkout's existing `deps/` and `_build/` directories for verification, then removed them before summary creation.
- **Files modified:** None committed.
- **Verification:** Focused tests and `mix precommit` ran successfully.
- **Committed in:** Not committed; temporary local setup only.

---

**Total deviations:** 1 auto-fixed (Rule 3)
**Impact on plan:** Verification could run in the isolated worktree without changing committed source scope.

## Issues Encountered

- Task 1's RED test failed for the expected reason: missing `:main_menu_clock_tick` interval subscription.
- Task 2's existing no-op test was already green before the explicit handler because the app has an unknown-message fallback returning `{state, []}`. The required explicit handler was still added and verified with source acceptance checks.
- `mix test test/foglet_bbs/tui/app_test.exs` emits existing async sandbox warnings from `ShellVisibility` config fallback tests, but the test run passes.

## Verification

- `mix test test/foglet_bbs/tui/app_test.exs` - RED before Task 1 implementation: 93 tests, 1 failure for missing clock subscription.
- `mix test test/foglet_bbs/tui/app_test.exs` - PASS after Task 1: 93 tests, 0 failures.
- `mix test test/foglet_bbs/tui/app_test.exs` - PASS after Task 2: 93 tests, 0 failures.
- `mix precommit` - PASS: compile, format, Credo, Sobelow, and Dialyzer completed successfully.

Acceptance checks:

- `rg -n "clock =|subscribe_interval\\(60_000, :main_menu_clock_tick\\)|heartbeat \\+\\+ clock \\+\\+ pubsub_subs" lib/foglet_bbs/tui/app.ex` - PASS.
- `rg -n "Process\\.send_after|GenServer\\.start_link|:heartbeat_tick.*main_menu_clock_tick|main_menu_clock_tick.*heartbeat_tick" lib/foglet_bbs/tui/app.ex` - PASS with no matches.
- `rg -n "defp do_update\\(:main_menu_clock_tick, state\\).*\\{state, \\[\\]\\}|defp do_update\\(:main_menu_clock_tick" lib/foglet_bbs/tui/app.ex` - PASS.
- `rg -n "main_menu_clock_tick.*heartbeat|heartbeat.*main_menu_clock_tick|Session\\.heartbeat\\(state\\.session_pid\\)" lib/foglet_bbs/tui/app.ex` - PASS by inspection: the only match is the existing `:heartbeat_tick` handler, not the clock handler.

## User Setup Required

None - no external service configuration required.

## TDD Gate Compliance

Plan 06-01 supplied the RED tests for this implementation plan. Task 1 observed the expected failing test before implementation. Task 2 did not produce a fresh RED failure because existing fallback behavior already returned `{state, []}` for unknown messages; the implementation still added the required explicit clause and passed source-level acceptance checks.

## Known Stubs

None.

## Threat Flags

None.

## Next Phase Readiness

Ready for downstream Phase 6 integration verification: the main-menu clock now renders through Plan 06-02 chrome work and refreshes at least once per minute while on the main menu.

## Self-Check: PASSED

- Summary file exists at `.planning/phases/06-chrome-clock-and-main-menu-wiring/06-03-SUMMARY.md`.
- Task commits exist: `fc0693e`, `fe60cc1`.
- No changes were made to `.planning/STATE.md` or `.planning/ROADMAP.md`.

---
*Phase: 06-chrome-clock-and-main-menu-wiring*
*Completed: 2026-04-24*
