# Phase 04: shared-invite-surface-activation - Discussion Log (Assumptions Mode)

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions captured in CONTEXT.md — this log preserves the analysis.

**Date:** 2026-04-23
**Phase:** 04-shared-invite-surface-activation
**Mode:** assumptions
**Areas analyzed:** Visibility and Surface Placement, Shared Invite State and Actions, Domain API Boundary, Rendering and Interaction Shape

## Assumptions Presented

### Visibility and Surface Placement

| Assumption | Confidence | Evidence |
|------------|------------|----------|
| `INVITES` should be added to Account, Moderation, and Sysop through each shell's existing tab-state construction, using `ShellVisibility.invites_visible?/2` as the shared policy seam. | Confident | `.planning/phases/04-shared-invite-surface-activation/04-SPEC.md`; `lib/foglet_bbs/tui/screens/account.ex`; `lib/foglet_bbs/tui/screens/account/state.ex`; `lib/foglet_bbs/tui/screens/moderation/state.ex`; `lib/foglet_bbs/tui/screens/sysop/state.ex`; `lib/foglet_bbs/tui/screens/shell_visibility.ex` |

### Shared Invite State and Actions

| Assumption | Confidence | Evidence |
|------------|------------|----------|
| List loading, generated-code display, selected-row state, refresh state, and error state should live in `InvitesState` or adjacent shared invite modules, with Account, Moderation, and Sysop only delegating when active tab is `INVITES`. | Confident | `.planning/phases/04-shared-invite-surface-activation/04-SPEC.md`; `.planning/phases/00-screen-shells-and-shared-surface-primitives/00-CONTEXT.md`; `lib/foglet_bbs/tui/screens/shared/invites_surface.ex`; `lib/foglet_bbs/tui/screens/shared/invites_state.ex`; `lib/foglet_bbs/tui/screens/account.ex` |

### Domain API Boundary

| Assumption | Confidence | Evidence |
|------------|------------|----------|
| The TUI should call only `Foglet.Accounts.create_invite/1`, `list_invites/1`, and `revoke_invite/2` for live behavior, and map tagged errors into visible TUI state instead of pre-authorizing or reimplementing policy. | Confident | `.planning/phases/04-shared-invite-surface-activation/04-SPEC.md`; `.planning/phases/01-authorization-and-scope-backbone/01-CONTEXT.md`; `.planning/phases/03-invite-persistence-and-registration-enforcement/03-VERIFICATION.md`; `lib/foglet_bbs/accounts.ex`; `test/foglet_bbs/accounts/invite_test.exs` |

### Rendering and Interaction Shape

| Assumption | Confidence | Evidence |
|------------|------------|----------|
| The live shared surface should replace scaffold/future-placeholder copy with rendered status rows from `Accounts.list_invites/1`, including code, issuer id, inserted timestamp, derived status, and state-specific consumed/revoked details; generation and revocation should be keyboard-driven actions in the shared active tab. | Likely | `.planning/phases/04-shared-invite-surface-activation/04-SPEC.md`; `lib/foglet_bbs/tui/screens/shared/invites_surface.ex`; `test/foglet_bbs/tui/screens/shared/invites_surface_test.exs`; `lib/foglet_bbs/accounts.ex` |

## Corrections Made

No corrections — all assumptions confirmed.

