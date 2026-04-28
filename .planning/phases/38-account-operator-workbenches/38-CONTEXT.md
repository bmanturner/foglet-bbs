# Phase 38: Account & Operator Workbenches - Context

**Gathered:** 2026-04-28 (assumptions mode)
**Status:** Ready for planning

<domain>
## Phase Boundary

Account, Moderation, and Sysop move to screen-owned `init/1`, `update/3`, and
`render/2` flows over screen-local state plus `Foglet.TUI.Context`. This phase
preserves existing account/operator behavior while removing workbench local-flow
ownership from `Foglet.TUI.App`. It does not change durable account, invite,
SSH key, moderation, board, config, or authorization domain behavior; redesign
the workbench UI; add product capabilities; remove unrelated App machinery
owned by Phase 39; or add browser-facing workflows.
</domain>

<spec_lock>
## Specification Lock

`.planning/phases/38-account-operator-workbenches/38-SPEC.md` locks 10
requirements and the phase boundaries. Downstream agents MUST read it before
planning. Do not duplicate or reinterpret the requirements from memory; use the
SPEC as the source of truth for what must be delivered and what remains out of
scope.
</spec_lock>

<decisions>
## Implementation Decisions

### Account Ownership
- **D-01:** `Foglet.TUI.Screens.Account` should keep the existing
  `Account.State`, `ProfileForm`, `PrefsForm`, `SSHKeysState`, and shared
  `InvitesState` shapes as the migration base rather than redesigning Account
  state during this phase.
- **D-02:** Account should expose `init/1`, `update/3`, and `render/2` around
  screen-local state plus `Foglet.TUI.Context`; broad App-shaped state should
  stop being the Account render/key/update input.
- **D-03:** Profile and preference saves should become Account task effects
  whose success/failure results are consumed by `Account.update/3`, reseeding
  forms, status, candidate theme preview, errors, and any needed session
  preference refresh requests locally.
- **D-04:** SSH key and invite loads/mutations should move out of synchronous
  legacy key helpers where domain work occurs and into Account-owned task
  effects/results, while preserving selection, add form, generated code,
  authorization failure, and local error/status behavior.

### Moderation Ownership
- **D-05:** `Foglet.TUI.Screens.Moderation` should keep its current workspace
  snapshot shape, `Moderation.State`, read-only table rows, summaries,
  `ConsoleTable` state, and conditional moderator INVITES state as the local
  reducer base.
- **D-06:** Moderation workspace loading and failure handling should move from
  App `{:load_moderation_workspace}` / `{:moderation_workspace_loaded, ...}`
  clauses into Moderation-owned task effects and `update/3` result handling.
- **D-07:** LOG, USERS, and BOARDS remain read-only table surfaces in this
  phase. Their key handling may update table navigation state, but must not
  emit user, board, sanction, or moderation mutation effects.
- **D-08:** Moderator invite generate/revoke/refresh behavior should be owned
  by Moderation local state and task results when domain work occurs, with
  visibility still controlled by the existing `ShellVisibility` policy.

### Sysop Ownership
- **D-09:** `Foglet.TUI.Screens.Sysop` should keep the existing lifecycle slot
  enum (`:not_loaded`, `:loading`, `{:loaded, sub}`, `{:error, reason}`), tab
  labels, nested submodules, invite state, and `armed_revoke?` semantics as
  the migration base.
- **D-10:** Sysop, not App, should become the writer for lifecycle loading,
  loaded, error, retry, and idempotent re-entry state for BOARDS, LIMITS,
  SYSTEM, and USERS.
- **D-11:** Sysop lifecycle loads/retries should emit `Foglet.TUI.Effect.task/3`
  values and consume results through `Sysop.update/3`; task result op atoms are
  flexible if they are clear, local to Sysop, and testable.
- **D-12:** Nested SITE, LIMITS, BOARDS, SYSTEM, USERS, and INVITES key
  behavior should remain delegated to existing submodules where possible, but
  submodule modal/navigation/domain events should be translated into explicit
  effects rather than direct App mutation.
- **D-13:** SITE may remain synchronous only where it is purely local/read
  behavior. Durable configuration mutations and authorization-sensitive work
  must still stay in the owning context boundary and surface through the
  screen-owned update/effect path.

### App Boundary
- **D-14:** Reuse the existing Phase 34 generic runtime path:
  `Foglet.TUI.Effect.task/3`, `Foglet.TUI.App.apply_effect/2`,
  `{:screen_task_result, screen_key, op, result}`, and
  `route_screen_update/3`. Do not invent a parallel task/result router for
  workbench screens.
- **D-15:** Remove or reduce App clauses and helpers that directly mutate
  Account, Moderation, or Sysop local state: account save helpers, moderation
  workspace load/result handling, sysop lifecycle load/result handling, and
  `put_*` screen-state mutation helpers.
- **D-16:** App remains responsible for generic runtime concerns only: Raxol
  callbacks, modal and SizeGate precedence, route storage, screen-state storage
  helpers, context construction, generic effect interpretation, command
  dispatch, session lifecycle, and PubSub/session forwarding.

### Testing And Preservation
- **D-17:** Migrate Account, Moderation, and Sysop tests toward `init/1` and
  `update/3` reducer/effect assertions over local state, task effects, task
  results, route/context data, and explicit modal/session effects.
- **D-18:** App tests should prove generic task/effect routing and absence of
  workbench-specific App ownership, not reassert the old App mutation paths.
- **D-19:** Preserve role visibility, policy denials, form validation, theme
  preview, preference refresh, SSH key management, invite behavior, moderation
  read-only tables, sysop retry/forbidden behavior, nested submodule key
  handling, modal behavior, keyboard behavior, and canonical render smoke
  checks.
- **D-20:** Avoid brittle tests that only assert text presence. Prefer state,
  effects, task-result handling, domain-result handling, route/context checks,
  and render smoke/layout contracts.

### the agent's Discretion
- Exact reducer message names, task op atoms, and internal helper names are
  flexible if ownership is screen-local and the generic App runtime path is
  preserved.
- The planner may split Account, Moderation, and Sysop into multiple plans, but
  each split must keep terminal behavior stable and avoid introducing a second
  compatibility layer.
- Existing state structs may be expanded incrementally when that is safer than
  converting everything in one pass.

### Folded Todos
None.
</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Locked Phase Scope
- `.planning/phases/38-account-operator-workbenches/38-SPEC.md` - Locked Phase
  38 requirements, boundaries, constraints, and acceptance criteria.
- `.planning/ROADMAP.md` - v2.0 phase sequencing, Phase 38 goal, and dependency
  notes.
- `.planning/PROJECT.md` - SSH-first product boundary and v2.0 milestone
  intent.
- `.planning/REQUIREMENTS.md` - v2.0 screen ownership requirements and Phase
  38 requirement mapping.

### Runtime Foundation And Prior Decisions
- `.planning/phases/34-runtime-contract-effects/34-CONTEXT.md` - Prior locked
  decisions for `Foglet.TUI.Context`, `Foglet.TUI.Effect`, route params,
  task-result routing, and state conventions.
- `.planning/phases/34-runtime-contract-effects/34-SPEC.md` - Phase 34
  foundation requirements that Phase 38 builds on.
- `.planning/phases/35-auth-home-screens/35-CONTEXT.md` - Prior migration
  decisions for screen-owned reducers, App boundary cleanup, modal routing, and
  testing style.
- `.planning/phases/36-board-thread-directory-flow/36-CONTEXT.md` - Prior
  decisions for screen-local loaded data, task effects, App boundary cleanup,
  and temporary compatibility bridge handling.
- `.planning/phases/37-post-composer-flow/37-CONTEXT.md` - Prior decisions for
  richer screen-owned state, route/context-derived identity, task effects, and
  post/composer App boundary cleanup.
- `lib/foglet_bbs/tui/screen.ex` - Screen behavior contract and transitional
  legacy callbacks.
- `lib/foglet_bbs/tui/context.ex` - Narrow screen-facing runtime context.
- `lib/foglet_bbs/tui/effect.ex` - Explicit effect constructors and task
  effect shape.
- `lib/foglet_bbs/tui/app.ex` - App runtime shell, generic effect
  interpretation, route helpers, legacy workbench clauses to migrate away from,
  and task-result routing.

### Account Workbench
- `lib/foglet_bbs/tui/screens/account.ex` - Current Account render/key
  behavior, tab handling, profile/prefs delegation, SSH key actions, invite
  actions, and legacy App-shaped state access.
- `lib/foglet_bbs/tui/screens/account/state.ex` - Existing Account local state
  struct, form seeds, tab visibility, drafts, errors, dirty flags, and theme
  preview state.
- `lib/foglet_bbs/tui/screens/account/profile_form.ex` - Current profile form
  key handling and save command emission.
- `lib/foglet_bbs/tui/screens/account/prefs_form.ex` - Current preferences
  form key handling, preview behavior, and save command emission.
- `lib/foglet_bbs/tui/screens/account/ssh_keys_state.ex` - SSH key list/add
  local state.
- `lib/foglet_bbs/tui/screens/account/ssh_keys_actions.ex` - Current SSH key
  domain calls to move behind Account-owned task effects.
- `lib/foglet_bbs/tui/screens/shared/invites_state.ex` - Shared invite surface
  state used by Account, Moderation, and Sysop.
- `lib/foglet_bbs/tui/screens/shared/invites_actions.ex` - Current invite
  domain calls to move behind owning screen task effects where domain work
  occurs.
- `lib/foglet_bbs/tui/screens/shell_visibility.ex` - Account/operator
  visibility and invite-tab policy checks.

### Moderation Workbench
- `lib/foglet_bbs/tui/screens/moderation.ex` - Current Moderation render/key
  behavior, table handling, invite handling, and legacy App-shaped state access.
- `lib/foglet_bbs/tui/screens/moderation/state.ex` - Existing Moderation local
  state, workspace rows, summaries, and read-only table builders.
- `lib/foglet_bbs/moderation.ex` - Workspace snapshot domain boundary and
  moderation visibility data source.

### Sysop Workbench
- `lib/foglet_bbs/tui/screens/sysop.ex` - Current Sysop render/key behavior,
  lifecycle dispatch tuples, nested submodule delegation, retry behavior,
  invite revoke arming, and direct modal mutation to replace with effects.
- `lib/foglet_bbs/tui/screens/sysop/state.ex` - Existing Sysop local state,
  lifecycle slots, tab labels, invite state, and revoke arming flag.
- `lib/foglet_bbs/tui/screens/sysop/site_form.ex` - SITE form behavior and
  configuration interaction.
- `lib/foglet_bbs/tui/screens/sysop/limits_form.ex` - LIMITS form behavior and
  configuration mutation path.
- `lib/foglet_bbs/tui/screens/sysop/boards_view.ex` - BOARDS subview behavior.
- `lib/foglet_bbs/tui/screens/sysop/system_snapshot.ex` - SYSTEM subview
  behavior.
- `lib/foglet_bbs/tui/screens/sysop/users_view.ex` - USERS subview behavior and
  user status administration events.

### Domain APIs
- `lib/foglet_bbs/accounts.ex` - Profile, preferences, SSH key, and user status
  administration APIs.
- `lib/foglet_bbs/accounts/invites.ex` - Invite list/create/revoke APIs and
  authorization outcomes.
- `lib/foglet_bbs/config.ex` - Runtime config read/write API and actor-aware
  `put/3` behavior.
- `lib/foglet_bbs/authorization.ex` - Context-level policy enforcement and
  operator scopes.

### Tests And Codebase Maps
- `test/foglet_bbs/tui/screens/account_test.exs` - Existing Account behavior,
  profile/prefs, SSH key, invite, and render coverage to migrate to reducer/
  effect assertions where needed.
- `test/foglet_bbs/tui/screens/moderation_test.exs` - Existing Moderation
  workspace, read-only table, invite, role visibility, and render coverage.
- `test/foglet_bbs/tui/screens/sysop_test.exs` - Existing Sysop lifecycle,
  retry, nested subview, invite, role visibility, and render coverage.
- `test/foglet_bbs/tui/screens/sysop/site_form_test.exs` - SITE form behavior.
- `test/foglet_bbs/tui/screens/sysop/config_accountability_test.exs` -
  Configuration accountability coverage.
- `test/foglet_bbs/tui/app_runtime_contract_test.exs` - Generic route,
  context, effect, and task-result routing proof.
- `test/foglet_bbs/tui/app_test.exs` - Existing App runtime and legacy
  workbench assertions to update.
- `test/foglet_bbs/tui/layout_smoke_test.exs` - Canonical TUI render smoke
  harness.
- `.planning/codebase/CONVENTIONS.md` - Elixir module, state, docs, specs, and
  precommit conventions.
- `.planning/codebase/STRUCTURE.md` - Source/test layout and state-module
  placement conventions.
- `.planning/codebase/TESTING.md` - ExUnit, TUI, OTP, and render smoke testing
  patterns.
</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `Foglet.TUI.Screen` already defines the target `init/1`, `update/3`, and
  `render/2` callbacks while retaining transitional legacy callbacks.
- `Foglet.TUI.Context` already exposes current user, session context,
  terminal size, route params, and domain overrides without App screen storage.
- `Foglet.TUI.Effect.task/3` and `Foglet.TUI.App.apply_effect/2` already route
  task success/failure into `{:screen_task_result, screen_key, op, result}`.
- `Foglet.TUI.App` already has generic helpers for route lookup, screen-state
  storage, context construction, effect interpretation, and routed screen
  updates.
- Account, Moderation, and Sysop already have first-class state structs, so the
  phase should expand/adapt them rather than inventing new state storage.
- Shared `InvitesState`/`InvitesActions` and Account `SSHKeysState`/
  `SSHKeysActions` provide reusable local-state transitions, but durable
  operations currently happen synchronously and need screen-owned task routing.

### Established Patterns
- New-contract screens receive local state plus `Foglet.TUI.Context`; they do
  not receive `%Foglet.TUI.App{}` for local decisions.
- Domain side effects stay in contexts (`Foglet.Accounts`,
  `Foglet.Accounts.Invites`, `Foglet.Config`, `Foglet.Moderation`) and are
  requested from screens through task effects.
- App owns runtime concerns, not screen-local loaded data, drafts, validation
  state, lifecycle slots, retry state, invite state, or task-result outcomes.
- TUI tests mirror source paths and should assert reducer state/effects, task
  results, route/context data, and render smoke contracts before relying on
  render text.
- Existing workbench visible behavior is preservation work, not redesign.

### Integration Points
- `lib/foglet_bbs/tui/app.ex` currently contains the Phase 38 local-flow
  handlers to remove or reduce: `{:account_save_profile, _}`,
  `{:account_save_prefs, _}`, `{:load_moderation_workspace}`,
  `{:moderation_workspace_loaded, _}`, `{:load_sysop_users}`,
  `{:load_sysop_boards}`, `{:load_sysop_limits}`, `{:load_sysop_system}`,
  and `{:sysop_*_loaded, _}`.
- `App.route_screen_update/3` is the generic hook for migrated screens to
  receive key/task/update messages.
- `App.init_route_screen_state/3`, `App.context_for_screen_key/2`, and
  `App.apply_effects/2` are the runtime helpers planners should reuse rather
  than inventing parallel dispatch.
- Account preference saves may still require an explicit session preference
  refresh effect so runtime theme/time behavior remains immediate after a save.
- Sysop submodule `{:error_modal, message, destination}` events currently
  mutate App modal/current_screen directly from `Sysop.handle_key/2`; Phase 38
  should translate these into modal/navigation effects.
</code_context>

<specifics>
## Specific Ideas

- User confirmed the assumptions-mode pass without corrections.
- No visual redesign, new workbench capability, domain behavior change, or
  browser workflow was added during discussion.
- No external research is required; the relevant runtime behavior is local in
  Phase 34-37 artifacts and the Foglet codebase.
</specifics>

<deferred>
## Deferred Ideas

None - analysis stayed within phase scope.
</deferred>

---

*Phase: 38-account-operator-workbenches*
*Context gathered: 2026-04-28*
