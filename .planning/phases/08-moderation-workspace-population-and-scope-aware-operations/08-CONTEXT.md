# Phase 08: moderation-workspace-population-and-scope-aware-operations - Context

**Gathered:** 2026-04-24 (assumptions mode)
**Status:** Ready for planning

<domain>
## Phase Boundary

Moderators can hide abusive oneliners from the populated Moderation workspace/main-menu moderation affordance, with every visible datum and available action constrained by the current operator's authorized scope. This phase replaces Phase 0 Moderation placeholder tab bodies with real scoped content or honest empty/unavailable states, adds actor-aware oneliner hide behavior with required reasons, persists narrow hide audit records, and renders hide history in the `LOG` tab.

It does not add general report creation/resolution, sanction issuance, user mutation, thread/post moderation actions, board/category lifecycle management, profile navigation, real-time push refresh, or board-scoped moderator assignment UI.
</domain>

<decisions>
## Implementation Decisions

### Domain Surface
- **D-01:** Add or extend `Foglet.Oneliners` / `Foglet.Oneliners.Entry` as the owner of oneliner state, and put the actor-first hide operation there rather than only in the TUI or a broad moderation context.
- **D-02:** The hide operation accepts actor, target oneliner, and required reason; it rejects blank or whitespace-only reasons before persistence and leaves the row unchanged.
- **D-03:** Hidden oneliners are excluded by the domain recent-visible query contract, not by special TUI filtering.

### Authorization and Scope
- **D-04:** Hide and workspace population consume `Foglet.Authorization.scopes_for(actor, action)` as a list, preserving the `:site | {:board, board_id}` contract even though v1.1 currently returns `[:site]` for mods/sysops.
- **D-05:** The hide mutation calls `Bodyguard.permit(Foglet.Authorization, :hide_oneliner, actor, scope)` before side effects and returns `{:error, :forbidden}` with no mutation for unauthorized actors.
- **D-06:** TUI visibility checks remain advisory only. Domain context functions are the trust boundary.

### Moderation Audit Log
- **D-07:** Add a narrow moderation audit path for `:hide_oneliner` only, using a `mod_actions`-backed schema/context such as `Foglet.Moderation.Action`.
- **D-08:** Successful hides insert exactly one audit record with moderator, target kind/id, required reason, timestamp, and enough target metadata for the `LOG` tab to render history.
- **D-09:** Forbidden or invalid hide attempts insert no audit record.
- **D-10:** Do not build the full reports, sanctions, or broad moderation model in this phase.

### Oneliner Selection and Hide UX
- **D-11:** All users can select/focus an oneliner in the main-menu shoutbox/oneliner strip.
- **D-12:** `[Enter]` on a selected oneliner is reserved for future user-profile navigation, but profile navigation is not implemented in this phase.
- **D-13:** Moderators and sysops see an inline operator affordance such as `[H] Hide oneliner` only when the selected oneliner is hideable within their authorized scope.
- **D-14:** `[H]` opens a `Modal.Form`-style required-reason flow.
- **D-15:** Confirming the modal calls the actor-aware domain hide operation.
- **D-16:** After a successful hide, the selected oneliner disappears from the visible strip immediately by refreshing or removing it from loaded oneliner state.
- **D-17:** The shoutbox/oneliner strip does not need to become scrollable in this phase.
- **D-18:** Research should determine the exact Raxol widgets and primitives required for selectable rows, focus styling, inline key hints, and the reason modal.

### Scope-Aware Tab Population
- **D-19:** Keep the fixed base Moderation tabs: `QUEUE`, `LOG`, `USERS`, `SANCTIONS`, `BOARDS`, with conditional shared `INVITES` behavior left intact.
- **D-20:** `QUEUE` is reserved for reports. Because no report workflow exists in v1.1 Phase 8, it should render an honest report-queue empty/unavailable state rather than oneliner moderation items.
- **D-21:** Replace every Phase 8 placeholder body with scoped render state loaded through `Foglet.TUI.App` command/task patterns, not direct database reads inside render functions.
- **D-22:** `LOG` lists oneliner hide audit records newest first within the actor's authorized scopes.
- **D-23:** `USERS` provides read-only user lookup/list context only; no promotion, suspension, deletion, or account-editing actions.
- **D-24:** `SANCTIONS` renders an honest unavailable state because v1.1 has no sanction workflow.
- **D-25:** `BOARDS` renders read-only authorized scope/board context; board/category lifecycle remains sysop workspace scope.
- **D-26:** `QUEUE`, `USERS`, `SANCTIONS`, and `BOARDS` must not expose fake approve, ban, sanction, delete, or board-management commands.

### the agent's Discretion
- Exact module/function names for the moderation audit context/schema, as long as ownership is clear and tests cover persistence.
- Exact selected-oneliner focus styling, copy, and empty-state wording.
- Exact key binding presentation for hide, provided it fits existing TUI key-bar patterns and does not conflict with main-menu navigation.
- Exact refresh message names and app-state shape for oneliner and moderation data.
- Whether the hide reason modal uses an existing shared modal/form primitive directly or a small dedicated wrapper around it.

### Folded Todos
None - `gsd-sdk query todo.match-phase 08` returned 0 matches.
</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase Scope and Requirements
- `.planning/phases/08-moderation-workspace-population-and-scope-aware-operations/08-SPEC.md` - locked Phase 8 requirements, boundaries, constraints, acceptance criteria, and interview log.
- `.planning/ROADMAP.md` - Phase 8 goal, dependencies, and success criteria.
- `.planning/REQUIREMENTS.md` - `MODR-01`, `MODR-02`, `MODR-03`, `MODR-05`, plus v2 `MODR-06`/`MODR-07` boundaries.
- `.planning/PROJECT.md` - terminal-first product direction, authorization constraint, and v1.1 operations-surface goals.

### Prior Decisions
- `.planning/phases/00-screen-shells-and-shared-surface-primitives/00-CONTEXT.md` - fixed Moderation tab shell, role-gated entry, no fake operator actions.
- `.planning/phases/01-authorization-and-scope-backbone/01-CONTEXT.md` - `Foglet.Authorization`, Bodyguard call shape, `scopes_for/2` list contract, and domain trust-boundary rule.
- `.planning/phases/04-shared-invite-surface-activation/04-CONTEXT.md` - conditional shared `INVITES` tab behavior that must remain intact.
- `.planning/phases/07-oneliners-and-main-menu-social-strip/07-CONTEXT.md` - oneliner domain/schema decisions, visible-only recent listing, hidden fields, and main-menu strip constraints.

### Data Model and Architecture
- `docs/DATA_MODEL.md` section 7 - documented `oneliners` schema fields and visible recent index.
- `docs/DATA_MODEL.md` section 10 - documented `mod_actions` schema shape and `:hide_oneliner` audit action.
- `docs/ARCHITECTURE.md` - system architecture and domain/TUI separation.
- `.planning/codebase/ARCHITECTURE.md` - TUI/domain layering, Raxol app ownership, and command task pattern.
- `.planning/codebase/CONVENTIONS.md` - context, schema, changeset, tagged-tuple, authorization, and test conventions.
- `.planning/codebase/STRUCTURE.md` - module layout for contexts, schemas, TUI screens, widgets, and tests.
- `.planning/codebase/TESTING.md` - ExUnit, DataCase, TUI render helper, and deterministic process-test patterns.

### Raxol and TUI References
- `docs/raxol/README.md` - Raxol documentation entry point.
- `docs/raxol/getting-started/WIDGET_GALLERY.md` - available layout and input primitives.
- `lib/foglet_bbs/tui/widgets/README.md` - local themed widget overview.
</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `Foglet.Authorization` - already defines `:hide_oneliner`, permits mods/sysops at site and board scopes, and exposes `scopes_for/2`.
- `Foglet.TUI.Screens.MainMenu` - current main-menu renderer/key handler and oneliner strip integration point from Phase 7.
- `Foglet.TUI.Screens.Moderation` - current shell renders fixed tabs and Phase 8 placeholder copy; this is the Moderation workspace integration point.
- `Foglet.TUI.Screens.Moderation.State` - owns tab state for `QUEUE`, `LOG`, `USERS`, `SANCTIONS`, `BOARDS`, with conditional `INVITES`.
- `Foglet.TUI.Screens.Shared.InvitesSurface` / `InvitesActions` / `InvitesState` - conditional shared tab behavior to preserve.
- `Foglet.TUI.App` - owns screen routing, command-task conversion, app state, modal routing, and async domain reads.
- `Foglet.TUI.Modal` and themed modal/form/input widgets - likely fit the required hide-reason flow.
- `Foglet.Schema` and existing context/schema modules - local pattern for UUID primary keys, utc microsecond timestamps, changesets, and context-owned mutation APIs.

### Established Patterns
- Domain contexts own persistence and return tagged tuples or changesets; TUI code maps those results into visible UI state.
- Actor-aware guarded mutations call `Bodyguard.permit/4` before side effects.
- Programmatically set fields such as actor ids and target ids are assigned by context code, not accepted through untrusted caller attrs.
- Screens render from state already loaded into the TUI app; render functions should not perform database reads.
- Tabs use `Foglet.TUI.Widgets.Input.Tabs`, and active-tab delegation is already used for the shared `INVITES` tab.
- Existing moderation shell defensively checks role visibility in `render/1`; populated content should retain that defensive behavior.

### Integration Points
- Add or extend `lib/foglet_bbs/oneliners.ex` and `lib/foglet_bbs/oneliners/entry.ex` with hide behavior and visible-list exclusion.
- Add a `mod_actions` migration and moderation audit schema/context, likely under `lib/foglet_bbs/moderation/`.
- Extend `lib/foglet_bbs/tui/app.ex` with selected-oneliner state, hide modal handling, hide command dispatch, and refresh behavior.
- Extend `lib/foglet_bbs/tui/screens/main_menu.ex` to render selectable oneliner rows and moderator-only hide affordance.
- Extend `lib/foglet_bbs/tui/screens/moderation.ex` and `lib/foglet_bbs/tui/screens/moderation/state.ex` to render scoped tab data without fake actions.
- Add or extend tests under `test/foglet_bbs/oneliners/`, `test/foglet_bbs/moderation/`, `test/foglet_bbs/tui/screens/main_menu_test.exs`, `test/foglet_bbs/tui/screens/moderation_test.exs`, `test/foglet_bbs/tui/app_test.exs`, and `test/foglet_bbs/tui/layout_smoke_test.exs`.
</code_context>

<specifics>
## Specific Ideas

- Moderator hide UX should happen where the infringing behavior is found: the main-menu shoutbox/oneliner strip.
- All users can select an oneliner; moderators/sysops get an extra `[H] Hide oneliner` affordance when authorized.
- `[Enter]` on selected oneliners should be reserved for later profile navigation.
- Hide requires a moderator-entered reason through a focused modal/form.
- After hide, the oneliner should disappear from the visible strip so it looks like the action worked.
- The shoutbox does not need scrolling in this phase.
</specifics>

<deferred>
## Deferred Ideas

- User-profile navigation from selected oneliners via `[Enter]` - reserved by this phase but implemented later.
- Full report queue creation/resolution - out of scope for v1.1 Phase 8; `QUEUE` remains reserved for reports.
- Sanction issuance/lifting/enforcement - out of scope for v1.1 Phase 8.
- User promotion/demotion/suspension/deletion/account editing from Moderation - out of scope for v1.1 Phase 8.
- Board-scoped moderator assignment UI - v2 scope under `MODR-06`.
- Thread/post moderation actions - outside this phase's oneliner-focused visible mutation.

### Reviewed Todos (not folded)
None reviewed - `gsd-sdk query todo.match-phase 08` returned 0 matches.
</deferred>

---

*Phase: 08-moderation-workspace-population-and-scope-aware-operations*
*Context gathered: 2026-04-24*
