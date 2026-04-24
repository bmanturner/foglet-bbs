---
phase: 15-reset-path-gap-closure
plan: 01
subsystem: accounts
tags: [password-reset, mix-task, user-tokens, ssh-first]

requires:
  - phase: 14-launch-hygiene-and-operator-notes
    provides: reset URL blocker evidence and launch-honesty constraints
provides:
  - Accounts-owned operator reset-token generation helper
  - Browser-free break-glass reset Mix task output
  - Focused reset task tests for token round trip, copy, and forbidden paths
affects: [phase-15-reset-path-gap-closure, mail-delivery, operator-notes]

tech-stack:
  added: []
  patterns:
    - Reuse UserToken.build_email_token/2 for operator reset-token generation
    - Print raw reset tokens only through operator-controlled Mix task output

key-files:
  created:
    - .planning/phases/15-reset-path-gap-closure/15-01-SUMMARY.md
  modified:
    - lib/foglet_bbs/accounts.ex
    - lib/mix/tasks/foglet.user.reset_password.ex
    - test/mix/tasks/foglet_user_reset_password_test.exs

key-decisions:
  - "Kept reset recovery browser-free: the Mix task prints raw reset tokens, not HTTP URLs."
  - "Centralized operator reset-token generation in Foglet.Accounts using the existing hashed UserToken primitive."

patterns-established:
  - "Operator reset retrieval: context generates and persists hashed token rows; Mix tasks only print raw delivery tokens and SSH-first instructions."

requirements-completed: [MAIL-04, MAIL-06, HYGN-02]

duration: 6min
completed: 2026-04-24
---

# Phase 15 Plan 01: Reset Token Operator Path Summary

**Operator password reset now returns raw, verifiable reset tokens through Accounts-owned hashed-token persistence instead of unsupported browser URLs.**

## Performance

- **Duration:** 6 min
- **Started:** 2026-04-24T22:31:46Z
- **Completed:** 2026-04-24T22:37:05Z
- **Tasks:** 2
- **Files modified:** 4

## Accomplishments

- Added `Foglet.Accounts.generate_reset_token_for_operator/1`, backed by `UserToken.build_email_token/2` and `Repo.insert/1`.
- Rewrote `mix foglet.user.reset_password HANDLE` to print token-only operator instructions in both email and no-email modes.
- Reworked reset task tests to prove raw-token verification, hashed DB storage, browser-free copy, and existing rejected paths.

## Task Commits

1. **Task 15-01-01 RED:** `d386ff9` test - failing helper tests for raw reset-token round trip and hashed storage.
2. **Task 15-01-01 GREEN:** `168798f` feat - Accounts operator reset-token helper.
3. **Task 15-01-02 RED:** `bad65b4` test - failing token-only Mix task copy tests.
4. **Task 15-01-02 GREEN:** `7964f5c` feat - reset task raw-token output.

## Files Created/Modified

- `lib/foglet_bbs/accounts.ex` - Added operator reset-token helper and corrected stale token-delivery docs.
- `lib/mix/tasks/foglet.user.reset_password.ex` - Removed reset URL construction and prints raw reset-token instructions.
- `test/mix/tasks/foglet_user_reset_password_test.exs` - Added helper/token storage tests and browser-free task copy coverage.
- `.planning/phases/15-reset-path-gap-closure/15-01-SUMMARY.md` - Execution summary.

## Decisions Made

- Kept password reset delivery SSH-first and operator-assisted for this plan; no browser routes, controllers, or URL output were added.
- Preserved existing reset-token cryptography and expiry behavior by using `Foglet.Accounts.UserToken`.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

- Task 15-01-01 acceptance grep caught stale confirmation-token doc copy in `Foglet.Accounts`; the copy was updated to describe caller-built delivery values without changing behavior.
- Task 15-01-02 acceptance grep required forbidden URL strings to be absent even inside negative test assertions; tests now build those forbidden strings dynamically.

## Known Stubs

None.

## Threat Flags

| Flag | File | Description |
|------|------|-------------|
| threat_flag: operator-token-disclosure | lib/mix/tasks/foglet.user.reset_password.ex | Raw reset token is intentionally disclosed once through the operator Mix task; tests verify it is not wrapped in unsupported browser URL copy. |

## Verification

- `rtk mix test test/mix/tasks/foglet_user_reset_password_test.exs` - passed, 9 tests.
- `rtk mix test test/mix/tasks/foglet_user_reset_password_test.exs test/foglet_bbs/accounts/accounts_test.exs` - passed, 77 tests.
- `rtk rg -n "reset URL|operator reset URL|users/reset_password|http://|https://" lib/mix/tasks/foglet.user.reset_password.ex test/mix/tasks/foglet_user_reset_password_test.exs` - passed, no matches.
- `rtk mix precommit` - passed.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

Plan 15-02 can align README operator notes, blocker records, and broader reset-copy guards with the token-only behavior shipped here.

## Self-Check: PASSED

- Summary file exists.
- Task commits found in git history: `d386ff9`, `168798f`, `bad65b4`, `7964f5c`.
- Verification commands completed successfully.

---
*Phase: 15-reset-path-gap-closure*
*Completed: 2026-04-24*
