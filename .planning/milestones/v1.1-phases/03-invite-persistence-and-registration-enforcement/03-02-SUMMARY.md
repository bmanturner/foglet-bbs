---
phase: 03-invite-persistence-and-registration-enforcement
plan: 02
subsystem: accounts
tags: [elixir, ecto, invites, authorization, tdd]

requires:
  - phase: 03-invite-persistence-and-registration-enforcement
    provides: invite_codes persistence table and Invite schema from Plan 01
provides:
  - Accounts-domain invite generation with Bodyguard authorization and runtime policy enforcement
  - Secure persisted invite code creation with per-user cap support
  - Invite listing, status lookup, and unused invite revocation APIs
affects: [phase-03-plan-03, shared-invites-surface, invite-only-registration]

tech-stack:
  added: []
  patterns:
    - domain-side Bodyguard checks before invite side effects
    - exact invite status projection maps for lifecycle APIs
    - conditional Ecto update_all for available-only revocation

key-files:
  created:
    - .planning/phases/03-invite-persistence-and-registration-enforcement/03-02-SUMMARY.md
  modified:
    - lib/foglet_bbs/accounts.ex
    - lib/foglet_bbs/authorization.ex
    - test/foglet_bbs/accounts/invite_test.exs

key-decisions:
  - "Regular users pass only the coarse :generate_invite site authorization gate; Accounts.create_invite/1 still enforces invite_code_generators and caps."
  - "Accounts.list_invites/1 returns the plan-specified {:ok, rows} tuple, so the RED test was aligned to the documented public interface."

patterns-established:
  - "Invite lifecycle APIs return tagged errors for forbidden, not_found, limit_reached, and unavailable states."
  - "Revocation uses a conditional database update so consumed or already-revoked invites are not mutated."

requirements-completed: [INVT-02, INVT-03, INVT-04]

duration: 25min
completed: 2026-04-24
---

# Phase 03 Plan 02: Invite Lifecycle API Summary

**Accounts-domain invite generation, review, and revocation backed by persisted invite codes**

## Performance

- **Duration:** 25 min
- **Started:** 2026-04-24T00:01:30Z
- **Completed:** 2026-04-24T00:26:30Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments

- Added `Accounts.create_invite/1` with Bodyguard authorization, runtime `invite_code_generators` policy enforcement, secure Base32 code generation, unique-collision retry, and per-user cap checks.
- Added narrow `Foglet.Authorization` support for active regular users to pass the `:generate_invite` site gate without broadening revocation.
- Added `Accounts.list_invites/1`, `Accounts.get_invite_status/1`, and `Accounts.revoke_invite/2` with lifecycle status maps and conditional available-only revocation.

## Task Commits

1. **Task 1: Implement secure policy-authorized invite generation** - `c33521f` (feat)
2. **Task 2: Implement invite status review and revocation** - `cd0bf7c` (feat)

## Files Created/Modified

- `lib/foglet_bbs/accounts.ex` - Invite generation, status projection, listing, lookup, and revocation APIs.
- `lib/foglet_bbs/authorization.ex` - Narrow regular-user `:generate_invite` authorization allowance.
- `test/foglet_bbs/accounts/invite_test.exs` - Updated list API expectation to the plan-specified tagged tuple.
- `.planning/phases/03-invite-persistence-and-registration-enforcement/03-02-SUMMARY.md` - This execution summary.

## Decisions Made

- Kept regular-user authorization coarse and narrow: Bodyguard permits active users for `:generate_invite` at `:site`, while `Accounts.create_invite/1` remains the runtime policy boundary for `"any_user"`.
- Kept `revoke_invite/2` authorization unchanged for regular users; unauthorized callers are rejected before lookup or mutation.
- Treated the Plan 01 list test as RED contract drift and aligned it to the Plan 02 public interface: `{:ok, [invite_status]}`.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Aligned list invite test with documented return tuple**
- **Found during:** Task 2
- **Issue:** The existing RED test matched a bare list from `Accounts.list_invites/1`, but the plan interface required `{:ok, [map()]}`.
- **Fix:** Updated the test expectation to match `{:ok, rows}` and implemented the public API with that shape.
- **Files modified:** `test/foglet_bbs/accounts/invite_test.exs`, `lib/foglet_bbs/accounts.ex`
- **Verification:** `mix test test/foglet_bbs/accounts/invite_test.exs`
- **Committed in:** `cd0bf7c`

**2. [Rule 1 - Bug] Tightened invite status type spec for Dialyzer**
- **Found during:** Plan-level `mix precommit`
- **Issue:** `get_invite_status/1` specified `map()`, which Dialyzer flagged as wider than the exact returned status projection.
- **Fix:** Added an `invite_status` type and used it for `list_invites/1` and `get_invite_status/1`.
- **Files modified:** `lib/foglet_bbs/accounts.ex`
- **Verification:** `mix precommit`
- **Committed in:** `cd0bf7c`

---

**Total deviations:** 2 auto-fixed (2 Rule 1 bugs)
**Impact on plan:** Both fixes preserved the planned API and improved verification precision.

## Issues Encountered

- `mix precommit` initially failed on a Dialyzer contract precision warning for `get_invite_status/1`; the spec was tightened and precommit then passed.
- Parallel work added commit `8920ff6` after this plan's task commits. It was not reverted or included in this plan's task scope.

## Verification

- `mix test test/foglet_bbs/accounts/invite_test.exs` - passed, 13 tests.
- Acceptance greps for secure randomness, generation authorization, cap enforcement, revocation authorization, and `Invite.status` - passed.
- `mix precommit` - passed after the Dialyzer spec fix.

## Known Stubs

None. Stub scan only found test assertions for non-empty and non-nil values plus existing account-control comments.

## Threat Flags

None. New security-relevant surface matches the plan threat model: side-effecting APIs authorize in `Foglet.Accounts`, code generation uses secure randomness, and revocation uses a conditional available-only update.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

Plan 03 can implement invite-only registration and atomic invite consumption against persisted invite codes. Shared invite UI activation can now call real Accounts lifecycle APIs instead of placeholders.

## Self-Check: PASSED

- Found `lib/foglet_bbs/accounts.ex`
- Found `lib/foglet_bbs/authorization.ex`
- Found `test/foglet_bbs/accounts/invite_test.exs`
- Found task commit `c33521f`
- Found task commit `cd0bf7c`

---
*Phase: 03-invite-persistence-and-registration-enforcement*
*Completed: 2026-04-24*
