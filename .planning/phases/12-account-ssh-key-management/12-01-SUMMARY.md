---
phase: 12-account-ssh-key-management
plan: 01
subsystem: auth
tags: [ssh-keys, accounts, public-key-auth, ecto]

requires:
  - phase: 12-account-ssh-key-management
    provides: Phase 12 specification and context for SSH key lifecycle behavior
provides:
  - Accounts-owned SSH key registration, listing, and ownership-safe revocation
  - Registered-key public-key authentication with last-used metadata recording
  - CLIHandler wiring through the Accounts metadata-recording auth path
affects: [account-ssh-key-management, ssh-auth, account-tui]

tech-stack:
  added: []
  patterns:
    - Context-owned SSH key lifecycle APIs
    - Public-key auth lookup that updates metadata only after active user match

key-files:
  created:
    - .planning/phases/12-account-ssh-key-management/12-01-SUMMARY.md
  modified:
    - lib/foglet_bbs/accounts.ex
    - lib/foglet_bbs/accounts/ssh_key.ex
    - lib/foglet_bbs/ssh/cli_handler.ex
    - test/foglet_bbs/accounts/accounts_test.exs
    - test/foglet_bbs/accounts/ssh_key_test.exs
    - test/foglet_bbs/ssh/cli_handler_test.exs

key-decisions:
  - "Revocation hard-deletes owned ssh_keys rows through Foglet.Accounts.revoke_ssh_key/2."
  - "Public-key login uses Foglet.Accounts.authenticate_by_public_key/1 so last_used_at writes stay out of CLIHandler."
  - "Duplicate per-user SSH key labels surface changeset errors on :label for Account/TUI error mapping."

patterns-established:
  - "Ownership-safe key mutation: query by both key id and actor user_id before deleting."
  - "Fail-closed key auth: invalid, unregistered, revoked, and deleted-user keys all return {:error, :not_found}."

requirements-completed: [KEYS-02, KEYS-03, KEYS-04, KEYS-05]

duration: 28min
completed: 2026-04-24
---

# Phase 12 Plan 01: Account SSH Key Management Summary

**Accounts-owned SSH key lifecycle APIs with registered-key authentication that records last-used metadata only after successful active-user matches.**

## Performance

- **Duration:** 28 min
- **Started:** 2026-04-24T16:49:00Z
- **Completed:** 2026-04-24T17:16:46Z
- **Tasks:** 2
- **Files modified:** 6

## Accomplishments

- Added `Foglet.Accounts.revoke_ssh_key/2` with owner-scoped hard deletion.
- Kept SSH key registration/listing inside Accounts and tightened duplicate-label changeset errors to `:label`.
- Added `Foglet.Accounts.authenticate_by_public_key/1` that updates only the matched key's `last_used_at` after resolving a non-deleted owner.
- Updated `Foglet.SSH.CLIHandler` to call the metadata-recording Accounts auth path.
- Expanded focused Accounts, SSH key schema, and CLIHandler tests for KEYS-02 through KEYS-05.

## Task Commits

1. **Task 1: Add ownership-safe SSH key lifecycle APIs** - `9bada0b` (feat)
2. **Task 2: Record last-used only for successful registered-key authentication** - `eb67e6b` (feat)

**Plan metadata:** pending in final summary commit

## Files Created/Modified

- `lib/foglet_bbs/accounts.ex` - Added `revoke_ssh_key/2`, `authenticate_by_public_key/1`, and active key/user lookup.
- `lib/foglet_bbs/accounts/ssh_key.ex` - Mapped duplicate per-user label constraint errors to `:label`.
- `lib/foglet_bbs/ssh/cli_handler.ex` - Routed public-key resolution through `Accounts.authenticate_by_public_key/1`.
- `test/foglet_bbs/accounts/accounts_test.exs` - Added lifecycle, revoke, and last-used authentication coverage.
- `test/foglet_bbs/accounts/ssh_key_test.exs` - Tightened duplicate label assertion to the intended field.
- `test/foglet_bbs/ssh/cli_handler_test.exs` - Updated pubkey resolution coverage and added guest no-write assertion.

## Decisions Made

- Followed D-03 and implemented revocation as a hard delete rather than adding a soft-revocation column.
- Preserved `get_user_by_public_key/1` as a non-mutating lookup; CLIHandler now uses the new mutating authentication API.
- Set `updated_at` with `last_used_at` in the key auth update so timestamp columns remain coherent.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

- Fresh worktree dependencies were absent. Ran `rtk mix deps.get`; no source changes were needed.
- `rtk mix compile --warnings-as-errors` emitted dependency warnings from third-party packages during fresh dev build but exited successfully. No Foglet source warnings were reported.

## Verification

- `rtk mix test test/foglet_bbs/accounts/accounts_test.exs test/foglet_bbs/accounts/ssh_key_test.exs` - passed, 57 tests, 0 failures.
- `rtk mix test test/foglet_bbs/accounts/accounts_test.exs test/foglet_bbs/ssh/cli_handler_test.exs` - passed, 72 tests, 0 failures.
- `rtk mix test test/foglet_bbs/accounts/accounts_test.exs test/foglet_bbs/accounts/ssh_key_test.exs test/foglet_bbs/ssh/cli_handler_test.exs` - passed, 77 tests, 0 failures.
- `rtk mix compile --warnings-as-errors` - passed.

## Known Stubs

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

Plan 12-02 can build the Account TUI SSH KEYS tab on top of Accounts-owned add/list/revoke APIs and the metadata-recording authentication path.

## Self-Check: PASSED

- Summary file exists at `.planning/phases/12-account-ssh-key-management/12-01-SUMMARY.md`.
- Task commits exist: `9bada0b`, `eb67e6b`.
- No tracked files were deleted by task commits.

---
*Phase: 12-account-ssh-key-management*
*Completed: 2026-04-24*
