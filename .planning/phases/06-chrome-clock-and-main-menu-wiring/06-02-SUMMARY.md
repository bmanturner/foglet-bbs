---
phase: 06-chrome-clock-and-main-menu-wiring
plan: 02
subsystem: tui
tags: [elixir, exunit, raxol, tui, chrome, clock]

requires:
  - phase: 06-chrome-clock-and-main-menu-wiring
    provides: deterministic RED tests for chrome clock behavior
provides:
  - Preference-aware pure chrome clock formatter
  - Main-menu-only status-bar clock plus handle rendering
  - Persistence-free status-bar clock integration
affects: [phase-06, tui-chrome, main-menu, account-preferences]

tech-stack:
  added: []
  patterns:
    - Pure formatter consuming user timezone and preferences snapshot
    - StatusBar private helper branch scoped to authenticated main-menu chrome

key-files:
  created:
    - lib/foglet_bbs/tui/widgets/chrome/clock_formatter.ex
  modified:
    - lib/foglet_bbs/tui/widgets/chrome/status_bar.ex

key-decisions:
  - "StatusBar renders clock text only for authenticated :main_menu state; all other screens keep existing identity text."
  - "ClockFormatter defaults invalid or missing timezone to Etc/UTC and invalid or missing time_format to 12h."

patterns-established:
  - "Clock rendering uses state.current_user and state.session_context only; no persistence reads occur in chrome render code."

requirements-completed: [MENU-01]

duration: 24min
completed: 2026-04-24
---

# Phase 06 Plan 02: Main-Menu Chrome Clock Summary

**Preference-aware main-menu clock rendering through shared StatusBar chrome**

## Performance

- **Duration:** 24 min
- **Started:** 2026-04-24T02:37:00Z
- **Completed:** 2026-04-24T03:01:09Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments

- Added `Foglet.TUI.Widgets.Chrome.ClockFormatter.format/2` with deterministic timezone conversion and 12h/24h formatting.
- Wired `StatusBar.render/2` to show `"YYYY-MM-DD ...  @handle"` only for authenticated main-menu chrome.
- Preserved non-main-menu authenticated text as `@handle ` and guest text as `guest `.

## Task Commits

Each task was committed atomically:

1. **Task 1: Implement pure clock formatter** - `3eaa003` (feat)
2. **Task 2: Wire StatusBar main-menu clock branch** - `e33c506` (feat)

**Plan metadata:** pending in final docs commit.

## Files Created/Modified

- `lib/foglet_bbs/tui/widgets/chrome/clock_formatter.ex` - Pure formatter for fixed UTC instants, user timezone, and `preferences["time_format"]`.
- `lib/foglet_bbs/tui/widgets/chrome/status_bar.ex` - Main-menu-only clock composition via `ClockFormatter`, with deterministic `session_context[:clock_now]` test seam.

## Decisions Made

Followed the plan's locked ownership: `StatusBar` owns the clock and `ScreenFrame.render/4` remains the chrome path. The implementation reads only `state.current_user` and `state.session_context`, preserving the no-persistence render boundary.

## Deviations from Plan

None - plan executed exactly as written.

---

**Total deviations:** 0 auto-fixed.
**Impact on plan:** None.

## Issues Encountered

- The isolated worktree did not contain `deps/` or `_build/`, so temporary symlinks to the main checkout's existing dependency/build directories were used for verification and removed before the summary commit.
- Task 1's RED tests were supplied by Plan 06-01, so this plan produced implementation commits rather than duplicating test-only RED commits.

## Verification

- `mix test test/foglet_bbs/tui/widgets/chrome/status_bar_test.exs:10 test/foglet_bbs/tui/widgets/chrome/status_bar_test.exs:27 test/foglet_bbs/tui/widgets/chrome/status_bar_test.exs:42 test/foglet_bbs/tui/widgets/chrome/status_bar_test.exs:57` - PASS: formatter-focused cases passed.
- `mix test test/foglet_bbs/tui/widgets/chrome/status_bar_test.exs test/foglet_bbs/tui/layout_smoke_test.exs` - PASS: 24 tests, 0 failures.
- `mix precommit` - PASS: compile, format, Credo, Sobelow, and Dialyzer completed successfully.

Acceptance checks:

- `test -f lib/foglet_bbs/tui/widgets/chrome/clock_formatter.ex` - PASS.
- Required `ClockFormatter` `rg` checks for module, spec, Timex validation/conversion, UTC fallback, and 12h/24h strings - PASS.
- Forbidden HTTP/wall-clock `rg` check in `clock_formatter.ex` - PASS with no matches.
- Required `StatusBar` `rg` checks for `ClockFormatter`, `current_screen: :main_menu`, `clock_now`, `DateTime.utc_now`, and `Foglet BBS —` - PASS.
- Forbidden persistence `rg` check in `status_bar.ex` and `clock_formatter.ex` - PASS with no matches.

## User Setup Required

None - no external service configuration required.

## Known Stubs

None.

## Threat Flags

None.

## Next Phase Readiness

Ready for Plan 06-03 to add the main-menu-only clock refresh subscription and no-op tick handling in `Foglet.TUI.App`.

## Self-Check: PASSED

- Summary file exists at `.planning/phases/06-chrome-clock-and-main-menu-wiring/06-02-SUMMARY.md`.
- Task commits exist: `3eaa003`, `e33c506`.
- No changes were made to `.planning/STATE.md` or `.planning/ROADMAP.md`.

---
*Phase: 06-chrome-clock-and-main-menu-wiring*
*Completed: 2026-04-24*
