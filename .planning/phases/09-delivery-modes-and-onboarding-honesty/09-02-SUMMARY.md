---
phase: 09-delivery-modes-and-onboarding-honesty
plan: 02
subsystem: auth
tags: [email, verification, swoosh, tui, accounts]

requires:
  - phase: 09-01
    provides: Swoosh mailer boundary, delivery_mode config, and Accounts email builders
provides:
  - Accounts-level verification delivery API
  - Register and Verify delivery-mode-aware verification flow
  - Honest attempted-delivery copy for verification and resend
affects: [phase-09, accounts, register, verify, onboarding]

tech-stack:
  added: []
  patterns:
    - TUI screens call Accounts delivery APIs instead of token primitives
    - Delivery provider failures collapse to generic user-facing results

key-files:
  created:
    - .planning/phases/09-delivery-modes-and-onboarding-honesty/09-02-SUMMARY.md
  modified:
    - lib/foglet_bbs/accounts.ex
    - lib/foglet_bbs/tui/screens/register.ex
    - lib/foglet_bbs/tui/screens/verify.ex
    - test/foglet_bbs/accounts/accounts_test.exs
    - test/foglet_bbs/tui/screens/register_test.exs
    - test/foglet_bbs/tui/screens/verify_test.exs

key-decisions:
  - "Accounts.deliver_verification_code/1 is the verification delivery boundary; build_verify_code/1 remains an internal/test token primitive."
  - "No-email mode returns unavailable and does not create email_verify tokens."
  - "TUI copy uses generic attempted-delivery language and avoids provider-detail disclosure."

patterns-established:
  - "Registration and resend verification delivery route through Foglet.Accounts."
  - "Verify resend success updates resend cooldown only after delivery was attempted."

requirements-completed: [MAIL-02, MAIL-03, MAIL-05]

duration: 7min
completed: 2026-04-24
---

# Phase 09 Plan 02: Verification Delivery API Summary

**Accounts-owned Swoosh verification delivery with honest Register and Verify terminal copy**

## Performance

- **Duration:** 7 min
- **Started:** 2026-04-24T16:54:52Z
- **Completed:** 2026-04-24T17:01:18Z
- **Tasks:** 2
- **Files modified:** 6

## Accomplishments

- Added `Accounts.deliver_verification_code/1`, which creates an `email_verify` token and attempts Swoosh delivery only in `"email"` mode.
- Changed Register and Verify resend to call the Accounts delivery API instead of `Accounts.build_verify_code/1`.
- Removed false TUI delivery claims such as “emailed to you,” “new code has been sent,” and pending-approval email notification copy.
- Added focused Swoosh assertion tests for email-mode delivery and no-email unavailability.

## Task Commits

1. **Task 1 RED:** `97d085c` test(09-02): add failing verification delivery tests
2. **Task 1 GREEN:** `7b31a96` feat(09-02): add verification delivery API
3. **Task 2 RED:** `f7b8f93` test(09-02): add failing TUI delivery honesty tests
4. **Task 2 GREEN:** `7b1f27c` feat(09-02): wire TUI verification delivery

## Files Created/Modified

- `lib/foglet_bbs/accounts.ex` - Adds `deliver_verification_code/1` and sends verification emails through `Foglet.Mailer`.
- `lib/foglet_bbs/tui/screens/register.ex` - Routes verification-required registrations through the delivery API and updates no-email/failure/pending copy.
- `lib/foglet_bbs/tui/screens/verify.ex` - Routes resend through the delivery API, preserves cooldown semantics, and updates prompt/resend copy.
- `test/foglet_bbs/accounts/accounts_test.exs` - Covers email-mode attempted delivery and no-email no-token behavior.
- `test/foglet_bbs/tui/screens/register_test.exs` - Covers registration delivery attempts and no-email refusal.
- `test/foglet_bbs/tui/screens/verify_test.exs` - Covers prompt honesty, resend delivery attempts, and cooldown preservation.

## Decisions Made

- Kept `build_verify_code/1` available for verification-token tests and internal primitives, but removed TUI use of it.
- Returned `{:error, :delivery_failed}` for all provider failures so terminal copy cannot leak mailer details.
- Used explicit no-email unavailable modals rather than treating no-email as an operator-relay verification mode.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

- Parallel worktree activity interleaved unrelated commits in `git log`; all 09-02 task commits were still created atomically and verified by hash.
- Existing unrelated untracked files remained in the worktree and were not staged.

## Known Stubs

None.

## Threat Flags

None beyond the planned TUI-to-Accounts and Accounts-to-Swoosh boundaries.

## Verification

- `rtk mix test test/foglet_bbs/accounts/accounts_test.exs`
- `rtk mix test test/foglet_bbs/tui/screens/register_test.exs test/foglet_bbs/tui/screens/verify_test.exs`
- `rtk mix test test/foglet_bbs/accounts/accounts_test.exs test/foglet_bbs/tui/screens/register_test.exs test/foglet_bbs/tui/screens/verify_test.exs`
- `rg -n 'def deliver_verification_code' lib/foglet_bbs/accounts.ex`
- `rg -n 'Foglet\.Mailer\.deliver|Mailer\.deliver' lib/foglet_bbs/accounts.ex`
- `rg -n 'Accounts\.build_verify_code' lib/foglet_bbs/tui/screens/register.ex lib/foglet_bbs/tui/screens/verify.ex` returned no matches.
- `rg -n 'emailed to you|new code has been sent|notified by email' lib/foglet_bbs/tui/screens/register.ex lib/foglet_bbs/tui/screens/verify.ex` returned no matches.

## Self-Check: PASSED

- Created summary file exists.
- Task commits exist: `97d085c`, `7b31a96`, `f7b8f93`, `7b1f27c`.
- No tracked files were deleted by task commits.
- No summary-blocking stubs were found in created or modified plan files.
- `STATE.md` and `ROADMAP.md` were not modified by this executor.

## User Setup Required

None for tests. Operators must use `"email"` delivery mode with runtime SMTP configuration for real outbound delivery.

## Next Phase Readiness

Verification delivery is now centralized in Accounts and safe for downstream login/reset/sysop work to consume without treating raw token generation as user delivery.

---
*Phase: 09-delivery-modes-and-onboarding-honesty*
*Completed: 2026-04-24*
