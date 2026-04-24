---
phase: 03-invite-persistence-and-registration-enforcement
plan: 01
subsystem: accounts
tags: [elixir, ecto, postgres, invites, tdd]

requires:
  - phase: 02-sysop-config-and-board-management
    provides: invite_generation_per_user_limit runtime config dependency
provides:
  - invite_codes persistence table with lifecycle indexes
  - Foglet.Accounts.Invite schema, changeset, and status helper
  - RED tests for invite generation, review, revocation, and invite-only registration
affects: [phase-03-plan-02, phase-03-plan-03, shared-invites-surface]

tech-stack:
  added: []
  patterns: [programmatic foreign keys in fixtures, derived invite status from timestamps]

key-files:
  created:
    - lib/foglet_bbs/accounts/invite.ex
    - priv/repo/migrations/20260424001147_create_invite_codes.exs
    - test/foglet_bbs/accounts/invite_test.exs
    - test/foglet_bbs/accounts/invite_registration_test.exs
  modified:
    - test/support/accounts_fixtures.ex

key-decisions:
  - "Invite changeset casts only the public code; issuer and consumption fields remain programmatic."
  - "Tests use the existing invite_code_generators enum value sysop_only rather than the plan shorthand sysops."

patterns-established:
  - "Invite lifecycle status is derived from persisted revoked_at and consumed_at timestamps, with revocation taking precedence."
  - "Invite fixtures set issuer_id on the struct before changeset construction to preserve programmatic ownership."

requirements-completed: [INVT-02, INVT-03, INVT-04, INVT-05]

duration: 20min
completed: 2026-04-24
---

# Phase 03 Plan 01: Invite Persistence and Registration Enforcement Summary

**Invite persistence schema plus RED lifecycle and registration tests for invite-only onboarding**

## Performance

- **Duration:** 20 min
- **Started:** 2026-04-24T00:11:00Z
- **Completed:** 2026-04-24T00:16:44Z
- **Tasks:** 2
- **Files modified:** 5

## Accomplishments

- Created the `invite_codes` table migration with UUID primary key, issuer and consumed-by user FKs, lifecycle timestamps, unique code index, and lifecycle query indexes.
- Added `Foglet.Accounts.Invite` with code validation, unique constraint, and `status/1` derivation.
- Added focused RED tests for invite generation policy, listing/status review, revocation behavior, and invite-only registration redemption semantics.

## Task Commits

1. **Task 1: Verify Phase 2 dependency and create invite persistence** - `511ec14` (feat)
2. **Task 2: Add failing invite lifecycle and registration tests** - `ccb172d` (test)
3. **Task 1 formatting follow-up** - `19bd7f2` (style)

**Plan metadata:** `38c7e06` (initial docs), final summary correction in this docs commit.

## Files Created/Modified

- `lib/foglet_bbs/accounts/invite.ex` - Invite schema, changeset, and derived status helper.
- `priv/repo/migrations/20260424001147_create_invite_codes.exs` - Invite persistence table and indexes.
- `test/foglet_bbs/accounts/invite_test.exs` - Invite persistence foundation and lifecycle RED tests.
- `test/foglet_bbs/accounts/invite_registration_test.exs` - Invite-only registration RED tests.
- `test/support/accounts_fixtures.ex` - Reusable invite fixture helpers.

## Decisions Made

- Used the existing config enum value `"sysop_only"` in tests because `Foglet.Config.Schema` rejects `"sysops"`.
- Kept issuer and consumption fields out of `Invite.changeset/2` and set `issuer_id` directly in fixtures, matching project Ecto guidance for programmatic fields.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Corrected test setup for role-specific actors**
- **Found during:** Task 2
- **Issue:** Passing `%{role: :sysop}` or `%{role: :mod}` into `user_fixture/1` did not create promoted actors because registration does not cast role.
- **Fix:** Added local test helper promotion through `Accounts.update_role/2`.
- **Files modified:** `test/foglet_bbs/accounts/invite_test.exs`, `test/foglet_bbs/accounts/invite_registration_test.exs`
- **Verification:** Focused test run reaches expected RED failures instead of incorrect actor setup failures.
- **Committed in:** `ccb172d`

**2. [Rule 1 - Bug] Corrected invite fixture arity and code length**
- **Found during:** Task 2
- **Issue:** `invite_fixture(sysop)` was ambiguous with the default attrs helper, and generated codes could be shorter than the schema minimum.
- **Fix:** Added explicit one-arg issuer clause and generated longer uppercase fixture codes.
- **Files modified:** `test/support/accounts_fixtures.ex`
- **Verification:** Focused test run no longer fails from fixture changeset or function-clause errors.
- **Committed in:** `ccb172d`

---

**Total deviations:** 2 auto-fixed (2 Rule 1 bugs)
**Impact on plan:** Test setup was corrected so remaining failures represent the intended RED contract for later plans.

## Issues Encountered

- `mix ecto.gen.migration` initially failed inside the sandbox because Mix PubSub could not open a local TCP socket. Retried with approved escalation and generated the migration successfully.
- Focused verification currently fails as expected for missing production behavior:
  - `Foglet.Accounts.create_invite/1`
  - `Foglet.Accounts.list_invites/1`
  - `Foglet.Accounts.get_invite_status/1`
  - `Foglet.Accounts.revoke_invite/2`
  - invite-only enforcement and atomic invite consumption in `register_user/1`

## Verification

- `mix test test/foglet_bbs/accounts/invite_test.exs` after Task 1: passed, 3 tests.
- `mix test test/foglet_bbs/accounts/invite_test.exs test/foglet_bbs/accounts/invite_registration_test.exs` after Task 2: reached expected RED failures only for future production APIs and registration enforcement.
- Acceptance greps for required markers all passed.

## Known Stubs

None. Stub scan hits were test assertions for nil/non-empty values, not placeholder implementation.

## Threat Flags

None. New security-relevant surface matches the plan threat model: persisted invite codes and lifecycle state.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

Plan 02 can implement invite generation, listing, status lookup, and revocation directly against the RED tests in `invite_test.exs`. Plan 03 can implement invite-only registration and transactional redemption against `invite_registration_test.exs`.

## Self-Check: PASSED

- Found `lib/foglet_bbs/accounts/invite.ex`
- Found `priv/repo/migrations/20260424001147_create_invite_codes.exs`
- Found `test/foglet_bbs/accounts/invite_registration_test.exs`
- Found task commit `511ec14`
- Found task commit `ccb172d`

---
*Phase: 03-invite-persistence-and-registration-enforcement*
*Completed: 2026-04-24*
