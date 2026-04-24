# Phase 8: Moderation Workspace Population and Scope-Aware Operations — Specification

**Created:** 2026-04-24
**Ambiguity score:** 0.16 (gate: ≤ 0.20)
**Requirements:** 7 locked

## Goal

Moderators can hide abusive oneliners from the populated Moderation workspace, with every visible datum and available action constrained by the current operator's authorized scope.

## Background

Phase 0 created the Moderation screen shell with five fixed tabs: `QUEUE`, `LOG`, `USERS`, `SANCTIONS`, and `BOARDS`. Those tabs currently render Phase 8 placeholder text and dispatch no moderation commands. Phase 1 added `Foglet.Authorization`, including `:hide_oneliner`, `Bodyguard.permit/4` policy enforcement, and `Foglet.Authorization.scopes_for/2` for data-visibility filtering. Phase 7 is expected to add persisted oneliners with `hidden`, `hidden_reason`, `hidden_by_id`, author data, and recent-visible listing behavior, but it explicitly excludes hide UI. There is no implemented moderation report, sanction, or general user-administration workflow today.

## Requirements

1. **Scoped workspace population**: The Moderation workspace replaces Phase 0 placeholder copy with real scoped content or explicit empty states for each tab.
   - Current: `Foglet.TUI.Screens.Moderation` renders "will arrive in Phase 8" placeholders for all tab bodies.
   - Target: Each tab renders data derived from existing domain state and `Foglet.Authorization.scopes_for/2`, or an honest empty/unavailable state when the corresponding v1.1 workflow does not exist.
   - Acceptance: Rendering `QUEUE`, `LOG`, `USERS`, `SANCTIONS`, and `BOARDS` for a moderator or sysop contains no Phase 8 placeholder copy and does not expose data outside the actor's scopes.

2. **Oneliner hide domain operation**: A moderator or sysop can hide an existing visible oneliner through an actor-aware domain API.
   - Current: Phase 7 owns oneliner creation/listing and hidden fields, but exposes no hide operation.
   - Target: The oneliner domain exposes a hide operation that accepts the actor, target oneliner, and non-empty reason; authorizes `:hide_oneliner` against the appropriate scope before mutating; sets `hidden: true`, `hidden_reason`, and `hidden_by_id`.
   - Acceptance: Authorized mod/sysop actors can hide a visible oneliner; regular users, guests, deleted users, pending users, suspended users, and out-of-scope actors receive `{:error, :forbidden}` with no row mutation.

3. **Required hide reason**: Oneliner hide actions require a non-empty moderator-entered reason.
   - Current: `hidden_reason` is documented as part of the oneliner schema, but no hide workflow exists.
   - Target: Blank or missing reasons are rejected before persistence and the target oneliner remains visible.
   - Acceptance: A database-backed test proves blank and whitespace-only reasons return a validation/domain error and leave `hidden`, `hidden_reason`, and `hidden_by_id` unchanged.

4. **Recent-visible exclusion**: Hidden oneliners disappear from the main-menu recent-visible list through the domain query contract.
   - Current: Phase 7 recent listing is expected to return visible entries only, and Phase 8 has no hide behavior yet.
   - Target: Once an oneliner is hidden, calls to the recent-visible listing exclude it without requiring direct database edits or special TUI filtering.
   - Acceptance: After hiding an oneliner, the public recent-visible listing no longer returns that entry and still returns other visible entries in newest-first order.

5. **Narrow moderation audit log**: Every successful oneliner hide action creates a moderation audit record visible in the `LOG` tab.
   - Current: The data model documents `mod_actions`, but no moderation audit persistence is implemented.
   - Target: Phase 8 persists a narrow audit record for `:hide_oneliner` containing the moderator, target kind/id, required reason, timestamp, and enough target metadata for the Moderation `LOG` tab to render the action history.
   - Acceptance: A successful hide inserts exactly one hide audit record; forbidden or invalid hide attempts insert none; the `LOG` tab lists hide records newest first for the actor's authorized scope.

6. **Scope-aware tab content**: Tabs without a complete v1.1 backing workflow render honest, scope-aware operational states rather than fake actions.
   - Current: `QUEUE`, `USERS`, `SANCTIONS`, and `BOARDS` are placeholder-only and deliberately avoid fake commands.
   - Target: `QUEUE` surfaces oneliner-related moderation items if any exist, otherwise a scoped empty state; `USERS` shows read-only user lookup/list context without mutation actions; `SANCTIONS` states that no sanction workflow is available in v1.1; `BOARDS` shows the actor's authorized scope/board context read-only.
   - Acceptance: TUI tests prove those tabs render without fake approve/ban/sanction/delete commands and that regular users cannot access the workspace content.

7. **No global-only assumptions**: The workspace and domain APIs preserve the `:site | {:board, board_id}` scope contract so future board-scoped moderators can be added without changing the call shapes.
   - Current: v1.1 `scopes_for/2` returns `[:site]` for mods and sysops, but Phase 1 locked the list-shaped return contract for future board scopes.
   - Target: Phase 8 list/filter/action code consumes scopes as a list and handles both `:site` and `{:board, board_id}` shapes without assuming all moderators are globally scoped.
   - Acceptance: Unit tests or focused helper tests cover site-scope and board-scope inputs; no new public API requires a boolean `global_mod?` or hard-codes mod visibility as all-site outside the authorization seam.

## Boundaries

**In scope:**
- Replace Moderation tab placeholders with real scoped content or explicit empty/unavailable states.
- Add actor-aware oneliner hide behavior with required reason and domain-level authorization.
- Ensure hidden oneliners are excluded by the recent-visible listing contract.
- Persist and display a narrow moderation audit log for oneliner hide actions.
- Keep all tab data/action visibility driven by the actor's authorization scopes.
- Preserve the fixed Phase 0 tab set: `QUEUE`, `LOG`, `USERS`, `SANCTIONS`, `BOARDS`.
- Add tests for authorization failure, validation failure, persistence, recent-list exclusion, audit logging, and TUI rendering.

**Out of scope:**
- General report creation/resolution workflows — no report domain exists yet, and `MODR-05` only requires oneliner moderation.
- Full sanctions issuance, lifting, or enforcement — `SANCTIONS` may render an unavailable state, but sanction behavior is not a v1.1 requirement here.
- User promotion/demotion, suspension, deletion, or account editing — the `USERS` tab is read-only context in this phase.
- Thread/post moderation UI or operator actions — this phase keeps visible mutations focused on oneliner hide only.
- Board/category lifecycle management — sysop board management belongs to the Sysop workspace, not the Moderation workspace.
- Real-time push updates to every active main menu after hide — hidden entries must be excluded by the query contract; existing refresh/list behavior can surface the change.
- Board-scoped moderator assignment UI or `board_moderators` schema — future v2 work must fit the scope contract but is not implemented here.

## Constraints

- The domain context function remains the trust boundary: TUI visibility checks are advisory only.
- All hide mutations must call `Bodyguard.permit(Foglet.Authorization, :hide_oneliner, actor, scope)` or equivalent policy enforcement before side effects.
- Scope filtering must consume `Foglet.Authorization.scopes_for/2` as a list and must not assume every moderator is globally scoped.
- Oneliner list/query code must preload author and moderator data needed for TUI rendering; templates must not rely on lazy loads.
- Programmatically set fields such as `hidden_by_id`, moderator id, and audit target ids must not be accepted from untrusted caller attrs.
- Phase 8 must not add fake moderation commands for workflows that are not implemented.

## Acceptance Criteria

- [ ] The Moderation workspace no longer renders Phase 8 placeholder copy in any of the five tabs.
- [ ] Authorized mod/sysop actors can hide a visible oneliner with a non-empty reason.
- [ ] Unauthorized actors receive `{:error, :forbidden}` when attempting to hide an oneliner and no mutation occurs.
- [ ] Blank or whitespace-only hide reasons are rejected and no mutation occurs.
- [ ] Hidden oneliners are excluded from the public recent-visible listing.
- [ ] Every successful oneliner hide creates exactly one narrow `:hide_oneliner` audit record.
- [ ] The `LOG` tab renders oneliner hide audit records newest first within the actor's authorized scope.
- [ ] `QUEUE`, `USERS`, `SANCTIONS`, and `BOARDS` render honest scoped content or empty/unavailable states without fake mutation commands.
- [ ] Regular users and guests cannot access populated Moderation workspace content.
- [ ] Site-scope and board-scope inputs are covered so future board-scoped moderation does not require API shape changes.

## Ambiguity Report

| Dimension          | Score | Min   | Status | Notes |
|--------------------|-------|-------|--------|-------|
| Goal Clarity       | 0.90  | 0.75  | ✓      | Oneliner hide is the required mutation; workspace population supports it. |
| Boundary Clarity   | 0.86  | 0.70  | ✓      | General reports, sanctions, user mutation, thread/post moderation, and board assignment are excluded. |
| Constraint Clarity | 0.78  | 0.65  | ✓      | Domain authorization, required reason, scope list contract, and query-level hiding are locked. |
| Acceptance Criteria| 0.84  | 0.70  | ✓      | Pass/fail checks cover domain, audit, query, scope, and TUI behavior. |
| **Ambiguity**      | 0.16  | ≤0.20 | ✓      | Gate passed after round 2. |

Status: ✓ = met minimum, ⚠ = below minimum (planner treats as assumption)

## Interview Log

| Round | Perspective | Question summary | Decision locked |
|-------|-------------|------------------|-----------------|
| 1 | Researcher | Should all five tabs be fully populated or should the core be oneliner moderation with honest states elsewhere? | Must-ship core is `MODR-05`; replace placeholders with real scoped content where backed by current domains and honest states where no domain exists. |
| 1 | Researcher | Should hiding require a moderator-entered reason? | Yes. Hide requires a non-empty reason so audit/history is useful. |
| 1 | Researcher | Should hidden oneliners disappear immediately from the main-menu strip or only be persisted as hidden? | Hidden entries must be excluded by the recent-visible domain query; Phase 8 does not add real-time push refresh. |
| 2 | Researcher + Simplifier | Does this phase include the moderation audit log? | Yes, narrowly: persist and render audit records for oneliner hide actions only. |
| 2 | Researcher + Simplifier | What does "real data" mean for tabs without backing v1.1 domains? | Render scoped operational states or empty/unavailable states; no fake report/sanction/user mutation behavior. |
| 2 | Researcher + Simplifier | Should thread/post moderation actions be wired now? | No. Visible mutation actions stay focused on oneliner hide because Phase 8 maps only to `MODR-05`. |

---

*Phase: 08-moderation-workspace-population-and-scope-aware-operations*
*Spec created: 2026-04-24*
*Next step: $gsd-discuss-phase 8 — implementation decisions (how to build what's specified above)*
