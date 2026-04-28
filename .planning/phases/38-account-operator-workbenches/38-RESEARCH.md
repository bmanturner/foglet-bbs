# Phase 38: Account & Operator Workbenches - Research

**Researched:** 2026-04-28
**Domain:** Elixir/Raxol TUI reducer/effect ownership migration
**Confidence:** HIGH

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions

#### Account Ownership
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

#### Moderation Ownership
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

#### Sysop Ownership
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

#### App Boundary
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

#### Testing And Preservation
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

### Deferred Ideas (OUT OF SCOPE)
None - analysis stayed within phase scope.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| SCREEN-05 | Account owns profile, preferences, SSH keys, invite tab state, save results, local theme preview, and form errors through the update loop. | Use `Account.State`, `ProfileForm`, `PrefsForm`, `SSHKeysState`, `InvitesState`, `Effect.task/3`, and Account-local task result handlers. [VERIFIED: .planning/REQUIREMENTS.md; lib/foglet_bbs/tui/screens/account/state.ex; lib/foglet_bbs/tui/effect.ex] |
| SCREEN-06 | Moderation and Sysop own tab lifecycle loading, retry behavior, nested state, invites behavior, and loaded/error results through the update loop. | Move App moderation/sysop result clauses into `Moderation.update/3` and `Sysop.update/3`, preserving lifecycle tags and read-only table boundaries. [VERIFIED: .planning/REQUIREMENTS.md; lib/foglet_bbs/tui/screens/moderation/state.ex; lib/foglet_bbs/tui/screens/sysop/state.ex; lib/foglet_bbs/tui/app.ex] |
| APP-02 | App no longer has screen-specific loaded-result clauses after migration. | Remove account save, moderation workspace, and sysop lifecycle result ownership while keeping `{:screen_task_result, key, op, result}` routing. [VERIFIED: .planning/REQUIREMENTS.md; lib/foglet_bbs/tui/app.ex] |
| VERIFY-02 | Screen reducer tests prove key handling, task result handling, and effect emission. | Existing `BoardListTest` and `AppRuntimeContractTest` provide the local testing pattern for this phase. [VERIFIED: test/foglet_bbs/tui/screens/board_list_test.exs; test/foglet_bbs/tui/app_runtime_contract_test.exs] |
</phase_requirements>

## Summary

Phase 38 is an ownership migration inside the existing SSH/TUI architecture, not a stack selection or UI redesign. [VERIFIED: .planning/phases/38-account-operator-workbenches/38-SPEC.md; AGENTS.md] The standard implementation pattern is already in the codebase: screens receive `Foglet.TUI.Context`, own first-class local state, emit `Foglet.TUI.Effect` values, and consume task results through `update/3`; `Foglet.TUI.App` routes messages and interprets effects generically. [VERIFIED: lib/foglet_bbs/tui/screen.ex; lib/foglet_bbs/tui/context.ex; lib/foglet_bbs/tui/effect.ex; lib/foglet_bbs/tui/app.ex]

The risky work is not inventing architecture; it is preserving dense workbench behavior while removing legacy App writers. [VERIFIED: .planning/phases/38-account-operator-workbenches/38-CONTEXT.md; lib/foglet_bbs/tui/app.ex] Account has synchronous SSH/invite helpers and App-owned profile/prefs persistence; Moderation has App-owned workspace loads; Sysop has App-owned lifecycle slot mutation plus nested submodule events that currently write modal/current_screen directly. [VERIFIED: lib/foglet_bbs/tui/screens/account.ex; lib/foglet_bbs/tui/screens/shared/invites_actions.ex; lib/foglet_bbs/tui/screens/account/ssh_keys_actions.ex; lib/foglet_bbs/tui/screens/moderation.ex; lib/foglet_bbs/tui/screens/sysop.ex; lib/foglet_bbs/tui/app.ex]

**Primary recommendation:** Use the Phase 34 reducer/effect runtime exactly as-is; add no libraries; migrate Account, Moderation, and Sysop by moving domain work behind screen-owned `Effect.task/3` calls and task-result clauses, while preserving current state structs and submodule state-transition helpers. [VERIFIED: .planning/phases/38-account-operator-workbenches/38-CONTEXT.md; lib/foglet_bbs/tui/effect.ex; test/foglet_bbs/tui/app_runtime_contract_test.exs]

## Project Constraints (from AGENTS.md)

- Foglet BBS is SSH-first; do not add end-user browser workflows for this phase. [VERIFIED: AGENTS.md]
- Use `rtk` as the shell command prefix in this repository. [VERIFIED: AGENTS.md]
- Keep domain workflows in `Foglet.*` contexts, not Phoenix controllers, SSH callbacks, or TUI render functions. [VERIFIED: AGENTS.md]
- Use context modules as public boundaries; contexts own transactions, authorization checks, preload choices, PubSub side effects, and cross-schema invariants. [VERIFIED: AGENTS.md]
- Use `Bodyguard.permit/4` before domain side effects; hidden or disabled UI is never authorization. [VERIFIED: AGENTS.md]
- Keep `Foglet.TUI.App` responsible for global runtime concerns, and keep screen-local state/key handling in screens or sibling state modules. [VERIFIED: AGENTS.md]
- Route colors through `Foglet.TUI.Theme`, pass theme explicitly, and keep render functions pure over already-loaded state. [VERIFIED: AGENTS.md]
- For TUI work, use `Foglet.TUI.Command`/Raxol commands for off-process work and widgets for reusable display. [VERIFIED: AGENTS.md]
- Do not write tests that merely assert incidental text presence; prefer state/effect/domain-result/layout contracts. [VERIFIED: AGENTS.md]
- Use `start_supervised!/1`, avoid `Process.sleep/1` and `Process.alive?/1`, and run `mix precommit` when code changes are complete. [VERIFIED: AGENTS.md]

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|--------------|----------------|-----------|
| Workbench tab/form/table local state | TUI Screen | Widgets | Account, Moderation, and Sysop already have first-class state structs; widgets own only widget-local interaction state such as `Tabs` and `ConsoleTable`. [VERIFIED: lib/foglet_bbs/tui/screens/account/state.ex; lib/foglet_bbs/tui/screens/moderation/state.ex; lib/foglet_bbs/tui/screens/sysop/state.ex; lib/foglet_bbs/tui/widgets/README.md] |
| Async domain work dispatch | TUI Screen | App runtime | Screens should emit `Effect.task/3`; App should convert tasks into `Foglet.TUI.Command.task/2` and route `screen_task_result` back. [VERIFIED: lib/foglet_bbs/tui/effect.ex; lib/foglet_bbs/tui/app.ex] |
| Durable account/config/moderation changes | Domain Contexts | Database | Accounts, Invites, Config, and Moderation modules own persistence and authorization; screens only request work. [VERIFIED: AGENTS.md; lib/foglet_bbs/accounts.ex; lib/foglet_bbs/accounts/invites.ex; lib/foglet_bbs/config.ex; lib/foglet_bbs/moderation.ex] |
| Modal precedence and runtime routing | App runtime | TUI Screen | App owns modal/SizeGate precedence; screens request modal effects and do not mutate App modal/current_screen directly after migration. [VERIFIED: AGENTS.md; lib/foglet_bbs/tui/app.ex; .planning/phases/38-account-operator-workbenches/38-CONTEXT.md] |
| Role visibility and access control | Domain/Authorization | TUI advisory rendering | Shell visibility controls tabs/menu affordances, but context/domain authorization must remain authoritative for mutations. [VERIFIED: AGENTS.md; lib/foglet_bbs/tui/screens/shell_visibility.ex; lib/foglet_bbs/authorization.ex] |

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Elixir / Mix | 1.19.5 available, project requires `~> 1.17` | Runtime, compiler, tests, build aliases | Existing project toolchain and `mix precommit` pipeline. [VERIFIED: rtk elixir --version; rtk mix --version; mix.exs] |
| Raxol | vendored path dependency; lock includes Raxol packages 2.4.0 | Terminal UI runtime and View DSL | Existing TUI framework; replacing it is out of scope. [VERIFIED: mix.exs; mix.lock; .planning/REQUIREMENTS.md] |
| Foglet.TUI.Screen / Context / Effect | local modules | Screen contract, narrow context, explicit effects | Phase 34 runtime foundation already used by migrated screens. [VERIFIED: lib/foglet_bbs/tui/screen.ex; lib/foglet_bbs/tui/context.ex; lib/foglet_bbs/tui/effect.ex] |
| Foglet.TUI.Command | local module over `Raxol.Core.Runtime.Command.task/1` | Off-process task execution with error wrapping | Existing App `Effect.task` interpreter uses this wrapper for screen task results. [VERIFIED: lib/foglet_bbs/tui/command.ex; lib/foglet_bbs/tui/app.ex; vendor/raxol/lib/raxol/core/runtime/command.ex] |
| Phoenix PubSub / App runtime | Phoenix 1.8.5, Phoenix PubSub transitive | Runtime messaging, subscriptions, app shell | App remains runtime infrastructure and not product web UI. [VERIFIED: mix.lock; AGENTS.md; lib/foglet_bbs/tui/app.ex] |
| Ecto SQL / Postgrex | Ecto SQL 3.13.5, Postgrex 0.22.0 | Durable state through contexts | Domain contexts and Repo remain authoritative for persistence. [VERIFIED: mix.lock; AGENTS.md] |
| Bodyguard | 2.4.3 | Authorization policy checks | Existing `Foglet.Authorization` implements Bodyguard policy. [VERIFIED: mix.lock; AGENTS.md; lib/foglet_bbs/authorization.ex] |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| ExUnit | built into Elixir 1.19.5 | Reducer, App runtime, screen, and submodule tests | Use for all Phase 38 focused tests. [VERIFIED: rtk mix --version; .planning/codebase/TESTING.md] |
| StreamData | 1.3.0 | Property tests | Existing project dependency, but not needed for this ownership migration unless a table/index invariant emerges. [VERIFIED: mix.lock; .planning/codebase/TESTING.md] |
| Credo / Sobelow / Dialyxir | Credo 1.7.18, Sobelow 0.14.1, Dialyxir 1.4.7 | Precommit quality gates | `mix precommit` runs them after code changes. [VERIFIED: mix.lock; mix.exs; AGENTS.md] |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Existing `Effect.task/3` + `screen_task_result` | A custom workbench task router | Rejected by locked D-14; it would duplicate App runtime plumbing. [VERIFIED: .planning/phases/38-account-operator-workbenches/38-CONTEXT.md] |
| Existing state structs | New generic workbench state abstraction | Rejected by locked D-01/D-05/D-09; current state structs encode tab, table, lifecycle, invite, and form semantics. [VERIFIED: .planning/phases/38-account-operator-workbenches/38-CONTEXT.md; lib/foglet_bbs/tui/screens/account/state.ex; lib/foglet_bbs/tui/screens/moderation/state.ex; lib/foglet_bbs/tui/screens/sysop/state.ex] |
| ExUnit focused reducer tests | Browser/LiveView tests | Rejected by SSH-first product boundary and no browser workflow scope. [VERIFIED: AGENTS.md; .planning/phases/38-account-operator-workbenches/38-SPEC.md] |

**Installation:**
```bash
# No new packages. Use the existing Mix dependencies and vendored Raxol path dependency.
rtk mix deps.get
```

**Version verification:** Versions above were verified from local tool output and `mix.lock`; no registry lookup was needed because this phase adds no dependencies. [VERIFIED: rtk elixir --version; rtk mix --version; mix.lock]

## Architecture Patterns

### System Architecture Diagram

```text
SSH key/input or task result
        |
        v
Foglet.TUI.App.update/2
  - SizeGate/modal precedence
  - current route lookup
        |
        v
route_screen_update(screen_key, message)
        |
        v
Account.update/3 | Moderation.update/3 | Sysop.update/3
  - mutate only local State struct
  - call widget/state helper transitions
  - emit Effect.task / Effect.navigate / Effect.open_modal / Effect.session
        |
        v
Foglet.TUI.App.apply_effects/2
  - task -> Foglet.TUI.Command.task/2
  - modal/session/navigation -> generic runtime handling
        |
        v
Domain contexts inside task closures
  Foglet.Accounts | Accounts.Invites | Foglet.Config | Foglet.Moderation
        |
        v
{:screen_task_result, screen_key, op, {:ok | :error, result}}
        |
        v
same screen update/3 consumes result and stores loaded/error/success state
```

This data flow is implemented for migrated screens and tested by the generic runtime contract test. [VERIFIED: lib/foglet_bbs/tui/app.ex; test/foglet_bbs/tui/app_runtime_contract_test.exs; lib/foglet_bbs/tui/screens/board_list.ex]

### Recommended Project Structure

```text
lib/foglet_bbs/tui/screens/
├── account.ex                 # init/update/render and Account-owned effects/results
├── account/state.ex           # existing local state expanded only as needed
├── account/profile_form.ex    # keep field transitions and submit payload shaping
├── account/prefs_form.ex      # keep theme preview transitions
├── account/ssh_keys_state.ex  # keep list/add/table state transitions
├── moderation.ex              # init/update/render, workspace task/results, tables/invites
├── moderation/state.ex        # existing snapshot/table/summary state
├── sysop.ex                   # init/update/render, lifecycle effects/results, submodule events
└── sysop/state.ex             # existing lifecycle enum and invite/revoke state
```

This structure matches the existing screen/state companion convention. [VERIFIED: .planning/codebase/STRUCTURE.md; lib/foglet_bbs/tui/screens/account/state.ex; lib/foglet_bbs/tui/screens/moderation/state.ex; lib/foglet_bbs/tui/screens/sysop/state.ex]

### Pattern 1: Screen-Owned Task Effect

**What:** Set local pending/loading state in `update/3`, emit `Effect.task(op, screen_key, fun)`, and consume `{ :task_result, op, result }` in the same screen. [VERIFIED: lib/foglet_bbs/tui/screens/board_list.ex; lib/foglet_bbs/tui/effect.ex]

**When to use:** Any Account SSH/invite mutation, profile/prefs save, Moderation workspace load, or Sysop lifecycle load/retry that touches a domain context. [VERIFIED: .planning/phases/38-account-operator-workbenches/38-SPEC.md]

**Example:**
```elixir
# Source: lib/foglet_bbs/tui/screens/board_list.ex
def update(:load, local_state, %Context{} = context) do
  local_state =
    local_state
    |> normalize_state()
    |> Map.merge(%{status: :loading, last_op: :load_boards, last_error: nil})

  {local_state, [load_boards_effect(context)]}
end

def update({:task_result, :load_boards, {:ok, directory}}, local_state, %Context{}) do
  {store_directory(local_state, directory), []}
end
```

### Pattern 2: Preserve Helper State Transitions, Move Boundary Calls

**What:** Keep helper modules like `SSHKeysState`, `InvitesState`, `ProfileForm`, `PrefsForm`, and Sysop subviews for pure state/event transitions, but move durable calls into task closures owned by the screen. [VERIFIED: lib/foglet_bbs/tui/screens/account/ssh_keys_state.ex; lib/foglet_bbs/tui/screens/shared/invites_state.ex; lib/foglet_bbs/tui/screens/account/profile_form.ex; lib/foglet_bbs/tui/screens/account/prefs_form.ex; lib/foglet_bbs/tui/screens/sysop.ex]

**When to use:** Existing helpers already encode selection, forms, generated code, and error formatting; replacing them increases behavioral risk. [VERIFIED: .planning/phases/38-account-operator-workbenches/38-CONTEXT.md]

**Example:**
```elixir
# Source pattern: lib/foglet_bbs/tui/screens/account/ssh_keys_actions.ex
# Migration direction: keep SSHKeysState.loaded/2 and SSHKeysState.with_error/2,
# but call Accounts.register_ssh_key/2 inside an Account Effect.task closure.
```

### Pattern 3: Lifecycle Slot Single Writer

**What:** Sysop `update/3` must be the only writer for `:not_loaded`, `:loading`, `{:loaded, sub}`, and `{:error, reason}` lifecycle slots after migration. [VERIFIED: .planning/phases/38-account-operator-workbenches/38-CONTEXT.md; lib/foglet_bbs/tui/screens/sysop/state.ex]

**When to use:** BOARDS, LIMITS, SYSTEM, and USERS first entry, retry, loaded, and error paths. [VERIFIED: .planning/phases/38-account-operator-workbenches/38-SPEC.md; lib/foglet_bbs/tui/screens/sysop.ex]

**Example:**
```elixir
# Source: lib/foglet_bbs/tui/screens/sysop/state.ex
@type lifecycle(struct_t) ::
        :not_loaded
        | :loading
        | {:loaded, struct_t}
        | {:error, atom()}
```

### Pattern 4: Modal/Navigation as Effects

**What:** Convert submodule `{:error_modal, message, destination}` events into `Effect.open_modal/1` and, if needed, `Effect.navigate/2` or another explicit effect instead of mutating `%App{modal:, current_screen:}`. [VERIFIED: lib/foglet_bbs/tui/screens/sysop.ex; lib/foglet_bbs/tui/effect.ex]

**When to use:** Sysop submodules such as SITE/LIMITS/BOARDS/USERS that can return error-modal events. [VERIFIED: lib/foglet_bbs/tui/screens/sysop.ex; test/foglet_bbs/tui/screens/sysop/config_accountability_test.exs]

### Anti-Patterns to Avoid

- **Parallel task router:** Do not introduce workbench-specific command/result plumbing; App already routes `screen_task_result` generically. [VERIFIED: .planning/phases/38-account-operator-workbenches/38-CONTEXT.md; lib/foglet_bbs/tui/app.ex]
- **App-local state mutation helpers:** Do not keep `put_account_*`, `put_moderation_*`, or `put_sysop_*` as writers for migrated state. [VERIFIED: .planning/phases/38-account-operator-workbenches/38-SPEC.md; lib/foglet_bbs/tui/app.ex]
- **UI visibility as authorization:** Do not treat hidden tabs or disabled keys as protection for mutations. [VERIFIED: AGENTS.md]
- **Read-only table drift:** Do not add LOG/USERS/BOARDS moderation mutation effects; those tabs remain read-only in this phase. [VERIFIED: .planning/phases/38-account-operator-workbenches/38-CONTEXT.md; lib/foglet_bbs/tui/screens/moderation/state.ex]
- **Text-only tests:** Do not replace reducer/effect assertions with incidental render substring checks. [VERIFIED: AGENTS.md; .planning/phases/38-account-operator-workbenches/38-CONTEXT.md]

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Async task dispatch/result routing | A workbench-specific GenServer or custom task tuple protocol | `Foglet.TUI.Effect.task/3` and App `{:screen_task_result, key, op, result}` | Existing runtime wraps exceptions and routes results back to the requesting screen. [VERIFIED: lib/foglet_bbs/tui/effect.ex; lib/foglet_bbs/tui/app.ex; lib/foglet_bbs/tui/command.ex] |
| Tab widgets and table cursor state | New tab/table state machines | Existing `Tabs`, `ConsoleTable`, `SSHKeysState`, `InvitesState` | Current state structs already store widget state and selection semantics. [VERIFIED: lib/foglet_bbs/tui/screens/account/ssh_keys_state.ex; lib/foglet_bbs/tui/screens/shared/invites_state.ex; lib/foglet_bbs/tui/screens/moderation/state.ex] |
| Authorization checks | Screen-local role predicates for mutations | Domain contexts plus `Foglet.Authorization`/Bodyguard | Project rules require context-level authorization for side effects. [VERIFIED: AGENTS.md; lib/foglet_bbs/authorization.ex] |
| Config persistence | Direct Repo writes or DB-backed secret keys | `Foglet.Config.put/3` for actor-aware writes; env/runtime config for secrets | Runtime config API owns validation, ETS cache invalidation, and actor checks. [VERIFIED: AGENTS.md; lib/foglet_bbs/config.ex] |
| Rendering/chrome/layout primitives | New ad hoc terminal layout components | Raxol View DSL plus existing Foglet widgets | Existing widgets route theme explicitly and the render smoke harness validates layout. [VERIFIED: docs/raxol/getting-started/WIDGET_GALLERY.md; lib/foglet_bbs/tui/widgets/README.md; test/foglet_bbs/tui/layout_smoke_test.exs] |

**Key insight:** The hidden complexity is preserving side-effect ownership, error mapping, lifecycle idempotence, and test-injected domains; custom plumbing would obscure those contracts instead of simplifying them. [VERIFIED: .planning/phases/38-account-operator-workbenches/38-SPEC.md; test/foglet_bbs/tui/app_runtime_contract_test.exs]

## Runtime State Inventory

| Category | Items Found | Action Required |
|----------|-------------|-----------------|
| Stored data | None; this phase does not rename or change durable account, invite, SSH key, moderation, board, config, or authorization data. [VERIFIED: .planning/phases/38-account-operator-workbenches/38-SPEC.md] | No data migration. [VERIFIED: .planning/phases/38-account-operator-workbenches/38-SPEC.md] |
| Live service config | None found in scope; Phase 38 changes TUI ownership only. [VERIFIED: .planning/phases/38-account-operator-workbenches/38-SPEC.md] | No live service patch. [VERIFIED: .planning/phases/38-account-operator-workbenches/38-SPEC.md] |
| OS-registered state | None found in scope; SSH daemon/session runtime remains App/SSH infrastructure. [VERIFIED: AGENTS.md; .planning/phases/38-account-operator-workbenches/38-SPEC.md] | No OS re-registration. [VERIFIED: .planning/phases/38-account-operator-workbenches/38-SPEC.md] |
| Secrets/env vars | None found in scope; secrets remain environment/runtime config, not DB-backed config. [VERIFIED: AGENTS.md] | No env var rename. [VERIFIED: AGENTS.md] |
| Build artifacts | Existing BEAM build artifacts may recompile, but no package/install rename is in scope. [VERIFIED: mix.exs; .planning/phases/38-account-operator-workbenches/38-SPEC.md] | Run normal compile/test/precommit. [VERIFIED: mix.exs; AGENTS.md] |

## Common Pitfalls

### Pitfall 1: Double Writers During Migration

**What goes wrong:** A screen flips local state while App still has matching workbench clauses that overwrite it later. [VERIFIED: lib/foglet_bbs/tui/app.ex; lib/foglet_bbs/tui/screens/sysop.ex]
**Why it happens:** Legacy helpers such as `put_sysop_loading/2`, `put_moderation_snapshot/2`, and `clear_account_save_state/2` still mutate `screen_state`. [VERIFIED: lib/foglet_bbs/tui/app.ex]
**How to avoid:** Move request and result handling as a pair; remove App writers in the same plan that adds screen result handlers. [VERIFIED: .planning/phases/38-account-operator-workbenches/38-CONTEXT.md]
**Warning signs:** App still matches `:account_save_profile`, `:moderation_workspace_loaded`, or `:sysop_*_loaded` after screen tests pass. [VERIFIED: lib/foglet_bbs/tui/app.ex]

### Pitfall 2: Nested Task Result Wrapping

**What goes wrong:** Screens may receive `{:ok, {:ok, value}}`, `{:ok, {:error, reason}}`, or `{:error, reason}` depending on whether the domain call returns tagged tuples or raises. [VERIFIED: lib/foglet_bbs/tui/app.ex; lib/foglet_bbs/tui/screens/main_menu.ex]
**Why it happens:** `Effect.task/3` wraps the task closure result in `{:ok, fun.()}`; existing screens use `unwrap_task_result/1` to normalize. [VERIFIED: lib/foglet_bbs/tui/app.ex; lib/foglet_bbs/tui/screens/main_menu.ex]
**How to avoid:** Add a small local unwrap helper or pattern-match both direct and nested domain result shapes. [VERIFIED: lib/foglet_bbs/tui/screens/main_menu.ex; lib/foglet_bbs/tui/screens/board_list.ex]
**Warning signs:** Successful domain errors render as successful payloads or errors show as `{:error, reason}` strings in status. [VERIFIED: lib/foglet_bbs/tui/screens/main_menu.ex]

### Pitfall 3: Losing Account Preference Refresh

**What goes wrong:** Preference saves update Account local state but the live session keeps old timezone/theme/time format. [VERIFIED: lib/foglet_bbs/tui/app.ex; .planning/phases/38-account-operator-workbenches/38-SPEC.md]
**Why it happens:** Current App save path updates `current_user`, merges session preferences, and calls `Session.update_preferences/2`. [VERIFIED: lib/foglet_bbs/tui/app.ex]
**How to avoid:** Account save success should emit explicit session/current-user effects or a generic session preference refresh effect that preserves the old immediacy. [VERIFIED: .planning/phases/38-account-operator-workbenches/38-CONTEXT.md; lib/foglet_bbs/tui/effect.ex]
**Warning signs:** Prefs form test passes locally but render/theme behavior changes only after reconnect. [VERIFIED: lib/foglet_bbs/tui/screens/account/prefs_form.ex; lib/foglet_bbs/tui/app.ex]

### Pitfall 4: Synchronous Helper Calls Hidden In Key Delegates

**What goes wrong:** Migrated `update/3` still blocks on `Accounts` or `Invites` because old action helpers were reused unchanged. [VERIFIED: lib/foglet_bbs/tui/screens/account/ssh_keys_actions.ex; lib/foglet_bbs/tui/screens/shared/invites_actions.ex]
**Why it happens:** `SSHKeysActions` and `InvitesActions` currently combine event handling, domain calls, reloading, and error mapping. [VERIFIED: lib/foglet_bbs/tui/screens/account/ssh_keys_actions.ex; lib/foglet_bbs/tui/screens/shared/invites_actions.ex]
**How to avoid:** Reuse their state/error mapping ideas, but split domain calls into screen-owned tasks when domain work occurs. [VERIFIED: .planning/phases/38-account-operator-workbenches/38-CONTEXT.md]
**Warning signs:** `Account.update/3`, `Moderation.update/3`, or `Sysop.update/3` calls `InvitesActions.generate/2`, `revoke_selected/2`, or `SSHKeysActions.add/3` directly. [VERIFIED: lib/foglet_bbs/tui/screens/account/ssh_keys_actions.ex; lib/foglet_bbs/tui/screens/shared/invites_actions.ex]

### Pitfall 5: Sysop Retry And USERS Key Collision

**What goes wrong:** Retry handling steals `R` from loaded USERS behavior or offers retry for forbidden errors. [VERIFIED: lib/foglet_bbs/tui/screens/sysop.ex]
**Why it happens:** Current Sysop code only retries when active lifecycle slot is `{:error, reason}` and `reason != :forbidden`; otherwise it delegates onward. [VERIFIED: lib/foglet_bbs/tui/screens/sysop.ex]
**How to avoid:** Preserve the same conditional in `Sysop.update/3` before submodule delegation. [VERIFIED: .planning/phases/38-account-operator-workbenches/38-SPEC.md; lib/foglet_bbs/tui/screens/sysop.ex]
**Warning signs:** `[R] Retry` appears on forbidden errors or loaded USERS can no longer use its own `R` action. [VERIFIED: lib/foglet_bbs/tui/screens/sysop.ex]

### Pitfall 6: Modal Effects From Submodules

**What goes wrong:** Sysop submodule errors keep mutating App modal/current_screen directly through legacy return handling. [VERIFIED: lib/foglet_bbs/tui/screens/sysop.ex]
**Why it happens:** `apply_submodule_result/6` currently writes `%App{modal:, current_screen:}` after `{:error_modal, msg, dest}`. [VERIFIED: lib/foglet_bbs/tui/screens/sysop.ex]
**How to avoid:** Translate events to `Effect.open_modal/1` plus explicit navigation/session effects. [VERIFIED: .planning/phases/38-account-operator-workbenches/38-CONTEXT.md; lib/foglet_bbs/tui/effect.ex]
**Warning signs:** `Sysop.update/3` or helpers return `%App{}` or mention `current_screen` directly. [VERIFIED: lib/foglet_bbs/tui/screen.ex; lib/foglet_bbs/tui/screens/sysop.ex]

## Code Examples

### Generic App Task Routing

```elixir
# Source: lib/foglet_bbs/tui/app.ex
def apply_effect(%__MODULE__{} = state, %Effect{
      type: :task,
      payload: %{op: op, screen_key: screen_key, fun: fun}
    }) do
  task =
    Foglet.TUI.Command.task(op, fn ->
      {:screen_task_result, screen_key, op, {:ok, fun.()}}
    end)

  {state, [task]}
end
```

### Screen Reducer Test Shape

```elixir
# Source: test/foglet_bbs/tui/screens/board_list_test.exs
{%BoardList.State{} = state, [effect]} = BoardList.update(:load, state, ctx)
assert effect.payload.op == :load_boards
assert effect.payload.screen_key == :board_list
{state, []} = BoardList.update({:task_result, :load_boards, {:ok, directory}}, state, ctx)
```

### Runtime Contract Test Shape

```elixir
# Source: test/foglet_bbs/tui/app_runtime_contract_test.exs
{new_state, []} = App.update({:command_result, task.()}, state)
assert %SampleScreen.State{results: [sample_load: {:ok, {:loaded, 1}}]} =
         App.screen_state_for(new_state, :sample_runtime)
```

### Domain Injection Shape

```elixir
# Source: lib/foglet_bbs/tui/screens/domain.ex and BoardList tests
Context.new(
  current_user: user,
  route: :account,
  domain: %{accounts: FakeAccounts, moderation: FakeModeration}
)
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Legacy `render/1` and `handle_key/2` receive broad App-shaped state | `init/1`, `update/3`, `render/2` receive local state plus `Context` | Phase 34 foundation | Phase 38 should finish this pattern for Account/Moderation/Sysop. [VERIFIED: .planning/STATE.md; lib/foglet_bbs/tui/screen.ex] |
| Screen commands returned legacy tuples that App interpreted with screen-specific clauses | Screens emit explicit effects and App interprets them generically | Phase 34-36 migrations | Phase 38 must reuse `Effect.task/3` and `screen_task_result`. [VERIFIED: .planning/STATE.md; lib/foglet_bbs/tui/effect.ex; lib/foglet_bbs/tui/app.ex] |
| App owned loaded/result state for account/operator workbenches | Owning screens consume their own task results | Target of Phase 38 | App should stop mutating Account, Moderation, and Sysop local state. [VERIFIED: .planning/phases/38-account-operator-workbenches/38-SPEC.md] |

**Deprecated/outdated:**
- App-owned workbench save/load/result clauses are transitional migration debt for Phase 38. [VERIFIED: .planning/phases/38-account-operator-workbenches/38-SPEC.md; lib/foglet_bbs/tui/app.ex]
- Synchronous screen helper domain calls are acceptable only for pure local/read behavior; durable or authorization-sensitive work should move to task/effect handling. [VERIFIED: .planning/phases/38-account-operator-workbenches/38-CONTEXT.md]

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | No external package version lookup is required because the phase adds no dependencies. [ASSUMED] | Standard Stack | If a planner adds a dependency anyway, it must verify registry currentness before implementation. |

## Open Questions

1. **Should Account preference refresh use existing `Effect.session/1` variants or a new precise session effect payload?**
   - What we know: `Effect.session/1` can send generic session payloads, and App already handles `{:set_current_user, user}` plus direct session messages. [VERIFIED: lib/foglet_bbs/tui/effect.ex; lib/foglet_bbs/tui/app.ex]
   - What's unclear: The exact payload name for session preference refresh is left to implementation discretion. [VERIFIED: .planning/phases/38-account-operator-workbenches/38-CONTEXT.md]
   - Recommendation: Use the smallest generic session effect that preserves current `Session.update_preferences/2` immediacy and is easy to assert in Account tests. [VERIFIED: .planning/phases/38-account-operator-workbenches/38-SPEC.md; lib/foglet_bbs/tui/app.ex]

2. **How much of `InvitesActions` should remain after domain calls move into tasks?**
   - What we know: `InvitesState` is reusable pure state, while `InvitesActions` currently performs domain calls and local transitions together. [VERIFIED: lib/foglet_bbs/tui/screens/shared/invites_state.ex; lib/foglet_bbs/tui/screens/shared/invites_actions.ex]
   - What's unclear: Whether implementation should split `InvitesActions` or keep private result-mapping helpers in each screen. [VERIFIED: .planning/phases/38-account-operator-workbenches/38-CONTEXT.md]
   - Recommendation: Prefer shared pure result helpers only if Account/Moderation/Sysop would otherwise duplicate nontrivial error mapping. [VERIFIED: lib/foglet_bbs/tui/screens/shared/invites_actions.ex]

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|-------------|-----------|---------|----------|
| `rtk` | All repo commands | yes | 0.37.2 | None; project requires `rtk` prefix. [VERIFIED: command -v rtk; rtk --version; AGENTS.md] |
| Elixir | Compile/test | yes | 1.19.5 / OTP 28 | Project requires `~> 1.17`; available version satisfies it. [VERIFIED: rtk elixir --version; mix.exs] |
| Mix | Tests/precommit | yes | 1.19.5 | None. [VERIFIED: rtk mix --version] |
| PostgreSQL client | Mix test DB setup | yes | psql 14.20 | Use project test setup; local server check reported no response on `/tmp:5432`. [VERIFIED: psql --version; pg_isready] |
| PostgreSQL server | `rtk mix test` aliases | partially | `pg_isready` no response, but targeted test completed | If DB tests fail later, start project DB before full suite. [VERIFIED: pg_isready; rtk mix test test/foglet_bbs/tui/app_runtime_contract_test.exs] |

**Missing dependencies with no fallback:**
- None identified for pure reducer/App runtime research. [VERIFIED: rtk mix test test/foglet_bbs/tui/app_runtime_contract_test.exs]

**Missing dependencies with fallback:**
- Local Postgres readiness was not detected by `pg_isready`, but the targeted runtime test completed through Mix's test alias; full DB-heavy tests may still require starting the project database. [VERIFIED: pg_isready; rtk mix test test/foglet_bbs/tui/app_runtime_contract_test.exs]

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | ExUnit built into Elixir 1.19.5. [VERIFIED: rtk mix --version; .planning/codebase/TESTING.md] |
| Config file | `test/test_helper.exs` starts ExUnit and SQL sandbox. [VERIFIED: .planning/codebase/TESTING.md] |
| Quick run command | `rtk mix test test/foglet_bbs/tui/screens/account_test.exs test/foglet_bbs/tui/screens/moderation_test.exs test/foglet_bbs/tui/screens/sysop_test.exs test/foglet_bbs/tui/app_runtime_contract_test.exs` [VERIFIED: .planning/codebase/TESTING.md] |
| Full suite command | `rtk mix precommit` [VERIFIED: AGENTS.md; mix.exs] |

### Phase Requirements -> Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|--------------|
| SCREEN-05 | Account init/update/render, profile/prefs saves, SSH keys, invites, theme preview | reducer/unit + render smoke | `rtk mix test test/foglet_bbs/tui/screens/account_test.exs` | yes. [VERIFIED: test/foglet_bbs/tui/screens/account_test.exs] |
| SCREEN-06 | Moderation workspace load/result, read-only tables, invites | reducer/unit + render smoke | `rtk mix test test/foglet_bbs/tui/screens/moderation_test.exs` | yes. [VERIFIED: test/foglet_bbs/tui/screens/moderation_test.exs] |
| SCREEN-06 | Sysop lifecycle slots, retry, nested subviews/forms, invites/revoke | reducer/unit + nested form tests | `rtk mix test test/foglet_bbs/tui/screens/sysop_test.exs test/foglet_bbs/tui/screens/sysop/site_form_test.exs test/foglet_bbs/tui/screens/sysop/config_accountability_test.exs` | yes. [VERIFIED: test/foglet_bbs/tui/screens/sysop_test.exs; test/foglet_bbs/tui/screens/sysop/site_form_test.exs; test/foglet_bbs/tui/screens/sysop/config_accountability_test.exs] |
| APP-02 | App no longer owns workbench-specific save/load/result mutation | App runtime/unit + grep-like assertions | `rtk mix test test/foglet_bbs/tui/app_test.exs test/foglet_bbs/tui/app_runtime_contract_test.exs` | yes. [VERIFIED: test/foglet_bbs/tui/app_test.exs; test/foglet_bbs/tui/app_runtime_contract_test.exs] |
| VERIFY-01 | Account/operator render smoke still fits supported sizes | layout smoke | `rtk mix test test/foglet_bbs/tui/layout_smoke_test.exs` | yes. [VERIFIED: test/foglet_bbs/tui/layout_smoke_test.exs] |

### Sampling Rate

- **Per task commit:** Run the specific screen test file being changed plus `test/foglet_bbs/tui/app_runtime_contract_test.exs`. [VERIFIED: .planning/codebase/TESTING.md; test/foglet_bbs/tui/app_runtime_contract_test.exs]
- **Per wave merge:** Run Account, Moderation, Sysop, App, and layout smoke targeted files. [VERIFIED: .planning/phases/38-account-operator-workbenches/38-SPEC.md]
- **Phase gate:** Run `rtk mix precommit` before verification or commit. [VERIFIED: AGENTS.md; mix.exs]

### Wave 0 Gaps

- None for test infrastructure; target files already exist. [VERIFIED: test/foglet_bbs/tui/screens/account_test.exs; test/foglet_bbs/tui/screens/moderation_test.exs; test/foglet_bbs/tui/screens/sysop_test.exs; test/foglet_bbs/tui/app_runtime_contract_test.exs; test/foglet_bbs/tui/layout_smoke_test.exs]
- Existing tests must be migrated from App-shaped assertions to local reducer/effect assertions where they currently assert legacy behavior. [VERIFIED: .planning/phases/38-account-operator-workbenches/38-SPEC.md]

## Sources

### Primary (HIGH confidence)

- `AGENTS.md` - SSH-first boundary, TUI workflows, context/domain rules, authorization, testing/precommit rules.
- `.planning/phases/38-account-operator-workbenches/38-SPEC.md` - Phase 38 locked goal, requirements, boundaries, and acceptance criteria.
- `.planning/phases/38-account-operator-workbenches/38-CONTEXT.md` - Phase 38 implementation decisions D-01 through D-20.
- `.planning/REQUIREMENTS.md` - v2.0 requirement mapping for SCREEN-05, SCREEN-06, APP-02, VERIFY requirements.
- `.planning/STATE.md` - prior phase decisions for screen reducer/effect ownership.
- `lib/foglet_bbs/tui/screen.ex`, `context.ex`, `effect.ex`, `command.ex`, `app.ex` - current runtime contract and generic effect/task path.
- `lib/foglet_bbs/tui/screens/account*`, `moderation*`, `sysop*`, `shared/invites*` - current workbench state and legacy helper behavior.
- `test/foglet_bbs/tui/app_runtime_contract_test.exs`, `board_list_test.exs` - verified reducer/effect and App routing test patterns.

### Secondary (MEDIUM confidence)

- `.planning/codebase/CONVENTIONS.md`, `STRUCTURE.md`, `TESTING.md` - generated codebase maps and test conventions used for planner guidance.
- `docs/raxol/getting-started/WIDGET_GALLERY.md`, `lib/foglet_bbs/tui/widgets/README.md` - local Raxol/Foglet widget conventions.

### Tertiary (LOW confidence)

- None.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - versions and dependencies are verified locally, and no new library is recommended. [VERIFIED: mix.exs; mix.lock; rtk mix --version]
- Architecture: HIGH - Phase 34 runtime modules, migrated screens, and App tests establish the exact target pattern. [VERIFIED: lib/foglet_bbs/tui/screen.ex; lib/foglet_bbs/tui/app.ex; test/foglet_bbs/tui/app_runtime_contract_test.exs]
- Pitfalls: HIGH - pitfalls are drawn from current legacy workbench clauses and locked Phase 38 requirements. [VERIFIED: lib/foglet_bbs/tui/app.ex; .planning/phases/38-account-operator-workbenches/38-SPEC.md]

**Research date:** 2026-04-28
**Valid until:** 2026-05-28 for this local architecture research; re-check if Phase 34-39 runtime modules change first. [ASSUMED]
