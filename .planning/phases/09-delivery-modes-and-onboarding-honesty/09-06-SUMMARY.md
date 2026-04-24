---
phase: 09-delivery-modes-and-onboarding-honesty
plan: 06
subsystem: auth
tags: [delivery-honesty, tui, mix-task, regression-coverage]

requires:
  - phase: 09-02
    provides: Verification delivery API and Register/Verify copy updates
  - phase: 09-03
    provides: Terminal reset request copy and browser-free Login flow
  - phase: 09-04
    provides: Sysop delivery-mode SiteForm surface and validation
  - phase: 09-05
    provides: Delivery-mode-aware reset Mix task copy
provides:
  - Cross-surface delivery-copy regression guard
  - Pending-approval copy aligned with Phase 9 MAIL-07 boundary
  - Sysop screen test baseline compatible with delivery-mode validation
affects: [phase-09, tui-copy, reset-tooling, sysop-tests]

tech-stack:
  added: []
  patterns:
    - Cross-surface TUI copy tests use flatten_text/1 over rendered Raxol trees
    - Copy guards forbid browser reset routes in user-facing terminal surfaces

key-files:
  created:
    - test/foglet_bbs/tui/screens/delivery_copy_test.exs
    - .planning/phases/09-delivery-modes-and-onboarding-honesty/09-06-SUMMARY.md
  modified:
    - lib/foglet_bbs/tui/screens/register.ex
    - test/mix/tasks/foglet_user_reset_password_test.exs
    - test/foglet_bbs/tui/screens/sysop_test.exs

key-decisions:
  - "Cross-surface copy assertions cover Login, Register pending approval, Verify, Sysop SiteForm, and reset Mix task output."
  - "The Mix task may still build an operator-only break-glass reset URL, but user-facing TUI reset copy must remain browser-free."
  - "Pending approval copy stops at account-created-and-pending; approval/rejection notifications remain out of scope for Phase 9."

patterns-established:
  - "Delivery honesty tests assert forbidden phrases and required honest phrases in one focused regression module."

requirements-completed: [MAIL-01, MAIL-02, MAIL-03, MAIL-04, MAIL-05, MAIL-06]

duration: 24min
completed: 2026-04-24
---

# Phase 09 Plan 06: Delivery Copy Regression Summary

**Cross-surface delivery-copy guards for Phase 9 terminal and operator reset surfaces**

## Performance

- **Duration:** 24 min
- **Started:** 2026-04-24T16:59:00Z
- **Completed:** 2026-04-24T17:23:39Z
- **Tasks:** 2
- **Files modified:** 4

## Accomplishments

- Added `test/foglet_bbs/tui/screens/delivery_copy_test.exs` covering Login reset copy, Register pending approval, Verify prompt/resend copy, and Sysop SiteForm delivery-mode copy.
- Guarded against false-delivery phrases: `emailed to you`, `A new code has been sent.`, `You will be notified by email.`, `approval notification`, browser reset route strings, and URL prefixes.
- Extended the reset Mix task test to assert the break-glass output says no email was sent by the task.
- Shortened Register pending-approval copy to avoid implying Phase 10/MAIL-07 notification behavior.

## Task Commits

1. **Task 1 RED:** `813b682` test(09-06): add delivery copy regression coverage
2. **Task 2 GREEN:** `f9ce5f0` fix(09-06): align pending approval copy

## Files Created/Modified

- `test/foglet_bbs/tui/screens/delivery_copy_test.exs` - New cross-surface regression module using `flatten_text/1` over Login, Register, Verify, and Sysop SiteForm outputs.
- `test/mix/tasks/foglet_user_reset_password_test.exs` - Adds an explicit assertion for `no email was sent by this task`.
- `lib/foglet_bbs/tui/screens/register.ex` - Changes pending approval copy to `Your account has been created and is pending sysop approval.`
- `test/foglet_bbs/tui/screens/sysop_test.exs` - Seeds a valid `delivery_mode=email` baseline before unrelated SiteForm save tests.

## Decisions Made

- Kept the reset Mix task's operator-only URL-generation path intact because it is not an end-user browser workflow.
- Treated browser URL strings as forbidden in TUI/user-facing reset surfaces while documenting the operator-only Mix internal exception.
- Used the exact pending approval copy requested by the plan instead of retaining the extra "A sysop will review it." sentence.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking Issue] Seeded valid delivery mode in Sysop screen tests**
- **Found during:** Task 2 broad verification
- **Issue:** `test/foglet_bbs/tui/screens/sysop_test.exs` seeded schema defaults where `delivery_mode=no_email` and `require_email_verification=true`, causing unrelated SITE save tests to hit the Phase 09-04 delivery/verification guard before their intended assertions.
- **Fix:** Set `delivery_mode` to `email` in the Sysop test setup after seeding defaults.
- **Files modified:** `test/foglet_bbs/tui/screens/sysop_test.exs`
- **Commit:** `f9ce5f0`

## Issues Encountered

- `rtk mix test test/foglet_bbs/tui/screens test/mix/tasks` initially failed in two existing Sysop tests because of the invalid default delivery/verification baseline above. After the targeted setup fix, the same command passed.
- Existing Raxol dependency warnings and existing ShellVisibility sandbox warnings appeared during test runs; they did not fail the suite.
- `.planning/ROADMAP.md`, `.codex/`, and `GAP_MILESTONE.md` were already modified or untracked in the worktree and were left untouched.

## Known Stubs

None.

## Threat Flags

None beyond the planned rendered TUI copy to user trust and Mix stdout to operator action boundaries.

## Verification

- `rtk mix test test/foglet_bbs/tui/screens/delivery_copy_test.exs test/mix/tasks/foglet_user_reset_password_test.exs` - RED failed before Task 2 on pending approval copy, then passed after Task 2.
- `rtk mix test test/foglet_bbs/tui/screens/sysop_test.exs`
- `rtk mix test test/foglet_bbs/tui/screens test/mix/tasks`
- `rg -n 'flatten_text' test/foglet_bbs/tui/screens/delivery_copy_test.exs`
- `rg -n 'notified by email|approval notification|emailed to you|A new code has been sent|/users/reset_password' lib/foglet_bbs/tui/screens lib/mix/tasks` returned only the existing operator-only Mix reset URL builder.
- `rg -n 'defmodule FogletBbsWeb.*Reset|reset_password' lib/foglet_bbs_web` returned no matches.

## TDD Gate Compliance

- RED gate commit exists: `813b682`.
- GREEN gate commit exists after RED: `f9ce5f0`.

## Self-Check: PASSED

- Summary file exists.
- Task commits exist: `813b682`, `f9ce5f0`.
- No tracked files were deleted by task commits.
- No summary-blocking stubs were found in files created or modified by this plan.
- `STATE.md` and `ROADMAP.md` were not modified by this executor.

## User Setup Required

None.

## Next Phase Readiness

Phase 9 now has regression coverage proving MAIL-01 through MAIL-06 changed terminal and Mix surfaces do not drift back into false email delivery claims, browser reset exposure, or premature MAIL-07 approval notification promises.

---
*Phase: 09-delivery-modes-and-onboarding-honesty*
*Completed: 2026-04-24*
