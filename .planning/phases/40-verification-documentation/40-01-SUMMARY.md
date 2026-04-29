---
phase: 40-verification-documentation
plan: 01
subsystem: tui-verification
tags: [tui, modal-form, dialyzer, verification]
requires:
  - phase: 39-app-shell-simplification
    provides: Phase 39 deferred blocker inventory and runtime-shell cleanup baseline
provides:
  - Phase 40 carry-forward disposition register
  - BL-01 modal-submit recovery tests restored to the MainMenu path
  - Deferred BoardList and Sysop Dialyzer warnings resolved
affects: [phase-40-verification, tui-runtime-shell, final-precommit]
tech-stack:
  added: []
  patterns:
    - "Use confirmed synthetic users when tests need authenticated MainMenu routing."
    - "Remove Dialyzer-unreachable reducer branches rather than suppressing warnings."
key-files:
  created:
    - .planning/phases/40-verification-documentation/40-SUMMARY.md
    - .planning/phases/40-verification-documentation/40-01-SUMMARY.md
  modified:
    - lib/foglet_bbs/tui/screens/board_list.ex
    - lib/foglet_bbs/tui/screens/sysop.ex
    - test/foglet_bbs/tui/screens/account_test.exs
key-decisions:
  - "BL-01 tests should construct a confirmed user so App.init/1 starts on MainMenu instead of Verify."
  - "The Process-dictionary modal submit seam remains bounded; existing MainMenu error modal creation already drives Modal.Form submit_state to {:error, _}."
patterns-established:
  - "Close-gate registers record exact warning locations, dispositions, and command evidence."
requirements-completed: [VERIFY-01, VERIFY-05]
duration: 9m32s
completed: 2026-04-29T15:00:38Z
---

# Phase 40 Plan 01: Deferred Blocker Cleanup Summary

**Carry-forward register plus BL-01 focused test recovery and zero-warning Dialyzer cleanup for the Phase 39 deferred blockers.**

## Performance

- **Duration:** 9m32s
- **Started:** 2026-04-29T14:51:06Z
- **Completed:** 2026-04-29T15:00:38Z
- **Tasks:** 3
- **Files modified:** 5

## Accomplishments

- Created `.planning/phases/40-verification-documentation/40-SUMMARY.md` with the required carry-forward disposition register.
- Restored the BL-01 Account/MainMenu modal tests to the intended MainMenu path by confirming the synthetic user.
- Removed the two deferred Dialyzer blockers in `board_list.ex` and `sysop.ex`, then recorded closure evidence in the register.

## Task Commits

1. **Task 1: Create carry-forward disposition register** - `dfea016` (docs)
2. **Task 2: Fix BL-01 modal submit error recovery** - `6432288` (fix)
3. **Task 3: Resolve deferred Dialyzer warnings** - `79e451c` (fix)

## Files Created/Modified

- `.planning/phases/40-verification-documentation/40-SUMMARY.md` - Phase-level carry-forward disposition register and evidence slots.
- `.planning/phases/40-verification-documentation/40-01-SUMMARY.md` - This plan closeout summary.
- `test/foglet_bbs/tui/screens/account_test.exs` - Confirms the BL-01 synthetic user so the modal tests exercise MainMenu.
- `lib/foglet_bbs/tui/screens/board_list.ex` - Removes the unreachable unsubscribe fallback.
- `lib/foglet_bbs/tui/screens/sysop.ex` - Removes the impossible tuple-shaped invites helper overload.

## Verification

- `rtk rg -n "Carry-Forward Disposition Register|BL-01|board_list\\.ex:161|sysop\\.ex:823|WR-02|WR-04|IN-02|IN-03|IN-04" .planning/phases/40-verification-documentation/40-SUMMARY.md` - passed.
- `rtk rg -n "Disposition|Evidence|Plan" .planning/phases/40-verification-documentation/40-SUMMARY.md` - passed.
- `rtk mix test test/foglet_bbs/tui/screens/account_test.exs` - passed, 62 tests, 0 failures.
- `rtk rg -n "doomed oneliner submit leaves form in \\{:error, _\\}|doomed hide-oneliner submit leaves form in \\{:error, _\\}|after doomed oneliner error, %\\{key: :escape\\} dismisses the modal|after doomed hide-oneliner error" test/foglet_bbs/tui/screens/account_test.exs` - passed.
- `rtk mix dialyzer` - passed successfully after removing the two deferred warnings.
- `rtk rg -n "board_list\\.ex:161|sysop\\.ex:823|Dialyzer" .planning/phases/40-verification-documentation/40-SUMMARY.md` - passed.

## Decisions Made

- Confirmed the BL-01 fixture user instead of bypassing email verification globally. That keeps the test focused on MainMenu modal behavior and avoids changing runtime auth routing.
- Left the modal submit Process-dictionary handoff in place for this plan. The BL-01 failure did not require a modal protocol redesign, and WR-04 remains bounded for later Phase 40 review.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] BL-01 fixture routed to Verify instead of MainMenu**
- **Found during:** Task 2
- **Issue:** The synthetic BL-01 user had `confirmed_at: nil`, so `App.init/1` routed to `:verify` while email verification was required. The tests were hitting a verification-code modal rather than the MainMenu oneliner modal.
- **Fix:** Set `confirmed_at` on the synthetic user in the BL-01 setup.
- **Files modified:** `test/foglet_bbs/tui/screens/account_test.exs`
- **Verification:** `rtk mix test test/foglet_bbs/tui/screens/account_test.exs`
- **Committed in:** `6432288`

**Total deviations:** 1 auto-fixed (Rule 1).
**Impact on plan:** The deviation restored the intended BL-01 coverage without weakening assertions or changing production behavior.

## Issues Encountered

- The first focused Account test run failed before reaching MainMenu because the fixture user was unconfirmed. Fixed as the Rule 1 deviation above.
- The first Dialyzer rerun after BoardList cleanup exposed the exact Sysop warning at the shifted line `sysop.ex:818`; removing the unused tuple overload cleared the gate.

## Known Stubs

None introduced by this plan. The stub scan found pre-existing Sysop placeholder wording and existing test assertions, but no new stubbed UI/data flow was added.

## Threat Flags

None. This plan changed TUI test fixtures, reducer branch shape, and documentation only; it introduced no new network endpoints, auth paths, file access, or schema trust boundary.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

Plan 40-02 can start from a clean close-gate baseline for the known BL-01 and Dialyzer blockers. The phase register now tracks the remaining callback, breadcrumb, verification, and documentation follow-ups.

## Self-Check: PASSED

- Created files exist: `.planning/phases/40-verification-documentation/40-SUMMARY.md`, `.planning/phases/40-verification-documentation/40-01-SUMMARY.md`.
- Task commits exist: `dfea016`, `6432288`, `79e451c`.
- Verification commands above were run and passed.

---
*Phase: 40-verification-documentation*
*Completed: 2026-04-29T15:00:38Z*
