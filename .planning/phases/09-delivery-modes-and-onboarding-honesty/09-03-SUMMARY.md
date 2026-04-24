---
phase: 09-delivery-modes-and-onboarding-honesty
plan: 03
subsystem: auth
tags: [email, password-reset, swoosh, tui, accounts]

requires:
  - phase: 09-01
    provides: Delivery mode config, Swoosh mailer boundary, and reset email builder
  - phase: 09-02
    provides: TUI delivery-honesty patterns and Accounts-owned delivery APIs
provides:
  - Enumeration-safe Accounts password reset request API
  - Email-mode-only Login forgot-password reset request subflow
  - Generic browser-free terminal reset copy
affects: [phase-09, accounts, login, onboarding]

tech-stack:
  added: []
  patterns:
    - User reset delivery requests route through Foglet.Accounts
    - Login gates reset availability through Foglet.Config.delivery_mode/0

key-files:
  created:
    - .planning/phases/09-delivery-modes-and-onboarding-honesty/09-03-SUMMARY.md
  modified:
    - lib/foglet_bbs/accounts.ex
    - lib/foglet_bbs/tui/screens/login.ex
    - test/foglet_bbs/accounts/accounts_test.exs
    - test/foglet_bbs/tui/screens/login_test.exs

key-decisions:
  - "Password reset requests return only {:ok, :generic_response} in email mode, including unknown, inactive, deleted, and delivery-failed identifiers."
  - "Login exposes [F] Forgot password only when delivery_mode is email."
  - "Reset request UI copy stays terminal-native and contains no browser reset routes or URLs."

patterns-established:
  - "Accounts request APIs collapse provider and enumeration details before returning to TUI callers."
  - "Login subflows keep screen-local form state in screen_state[:login] and call context APIs on Enter."

requirements-completed: [MAIL-04, MAIL-05]

duration: 7min
completed: 2026-04-24
---

# Phase 09 Plan 03: Terminal Reset Request Summary

**Enumeration-safe terminal password reset requests wired from Login to Accounts in email delivery mode**

## Performance

- **Duration:** 7 min
- **Started:** 2026-04-24T17:03:55Z
- **Completed:** 2026-04-24T17:11:02Z
- **Tasks:** 2
- **Files modified:** 4

## Accomplishments

- Added `Accounts.request_password_reset_delivery/1`, which is unavailable in no-email mode and enumeration-safe in email mode.
- Active email-mode matches create a `reset_password` token and attempt Swoosh delivery through `Foglet.Mailer`.
- Login now shows `[F] Forgot password` only in email mode and collects a handle or email in a terminal-native reset subflow.
- Pending-account Login copy no longer promises an approval notification before Phase 10 owns that behavior.

## Task Commits

1. **Task 1 RED:** `65d098b` test(09-03): add failing reset delivery tests
2. **Task 1 GREEN:** `ca5ba3b` feat(09-03): add reset delivery request API
3. **Task 2 RED:** `7ac7b36` test(09-03): add failing login reset tests
4. **Task 2 GREEN:** `21343cc` feat(09-03): add login reset request subflow

## Files Created/Modified

- `lib/foglet_bbs/accounts.ex` - Adds `request_password_reset_delivery/1` and private active-user reset delivery helpers.
- `lib/foglet_bbs/tui/screens/login.ex` - Adds the `:reset_request` subflow, email-mode menu gating, generic reset messages, and updated pending-copy text.
- `test/foglet_bbs/accounts/accounts_test.exs` - Covers active, unknown, deleted, pending, suspended, delivery-failed, and no-email reset request behavior.
- `test/foglet_bbs/tui/screens/login_test.exs` - Covers reset menu visibility, reset subflow handling, browser-free copy, and pending-copy honesty.

## Decisions Made

- Reused `UserToken.build_email_token/2` and `Email.password_reset/2` directly for user-requested reset delivery rather than the URL-returning break-glass helper.
- Kept provider delivery failures indistinguishable from all other email-mode reset request outcomes.
- Stored reset-request feedback in the Login substate rather than a global modal so the user remains in the request flow.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

- `Mix.PubSub` could not open its local TCP socket under sandbox restrictions during one focused Login test rerun, so the same `rtk mix test test/foglet_bbs/tui/screens/login_test.exs` command was rerun with approved escalation and passed.
- Parallel worktree activity modified `.planning/STATE.md` while this executor was running; this executor restored only `.planning/STATE.md` and did not commit shared orchestrator artifacts.
- Interleaved parallel commits appear in `git log`, but all 09-03 task commits were created atomically and verified by hash.

## Known Stubs

None.

## Threat Flags

None beyond the planned unauthenticated TUI-to-Accounts, token-table, and Swoosh delivery boundaries in the plan threat model.

## Verification

- `rtk mix test test/foglet_bbs/accounts/accounts_test.exs`
- `rtk mix test test/foglet_bbs/tui/screens/login_test.exs`
- `rtk mix test test/foglet_bbs/accounts/accounts_test.exs test/foglet_bbs/tui/screens/login_test.exs`
- `rg -n 'def request_password_reset_delivery' lib/foglet_bbs/accounts.ex`
- `rg -n ':generic_response' lib/foglet_bbs/accounts.ex test/foglet_bbs/accounts/accounts_test.exs`
- `rg -n 'Forgot password|reset_request|request_password_reset_delivery' lib/foglet_bbs/tui/screens/login.ex test/foglet_bbs/tui/screens/login_test.exs`
- `rg -n '/users/reset_password|http://|https://' lib/foglet_bbs/tui/screens/login.ex test/foglet_bbs/tui/screens/login_test.exs` returned no matches.
- `rg -n 'approval notification|notified by email' lib/foglet_bbs/tui/screens/login.ex` returned no matches.

## TDD Gate Compliance

- RED gate commit exists for Task 1: `65d098b`.
- GREEN gate commit exists for Task 1: `ca5ba3b`.
- RED gate commit exists for Task 2: `7ac7b36`.
- GREEN gate commit exists for Task 2: `21343cc`.

## Self-Check: PASSED

- Summary file exists.
- Task commits exist: `65d098b`, `ca5ba3b`, `7ac7b36`, `21343cc`.
- No tracked files were deleted by task commits.
- No summary-blocking stubs were found in files created or modified by this plan.
- `STATE.md` and `ROADMAP.md` were not modified or committed by this executor.

## User Setup Required

None for tests. Operators must set `delivery_mode` to `"email"` and configure runtime SMTP settings for real outbound reset delivery.

## Next Phase Readiness

User-requested reset delivery is now centralized in Accounts and exposed from the terminal Login screen only when email delivery is configured. Downstream operator reset tooling can reuse the same delivery-mode boundary while keeping no-email reset workflows unavailable.

---
*Phase: 09-delivery-modes-and-onboarding-honesty*
*Completed: 2026-04-24*
