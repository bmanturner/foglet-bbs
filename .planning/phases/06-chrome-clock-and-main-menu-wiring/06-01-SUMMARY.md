---
phase: 06-chrome-clock-and-main-menu-wiring
plan: 01
subsystem: tui
tags: [elixir, exunit, raxol, tui, chrome, main-menu]

requires:
  - phase: 05-account-preferences-and-live-session-refresh
    provides: user timezone, time_format preference, and live session preference snapshots
provides:
  - Deterministic RED coverage for chrome clock formatting and status-bar integration
  - Main-menu-only clock subscription and no-op tick regression tests
  - ShellVisibility drift regression for menu rows, key-bar labels, and navigation keys
affects: [phase-06, tui-chrome, main-menu, shell-visibility]

tech-stack:
  added: []
  patterns:
    - Fixed-instant clock assertions with explicit timezone and time_format inputs
    - Role-table visibility tests deriving expected behavior from ShellVisibility

key-files:
  created:
    - test/foglet_bbs/tui/widgets/chrome/status_bar_test.exs
  modified:
    - test/foglet_bbs/tui/app_test.exs
    - test/foglet_bbs/tui/screens/main_menu_test.exs

key-decisions:
  - "Wave 0 intentionally leaves production code untouched so later Phase 6 implementation plans turn the RED tests green."
  - "Clock tests use fixed UTC instants and explicit timezone/time_format inputs instead of wall-clock assertions."

patterns-established:
  - "Clock RED tests assert deterministic date/time substrings and main-menu-only chrome behavior."
  - "Main-menu drift tests use ShellVisibility predicates as the expected source of truth."

requirements-completed: [MENU-01, MENU-02]

duration: 42min
completed: 2026-04-24
---

# Phase 06 Plan 01: Wave 0 Validation Net Summary

**Deterministic ExUnit coverage for Phase 6 chrome clock rendering, main-menu refresh ticks, and ShellVisibility-aligned navigation behavior**

## Performance

- **Duration:** 42 min
- **Started:** 2026-04-24T02:11:00Z
- **Completed:** 2026-04-24T02:53:11Z
- **Tasks:** 3
- **Files modified:** 3

## Accomplishments

- Added `StatusBar` / `ClockFormatter` tests with fixed `~U[...]` instants for 24-hour, 12-hour, invalid preference fallback, and missing preference fallback cases.
- Added `App.subscribe/1` tests for a main-menu-only `:main_menu_clock_tick` interval no slower than 60 seconds, plus a no-op tick preservation test.
- Added role-table regression coverage proving rendered menu rows, key-bar labels, and `A`/`M`/`S` key handling match `ShellVisibility`.

## Task Commits

1. **Task 1: Add deterministic chrome clock tests** - `c670813` (test)
2. **Task 2: Add main-menu clock subscription tests** - `ae9c9ba` (test)
3. **Task 3: Add ShellVisibility drift regression tests** - `9953f5b` (test)

**Plan metadata:** pending in final docs commit.

## Files Created/Modified

- `test/foglet_bbs/tui/widgets/chrome/status_bar_test.exs` - New deterministic RED coverage for clock formatting and main-menu status bar clock text.
- `test/foglet_bbs/tui/app_test.exs` - Added main-menu clock interval and no-op tick invariants.
- `test/foglet_bbs/tui/screens/main_menu_test.exs` - Added ShellVisibility-driven role-table assertions for rows, key-bar labels, and keys.

## Decisions Made

Followed the plan's Wave 0 intent: production implementation was not added in this plan. The focused validation command remains RED until Plans 02 and 03 add `ClockFormatter`, status-bar clock integration, and the main-menu interval subscription.

## Deviations from Plan

None - plan executed exactly as written.

---

**Total deviations:** 0 auto-fixed.
**Impact on plan:** None.

## Issues Encountered

- Worktree-local `deps/` and `_build/` were absent, so initial `mix test` could not load dependencies. Temporary symlinks to the main repo's existing dependency/build directories were used for verification and removed before commits.
- Mix needed escalated execution because `Mix.PubSub` opens a local TCP socket in this sandbox. Verification was rerun with approval.

## Verification

- `mix test test/foglet_bbs/tui/widgets/chrome/status_bar_test.exs` - RED as expected: 6 tests, 5 failures for missing `ClockFormatter` and missing main-menu status-bar clock text.
- `mix test test/foglet_bbs/tui/app_test.exs` - RED as expected: 93 tests, 1 failure for missing `:main_menu_clock_tick` interval subscription.
- `mix test test/foglet_bbs/tui/screens/main_menu_test.exs` - PASS: 20 tests, 0 failures.
- `mix test test/foglet_bbs/tui/widgets/chrome/status_bar_test.exs test/foglet_bbs/tui/app_test.exs test/foglet_bbs/tui/screens/main_menu_test.exs` - RED as expected: 119 tests, 6 failures.

Acceptance checks:

- `test -f test/foglet_bbs/tui/widgets/chrome/status_bar_test.exs` - PASS.
- Required `rg` checks for `ClockFormatter.format`, `StatusBar.render`, fixed instants, timezone, and time format strings - PASS.
- Wall-clock anti-pattern `rg` check for `DateTime.utc_now|Timex.now|Timezone.local` in `status_bar_test.exs` - PASS with no matches.
- Required `rg` checks for `main_menu_clock_tick`, `60_000`, main-menu and board-list screen values - PASS.
- Required `rg` checks for preserved App state fields in the clock tick test - PASS.
- Required `rg` checks for `ShellVisibility` predicates and menu/key labels - PASS.
- Private `visible_menu_items/1` and `visible_menu_keys/1` remain private in `MainMenu` - PASS.

`mix precommit` was not run because this Wave 0 validation plan is intentionally RED until later implementation plans. Running precommit now would fail on the planned RED tests.

## User Setup Required

None - no external service configuration required.

## Known Stubs

None.

## Threat Flags

None.

## Next Phase Readiness

Ready for Plan 06-02 to implement `Foglet.TUI.Widgets.Chrome.ClockFormatter` and main-menu `StatusBar` clock rendering against the new deterministic tests.

## Self-Check: PASSED

- Summary file exists at `.planning/phases/06-chrome-clock-and-main-menu-wiring/06-01-SUMMARY.md`.
- Task commits exist: `c670813`, `ae9c9ba`, `9953f5b`.
- No changes were made to `.planning/STATE.md` or `.planning/ROADMAP.md`.

---
*Phase: 06-chrome-clock-and-main-menu-wiring*
*Completed: 2026-04-24*
