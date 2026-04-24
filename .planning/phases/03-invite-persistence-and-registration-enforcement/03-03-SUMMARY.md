---
phase: 03-invite-persistence-and-registration-enforcement
plan: 03
subsystem: accounts
tags: [elixir, ecto, invites, registration, tui]

requires:
  - phase: 03-invite-persistence-and-registration-enforcement
    provides: invite_codes persistence and invite lifecycle APIs from Plans 01-02
provides:
  - invite-only registration enforcement through Foglet.Accounts.register_user/1
  - transactional single-use invite redemption coupled to user creation
  - non-consuming register-screen invite-code preflight
affects: [shared-invites-surface, invite-only-registration, account-registration]

tech-stack:
  added: []
  patterns:
    - domain-side invite redemption as the registration trust boundary
    - TUI invite preflight limited to syntax checks only

key-files:
  created:
    - .planning/phases/03-invite-persistence-and-registration-enforcement/03-03-SUMMARY.md
  modified:
    - lib/foglet_bbs/accounts.ex
    - lib/foglet_bbs/tui/screens/register.ex
    - test/foglet_bbs/accounts/invite_registration_test.exs
    - test/foglet_bbs/tui/screens/register_test.exs
    - test/foglet_bbs/authorization_test.exs
    - test/foglet_bbs/config/schema_test.exs

key-decisions:
  - "Foglet.Accounts.register_user/1 is the only invite consumption path; the register screen only collects and forwards invite_code."
  - "Unavailable invite failures share one generic invite_code changeset error."
  - "User changeset validation runs before invite mutation so invalid account details leave valid invites available."

patterns-established:
  - "Invite redemption uses a conditional update inside Repo.transact/1 so race-lost redemptions roll back user creation."
  - "Register-screen invite preflight checks only the generated-code shape, not persistence or availability."

requirements-completed: [INVT-05]

duration: 7min
completed: 2026-04-24
---

# Phase 03 Plan 03: Invite Registration Enforcement Summary

**Invite-only registration now redeems persisted invites atomically while the TUI preflight stays non-consuming**

## Performance

- **Duration:** 7 min
- **Started:** 2026-04-24T00:28:57Z
- **Completed:** 2026-04-24T00:35:34Z
- **Tasks:** 3
- **Files modified:** 6

## Accomplishments

- `Accounts.register_user/1` now routes `"invite_only"` mode through transactional invite redemption.
- Missing, unknown, revoked, consumed, and race-lost invite codes return one generic `invite_code` changeset error.
- Invalid user attrs are rejected before invite mutation, preserving invite availability.
- The register screen no longer calls or probes `consume_invite_code/1`; it only checks invite-code format and forwards the code to final submission.

## Task Commits

1. **Task 1: Implement invite-only registration transaction** - `04c9b40` (feat)
2. **Task 2: Remove register-screen consume-on-preflight behavior** - `4874431` (fix)
3. **Task 3: Run full phase verification and precommit** - `7c1d790` (test)
4. **Precommit refactor follow-up** - `8950c75` (refactor)

**Plan metadata:** recorded in a docs commit after this summary was created.

## Files Created/Modified

- `lib/foglet_bbs/accounts.ex` - Invite-only registration branch, transactional redemption helpers, and generic invite-code errors.
- `lib/foglet_bbs/tui/screens/register.ex` - Non-consuming invite-code format preflight.
- `test/foglet_bbs/accounts/invite_registration_test.exs` - Invite-only registration tests adjusted so fixtures can exist while invite-only mode is under test.
- `test/foglet_bbs/tui/screens/register_test.exs` - Preflight tests for non-consuming valid and malformed invite codes.
- `test/foglet_bbs/authorization_test.exs` - Aligned regular-user invite generation gate expectation with Plan 02 behavior.
- `test/foglet_bbs/config/schema_test.exs` - Aligned config schema expectations with the invite generation cap key added in Plan 02.

## Decisions Made

- Preserved open registration behavior for non-`"invite_only"` modes, including post-commit default board subscription.
- Kept true invite availability validation out of the TUI; `Accounts.register_user/1` owns persistence and consumption.
- Treated stale Plan 02 test expectations as verification blockers and updated tests without changing production policy.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Kept invite registration fixtures independent of invite-only enforcement**
- **Found during:** Task 1
- **Issue:** Forcing `registration_mode` to `"invite_only"` before fixture creation caused `AccountsFixtures.user_fixture/1` and `invite_fixture/1` to fail because fixtures use `Accounts.register_user/1`.
- **Fix:** Added a local `with_open_registration/1` helper in the invite registration test so issuer, consumed-user, and invite fixture setup can happen under open registration while assertions still exercise invite-only mode.
- **Files modified:** `test/foglet_bbs/accounts/invite_registration_test.exs`
- **Verification:** `mix test test/foglet_bbs/accounts/invite_registration_test.exs`
- **Committed in:** `04c9b40`

**2. [Rule 1 - Bug] Aligned stale Plan 02 verification expectations**
- **Found during:** Task 3
- **Issue:** Full `mix test` still expected six config schema keys and regular users to fail the coarse `:generate_invite` authorization gate, both superseded by Plan 02.
- **Fix:** Updated config schema tests for `invite_generation_per_user_limit` and authorization matrix expectations for regular-user invite generation.
- **Files modified:** `test/foglet_bbs/authorization_test.exs`, `test/foglet_bbs/config/schema_test.exs`
- **Verification:** `mix test test/foglet_bbs/authorization_test.exs test/foglet_bbs/config/schema_test.exs test/foglet_bbs/accounts/invite_test.exs test/foglet_bbs/accounts/invite_registration_test.exs test/foglet_bbs/tui/screens/register_test.exs`
- **Committed in:** `7c1d790`

**3. [Rule 1 - Bug] Simplified invite registration transaction for Credo**
- **Found during:** Task 3
- **Issue:** `mix precommit` flagged the initial transaction code for a redundant `with` clause and then excessive cyclomatic complexity.
- **Fix:** Extracted blank-code, transaction, and result-handling helpers while preserving the same redemption behavior.
- **Files modified:** `lib/foglet_bbs/accounts.ex`
- **Verification:** `mix test test/foglet_bbs/accounts/invite_registration_test.exs`; `mix precommit`
- **Committed in:** `8950c75`

---

**Total deviations:** 3 auto-fixed (3 Rule 1 bugs)
**Impact on plan:** All fixes were required to make the planned invite enforcement verifiable without expanding the Phase 3 surface.

## Issues Encountered

- Concurrent unrelated sysop/Plan 02-04 work was present and continued during this execution. It was not reverted or included in Plan 03-03 commits.
- `mix precommit` formatted an unrelated dirty sysop file already present in the worktree. That file was left uncommitted per the sequential execution constraint.

## Verification

- `mix test test/foglet_bbs/accounts/invite_registration_test.exs` - passed, 5 tests.
- `mix test test/foglet_bbs/tui/screens/register_test.exs test/foglet_bbs/accounts/invite_registration_test.exs` - passed, 35 tests.
- `mix test test/foglet_bbs/accounts/invite_test.exs test/foglet_bbs/accounts/invite_registration_test.exs test/foglet_bbs/tui/screens/register_test.exs` - passed, 48 tests.
- `mix test` - passed, 1111 tests.
- `mix precommit` - passed.
- Acceptance greps for invite-only helpers, generic invite errors, `consumed_by_user_id`, non-consuming register preflight, and final `Accounts.register_user(data)` submit path all passed.
- Plan 03-03 commits did not touch shared invite surface activation files under `lib/foglet_bbs/tui/screens/shared/`, account/moderation/sysop invite tabs, or TUI invite commands.

## Known Stubs

None. Stub scan hits were assertions for nil/empty values in tests and existing account-state logic, not placeholder implementation.

## Threat Flags

None. The new security-relevant surface matches the plan threat model: untrusted invite codes enter `Accounts.register_user/1`, redemption is transactional, and the TUI remains advisory only.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

Phase 4 can activate the shared invite surface against real lifecycle APIs and rely on `Accounts.register_user/1` as the single invite redemption boundary.

## Self-Check: PASSED

- Found `lib/foglet_bbs/accounts.ex`
- Found `lib/foglet_bbs/tui/screens/register.ex`
- Found `test/foglet_bbs/accounts/invite_registration_test.exs`
- Found `test/foglet_bbs/tui/screens/register_test.exs`
- Found task commit `04c9b40`
- Found task commit `4874431`
- Found task commit `7c1d790`
- Found refactor commit `8950c75`

---
*Phase: 03-invite-persistence-and-registration-enforcement*
*Completed: 2026-04-24*
