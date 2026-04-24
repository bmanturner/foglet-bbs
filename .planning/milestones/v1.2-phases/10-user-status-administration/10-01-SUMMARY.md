---
phase: 10-user-status-administration
plan: 01
subsystem: accounts
tags: [elixir, ecto, authorization, user-status, postgres]

requires:
  - phase: 09-delivery-modes-and-onboarding-honesty
    provides: delivery-mode configuration consumed by account email/reset flows
provides:
  - Durable rejected user status persisted through the existing string-backed status column
  - Accounts-owned sysop status transition API with a locked transition graph
  - Sysop-only manage_user_status authorization action and rejected actor guard
  - Non-deleted user status administration target listing grouped by status
affects: [user-status-administration, sysop-users-surface, mix-user-status-task, login-status-copy]

tech-stack:
  added: []
  patterns:
    - Bodyguard.permit/4 before status target lookup or mutation
    - String-backed Ecto.Enum lifecycle values with check-constraint migration

key-files:
  created:
    - priv/repo/migrations/20260424000000_add_rejected_user_status.exs
    - test/foglet_bbs/accounts/user_status_test.exs
  modified:
    - docs/DATA_MODEL.md
    - lib/foglet_bbs/accounts.ex
    - lib/foglet_bbs/accounts/user.ex
    - lib/foglet_bbs/authorization.ex
    - test/foglet_bbs/accounts/accounts_test.exs
    - test/foglet_bbs/authorization_test.exs

key-decisions:
  - "Kept user status as a string-backed Ecto.Enum and extended the existing check-constraint style."
  - "Authorized status transitions before target lookup to avoid account-existence probing."

patterns-established:
  - "Status transition callers use Foglet.Accounts.transition_user_status/3 rather than direct Repo updates."
  - "Status administration lists use Accounts grouping and exclude soft-deleted users."

requirements-completed: [USER-02, USER-03]

duration: ~25min
completed: 2026-04-24T17:17:23Z
---

# Phase 10 Plan 01: User Status Boundary Summary

**Durable rejected users with a sysop-only Accounts transition boundary and locked status graph**

## Performance

- **Duration:** ~25 min
- **Started:** 2026-04-24T16:52:00Z
- **Completed:** 2026-04-24T17:17:23Z
- **Tasks:** 2
- **Files modified:** 9

## Accomplishments

- Added `:rejected` as a durable, non-deleted account status in schema validation, database constraint migration, and data-model docs.
- Added `Foglet.Accounts.transition_user_status/3` with exact allowed transitions: `pending -> active`, `pending -> rejected`, `active -> suspended`, and `suspended -> active`.
- Added `Foglet.Accounts.list_user_status_admin_targets/1` and `:manage_user_status` authorization, including rejected actor denial in policy and scopes.

## Task Commits

1. **Task 1 RED:** `501ede8` test(10-01): add failing rejected status tests
2. **Task 1 GREEN:** `7966554` feat(10-01): add rejected user status persistence
3. **Task 2 RED:** `a768e7f` test(10-01): add failing user status administration tests
4. **Task 2 GREEN:** `f41633c` feat(10-01): add user status transition boundary

## Files Created/Modified

- `priv/repo/migrations/20260424000000_add_rejected_user_status.exs` - Extends and restores the user status check constraint.
- `test/foglet_bbs/accounts/user_status_test.exs` - Covers rejected status validation and persistence.
- `lib/foglet_bbs/accounts/user.ex` - Adds `:rejected` to valid statuses and documents transition ownership.
- `lib/foglet_bbs/accounts.ex` - Adds status transition/listing APIs and a minimal password reset delivery boundary needed by existing tests.
- `lib/foglet_bbs/authorization.ex` - Adds `:manage_user_status` and rejects `:rejected` actors.
- `test/foglet_bbs/accounts/accounts_test.exs` - Covers transition graph, forbidden actors, missing/deleted targets, grouped listings, and fixes a blocking reset-delivery assertion.
- `test/foglet_bbs/authorization_test.exs` - Covers manage_user_status and rejected actor scopes.
- `docs/DATA_MODEL.md` - Documents rejected as a non-deleted lifecycle status.

## Decisions Made

- Rejected status remains part of the existing string-backed status column, not a Postgres enum.
- Status mutation authorization happens before target lookup so unauthorized actors receive `{:error, :forbidden}` without probing targets.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Implemented missing password reset delivery boundary**
- **Found during:** Task 2 verification
- **Issue:** The required `accounts_test.exs` command included pre-existing MAIL-04/MAIL-05 tests for `Accounts.request_password_reset_delivery/1`, but that function was absent on the requested base commit.
- **Fix:** Added minimal Accounts-owned reset delivery behavior matching existing tests: no-email returns unavailable, email mode returns a generic response, active users get reset tokens/emails, and provider failures do not enumerate accounts.
- **Files modified:** `lib/foglet_bbs/accounts.ex`, `test/foglet_bbs/accounts/accounts_test.exs`
- **Verification:** `rtk mix test test/foglet_bbs/accounts/accounts_test.exs test/foglet_bbs/authorization_test.exs`
- **Committed in:** `f41633c`

---

**Total deviations:** 1 auto-fixed blocking issue.
**Impact on plan:** Needed to make the plan's required test file executable against the requested base commit; no browser/TUI/Mix status surface was added.

## Issues Encountered

- Fresh worktree dependencies were absent; ran `rtk mix deps.get`.
- Mix needed local socket access for test/compile PubSub under sandboxing; reran affected commands with approved escalation.

## Verification

- `rtk mix test test/foglet_bbs/accounts/user_test.exs test/foglet_bbs/accounts/user_status_test.exs`
- `rtk mix test test/foglet_bbs/accounts/accounts_test.exs test/foglet_bbs/authorization_test.exs`
- `rtk mix test test/foglet_bbs/accounts/user_test.exs test/foglet_bbs/accounts/user_status_test.exs test/foglet_bbs/accounts/accounts_test.exs test/foglet_bbs/authorization_test.exs`
- `rtk mix compile --warnings-as-errors`

## Known Stubs

None.

## Threat Flags

| Flag | File | Description |
|------|------|-------------|
| threat_flag: reset_delivery | `lib/foglet_bbs/accounts.ex` | Added a password reset delivery entry point required by existing tests; it is account-enumeration resistant and returns generic email-mode responses. |

## Self-Check: PASSED

- Created files exist.
- Task commits exist on branch `gsd-phase-10-01`.
- No `STATE.md` or `ROADMAP.md` changes were made or committed.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

Downstream Sysop USERS UI and break-glass Mix task plans can call `Foglet.Accounts.transition_user_status/3` and display the tagged results directly.

---
*Phase: 10-user-status-administration*
*Completed: 2026-04-24*
