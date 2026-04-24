---
phase: 12-account-ssh-key-management
plan: 02
subsystem: tui
tags: [ssh-keys, account, raxol, tui, accounts]

requires:
  - phase: 12-account-ssh-key-management
    provides: Plan 12-01 Accounts SSH key APIs for list, register, revoke, and public-key auth
provides:
  - Account SSH KEYS tab with key list metadata rendering
  - Screen-local SSH key state, pure surface rendering, and Accounts-backed actions
  - Account screen tests for key load, add, validation, refresh, and revoke flows
affects: [account-tui, ssh-key-management, pre-alpha-gap-closure]

tech-stack:
  added: []
  patterns:
    - Account sibling modules for SSH key state/actions/surface
    - TDD commits for Account TUI SSH key behavior

key-files:
  created:
    - lib/foglet_bbs/tui/screens/account/ssh_keys_actions.ex
    - lib/foglet_bbs/tui/screens/account/ssh_keys_state.ex
    - lib/foglet_bbs/tui/screens/account/ssh_keys_surface.ex
  modified:
    - lib/foglet_bbs/tui/screens/account.ex
    - lib/foglet_bbs/tui/screens/account/state.ex
    - test/foglet_bbs/tui/screens/account_test.exs

key-decisions:
  - "SSH key UI persistence routes only through Foglet.Accounts APIs; Account TUI files do not call Repo."
  - "The key list renders label, fingerprint, created time, and last-used state, but omits raw OpenSSH public-key material."

patterns-established:
  - "Account SSH key flows live in sibling SSHKeysState, SSHKeysActions, and SSHKeysSurface modules."
  - "Entering the SSH KEYS tab lazily loads keys for the current user, matching the existing INVITES tab pattern."

requirements-completed: [KEYS-01, KEYS-02, KEYS-03, KEYS-04]

duration: 25min
completed: 2026-04-24
---

# Phase 12 Plan 02: Account SSH Key Tab Summary

**Terminal Account SSH key management with Accounts-backed add, list, refresh, and revoke flows.**

## Performance

- **Duration:** 25 min
- **Started:** 2026-04-24T17:10:00Z
- **Completed:** 2026-04-24T17:34:58Z
- **Tasks:** 2
- **Files modified:** 6

## Accomplishments

- Added an authenticated Account `SSH KEYS` tab after `PROFILE` and `PREFS`, with conditional `INVITES` shifted after it.
- Added screen-local SSH key state, pure key metadata rendering, and raw public-key suppression in list rows.
- Wired load, refresh, add, validation-error display, selection, and revoke through `Foglet.Accounts`.
- Extended Account screen tests for empty state, metadata display, non-leakage, add validation, refresh, and revoke behavior.

## Task Commits

1. **Task 1 RED: Add failing Account SSH key tab render tests** - `5fb99ac` (test)
2. **Task 1 GREEN: Render Account SSH key tab state** - `1cf3444` (feat)
3. **Task 2 RED: Add failing Account SSH key action tests** - `8b681df` (test)
4. **Task 2 GREEN: Wire Account SSH key actions** - `10b673f` (feat)

## Files Created/Modified

- `lib/foglet_bbs/tui/screens/account.ex` - Adds SSH KEYS tab rendering, lazy load, and key-event delegation.
- `lib/foglet_bbs/tui/screens/account/state.ex` - Adds SSH KEYS to Account tab ordering and screen state.
- `lib/foglet_bbs/tui/screens/account/ssh_keys_actions.ex` - Maps terminal key events to Accounts list/register/revoke calls.
- `lib/foglet_bbs/tui/screens/account/ssh_keys_state.ex` - Stores key list, selection, add form, errors, and status messages.
- `lib/foglet_bbs/tui/screens/account/ssh_keys_surface.ex` - Renders loading, add form, metadata rows, empty state, and hints.
- `test/foglet_bbs/tui/screens/account_test.exs` - Covers Account SSH key tab and action behavior.

## Decisions Made

- Used a simple inline add mode instead of a modal so the SSH key workflow stays compact and testable in the existing Account screen style.
- Kept raw public-key text visible only in the add input field; stored key rows render metadata only.
- Preserved the shared INVITES behavior by moving it to tab 4 when visible.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

- Fresh worktree dependencies were absent, so `rtk mix deps.get` was required before tests could run.
- Mix needed permission to open its local PubSub socket during test runs; focused test commands were rerun with escalation.

## Verification

- `rtk mix test test/foglet_bbs/tui/screens/account_test.exs` - passed, 33 tests, 0 failures.
- `rtk mix test test/foglet_bbs/accounts/accounts_test.exs test/foglet_bbs/accounts/ssh_key_test.exs test/foglet_bbs/tui/screens/account_test.exs test/foglet_bbs/ssh/cli_handler_test.exs` - passed, 110 tests, 0 failures.
- Task acceptance `rg` checks passed, including no `Repo` usage in Account SSH key TUI files.

## Known Stubs

None.

## Threat Flags

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

Plan 12-03 can exercise end-to-end SSH key management and public-key authentication coverage using the Account UI surface added here and the Accounts APIs from Plan 12-01.

## Self-Check: PASSED

- Summary file exists at `.planning/phases/12-account-ssh-key-management/12-02-SUMMARY.md`.
- Task commits exist on branch `gsd-phase-12-02`: `5fb99ac`, `1cf3444`, `8b681df`, `10b673f`.
- No shared `.planning/STATE.md` or `.planning/ROADMAP.md` updates were made in this worktree.

---
*Phase: 12-account-ssh-key-management*
*Completed: 2026-04-24*
