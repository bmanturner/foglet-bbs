---
phase: 09-delivery-modes-and-onboarding-honesty
plan: 07
subsystem: auth
tags: [mail, verification, password-reset, tui, mix-tasks]
requires:
  - phase: 09-delivery-modes-and-onboarding-honesty
    provides: Phase 9 delivery mode foundation and cross-surface copy
provides:
  - Valid no-email open-registration defaults
  - Returning-user Login verification through Accounts delivery
  - Operator no-email verification and reset retrieval workflows
affects: [accounts, config, tui-login, operator-tasks]
tech-stack:
  added: []
  patterns: [operator-only Mix retrieval, delivery-aware TUI routing]
key-files:
  created:
    - lib/mix/tasks/foglet.user.verification_code.ex
    - test/mix/tasks/foglet_user_verification_code_test.exs
  modified:
    - lib/foglet_bbs/config/schema.ex
    - lib/foglet_bbs/tui/screens/login.ex
    - lib/mix/tasks/foglet.user.reset_password.ex
    - test/foglet_bbs/config/schema_test.exs
    - test/foglet_bbs/config_test.exs
    - test/foglet_bbs/tui/screens/login_test.exs
    - test/mix/tasks/foglet_user_reset_password_test.exs
key-decisions:
  - "Keep no-email recovery details in explicit operator Mix tasks only."
  - "Preserve seed idempotency while making fresh schema defaults valid."
patterns-established:
  - "Login verification delivery handles :unavailable and :delivery_failed without exposing raw codes."
  - "No-email operator retrieval output must explicitly state no email was sent."
requirements-completed: [MAIL-01, MAIL-02, MAIL-03, MAIL-04, MAIL-05, MAIL-06]
duration: 45min
completed: 2026-04-24
---

# Phase 09 Plan 07 Summary

**Delivery-mode gap closure for valid no-email defaults, Login verification delivery, and operator retrieval tasks**

## Performance

- **Duration:** 45 min
- **Started:** 2026-04-24T20:14:30Z
- **Completed:** 2026-04-24T20:24:00Z
- **Tasks:** 3
- **Files modified:** 9

## Accomplishments

- Changed schema defaults so a fresh no-email open-registration install does not require email verification.
- Routed returning unconfirmed Login users through `Accounts.deliver_verification_code/1` with delivery-mode-aware error modals.
- Added `mix foglet.user.verification_code HANDLE` and updated reset-password no-email behavior for operator retrieval.

## Task Commits

1. **Task 1: Make seeded delivery defaults valid** - `560c5b6` (fix)
2. **Task 2: Route Login returning-user verification through delivery API** - `9f26913` (fix)
3. **Task 3: Add explicit no-email operator retrieval workflows** - `d7453da` (fix)

## Files Created/Modified

- `lib/foglet_bbs/config/schema.ex` - Sets `require_email_verification` default to `false`.
- `test/foglet_bbs/config/schema_test.exs` - Covers the valid no-email/open/default combination.
- `test/foglet_bbs/config_test.exs` - Resets config tests to schema defaults and asserts the typed accessor default.
- `lib/foglet_bbs/tui/screens/login.ex` - Uses Accounts delivery for returning-user verification.
- `test/foglet_bbs/tui/screens/login_test.exs` - Covers email-mode delivery and no-email unavailability.
- `lib/mix/tasks/foglet.user.reset_password.ex` - Prints no-email operator reset details.
- `lib/mix/tasks/foglet.user.verification_code.ex` - Adds operator no-email verification-code retrieval.
- `test/mix/tasks/foglet_user_reset_password_test.exs` - Covers no-email reset URL generation.
- `test/mix/tasks/foglet_user_verification_code_test.exs` - Covers verification-code retrieval and rejection paths.

## Decisions Made

- Kept `priv/repo/seeds/config.exs` idempotent so existing operator-edited config is not overwritten.
- Kept no-email retrieval out of TUI and browser surfaces; only explicit operator Mix tasks expose sensitive values.

## Deviations from Plan

None - plan executed as specified.

## Issues Encountered

- Fresh worktree lacked untracked dependencies; resolved with `rtk mix deps.get`.
- Sandbox blocked Mix PubSub TCP sockets on some test reruns; reran affected tests with approved escalation.

## User Setup Required

None.

## Verification

- `rtk mix test test/foglet_bbs/config/schema_test.exs test/foglet_bbs/config_test.exs`
- `rtk mix test test/foglet_bbs/tui/screens/login_test.exs test/foglet_bbs/accounts/accounts_test.exs`
- `rtk mix test test/mix/tasks/foglet_user_reset_password_test.exs test/mix/tasks/foglet_user_verification_code_test.exs`
- `rtk mix test test/foglet_bbs/tui/screens/delivery_copy_test.exs`

## Next Phase Readiness

Phase 9's blocking verification gaps are closed. The phase can move to code review, precommit, and phase verification.

---
*Phase: 09-delivery-modes-and-onboarding-honesty*
*Completed: 2026-04-24*
