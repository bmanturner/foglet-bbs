# Phase 3: Invite Persistence and Registration Enforcement - Specification

**Created:** 2026-04-23
**Ambiguity score:** 0.15 (gate: <= 0.20)
**Requirements:** 6 locked

## Goal

Invite-only registration changes from accepting placeholder invite codes to requiring persisted, policy-authorized, single-use invites redeemed transactionally with user creation.

## Background

`registration_mode` already supports `"invite_only"`, and the registration screen already collects an invite code before account details in that mode. Today, `Foglet.TUI.Screens.Register.valid_invite_code?/1` falls back to accepting any non-empty alphanumeric placeholder code when `Foglet.Accounts.consume_invite_code/1` is absent, and `Foglet.Accounts.register_user/1` ignores the submitted `invite_code`. Authorization actions for `:generate_invite` and `:revoke_invite` already exist, and Phase 2 defines runtime invite policy through `invite_code_generators` plus `invite_generation_per_user_limit`. No invite schema, migration, status API, revocation behavior, or transactional invite redemption exists yet.

## Requirements

1. **Persisted invite records**: The system stores single-use invite records with enough state to generate, review, revoke, and redeem invites.
   - Current: No invite schema or table exists; invite codes are not persisted.
   - Target: Invite records persist a unique public `code`, `issuer_id`, `consumed_at`, `consumed_by_user_id`, `revoked_at`, and timestamps. Derived status is exposed as `:available`, `:consumed`, or `:revoked`.
   - Acceptance: Tests can create invite records, query their persisted issuer/created/consumed/revoked fields, and observe the correct derived status for available, consumed, and revoked records.

2. **Policy-authorized invite generation**: Invite creation is allowed only when the actor is authorized and the runtime invite generation policy permits it.
   - Current: `Authorization` exposes invite actions, and runtime config exposes invite policy, but no domain invite generation function exists.
   - Target: `Foglet.Accounts` exposes an invite creation function that enforces `Authorization.authorize(:generate_invite, actor, :site)`, `Foglet.Config.invite_code_generators/0`, and `Foglet.Config.invite_generation_per_user_limit/0` when policy is `"any_user"`. A limit value of `0` means unlimited.
   - Acceptance: Tests prove sysop/mod/user actors are allowed or rejected according to `invite_code_generators`, and a numeric per-user cap rejects generation after the actor reaches the cap while `0` does not cap generation.

3. **Invite status review**: Authorized domain callers can review invite status without building the shared invite UI.
   - Current: No invite status query exists.
   - Target: `Foglet.Accounts` exposes status/list retrieval that returns `code`, `issuer_id`, `created_at`, `consumed_at`, `consumed_by_user_id`, `revoked_at`, and derived status.
   - Acceptance: Tests can retrieve generated invites and verify the returned status fields match persisted state before revocation, after revocation, and after redemption.

4. **Unused invite revocation**: Authorized actors can revoke unused invite codes, and revoked codes cannot be redeemed.
   - Current: No revoke behavior exists.
   - Target: `Foglet.Accounts` exposes a revocation function that enforces `Authorization.authorize(:revoke_invite, actor, :site)`, sets `revoked_at` on available invites, rejects missing or already-consumed invites, and leaves consumed invites unchanged.
   - Acceptance: Tests prove available invites become revoked, revoked invites are rejected by registration, consumed invites cannot be revoked, and unauthorized actors cannot revoke invites.

5. **Invite-only registration enforcement**: Registration in `invite_only` mode accepts only persisted, available invite codes.
   - Current: The register screen accepts placeholder alphanumeric invite codes when the invite domain API is absent, and `Accounts.register_user/1` ignores `invite_code`.
   - Target: In `invite_only` mode, registration rejects missing, invalid, revoked, or consumed invite codes with a changeset-style error on `invite_code`.
   - Acceptance: Tests prove registration fails for missing, unknown, revoked, and consumed invite codes, and the failure is surfaced as a field error associated with `invite_code`.

6. **Transactional single-use redemption**: Successful invite-only registration consumes exactly one invite in the same transaction as user creation.
   - Current: User creation and invite code handling are not coupled.
   - Target: A valid invite is consumed only when user creation succeeds; failed user changesets do not consume invites; concurrent redemption cannot create two users from one invite.
   - Acceptance: Tests prove a successful registration sets `consumed_at` and `consumed_by_user_id`, a failed registration leaves the invite available, and a second redemption attempt for the same invite fails.

## Boundaries

**In scope:**
- Invite persistence migration and schema for single-use v1.1 invites.
- Domain/API functions in `Foglet.Accounts` for create, list/status retrieval, revoke, and transactional redemption.
- Enforcement of existing actor authorization plus Phase 2 runtime invite generation policy.
- Registration enforcement for `invite_only` mode.
- Tests covering invite lifecycle, policy enforcement, registration failure behavior, and transactional single-use redemption.

**Out of scope:**
- Shared `INVITES` tab activation or any new TUI command wiring - Phase 4 owns the reusable invite surface.
- Invite expiry, notes, multi-use limits, campaign/referral trees, or search/filtering - these are v2 invite workflow requirements.
- Hiding invite codes from operators through token-style hashing - v1.1 status review needs direct code display for sharing/review.
- Sysop approval registration behavior beyond preserving the existing `sysop_approved` pending-user path - this phase is about invite-only enforcement.
- Email delivery changes or verification-code UX - existing email verification behavior remains separate.

## Constraints

- Invite codes are stored as generated public codes with a unique index.
- Invite redemption must be atomic with user creation and must prevent double-consumption under concurrent attempts.
- Invalid, revoked, and consumed invite registration failures must all produce a changeset-style `invite_code` error rather than raising.
- `invite_generation_per_user_limit == 0` means unlimited; positive values are numeric caps for `"any_user"` generation.
- No new HTTP client or date/time dependency is required.

## Acceptance Criteria

- [ ] Generated invites persist `code`, `issuer_id`, timestamps, consumed state, revocation state, and expose derived status.
- [ ] Invite generation enforces actor authorization and `invite_code_generators` policy for sysop, mod, and user actors.
- [ ] `"any_user"` invite generation enforces `invite_generation_per_user_limit`, with `0` treated as unlimited.
- [ ] Invite status retrieval exposes `code`, `issuer_id`, `created_at`, `consumed_at`, `consumed_by_user_id`, `revoked_at`, and derived status.
- [ ] Revoking an available invite sets `revoked_at`; revoked or consumed invites cannot be redeemed.
- [ ] Consumed invites cannot be revoked and unauthorized actors cannot revoke invites.
- [ ] `invite_only` registration rejects missing, unknown, revoked, and consumed invite codes with an `invite_code` field error.
- [ ] Successful invite-only registration consumes the invite in the same transaction as user creation.
- [ ] Failed user registration does not consume a valid invite.
- [ ] A second redemption attempt for the same invite fails and does not create a second user.
- [ ] No new shared invite UI or TUI command wiring is added in Phase 3.

## Ambiguity Report

| Dimension          | Score | Min   | Status | Notes                                      |
|--------------------|-------|-------|--------|--------------------------------------------|
| Goal Clarity       | 0.92  | 0.75  | ✓      | Invite-only registration target is explicit |
| Boundary Clarity   | 0.90  | 0.70  | ✓      | Domain/API only; Phase 4 owns UI activation |
| Constraint Clarity | 0.80  | 0.65  | ✓      | Storage, policy, cap, and transaction rules locked |
| Acceptance Criteria| 0.84  | 0.70  | ✓      | Pass/fail lifecycle and registration criteria listed |
| **Ambiguity**      | 0.15  | <=0.20| ✓      | Gate passed                                |

Status: ✓ = met minimum, ⚠ = below minimum (planner treats as assumption)

## Interview Log

| Round | Perspective            | Question summary                         | Decision locked |
|-------|------------------------|------------------------------------------|-----------------|
| 1     | Researcher             | Domain/API only or temporary TUI?        | Phase 3 is domain/API only; Phase 4 activates the shared `INVITES` tab. |
| 1     | Researcher             | Which generation policies apply now?     | Invite generation enforces both existing `Authorization` actions and runtime policy/cap config. |
| 1     | Researcher             | How do invalid and failed-registration cases behave? | Invalid, revoked, and consumed codes reject with an `invite_code` changeset-style error; valid invites are consumed only with successful user creation. |
| 2     | Researcher + Simplifier | What status fields must be exposed?      | Status review exposes `code`, `issuer_id`, `created_at`, `consumed_at`, `consumed_by_user_id`, `revoked_at`, and derived status. |
| 2     | Researcher + Simplifier | Raw or hashed invite code storage?       | Store generated public codes raw with a unique index for v1.1. |
| 2     | Researcher + Simplifier | Minimum successful deliverable?          | Migration, schema, `Foglet.Accounts` invite functions, registration enforcement, and tests; no UI commands. |

---

*Phase: 03-invite-persistence-and-registration-enforcement*
*Spec created: 2026-04-23*
*Next step: $gsd-discuss-phase 3 - implementation decisions (how to build what's specified above)*
