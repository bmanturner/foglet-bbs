# Phase 38: Account & Operator Workbenches - Specification

**Created:** 2026-04-28
**Ambiguity score:** 0.16 (gate: <= 0.20)
**Requirements:** 10 locked

## Goal

Account, Moderation, and Sysop own their tab state, local forms, workspace data, lifecycle loads, mutations, async results, retries, and navigation decisions through the Phase 34 screen update-loop contract, without App-level account/operator workbench ownership.

## Background

Phase 34 added `Foglet.TUI.Screen.init/1`, `update/3`, and `render/2`, `Foglet.TUI.Context`, and explicit `Foglet.TUI.Effect` values. Phases 35 and 36 migrated auth/home and board/thread screens. Phase 37 specifies post/composer migration before this phase, leaving Account, Moderation, and Sysop as the densest remaining workbench screens before Phase 39 removes central App machinery.

The current Account screen has a first-class `Account.State` with PROFILE, PREFS, SSH KEYS, and conditional INVITES tabs. It still uses the legacy `render/1` and `handle_key/2` path with broad App-shaped state. PROFILE/PREFS submit commands are interpreted by App through `save_account/3`, `clear_account_save_state/2`, and `put_account_errors/3`, which mutate `screen_state[:account]`, `current_user`, session preferences, and session runtime state. SSH key and invite actions run synchronously through screen helper modules.

The current Moderation screen has a first-class `Moderation.State` with queue/log/users/sanctions/boards data, ConsoleTable state, summaries, loading/error flags, and conditional moderator invites. App still owns `{:load_moderation_workspace}` and `{:moderation_workspace_loaded, result}` clauses that write moderation snapshot/error state. Tab-local table navigation and invite actions are handled inside legacy screen key handlers.

The current Sysop screen has a first-class `Sysop.State` with SITE, BOARDS, LIMITS, SYSTEM, USERS, and conditional INVITES tabs. SITE remains synchronous today, while BOARDS/LIMITS/SYSTEM/USERS are lifecycle slots with `:not_loaded`, `:loading`, `{:loaded, sub}`, and `{:error, reason}` states. App owns the `{:load_sysop_*}` dispatch clauses, `{:sysop_*_loaded, result}` result clauses, and `put_sysop_loading|loaded|error` helpers. Sysop also owns nested subviews/forms, retry behavior, invite revoke arming, and modal error routing through legacy `handle_key/2`.

## Requirements

1. **Account contract migration**: `Foglet.TUI.Screens.Account` initializes, updates, and renders through screen-local state plus `Foglet.TUI.Context`.
   - Current: Account exposes `init_screen_state/1`, legacy `handle_key/2`, and legacy `render/1`, reading broad App fields such as `current_user`, `session_context`, `screen_state`, and `terminal_size`.
   - Target: Account exposes `init/1`, `update/3`, and `render/2`; local state stores tabs, active tab, profile/prefs forms, dirty flags, errors, status message, candidate theme preview, SSH key state, and invite state.
   - Acceptance: Reducer tests initialize Account from context, switch tabs, render from `Account.State` and `Context`, and update local PROFILE/PREFS/SSH KEYS/INVITES state without requiring an App-shaped struct.

2. **Account save ownership**: Account owns profile and preference save request/result handling through task effects and screen update logic.
   - Current: Profile and prefs forms emit `{:account_save_profile, attrs}` and `{:account_save_prefs, attrs}`; App calls `Accounts.update_profile/2`, mutates `current_user`, refreshes session preferences, reseeds Account state, and writes form errors.
   - Target: Account emits task effects for profile and preference saves, receives success/failure results through `update/3`, updates status/errors/forms locally, and requests any needed session preference refresh through explicit effects.
   - Acceptance: Tests prove successful profile save reseeds profile fields and status, successful prefs save clears candidate theme preview and requests session preference refresh, changeset errors attach to the correct form fields, and missing-user failures remain local Account errors without App account-save clauses.

3. **Account SSH key and invite ownership**: Account owns SSH key loading/actions and invite loading/actions through screen update logic.
   - Current: Account calls `SSHKeysActions.load/2`, `SSHKeysActions.handle_key/3`, `InvitesActions.load/2`, and `InvitesActions.handle_key/3` synchronously from legacy key handlers.
   - Target: Account requests SSH key and invite loads/mutations through task effects where domain work is involved, consumes success/failure locally, and keeps selection, form, last-generated code, and error state in `Account.State`.
   - Acceptance: Tests prove first entry to SSH KEYS requests key loading, key registration/revoke results update only Account local state, INVITES visibility follows `ShellVisibility.invites_visible?/2`, invite generate/revoke/refresh results update only Account invite state, and unauthorized/failed actions surface local errors.

4. **Moderation contract migration**: `Foglet.TUI.Screens.Moderation` owns workspace state, tab state, table state, invite state, and render input through the new update-loop contract.
   - Current: Moderation exposes `init_screen_state/1`, legacy `handle_key/2`, and legacy `render/1`; App loads and stores workspace snapshots/errors in `screen_state[:moderation]`.
   - Target: Moderation exposes `init/1`, `update/3`, and `render/2`; its local state stores loading/error status, scopes, queue/log/users/boards rows, ConsoleTable state, summaries, conditional invites tab state, and active tab.
   - Acceptance: Reducer tests initialize Moderation, request workspace loading, consume successful and failed workspace loads, preserve tab-local ConsoleTable navigation, render unauthorized state defensively from context, and operate without App `{:moderation_workspace_loaded, ...}` mutation clauses.

5. **Moderation invite and read-only boundary**: Moderation preserves read-only operator tables while owning conditional moderator invite behavior.
   - Current: LOG, USERS, and BOARDS table navigation is local, read-only, and selectable false; moderator INVITES actions are synchronous helper calls from the screen.
   - Target: Moderation keeps queue/log/users/sanctions/boards read-only, routes moderator invite domain actions through task effects where applicable, and stores all invite result/error state locally.
   - Acceptance: Tests prove LOG/USERS/BOARDS table key handling changes only table navigation state, no moderation tab emits user/board mutation effects, INVITES appears only for moderator-visible invite policy, and invite generate/revoke/refresh results update only Moderation state.

6. **Sysop contract migration**: `Foglet.TUI.Screens.Sysop` owns tab lifecycle, nested subview state, retry behavior, invite revoke arming, modal requests, and render input through the new update-loop contract.
   - Current: Sysop exposes `init_screen_state/1`, legacy `handle_key/2`, and legacy `render/1`; App owns lifecycle load/result clauses and slot mutation for BOARDS, LIMITS, SYSTEM, and USERS.
   - Target: Sysop exposes `init/1`, `update/3`, and `render/2`; its local state stores active tab, dynamic tab labels, SITE form, lifecycle slots, loaded subviews, invite state, and `armed_revoke?`.
   - Acceptance: Reducer tests initialize Sysop from context, switch tabs, request first lifecycle loads, consume loaded/error results, render forbidden and retry states, preserve invite revoke arming semantics, and operate without App `put_sysop_loading|loaded|error` helpers.

7. **Sysop lifecycle task ownership**: Sysop owns BOARDS, LIMITS, SYSTEM, and USERS load dispatch/results through task effects.
   - Current: Sysop emits tuples such as `{:load_sysop_users}`; App builds tasks, flips slots to loading, calls domain/subview builders, and handles `{:sysop_*_loaded, result}`.
   - Target: Sysop emits task effects for lifecycle loads and retries, flips the target slot to `:loading` in screen update logic, receives task results through `update/3`, and writes `{:loaded, sub}` or `{:error, reason}` locally.
   - Acceptance: Tests prove each lifecycle tab requests exactly one initial load when entering from `:not_loaded`, re-entering loaded/loading/error tabs is idempotent, retry is available only for non-forbidden errors, forbidden errors suppress retry, and task results for users/boards/limits/system update only the matching local slot.

8. **Sysop nested forms and subviews**: Sysop preserves nested SITE, LIMITS, BOARDS, SYSTEM, USERS, and INVITES behavior while moving ownership behind the screen boundary.
   - Current: SITE and loaded lifecycle submodules handle keys inside Sysop legacy key delegation; error-modal events mutate App modal/current_screen directly; invites revoke uses a two-step Enter then X gesture in Sysop state.
   - Target: Sysop delegates keys to loaded submodules from `update/3`, translates submodule events into explicit modal/navigation/task effects, keeps SITE local form behavior intact, and keeps INVITES generate/revoke/refresh result handling local.
   - Acceptance: Tests prove SITE and LIMITS form edits/submits still validate through their submodules, submodule error-modal events become modal effects rather than direct App mutation, USERS key behavior remains available on loaded USERS, invite Enter/X revoke behavior remains one-shot and row-bound, and tab switches clear stale revoke arming.

9. **App workbench ownership removal**: App no longer owns Account, Moderation, or Sysop local-flow clauses or state mutation.
   - Current: App contains account save helpers, moderation workspace load/result clauses, sysop lifecycle load/result clauses, and helpers that mutate `screen_state[:account]`, `screen_state[:moderation]`, and `screen_state[:sysop]`.
   - Target: Account, Moderation, and Sysop work routes through generic screen update/effect/task handling. Any App involvement is limited to generic runtime interpretation, modal/SizeGate precedence, route storage, PubSub/session hooks, task execution, and session preference refresh effects.
   - Acceptance: A code-level check or App test proves App no longer handles `:account_save_profile`, `:account_save_prefs`, `:load_moderation_workspace`, `:moderation_workspace_loaded`, `:load_sysop_users`, `:load_sysop_boards`, `:load_sysop_limits`, `:load_sysop_system`, or `:sysop_*_loaded` by mutating account/operator screen state directly.

10. **Feature parity and focused verification**: Existing account/operator behavior remains stable while ownership moves.
    - Current: Account, Moderation, Sysop, sysop subforms, invite surfaces, SSH key surfaces, ConsoleTable, and render smoke paths have coverage split across screen tests, App tests, widget tests, and submodule tests.
    - Target: Equivalent coverage asserts screen-local state and effects instead of App top-level mutation; render smoke checks still pass for account/operator screens; module docs describe the new ownership boundary.
    - Acceptance: Targeted Account/Moderation/Sysop reducer tests, relevant App generic-runtime tests, sysop nested form tests, SSH key/invite behavior tests, and canonical render smoke checks pass without tests that merely assert incidental text presence.

## Boundaries

**In scope:**
- Migrate Account PROFILE/PREFS forms, candidate theme preview, form errors, save statuses, SSH key state/actions, invite state/actions, tab state, and Back navigation into Account `init/update/render`.
- Migrate Moderation workspace loading/results, scope rows, moderation log/users/boards rows, read-only table state, summaries, conditional moderator invites, tab state, and Back navigation into Moderation `init/update/render`.
- Migrate Sysop lifecycle slot loading/results, retries, SITE form, BOARDS/LIMITS/SYSTEM/USERS loaded subviews, nested form/subview events, conditional sysop invites, revoke arming, tab state, and Back navigation into Sysop `init/update/render`.
- Route account/operator domain work through task effects and return results through the requesting screen update logic where practical.
- Replace App account/operator result and state-mutating clauses with generic effect/task interpretation.
- Preserve existing terminal behavior, keyboard behavior, role visibility checks, form validation, theme preview, session preference refresh, invite generation/revoke behavior, SSH key management, retry semantics, modal behavior, and render contracts.
- Update focused reducer/effect tests and relevant App runtime tests to assert screen-owned state and generic runtime behavior.
- Update module docs or state docs that currently describe App as the account/operator owner.

**Out of scope:**
- Changing durable account, invite, SSH key, board, config, moderation, or authorization domain behavior - context modules remain authoritative.
- Adding new Account, Moderation, or Sysop product capabilities - this phase is an ownership/runtime migration.
- Making moderation USERS/BOARDS tabs mutate users or boards - they remain read-only in this phase.
- Visual redesign of account/operator screens, widgets, tables, chrome, or forms - render contracts should remain stable except for minimal ownership adaptation.
- Removing unrelated App machinery for screens already migrated in earlier phases - Phase 39 owns final App shell simplification.
- Introducing browser-facing account/operator workflows - Foglet remains SSH/TUI-first.
- Replacing Raxol or moving screens into per-screen processes - App/Raxol remains the runtime process owner.

## Constraints

- The primary product surface remains SSH/TUI; no end-user Phoenix browser flow is introduced.
- Screens must use the Phase 34 screen contract: `init/1`, `update/3`, `render/2`, screen-local state, and `Foglet.TUI.Context`, not broad App-shaped state for local flow ownership.
- Domain side effects remain in `Foglet.Accounts`, `Foglet.Accounts.Invites`, `Foglet.Config`, `Foglet.Authorization`, moderation/domain context modules, and related boundary modules.
- Mutations must still pass context-level authorization; hidden tabs or disabled keys are never authorization.
- Async domain work must use the Phase 34 task-effect path through `Foglet.TUI.Command.task/2` or an equivalent generic effect interpreted by App.
- Task success/failure for migrated workbench flows must return through the requesting screen's `update/3`.
- Modal precedence, SizeGate behavior, route storage, session lifecycle, and generic effect interpretation remain App/runtime responsibilities.
- Session preference refresh after Account preference saves must remain at least as immediate as the current `Session.update_preferences/2` behavior.
- Existing render contracts should remain stable except where minimal adaptation is required by the ownership migration.
- `mix precommit` remains the finish-line check for code changes after this phase is implemented.

## Acceptance Criteria

- [ ] Account can be initialized, updated, and rendered through `init/1`, `update/3`, and `render/2` with tabs, profile/prefs forms, dirty flags, form errors, status message, candidate theme preview, SSH key state, and invite state stored locally.
- [ ] Account handles profile save success/error, preference save success/error, session preference refresh requests, theme preview cancellation, SSH key load/register/revoke results, invite load/generate/revoke results, tab visibility, and Back navigation without App account-save state mutation.
- [ ] Moderation can be initialized, updated, and rendered through `init/1`, `update/3`, and `render/2` with workspace loading/error state, scopes, queue/log/users/boards rows, table state, summaries, conditional invite state, and active tab stored locally.
- [ ] Moderation handles workspace load success/failure, read-only table navigation, conditional moderator invite actions, unauthorized render state, and Back navigation without App moderation workspace mutation clauses.
- [ ] Sysop can be initialized, updated, and rendered through `init/1`, `update/3`, and `render/2` with tab labels, active tab, SITE form, BOARDS/LIMITS/SYSTEM/USERS lifecycle slots, loaded subviews, invite state, and revoke arming stored locally.
- [ ] Sysop handles lifecycle load success/failure, retry dispatch, forbidden retry suppression, nested subview key delegation, submodule modal events, invite Enter/X revoke arming, tab switch clearing, and Back navigation without App sysop lifecycle state mutation clauses.
- [ ] App workbench-specific clauses and helpers are removed or reduced to generic effect/task/session/modal interpretation that does not mutate Account, Moderation, or Sysop local state directly.
- [ ] Existing role visibility, authorization-denial, validation-error, invite, SSH key, theme preview, session preference refresh, retry, modal, keyboard, and render smoke behavior remains covered.
- [ ] Targeted Account/Moderation/Sysop reducer tests, relevant App generic-runtime tests, nested sysop form/subview tests, SSH key/invite tests, and canonical account/operator render smoke checks pass.
- [ ] Target screen docs and state modules describe the screen-owned ownership boundary.

## Ambiguity Report

| Dimension           | Score | Min   | Status | Notes |
|---------------------|-------|-------|--------|-------|
| Goal Clarity        | 0.91  | 0.75  | met    | Full migration of Account, Moderation, and Sysop is locked. |
| Boundary Clarity    | 0.82  | 0.70  | met    | App workbench ownership removal is required; Phase 39 shell cleanup and product changes are excluded. |
| Constraint Clarity  | 0.78  | 0.65  | met    | Phase 34 contract, SSH/TUI surface, context authorization, task effects, and session preference refresh are locked. |
| Acceptance Criteria | 0.78  | 0.70  | met    | Pass/fail reducer ownership, task/result routing, App clause removal, nested subview behavior, and parity checks are specified. |
| **Ambiguity**       | 0.16  | <=0.20| met    | Gate passed after round 1. |

Status: met = meets minimum, below = below minimum (planner treats as assumption)

## Interview Log

| Round | Perspective | Question summary | Decision locked |
|-------|-------------|------------------|-----------------|
| 1 | Researcher | What is the locked core deliverable for Phase 38? | Full workbench migration: Account, Moderation, and Sysop all expose init/update/render and own local state, tab state, form state, async results, and navigation effects. |
| 1 | Researcher | How strict should this phase be about domain actions currently called synchronously from screens? | Move mutations to task effects where practical, including profile/prefs saves, SSH key actions, invite generate/revoke, and Sysop loaded tab work. |
| 1 | Researcher | What should count as unacceptable App ownership after this phase? | App may interpret generic effects, but must not own account, moderation, or sysop loaded-result/local-state mutation clauses. |
| 1 | Gate | Ambiguity score reached 0.16. Proceed? | User selected "Yes, write SPEC.md". |

---

*Phase: 38-account-operator-workbenches*
*Spec created: 2026-04-28*
*Next step: $gsd-discuss-phase 38 - implementation decisions (how to build what's specified above)*
