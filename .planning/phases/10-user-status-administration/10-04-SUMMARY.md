---
phase: 10-user-status-administration
plan: 04
subsystem: accounts-tui
tags: [elixir, swoosh, tui, user-status, delivery-mode]

requires:
  - phase: 10-user-status-administration
    plan: 01
    provides: Accounts status transition API
provides:
  - Approval and rejection notification email builders
  - Delivery metadata on pending approval/rejection transitions
  - Rejected login handling and no-email-safe pending copy
affects: [status-notifications, login-copy, registration-copy, sysop-users-surface]

tech-stack:
  added: []
  patterns:
    - Persist status transition before attempting optional notification delivery
    - Return delivery metadata instead of rolling back valid status changes

key-files:
  created: []
  modified:
    - lib/foglet_bbs/accounts.ex
    - lib/foglet_bbs/accounts/email.ex
    - lib/foglet_bbs/tui/screens/login.ex
    - lib/foglet_bbs/tui/screens/register.ex
    - test/foglet_bbs/accounts/accounts_test.exs
    - test/foglet_bbs/tui/screens/login_test.exs
    - test/foglet_bbs/tui/screens/register_test.exs

requirements-completed: [MAIL-07, USER-05]

duration: ~35min
completed: 2026-04-24T19:12:00Z
---

# Phase 10 Plan 04: Notification Metadata And Status Copy Summary

**Approval/rejection delivery metadata and honest login/registration copy**

## Accomplishments

- Added `Foglet.Accounts.Email.approval_notification/1` and `rejection_notification/1`.
- Updated `Accounts.transition_user_status/3` to return `:attempted`, `:skipped_no_email`, `:not_applicable`, or `{:failed, reason}` delivery metadata.
- Ensured approval/rejection delivery failures do not roll back persisted status transitions.
- Added rejected-login handling with terminal copy: `"Your registration was rejected. Contact the sysop."`
- Simplified pending-login copy and added no-email-safe sysop-approved registration assertions.

## Task Commits

1. **Task 1 GREEN:** `b2f2d63` feat(10-04): add status transition notification metadata
2. **Task 2 GREEN:** `5b545e0` fix(10-04): align login and registration status copy

## Files Created/Modified

- `lib/foglet_bbs/accounts.ex` - Adds delivery-mode-aware status notification metadata.
- `lib/foglet_bbs/accounts/email.ex` - Adds approval/rejection email builders.
- `lib/foglet_bbs/tui/screens/login.ex` - Adds rejected status branch and honest pending copy.
- `lib/foglet_bbs/tui/screens/register.ex` - Existing sysop-approved no-email-safe copy retained.
- `test/foglet_bbs/accounts/accounts_test.exs` - Covers approval/rejection emails, no-email skips, and failure-without-rollback.
- `test/foglet_bbs/tui/screens/login_test.exs` - Covers rejected login and exact pending copy.
- `test/foglet_bbs/tui/screens/register_test.exs` - Covers sysop-approved no-email-safe copy.

## Deviations from Plan

None.

## Verification

- `rtk mix test test/foglet_bbs/accounts/accounts_test.exs test/foglet_bbs/tui/screens/login_test.exs test/foglet_bbs/tui/screens/register_test.exs` - 135 tests, 0 failures
- `rtk mix compile --warnings-as-errors`

## Self-Check: PASSED

- Modified files exist.
- Task commits exist on branch `gsd-phase-10-04`.
- No `STATE.md` or `ROADMAP.md` changes were made or committed.

---
*Phase: 10-user-status-administration*
*Completed: 2026-04-24*
