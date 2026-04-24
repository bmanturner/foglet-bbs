# Phase 4: Shared Invite Surface Activation - Research

**Researched:** 2026-04-23
**Domain:** Phoenix/Elixir SSH TUI surface activation over existing invite domain APIs
**Confidence:** HIGH

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- **D-01:** Account, Moderation, and Sysop expose `INVITES` through each shell's existing tab-state construction, using `Foglet.TUI.Screens.ShellVisibility.invites_visible?/2` as the shared policy seam.
- **D-02:** Account remains the regular-user invite surface for `invite_code_generators == "any_user"`.
- **D-03:** Moderation adds `INVITES` only for moderators when `invite_code_generators == "mods"`.
- **D-04:** Sysop adds an allowed operator `INVITES` surface for sysops when policy permits sysop invite generation, including `sysop_only`; the planner should preserve sysop access under broader policies unless the locked SPEC tests prove a narrower interpretation is required.
- **D-05:** Hidden tabs are only UI exposure control. Domain authorization and runtime policy remain authoritative through `Foglet.Accounts`.
- **D-06:** List loading, generated-code display, selected-row state, refresh state, and error state live in `Foglet.TUI.Screens.Shared.InvitesState` or adjacent shared invite modules.
- **D-07:** Account, Moderation, and Sysop contain only tab visibility, tab dispatch, and delegation code for `INVITES`; they must not duplicate list/generate/revoke behavior.
- **D-08:** The shared action path handles load, refresh, generate, select, revoke, and error mapping for all three surfaces.
- **D-09:** The TUI calls only `Foglet.Accounts.create_invite/1`, `Foglet.Accounts.list_invites/1`, and `Foglet.Accounts.revoke_invite/2` for live invite behavior.
- **D-10:** The TUI must not reimplement invite authorization, generation limits, code generation, persistence queries, or registration redemption semantics.
- **D-11:** Tagged errors from `Accounts` such as `:forbidden`, `:limit_reached`, `:not_found`, and `:unavailable` are mapped into TUI-visible errors without mutating local state as though the action succeeded.
- **D-12:** `InvitesSurface.render/2` replaces scaffold/future-placeholder copy with live status rows from `Accounts.list_invites/1`.
- **D-13:** Each row shows invite code, issuer id, inserted timestamp, derived status, and state-specific consumed or revoked details required by `04-SPEC.md`.
- **D-14:** Generation and revocation are keyboard-driven commands in the shared active tab, consistent with terminal-first TUI conventions.
- **D-15:** A generated invite code is displayed immediately after successful creation so the actor can copy/share it once from the TUI, while the refreshed list also includes the new code.
- **D-16:** Consumed and revoked invites remain visible but cannot be successfully revoked; failed revoke attempts surface a TUI error and leave persisted state unchanged.
- **D-17:** Add regression tests for policy-controlled tab visibility across Account, Moderation, and Sysop.
- **D-18:** Add shared-surface tests for rendering available, consumed, and revoked invite rows with the required fields.
- **D-19:** Add action tests proving allowed Account, Moderation, and Sysop surfaces each delegate through the same shared generation path and persist exactly one invite.
- **D-20:** Add revoke tests for available, consumed, already revoked, missing, and unauthorized invite codes.
- **D-21:** `mix precommit` must pass before the phase is considered complete.

### Claude's Discretion
- Exact key bindings for generate, revoke, refresh, and row selection, as long as they are visible in the key bar and consistent with nearby TUI screens.
- Exact row layout and timestamp formatting, as long as the required fields are present and readable in terminal output.
- Whether shared action helpers live directly in `InvitesSurface`, in a new sibling module, or split between state/action/render modules. Prefer one shared path with clear tests over a particular module shape.
- Exact wording for TUI error messages, as long as forbidden, limit-reached, not-found, unavailable, and validation failures are distinguishable enough for the actor.

### Deferred Ideas (OUT OF SCOPE)
None -- analysis stayed within phase scope.
</user_constraints>

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| INVT-01 | Authorized actor can open a shared `INVITES` tab from Account, Moderation, or Sysop according to `invite_code_generators`. [VERIFIED: .planning/REQUIREMENTS.md] | Use `ShellVisibility.invites_visible?/2` and shared tab construction, not per-screen role matrices. [VERIFIED: 04-CONTEXT.md; lib/foglet_bbs/tui/screens/shell_visibility.ex] |
| MODR-04 | If `invite_code_generators` is `mods`, moderator workspace includes the shared `INVITES` tab with unlimited invite generation. [VERIFIED: .planning/REQUIREMENTS.md] | Add conditional `INVITES` to Moderation state/render/delegation and rely on `Accounts.create_invite/1` for operator-limit behavior. [VERIFIED: 04-SPEC.md; lib/foglet_bbs/accounts.ex] |
| SYSO-05 | If `invite_code_generators` is `sysop_only`, Sysop workspace includes the shared `INVITES` tab with unlimited invite generation. [VERIFIED: .planning/REQUIREMENTS.md] | Add conditional `INVITES` to Sysop state/render/delegation and preserve sysop access under broader policies unless SPEC tests constrain it. [VERIFIED: 04-CONTEXT.md; 04-SPEC.md] |
</phase_requirements>

## Summary

Phase 4 should be implemented as a TUI integration layer over the already-completed invite domain APIs. `Accounts.create_invite/1`, `Accounts.list_invites/1`, and `Accounts.revoke_invite/2` already own persistence, authorization, policy checks, per-user caps, code generation, and lifecycle state projection. [VERIFIED: lib/foglet_bbs/accounts.ex; .planning/phases/03-invite-persistence-and-registration-enforcement/03-VERIFICATION.md]

The established architecture is one shared invite state/action/render path consumed by Account, Moderation, and Sysop through thin tab dispatch. The work should grow `Foglet.TUI.Screens.Shared.InvitesState`, replace scaffold rendering in `InvitesSurface`, and add one shared action handler module, likely `Foglet.TUI.Screens.Shared.InvitesActions`. [VERIFIED: 04-CONTEXT.md; 04-SPEC.md; lib/foglet_bbs/tui/screens/shared/invites_state.ex; lib/foglet_bbs/tui/screens/shared/invites_surface.ex]

**Primary recommendation:** Build one shared invite controller-style module for load/refresh/generate/select/revoke, and have Account, Moderation, and Sysop delegate to it only when the active tab label is `INVITES`. [VERIFIED: 04-CONTEXT.md; .planning/codebase/ARCHITECTURE.md]

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|--------------|----------------|-----------|
| Invite visibility in shell tab bars | TUI Layer | Domain Core | The TUI decides whether to expose a tab through `ShellVisibility`, while domain APIs remain authoritative for action success. [VERIFIED: lib/foglet_bbs/tui/screens/shell_visibility.ex; 04-SPEC.md] |
| Invite listing and lifecycle status | Domain Core | TUI Layer | `Accounts.list_invites/1` returns status maps; the TUI renders those maps without querying `Repo`. [VERIFIED: lib/foglet_bbs/accounts.ex; .planning/codebase/ARCHITECTURE.md] |
| Invite generation and revocation | Domain Core | TUI Layer | `Accounts.create_invite/1` and `Accounts.revoke_invite/2` enforce Bodyguard and runtime config; the TUI only calls them and maps results. [VERIFIED: lib/foglet_bbs/accounts.ex; test/foglet_bbs/accounts/invite_test.exs] |
| Row selection and key handling | TUI Layer | Raxol widgets | Parent screens own state; local widgets such as `SelectionList` and `Tabs` are pure or state facades. [VERIFIED: lib/foglet_bbs/tui/widgets/list/selection_list.ex; lib/foglet_bbs/tui/widgets/input/tabs.ex] |
| Runtime config editing | Sysop Phase 2 | None in Phase 4 | Editing `invite_code_generators` and invite limits is explicitly out of Phase 4. [VERIFIED: 04-SPEC.md; .planning/ROADMAP.md] |

## Project Constraints (from CLAUDE.md)

- Run `mix precommit` after changes and fix failures. [VERIFIED: CLAUDE.md]
- Use `Req` for HTTP; do not add `httpoison`, `tesla`, or `httpc`. This phase needs no HTTP dependency. [VERIFIED: CLAUDE.md]
- Prefer Elixir stdlib date/time modules; do not add date/time dependencies. [VERIFIED: CLAUDE.md]
- Read `docs/ARCHITECTURE.md` for non-trivial architecture changes. [VERIFIED: CLAUDE.md; docs/ARCHITECTURE.md]
- Read Raxol docs and local widget docs for TUI work. [VERIFIED: CLAUDE.md; docs/raxol/README.md; lib/foglet_bbs/tui/widgets/README.md]
- Do not nest multiple modules in the same file. [VERIFIED: CLAUDE.md]
- Structs do not implement `Access`; use field access for structs. [VERIFIED: CLAUDE.md]
- Tests that start processes must use `start_supervised!/1`, and tests must avoid `Process.sleep/1` and `Process.alive?/1`. [VERIFIED: CLAUDE.md]
- Programmatically-set Ecto fields must not be passed through `cast/3`. This phase should not add invite schema changes. [VERIFIED: CLAUDE.md; 04-SPEC.md]

## Standard Stack

### Core

| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Elixir / Mix | Elixir 1.19.5, Mix 1.19.5, OTP 28 | Compile, test, and run the Phoenix/OTP app. | Project `mix.exs` requires Elixir `~> 1.17`, and local toolchain satisfies it. [VERIFIED: mix.exs; `elixir --version`; `mix --version`] |
| Phoenix | 1.8.5 | Application web framework and endpoint infrastructure. | Existing project dependency; Phase 4 does not add web UI. [VERIFIED: mix.exs; mix.lock; docs/ARCHITECTURE.md] |
| Ecto SQL | 3.13.5 | Persistence access through `Foglet.Accounts` and `FogletBbs.Repo`. | Existing domain contexts use Ecto; TUI must not access `Repo` directly. [VERIFIED: mix.lock; .planning/codebase/ARCHITECTURE.md] |
| Raxol | vendored `vendor/raxol`; locked transitive packages 2.4.0 | Terminal render tree, widget components, and TUI lifecycle. | Existing TUI runtime and widgets are Raxol-backed. [VERIFIED: mix.exs; mix.lock; docs/raxol/README.md] |
| Bodyguard | 2.4.3 | Actor-aware authorization in `Accounts` invite functions. | Existing `Accounts` APIs call `Bodyguard.permit/4`; Phase 4 must not bypass that. [VERIFIED: mix.lock; lib/foglet_bbs/accounts.ex] |
| ExUnit | built in to Elixir | Unit, DB, and TUI regression tests. | Existing tests and project testing docs use ExUnit. [VERIFIED: .planning/codebase/TESTING.md; `mix help test`] |

### Supporting

| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| Credo | 1.7.18 | Static code-quality checks. | Runs through `mix precommit`. [VERIFIED: mix.lock; mix.exs] |
| Sobelow | 0.14.1 | Phoenix security scanner. | Runs through `mix precommit`. [VERIFIED: mix.lock; mix.exs] |
| Dialyxir | 1.4.7 | Dialyzer integration. | Public specs and tuple returns must be accurate. [VERIFIED: mix.lock; .planning/codebase/CONVENTIONS.md] |
| StreamData | `~> 1.0` | Property tests. | Not needed for Phase 4 unless a new selection invariant warrants it. [VERIFIED: mix.exs; .planning/codebase/TESTING.md] |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Shared invite action module | Per-screen generate/revoke code | Rejected by locked D-07 and SPEC requirement 5 because it duplicates action flow. [VERIFIED: 04-CONTEXT.md; 04-SPEC.md] |
| `Foglet.Accounts` APIs | Direct `Repo` calls from TUI | Rejected because domain contexts own persistence and authorization. [VERIFIED: .planning/codebase/ARCHITECTURE.md; 04-SPEC.md] |
| New TUI widget dependency | Existing `SelectionList`, `ListRow`, `Tabs`, `ScreenFrame` | Rejected because local widgets already cover tab navigation, row selection, chrome, and key bars. [VERIFIED: lib/foglet_bbs/tui/widgets/README.md] |

**Installation:** No package installation is required for Phase 4. [VERIFIED: mix.exs; 04-SPEC.md]

**Version verification:** Versions above were verified from `mix.lock`, `mix.exs`, `elixir --version`, and `mix --version`; no registry fetch was required because this phase should not change dependencies. [VERIFIED: mix.lock; mix.exs; local command output]

## Architecture Patterns

### System Architecture Diagram

```text
SSH key/input event
    |
    v
Raxol Lifecycle / Foglet.TUI.App
    |
    v
Active screen: Account | Moderation | Sysop
    |
    +--> build tab labels with ShellVisibility.invites_visible?/2
    |       |
    |       v
    |   Shared policy seam over current_user + invite_code_generators
    |
    +--> if active tab != INVITES: existing tab handler
    |
    +--> if active tab == INVITES
            |
            v
        Shared.InvitesActions.handle_key/load/refresh
            |
            +--> Accounts.list_invites(actor) ----+
            +--> Accounts.create_invite(actor) ---+--> Bodyguard + Config + Repo
            +--> Accounts.revoke_invite(actor, code)-+
            |
            v
        Shared.InvitesState updated with rows, selected_index,
        loading/error state, and last_generated_code
            |
            v
        Shared.InvitesSurface.render/2
            |
            v
        ScreenFrame key bar + terminal output
```

### Recommended Project Structure

```text
lib/foglet_bbs/tui/screens/
├── shared/
│   ├── invites_state.ex      # state struct and constructors for live rows/error/selection
│   ├── invites_actions.ex    # one shared load/refresh/generate/select/revoke path
│   └── invites_surface.ex    # live rendering only; no Repo, no auth logic
├── account.ex                # active-tab detection and delegation
├── account/state.ex          # conditional INVITES tab and shared state field
├── moderation.ex             # conditional INVITES rendering and delegation
├── moderation/state.ex       # add conditional INVITES tab and invites state
├── sysop.ex                  # conditional INVITES rendering and delegation
└── sysop/state.ex            # add conditional INVITES tab and invites state
```

### Pattern 1: Shared State Owns Row Selection and Last Result

**What:** Extend `InvitesState` with `items`, `selected_index`, `loading?` or `status`, `last_generated_code`, `error`, and deterministic `frame`. [VERIFIED: 04-CONTEXT.md; lib/foglet_bbs/tui/screens/shared/invites_state.ex]

**When to use:** Use this for all Account, Moderation, and Sysop invite tabs. [VERIFIED: 04-SPEC.md]

**Example:**

```elixir
defstruct items: nil,
          selected_index: 0,
          last_generated_code: nil,
          error: nil,
          frame: 0
```

### Pattern 2: One Shared Action Handler

**What:** Put load, refresh, generate, select, and revoke in one shared module that receives actor plus `%InvitesState{}` and returns an updated `%InvitesState{}`. [VERIFIED: 04-CONTEXT.md; .planning/codebase/ARCHITECTURE.md]

**When to use:** Screen modules should delegate to this module only when their active tab label is `INVITES`. [VERIFIED: 04-SPEC.md; lib/foglet_bbs/tui/screens/sysop.ex]

**Example:**

```elixir
case InvitesActions.handle_key(event, ss.invites, state.current_user) do
  {:ok, invites} ->
    put_invites_state(state, ss, invites)

  :no_match ->
    :no_match
end
```

### Pattern 3: Domain APIs Are the Trust Boundary

**What:** The TUI calls `Accounts.create_invite/1`, `Accounts.list_invites/1`, and `Accounts.revoke_invite/2`, then maps tagged tuples to display state. [VERIFIED: lib/foglet_bbs/accounts.ex; 04-CONTEXT.md]

**When to use:** Every live invite operation in this phase. [VERIFIED: 04-SPEC.md]

**Example:**

```elixir
with {:ok, invite} <- Accounts.create_invite(actor),
     {:ok, rows} <- Accounts.list_invites(actor) do
  {:ok, %{state | items: rows, last_generated_code: invite.code, error: nil}}
else
  {:error, reason} -> {:ok, put_error(state, reason)}
end
```

### Anti-Patterns to Avoid

- **Per-screen invite flows:** Account, Moderation, and Sysop must not each implement generate/revoke/list. [VERIFIED: 04-CONTEXT.md; 04-SPEC.md]
- **Screen-only authorization:** Tab hiding is advisory; `Accounts` decides whether mutation succeeds. [VERIFIED: 04-CONTEXT.md; lib/foglet_bbs/accounts.ex]
- **Direct `Repo` in TUI:** Domain contexts own persistence and status projection. [VERIFIED: .planning/codebase/ARCHITECTURE.md]
- **Leaving Phase 0 placeholder copy:** Live `INVITES` render output must not contain "later phase", "scaffold", or "Phase 4 activates". [VERIFIED: 04-SPEC.md; test/foglet_bbs/tui/screens/shared/invites_surface_test.exs]
- **Using `struct[:field]`:** Project rules forbid Access on structs. [VERIFIED: CLAUDE.md]

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Authorization matrix | Local role checks for generate/revoke | `Foglet.Accounts` APIs with Bodyguard | Existing domain API enforces authorization and returns tagged errors. [VERIFIED: lib/foglet_bbs/accounts.ex] |
| Invite code generation | TUI-side random code generation | `Accounts.create_invite/1` | Domain function uses secure randomness and unique retry. [VERIFIED: lib/foglet_bbs/accounts.ex; 03-VERIFICATION.md] |
| Invite lifecycle projection | TUI status derivation from raw schema rows | `Accounts.list_invites/1` status maps | Domain projection includes `status`, issuer, created, consumed, and revoked fields. [VERIFIED: lib/foglet_bbs/accounts.ex] |
| Tab keyboard navigation | Custom left/right/1-9 handling | `Foglet.TUI.Widgets.Input.Tabs` | Existing wrapper supports Left/Right/Home/End/1-9 and returns tab-change actions. [VERIFIED: lib/foglet_bbs/tui/widgets/input/tabs.ex] |
| Selectable row rendering | Custom selection markers in each surface | `SelectionList` plus `ListRow` or equivalent shared row renderer | Existing list widgets centralize selection rendering and parent-owned selected index. [VERIFIED: lib/foglet_bbs/tui/widgets/list/selection_list.ex; lib/foglet_bbs/tui/widgets/list/list_row.ex] |
| Error modal architecture | New modal system | Existing screen-local error display or existing `Foglet.TUI.Modal` pattern where appropriate | Sysop already maps submodule error events through modal state. [VERIFIED: lib/foglet_bbs/tui/screens/sysop.ex] |

**Key insight:** The hard parts are already solved in the domain layer; Phase 4 risk is duplicated TUI glue that drifts across three surfaces. [VERIFIED: 03-VERIFICATION.md; 04-SPEC.md]

## Common Pitfalls

### Pitfall 1: Tab Visibility Freezes at State Construction

**What goes wrong:** A screen builds a `Tabs` widget once and then policy changes, leaving the visible tab list stale. [VERIFIED: lib/foglet_bbs/tui/screens/account/state.ex]

**Why it happens:** Existing Account state documents that `INVITES` tab presence is baked into `Tabs` at construction time. [VERIFIED: lib/foglet_bbs/tui/screens/account/state.ex]

**How to avoid:** Rebuild `Tabs.init(tabs: tab_labels(invites?), active: clamped_active)` when current visibility differs from stored labels. [VERIFIED: lib/foglet_bbs/tui/widgets/input/tabs.ex]

**Warning signs:** Tests pass initial render but fail after changing `invite_code_generators` in the same test session. [VERIFIED: test/foglet_bbs/accounts/invite_test.exs; .planning/codebase/TESTING.md]

### Pitfall 2: `InvitesSurface.visible?/2` Currently Treats Sysop as Always Visible

**What goes wrong:** Sysop tab visibility may be broader than SPEC wording if blindly copied. [VERIFIED: lib/foglet_bbs/tui/screens/shared/invites_surface.ex; 04-SPEC.md]

**Why it happens:** Phase 0 convention says sysop is always visible, while Phase 4 SPEC specifically requires sysop visibility for `sysop_only` and context D-04 says preserve broader sysop access unless locked tests prove narrower. [VERIFIED: lib/foglet_bbs/tui/screens/shared/invites_surface.ex; 04-CONTEXT.md; 04-SPEC.md]

**How to avoid:** Write explicit policy matrix tests first for Account, Moderation, and Sysop, then conform implementation to those tests and D-04. [VERIFIED: 04-CONTEXT.md]

**Warning signs:** A regular user sees `INVITES` under `"mods"`, or a moderator sees it under `"any_user"` in Moderation. [VERIFIED: test/foglet_bbs/tui/screens/shared/invites_surface_test.exs]

### Pitfall 3: Error Results Mutate Local State as if Success Happened

**What goes wrong:** A failed revoke or generate updates rows or clears selection, making the UI lie about persisted state. [VERIFIED: 04-CONTEXT.md; lib/foglet_bbs/accounts.ex]

**Why it happens:** TUI code handles `{:error, reason}` and success tuples in the same branch. [ASSUMED]

**How to avoid:** In shared actions, success paths refresh rows; error paths only set `error` and preserve `items`, `selected_index`, and `last_generated_code` unless intentionally cleared. [VERIFIED: 04-CONTEXT.md]

**Warning signs:** Tests for consumed/already revoked/missing/unauthorized revokes show changed persisted records or changed rendered status. [VERIFIED: 04-SPEC.md]

### Pitfall 4: DB/Config Tests Run Async While Mutating Global Config

**What goes wrong:** Invite policy tests leak `:foglet_config` ETS state across modules. [VERIFIED: .planning/codebase/TESTING.md; test/foglet_bbs/accounts/invite_test.exs]

**Why it happens:** Config cache is a global named ETS table. [VERIFIED: .planning/codebase/ARCHITECTURE.md]

**How to avoid:** Use `async: false` for tests that mutate config and restore config with `on_exit`. [VERIFIED: test/foglet_bbs/accounts/invite_test.exs; .planning/codebase/TESTING.md]

**Warning signs:** Policy matrix tests are order-dependent. [ASSUMED]

### Pitfall 5: Formatting DateTimes With a New Dependency

**What goes wrong:** A dependency is added for simple timestamp formatting. [VERIFIED: CLAUDE.md]

**Why it happens:** Invite rows need readable inserted/consumed/revoked times. [VERIFIED: 04-SPEC.md]

**How to avoid:** Use Elixir stdlib `DateTime`/`Calendar` functions or existing project helpers if available; do not add a date/time dependency. [VERIFIED: CLAUDE.md]

**Warning signs:** `mix.exs` changes for timestamp rendering. [VERIFIED: CLAUDE.md]

## Code Examples

Verified patterns from local sources:

### Tagged Domain Calls

```elixir
with :ok <- Bodyguard.permit(Foglet.Authorization, :generate_invite, actor, :site),
     :ok <- ensure_invite_generation_policy(actor),
     :ok <- ensure_invite_generation_limit(actor) do
  insert_invite(actor, 5)
else
  {:error, :forbidden} -> {:error, :forbidden}
  {:error, :limit_reached} -> {:error, :limit_reached}
end
```

Source: `lib/foglet_bbs/accounts.ex` [VERIFIED: local code]

### TUI Screen Delegation Contract

```elixir
def handle_key(event, state) do
  ss = get_screen_state(state)
  {new_tabs, action} = Tabs.handle_event(event, ss.tabs)

  if action == nil and new_tabs == ss.tabs do
    delegate_to_active_tab(event, state, ss)
  else
    # update active tab
  end
end
```

Source: `lib/foglet_bbs/tui/screens/sysop.ex` [VERIFIED: local code]

### Selection List Ownership

```elixir
SelectionList.render(items, selected_index, fn {item, _idx, selected?} ->
  ListRow.render(format_invite_row(item), selected?, theme)
end)
```

Source pattern: `SelectionList.render/3` contract in `lib/foglet_bbs/tui/widgets/list/selection_list.ex` [VERIFIED: local code]

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Scaffold-only shared `INVITES` render branch | Live shared surface backed by `Accounts` invite APIs | Phase 4 target after Phase 3 verification | Remove placeholder copy and add shared action state. [VERIFIED: 04-SPEC.md; 03-VERIFICATION.md] |
| UI visibility as future placeholder policy | UI visibility plus domain authorization as trust boundary | Phase 1 and Phase 3 | Hidden tabs are not security controls. [VERIFIED: 04-CONTEXT.md; lib/foglet_bbs/accounts.ex] |
| No TUI invite action wiring | One shared load/generate/revoke action path | Phase 4 target | Avoid three duplicated invite workflows. [VERIFIED: 04-SPEC.md] |

**Deprecated/outdated:**
- `InvitesSurface.render/2` future-placeholder branch for non-empty items must be removed or rewritten. [VERIFIED: lib/foglet_bbs/tui/screens/shared/invites_surface.ex; 04-SPEC.md]
- `InvitesState` accepting arbitrary list elements is insufficient for live invite status rows. [VERIFIED: lib/foglet_bbs/tui/screens/shared/invites_state.ex]

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | TUI code may accidentally handle error and success tuples in the same branch if not tested. | Common Pitfalls | Low; tests can force explicit error branch behavior. |
| A2 | Policy matrix tests may become order-dependent if global config restoration is incomplete. | Common Pitfalls | Medium; flaky tests and false plan confidence. |

## Open Questions

1. **Should sysop see `INVITES` under `mods` and `any_user` policies in Sysop?**
   - What we know: D-04 says preserve sysop access under broader policies unless locked SPEC tests prove narrower. [VERIFIED: 04-CONTEXT.md]
   - What's unclear: The SPEC acceptance list explicitly names `sysop_only` but also says retain an allowed operator surface under broader policies. [VERIFIED: 04-SPEC.md]
   - Recommendation: Plan tests that encode D-04: sysop sees Sysop `INVITES` for `sysop_only`, `mods`, and `any_user`, while Account remains regular-user `any_user` and Moderation remains moderator `mods`. [VERIFIED: 04-CONTEXT.md]

2. **Should invite loading happen eagerly on screen init or lazily on active tab render/key input?**
   - What we know: existing Sysop submodules lazily initialize on key handling for some tabs; Account currently has placeholder state at construction. [VERIFIED: lib/foglet_bbs/tui/screens/sysop.ex; lib/foglet_bbs/tui/screens/account/state.ex]
   - What's unclear: No existing async command pattern is mandated for this specific shared tab. [ASSUMED]
   - Recommendation: Use a synchronous shared action helper in tests unless existing `Command.task` plumbing is needed for responsiveness; the domain calls are simple DB operations. [VERIFIED: .planning/codebase/ARCHITECTURE.md; lib/foglet_bbs/accounts.ex]

## Environment Availability

| Dependency | Required By | Available | Version | Fallback |
|------------|-------------|-----------|---------|----------|
| Elixir | compile/test | yes | 1.19.5 / OTP 28 | none |
| Mix | compile/test/precommit | yes | 1.19.5 | none |
| PostgreSQL client tools | DB readiness checks | yes | `psql` and `pg_isready` found | none |
| PostgreSQL server | `mix test` DB setup | no response on `/tmp:5432` during research | unknown | Start local Postgres before DB tests |

**Missing dependencies with no fallback:**
- Running DB-backed tests requires a reachable PostgreSQL server; `pg_isready` reported no response during research. [VERIFIED: local command output]

**Missing dependencies with fallback:**
- None. [VERIFIED: local command output]

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | ExUnit built into Elixir 1.19.5 [VERIFIED: `elixir --version`; `mix help test`] |
| Config file | `test/test_helper.exs`; Ecto SQL sandbox manual mode [VERIFIED: .planning/codebase/TESTING.md] |
| Quick run command | `mix test test/foglet_bbs/tui/screens/shared/invites_surface_test.exs test/foglet_bbs/tui/screens/account_test.exs test/foglet_bbs/tui/screens/moderation_test.exs test/foglet_bbs/tui/screens/sysop_test.exs` |
| Full suite command | `mix test` |

### Phase Requirements -> Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|--------------|
| INVT-01 | Policy-controlled shared `INVITES` tab across Account, Moderation, Sysop | screen unit/integration | `mix test test/foglet_bbs/tui/screens/account_test.exs test/foglet_bbs/tui/screens/moderation_test.exs test/foglet_bbs/tui/screens/sysop_test.exs` | yes, extend |
| INVT-01 | Live shared rendering of available/consumed/revoked invite rows | shared render unit | `mix test test/foglet_bbs/tui/screens/shared/invites_surface_test.exs` | yes, replace scaffold assertions |
| MODR-04 | Moderator surface generates unlimited invites under `mods` policy | DB-backed screen/action test | `mix test test/foglet_bbs/tui/screens/moderation_test.exs` | yes, extend |
| SYSO-05 | Sysop surface generates unlimited invites under `sysop_only` policy | DB-backed screen/action test | `mix test test/foglet_bbs/tui/screens/sysop_test.exs` | yes, extend |

### Sampling Rate

- **Per task commit:** Run the focused file touched by the task plus `test/foglet_bbs/tui/screens/shared/invites_surface_test.exs`. [VERIFIED: .planning/codebase/TESTING.md]
- **Per wave merge:** Run Account, Moderation, Sysop, shared invites, shell visibility, and accounts invite tests. [VERIFIED: local test file inventory]
- **Phase gate:** Run `mix precommit`. [VERIFIED: CLAUDE.md; mix.exs]

### Wave 0 Gaps

- [ ] `test/foglet_bbs/tui/screens/shared/invites_actions_test.exs` -- covers shared load/generate/revoke/error behavior if a new action module is added. [VERIFIED: 04-SPEC.md]
- [ ] Extend `test/foglet_bbs/tui/screens/shared/invites_surface_test.exs` -- replace scaffold expectations with live row/status/error/key-hint expectations. [VERIFIED: existing test file]
- [ ] Extend `test/foglet_bbs/tui/screens/account_test.exs`, `moderation_test.exs`, and `sysop_test.exs` -- policy matrix and thin delegation checks. [VERIFIED: local test file inventory]

## Security Domain

### Applicable ASVS Categories

| ASVS Category | Applies | Standard Control |
|---------------|---------|------------------|
| V2 Authentication | no new auth | Existing current_user/session context only; no auth changes. [VERIFIED: 04-SPEC.md] |
| V3 Session Management | no new session behavior | Existing TUI App/session state only. [VERIFIED: .planning/codebase/ARCHITECTURE.md] |
| V4 Access Control | yes | `Foglet.Accounts` APIs with Bodyguard; UI visibility is advisory. [VERIFIED: lib/foglet_bbs/accounts.ex; 04-CONTEXT.md] |
| V5 Input Validation | yes | Use existing invite code/domain validation; do not accept arbitrary local revoke payloads outside selected row/code string. [VERIFIED: lib/foglet_bbs/accounts.ex] |
| V6 Cryptography | yes, indirectly | `Accounts.create_invite/1` owns secure code generation; TUI must not generate codes. [VERIFIED: lib/foglet_bbs/accounts.ex; 03-VERIFICATION.md] |

### Known Threat Patterns for This Stack

| Pattern | STRIDE | Standard Mitigation |
|---------|--------|---------------------|
| Elevation via hidden-tab bypass | Elevation of privilege | Re-check domain authorization in `Accounts`; never trust tab visibility. [VERIFIED: 04-CONTEXT.md; lib/foglet_bbs/accounts.ex] |
| Tampering via stale runtime policy in tab state | Tampering | Recompute/rebuild tab labels when visibility changes, and keep domain checks authoritative. [VERIFIED: lib/foglet_bbs/tui/screens/account/state.ex; 04-SPEC.md] |
| Information disclosure through over-broad invite list | Information disclosure | Use existing `Accounts.list_invites/1` behavior; do not add raw Repo queries. [VERIFIED: lib/foglet_bbs/accounts.ex] |
| Spoofed success after failed revoke | Tampering | Preserve local rows on error and surface distinct error messages. [VERIFIED: 04-CONTEXT.md] |

## Sources

### Primary (HIGH confidence)
- `04-CONTEXT.md` - locked implementation decisions and source seams.
- `04-SPEC.md` - locked requirements, boundaries, and acceptance criteria.
- `.planning/REQUIREMENTS.md` - INVT-01, MODR-04, SYSO-05.
- `.planning/ROADMAP.md` - Phase 4 goal and success criteria.
- `.planning/phases/03-invite-persistence-and-registration-enforcement/03-VERIFICATION.md` - verified existing invite domain APIs.
- `docs/ARCHITECTURE.md` and `.planning/codebase/ARCHITECTURE.md` - layer boundaries and data flow.
- `lib/foglet_bbs/accounts.ex` - invite API behavior and tagged errors.
- `lib/foglet_bbs/tui/screens/shared/invites_surface.ex`, `invites_state.ex`, `shell_visibility.ex` - current shared surface and visibility seams.
- `lib/foglet_bbs/tui/widgets/README.md`, `SelectionList`, `ListRow`, `Tabs` - local widget contracts.
- `mix.exs` and `mix.lock` - dependency and precommit stack.

### Secondary (MEDIUM confidence)
- `docs/raxol/README.md` and `docs/raxol/getting-started/WIDGET_GALLERY.md` - vendored Raxol component orientation.
- `mix help test` - current Mix test task behavior and options.

### Tertiary (LOW confidence)
- None.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - verified from `mix.exs`, `mix.lock`, and local tool versions.
- Architecture: HIGH - verified from locked context/spec, architecture docs, and current modules.
- Pitfalls: MEDIUM - most pitfalls are verified from current code; two failure-mode claims are explicitly assumed and logged.

**Research date:** 2026-04-23
**Valid until:** 2026-05-23 for local codebase architecture; re-check dependency versions if changing `mix.exs`.
