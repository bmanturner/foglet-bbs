# Phase 4: Shared Invite Surface Activation - Specification

**Created:** 2026-04-24
**Ambiguity score:** 0.12 (gate: <= 0.20)
**Requirements:** 5 locked

## Goal

The shared `INVITES` tab changes from scaffold-only placeholder UI to a live invite-management surface that appears in Account, Moderation, and Sysop only for roles permitted by `invite_code_generators`.

## Background

Phase 0 created `Foglet.TUI.Screens.Shared.InvitesSurface`, `InvitesState`, and shell tab scaffolding. Account already has a conditional `INVITES` tab, while Moderation and Sysop explicitly defer adding that tab until Phase 4. The shared surface still renders loading/scaffold/future-placeholder copy and exposes no live invite actions.

Phase 1 added actor-aware authorization for `:generate_invite` and `:revoke_invite`. Phase 2 added runtime config keys for `invite_code_generators` and `invite_generation_per_user_limit`. Phase 3 added persisted single-use invites plus `Accounts.create_invite/1`, `Accounts.list_invites/1`, `Accounts.get_invite_status/1`, and `Accounts.revoke_invite/2`. Phase 4 connects that existing domain behavior to the reusable TUI surface without creating separate invite flows per screen.

## Requirements

1. **Policy-controlled tab visibility**: Account, Moderation, and Sysop expose `INVITES` only when the current role and `invite_code_generators` policy allow invite generation.
   - Current: Account can include `INVITES`; Moderation and Sysop state modules keep fixed tab lists that exclude it. `ShellVisibility.invites_visible?/2` already resolves the role/policy matrix.
   - Target: Account users see `INVITES` only in `any_user`; moderators see it in Moderation only in `mods`; sysops see it in Sysop when `sysop_only` is active and retain an allowed operator surface under broader policies.
   - Acceptance: Tests prove the tab appears for `{user, "any_user"}`, `{mod, "mods"}`, and `{sysop, "sysop_only"}`, and does not appear for disallowed role/policy combinations or nil users.

2. **Live invite listing and status display**: The shared `INVITES` body renders real persisted invite records instead of scaffold copy.
   - Current: `InvitesSurface.render/2` treats non-empty items as a future placeholder and does not display invite code, issuer, created time, consumed state, or revocation state.
   - Target: The tab loads invite statuses from `Accounts.list_invites/1` for the current actor and renders each invite's code, issuer id, created timestamp, status, consumed timestamp/user when present, and revoked timestamp when present.
   - Acceptance: Given available, consumed, and revoked invites, rendering the active `INVITES` tab includes each code and the correct `available`, `consumed`, or `revoked` status without scaffold-only copy.

3. **Invite generation action**: An authorized actor can generate a single-use invite from the shared `INVITES` tab and view the newly created code once for sharing.
   - Current: No Account, Moderation, Sysop, or shared invite screen handler dispatches `Accounts.create_invite/1`.
   - Target: The active `INVITES` tab exposes one generate command that calls `Accounts.create_invite/1`, refreshes the list after success, and surfaces the generated code in the TUI without adding duplicate per-screen generation flows.
   - Acceptance: A key/action test from each allowed surface generates exactly one persisted invite for the actor, displays the generated code, and refreshes the rendered invite list.

4. **Invite revocation action**: An authorized actor can revoke an unused invite from the shared `INVITES` tab.
   - Current: `Accounts.revoke_invite/2` exists, but no TUI surface calls it and no invite row can be selected for revocation.
   - Target: The shared tab supports selecting an available invite and revoking it through `Accounts.revoke_invite/2`; consumed or already revoked invites remain visible but cannot be successfully revoked.
   - Acceptance: Revoking an available invite from the active tab changes its rendered status to `revoked`; attempting to revoke consumed, already revoked, missing, or unauthorized invite codes surfaces a TUI error and leaves persisted state unchanged.

5. **Single shared implementation across surfaces**: Account, Moderation, and Sysop reuse the same invite state, rendering, and action handling instead of copying invite-management logic.
   - Current: Only a shared renderer/state primitive exists; the shell modules do not share live action handling because there is no live handling yet.
   - Target: Invite list loading, generate, revoke, selection, refresh, and error display are implemented in shared invite modules and called by the three shell surfaces through thin delegation only.
   - Acceptance: Static checks or tests confirm there is one shared invite action path, with shell modules containing only tab visibility, tab dispatch, and delegation code for `INVITES`.

## Boundaries

**In scope:**
- Activate the existing shared `INVITES` surface as a real TUI feature.
- Add `INVITES` tab inclusion for Account, Moderation, and Sysop according to `invite_code_generators` and role.
- Load and render persisted invite statuses from the Accounts domain.
- Generate single-use invite codes from the active shared invite tab.
- Revoke available invite codes from the active shared invite tab.
- Surface forbidden, limit-reached, not-found, unavailable, and validation errors as TUI-visible failures.
- Add regression tests for policy visibility, shared rendering, generate, revoke, and non-duplication.

**Out of scope:**
- Changing invite persistence, code generation, redemption, or transaction semantics - Phase 3 owns these domain behaviors.
- Changing registration flow or invite-only registration errors - Phase 3 already enforces redemption.
- Editing `invite_code_generators` or invite-generation limits - Phase 2 owns sysop config editing.
- Adding expiry, notes, multi-use invites, filtering, search, or campaign/referral flows - these are v2 or explicitly out of scope.
- Building full Account preferences, Moderation queue, or Sysop user administration - later phases own those workspaces.
- Adding web administration UI - this milestone remains terminal-first.

## Constraints

- The TUI must call the existing `Foglet.Accounts` invite APIs rather than duplicating invite persistence or authorization logic.
- The shared invite modules must be the single source of invite rendering and action behavior across Account, Moderation, and Sysop.
- Operator roles covered by `sysop_only` and `mods` policies get unlimited generation through the allowed operator surfaces; the per-user cap applies only to `any_user` behavior already enforced by `Accounts.create_invite/1`.
- Visibility is not authorization: hidden tabs reduce UI exposure, but generate/revoke failures from `Accounts` must still be handled and shown safely.
- Tests that touch shared config or database state must follow existing project conventions, including deterministic synchronization and `start_supervised!/1` for started processes.

## Acceptance Criteria

- [ ] Account shows `INVITES` for a regular user only when `invite_code_generators == "any_user"`.
- [ ] Moderation shows `INVITES` for a moderator only when `invite_code_generators == "mods"`.
- [ ] Sysop shows an allowed `INVITES` operator surface when `invite_code_generators == "sysop_only"` and does not require a per-user generation cap.
- [ ] Disallowed role/policy combinations and nil users do not render an accessible invite tab.
- [ ] The active `INVITES` tab renders available, consumed, and revoked persisted invite statuses with code, issuer, created time, and state-specific timestamps/user ids when present.
- [ ] Generating an invite from each allowed surface persists exactly one new invite for the current actor and displays the new code.
- [ ] Revoking an available invite from the shared tab persists `revoked_at` and refreshes the rendered status to `revoked`.
- [ ] Revoking consumed, already revoked, missing, or unauthorized invite codes surfaces a TUI-visible error and does not mutate the invite record.
- [ ] Invite list loading, generation, revocation, selection, refresh, and error mapping are implemented in shared invite modules with only thin per-screen delegation.
- [ ] `mix precommit` passes after implementation.

## Ambiguity Report

| Dimension           | Score | Min   | Status | Notes |
|---------------------|-------|-------|--------|-------|
| Goal Clarity        | 0.90  | 0.75  | met    | Roadmap and Phase 0 comments identify the exact surface to activate. |
| Boundary Clarity    | 0.88  | 0.70  | met    | Phase ownership is clear: Phase 4 wires TUI behavior, not persistence/config/registration. |
| Constraint Clarity  | 0.80  | 0.65  | met    | Must reuse Accounts APIs, shared surface modules, and existing policy matrix. |
| Acceptance Criteria | 0.86  | 0.70  | met    | Criteria cover visibility, list, generate, revoke, shared implementation, and precommit. |
| **Ambiguity**       | 0.12  | <=0.20| met    | Gate passed. |

Status: met = dimension meets minimum, below = planner treats as assumption

## Interview Log

Interactive question UI was unavailable in this execution mode, so the workflow fallback was used: defaults were selected from roadmap, requirements, existing code comments, and completed phase artifacts.

| Round | Perspective | Question summary | Decision locked |
|-------|-------------|------------------|-----------------|
| 1 | Researcher | What exists today related to invite surfaces? | Shared scaffold exists; Account conditionally includes `INVITES`; Moderation/Sysop defer tab inclusion; Accounts domain APIs are live. |
| 2 | Researcher + Simplifier | What is the minimum phase that solves the core problem? | Activate list, generate, and revoke in one shared tab; do not add expiry, notes, search, or richer invite history. |
| 3 | Boundary Keeper | What is explicitly not this phase? | No persistence redesign, no registration changes, no config editing, no full Account/Moderation/Sysop workspace population. |
| 4 | Failure Analyst | What would make verification reject the output? | Duplicated per-screen flows, visible tabs for unauthorized combinations, scaffold copy remaining in live state, or TUI actions bypassing `Accounts`. |

---

*Phase: 04-shared-invite-surface-activation*
*Spec created: 2026-04-24*
*Next step: $gsd-discuss-phase 4 - implementation decisions (how to build what's specified above)*
