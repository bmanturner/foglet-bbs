---
phase: 05-account-preferences-and-live-session-refresh
plan: 04
subsystem: tui
tags: [account, preferences, sessions, live-refresh, tdd]

requires:
  - phase: 05-account-preferences-and-live-session-refresh
    provides: "Plans 01-03 persisted preferences, session snapshots, and Account form command emission"
provides:
  - "Account save command handling through Foglet.Accounts.update_profile/2"
  - "Live current_user, session_context, and Session GenServer preference refresh after successful saves"
  - "Failed-save changeset errors rendered without mutating active snapshots"
affects: [account-screen, live-session-refresh, chrome-clock]

tech-stack:
  added: []
  patterns:
    - "Account persistence commands are handled in Foglet.TUI.App and keep payloads allowlisted"
    - "Successful Account saves refresh live display snapshots through Foglet.Sessions.Preferences.from_user/1"

key-files:
  created: []
  modified:
    - lib/foglet_bbs/tui/app.ex
    - test/foglet_bbs/tui/screens/account_test.exs

key-decisions:
  - "Kept Account saves on the existing Accounts.update_profile/2 boundary."
  - "Updated Session state only after Accounts persistence succeeds."
  - "Mapped Ecto changeset errors into Account profile/prefs error maps without refreshing current_user or session_context."

patterns-established:
  - "Live preference refresh: updated user -> Preferences.from_user/1 -> session_context merge -> Session.update_preferences/2."
  - "Account save failure: keep active snapshots unchanged and render field errors from the changeset."

requirements-completed: [ACCT-02, ACCT-03, ACCT-04, ACCT-05, ACCT-06]

duration: 8min
completed: 2026-04-24
---

# Phase 05 Plan 04: Account Save Refresh Summary

**Account saves now persist profile/preferences and refresh active TUI plus Session snapshots without reconnecting.**

## Performance

- **Duration:** 8 min
- **Started:** 2026-04-24T02:31:00Z
- **Completed:** 2026-04-24T02:38:25Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments

- Added Account save handling in `Foglet.TUI.App` for `{:account_save_profile, attrs}` and `{:account_save_prefs, attrs}`.
- Restricted save payloads to private profile fields and presentation preferences only.
- Refreshed `state.current_user`, `state.session_context`, and `Foglet.Sessions.Session` from the persisted user after successful saves.
- Rendered failed-save changeset errors while leaving `current_user`, `session_context`, and Session state unchanged.
- Ran Phase 5 targeted validation and final `mix precommit`.

## Task Commits

Each task was committed atomically:

1. **Task 1 RED: Account save refresh tests** - `2fd655e` (test)
2. **Task 1 GREEN: Account save refresh implementation** - `174836a` (feat)
3. **Task 2: Final precommit cleanup** - `8bd163f` (style)

**Plan metadata:** this summary commit

## Files Created/Modified

- `lib/foglet_bbs/tui/app.ex` - Handles Account save commands, calls `Accounts.update_profile/2`, refreshes live snapshots, updates `Session.update_preferences/2`, and maps changeset errors into Account state.
- `test/foglet_bbs/tui/screens/account_test.exs` - Adds integration coverage for successful profile/preference saves and failed-save non-refresh behavior.

## Decisions Made

- Used the existing Accounts mutation boundary rather than adding a TUI-specific persistence API.
- Built live refresh from `Preferences.from_user/1` so Account saves share the same snapshot shape as SSH startup and session promotion.
- Kept failed saves synchronous in App state: no Session cast occurs unless persistence returns `{:ok, updated_user}`.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Static Analysis] Reordered App aliases for Credo**
- **Found during:** Task 2 (Run Phase 5 validation and final precommit)
- **Issue:** `mix precommit` failed Credo strict because new aliases in `Foglet.TUI.App` were not alphabetically ordered.
- **Fix:** Reordered the alias group without changing behavior.
- **Files modified:** `lib/foglet_bbs/tui/app.ex`
- **Verification:** `mix precommit` passed.
- **Committed in:** `8bd163f`

---

**Total deviations:** 1 auto-fixed (Rule 1)
**Impact on plan:** Static-analysis cleanup only; no scope change.

## Issues Encountered

- The initial RED tests failed as expected because Account save commands were no-ops in `Foglet.TUI.App`.
- Vendored Raxol warnings still print during Mix commands; they are pre-existing and did not fail the project gates.

## Verification

- `mix test test/foglet_bbs/tui/screens/account_test.exs test/foglet_bbs/sessions/session_test.exs` - passed, 39 tests.
- `mix test test/foglet_bbs/accounts/accounts_test.exs test/foglet_bbs/sessions/session_test.exs test/foglet_bbs/tui/screens/account_test.exs` - passed, 77 tests.
- `mix precommit` - passed, including compile, format, Credo strict, Sobelow, and Dialyzer.
- `rg -n "once-per-minute|MENU-01|MENU-02|clock" lib/foglet_bbs/tui` - no new Phase 6 clock implementation in changed Phase 5 files; only pre-existing clock references in shared/sysop support files.

## Known Stubs

None.

## Threat Flags

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

Phase 6 can consume live `session_context.timezone`, `time_format`, `theme_id`, and `theme` immediately after Account saves. The backing Session process is refreshed without reconnecting, so chrome clock rendering can rely on current session state.

## Self-Check: PASSED

- Confirmed modified plan files exist.
- Confirmed commits `2fd655e`, `174836a`, and `8bd163f` exist in git history.
- Confirmed this executor did not modify `.planning/STATE.md` or `.planning/ROADMAP.md`.

---
*Phase: 05-account-preferences-and-live-session-refresh*
*Completed: 2026-04-24*
