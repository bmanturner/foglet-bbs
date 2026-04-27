# Phase 29: sysop-tab-lifecycle-bodies - Context

**Gathered:** 2026-04-27 (assumptions mode)
**Status:** Ready for planning

<domain>
## Phase Boundary

Phase 29 makes the Sysop screen's BOARDS, LIMITS, SYSTEM, and USERS tabs
auto-load on entry through `Foglet.TUI.Command`, render an honest
`:not_loaded | :loading | {:loaded, struct} | {:error, reason}` lifecycle with
a `[R] Retry` keybind on errors and a distinct "Insufficient role" panel on
`{:error, :forbidden}`, makes Sysop Site editable on top of Phase 28's
Modal.Form substrate (draft echo via Phase 28 D-08, Enter→`Foglet.Config.put/3`,
Esc→reset drafts), rewrites the user-facing copy on `@site_keys` field
descriptions, gates USERS keybinds to per-row valid transitions with named
from→to error copy, surfaces INVITES row focus + `[X] Revoke`, and aligns
`1-N Jump` advertising across Account, Moderation, and Sysop. Phase 29 adds
no new domain code — `Foglet.Config.put/3`, `Foglet.Accounts.transition_user_status/3`,
and `InvitesActions` are reused; one read-only predicate is exposed from
`Foglet.Accounts`.
</domain>

<decisions>
## Implementation Decisions

### Lifecycle Vehicle Wiring (App-level dispatch)

- **D-01:** Sysop's `handle_key/2` returns dispatch tuples in the `commands`
  list (third element of `{:update, new_state, commands}`). The four operations
  are `{:load_sysop_boards}`, `{:load_sysop_limits}`, `{:load_sysop_system}`,
  and `{:load_sysop_users}`. `Foglet.TUI.App.do_update/2` gains matching
  clauses that wrap each operation in `Foglet.TUI.Command.task/2`, capturing
  `state.current_user` and the `domain_module/2` test override hook in the
  closure — modeled directly on the existing
  `{:load_moderation_workspace}` clause at `app.ex:507-527`.
- **D-02:** Each load operation has a paired result tuple
  (`{:sysop_boards_loaded, result}`, `{:sysop_limits_loaded, result}`,
  `{:sysop_system_loaded, result}`, `{:sysop_users_loaded, result}`) where
  `result` is `{:ok, payload}` or `{:error, reason}`. App-side `put_sysop_loading/2`,
  `put_sysop_loaded/3`, and `put_sysop_error/3` helpers update
  `state.screen_state[:sysop]` slots in place, mirroring the
  `put_moderation_loading|snapshot|error` pattern at `app.ex:911-917, 942-952`.
- **D-03:** SITE remains synchronous — `SiteForm.init/1` continues to seed
  drafts via `Foglet.Config.get!/1` (no dispatch tuple, no lifecycle tagging).
  INVITES retains its existing `maybe_load_invites_on_entry/2` path at
  `sysop.ex:220-228` and is NOT migrated onto the tagged enum lifecycle.
- **D-04:** Direct calls to `Raxol.Core.Runtime.Command.task/1` from any
  `Foglet.TUI.Screens.Sysop.*` module are forbidden — verified by a grep
  test. All task wrapping happens in `App.do_update/2`.

### Tab-Switch Trigger Site

- **D-05:** The dispatch trigger fires from inside `Sysop.handle_key/2`'s
  tab-changed branch (after `Tabs.handle_event` at `sysop.ex:172`),
  before returning `{:update, new_state, commands}`. When the new active
  tab's slot is `:not_loaded`, the screen transitions that slot to `:loading`
  and emits the matching dispatch tuple in `commands`.
- **D-06:** A first-entry guard inside `Sysop.init/1` (or a sibling
  `maybe_dispatch_initial_load/1` invoked from `init/1`) checks the active
  tab on screen entry and dispatches if the slot is `:not_loaded`. This
  prevents a "Press any key" race when an operator lands on SYSOP defaulting
  to a lifecycle tab. Idempotent: re-entering an already-`{:loaded, _}` tab
  emits no command.

### Tagged Enum Representation

- **D-07:** `Foglet.TUI.Screens.Sysop.State` slots `:boards_view`, `:limits_form`,
  `:system_snapshot`, and `:users_view` (`state.ex:34-44`) hold the bare tagged
  values `:not_loaded | :loading | {:loaded, struct} | {:error, reason}`. The
  initial value is `:not_loaded` (replacing today's `nil`). The third element
  of `{:loaded, struct}` is the existing submodule struct verbatim
  (`%BoardsView{}`, `%LimitsForm{}`, `%SystemSnapshot{}`, `%UsersView{}`) — no
  new envelope module is introduced.
- **D-08:** `Foglet.TUI.Screens.Sysop.render_tab_body/3` (today at
  `sysop.ex:120-153`) is rewritten to pattern-match on the tag:
  - `:not_loaded` → `:loading` panel (briefly visible during the same render
    cycle that emits the dispatch tuple; should not persist after first App
    update).
  - `:loading` → loading panel.
  - `{:loaded, struct}` → delegates to existing submodule renderer.
  - `{:error, :forbidden}` → "Insufficient role" panel (D-12 below).
  - `{:error, _other}` → generic error panel (D-12 below).
- **D-09:** `delegate_to_submodule/5` (today at `sysop.ex:234-238`) is
  rewritten to require `{:loaded, sub}`. Calls during `:loading` or
  `{:error, _}` states are no-ops (event swallowed, state unchanged) — the
  submodule's `handle_key/2` is never invoked on a non-loaded slot. This is
  what kills "Press any key to load."
- **D-10:** No `nil` value reaches a renderer. A grep test verifies
  `state.ex` declares the four slots with the tagged enum typespec; `nil`
  in a render call is a state-construction error.

### Loading and Error Copy

- **D-11:** Loading panel renders the literal `"Loading…"` (theme `dim.fg`),
  matching `invites_surface.ex:61` and `moderation.ex:218`.
- **D-12:** Generic error panel renders `"Could not load <tab>. Press R to retry."`
  in `theme.error.fg`, where `<tab>` is the active tab name lowercased
  (`"boards"`, `"limits"`, `"system"`, `"users"`). `:forbidden` panel renders
  `"Insufficient role to view this tab."` in `theme.warning.fg`. Plan-phase
  may refine these literals; the contract is honest, distinct, and theme-routed.
- **D-13:** `[R] Retry` is advertised in the Sysop command bar **only when
  the active tab is in `{:error, reason}` with reason ≠ `:forbidden`**.
  Pressing `R` transitions the active tab's slot back to `:loading` and
  re-emits the matching dispatch tuple. If the active tab is in
  `{:error, :forbidden}`, `[R] Retry` is suppressed and `R` is a no-op.
  Errors on non-active tabs do not surface a retry hint until the user
  navigates to them.

### USERS Predicate and From→To Copy

- **D-14:** A new public function `Foglet.Accounts.valid_status_transitions/1`
  takes a status atom (`:pending | :active | :suspended | :rejected`) and
  returns the list of allowed `to` atoms — derived from the existing
  `permit_status_transition/2` clauses at `accounts.ex:187-191`. This is the
  single source of truth shared between `UsersView`'s footer/keybind gating
  and `transition_user_status/3`'s server-side check.
- **D-15:** `Foglet.TUI.Screens.Sysop.UsersView` consults
  `Foglet.Accounts.valid_status_transitions/1` for the focused row's current
  status when rendering its footer/command bar. Only keybinds whose target
  status is in the allowed set are advertised; pressing a non-advertised key
  (`A`, `R`, `S`, or `U`) is a no-op (no `status_message` change, no boundary
  call). Today's static `@footer = "[A] Approve  [R] Reject  [S] Suspend  [U] Reactivate  [j/k] Move"`
  at `users_view.ex:23, 100` becomes a render-time function.
- **D-16:** `error_message(:invalid_transition)` (today at `users_view.ex:213`)
  is replaced by a copy-builder that takes the user's handle, from-status,
  and to-status, returning `"Cannot change @<handle> from <from> to <to>."`.
  Statuses are stringified with `to_string/1` (`"pending"`, `"active"`,
  `"suspended"`, `"rejected"`), mirroring the existing success-message format
  at `users_view.ex:204-208`. Output never contains the substring
  `invalid_transition`.

### Sysop Site Editability (sits on Phase 28 substrate)

- **D-17:** Draft echo is inherited from Phase 28's Modal.Form rendering —
  the focused field renders `field_value/2` from the in-flight Modal.Form
  state, not the saved `Foglet.Config` value. No Phase 29 work needed beyond
  the SiteForm migration delivered by Phase 28 (D-17..D-21).
- **D-18:** Enter persistence: SiteForm's `on_submit` callback (registered
  via Phase 28's wrapper) runs the existing `validate_delivery_verification_pair/1`
  pre-flight (Phase 28 D-20), then calls `Foglet.Config.put/3` for every
  visible key. On all-keys-success, the callback transitions Modal.Form's
  `submit_state` from `:submitting` to `:saved` via
  `Modal.Form.set_submit_state(form, :saved)`. On any failure, transitions
  to `{:error, msg}`.
- **D-19:** Inline confirmation row is satisfied by Phase 28 D-08 — Modal.Form
  emits the literal `Saved.` row in `theme.dim.fg` for one render cycle when
  `submit_state == :saved`. Phase 29 adds no SiteForm-specific confirmation
  copy. Acceptance test asserts the rendered substring is `"Saved."`.

### Sysop Site Esc — Honor Phase 28 D-12 (SPEC amendment locked here)

- **D-20:** **SPEC SYSOP-03 acceptance ("the next render contains a discard
  status row") is amended.** Phase 28 D-10/D-12 is honored verbatim: pressing
  Esc on the Sysop Site tab body reseeds every draft from `Foglet.Config.get!/1`
  via SiteForm's `on_cancel` callback and triggers a redraw — **no inline
  "draft discarded" copy is rendered.** The visible signal is the field values
  themselves reverting on the next render. SiteForm gains no `status_message`
  field. Esc does not pop the tab (per Phase 28's Modal.Form `on_cancel`
  contract).
- **D-21:** SYSOP-03 acceptance is restated for Phase 29 plan-phase as:
  - (a) After Esc, the rendered draft equals the saved `Foglet.Config` value.
  - (b) After Esc, the rendered field values reflect the saved value (no
    draft echo).
  - (c) Esc does not navigate away from the Sysop Site tab.
  - The "discard status row" criterion in the SPEC is dropped. Phase 29
    SPEC text should be updated when next touched; planner does not block
    on the SPEC text.

### Site Field Description Rewrites

- **D-22:** Five descriptions in `lib/foglet_bbs/config/schema.ex` (the
  `@site_keys` set: `registration_mode`, `invite_code_generators`,
  `delivery_mode`, `require_email_verification`,
  `invite_generation_per_user_limit`) are rewritten as short user-facing
  operator copy. Plan-phase locks the literal strings; the contract is that
  each rewritten description passes the regex
  `(D-\d+|REQ-[A-Z]+-\d+|Phase \d+|Pitfall \d+|deliverable)/i` — matches
  zero substrings (case-insensitive).
- **D-23:** Proposed literal copy for plan-phase to refine:
  - `registration_mode` → `"How new accounts are created."`
  - `invite_code_generators` → `"Who can generate invite codes."`
  - `delivery_mode` → `"Whether outbound email is sent."`
  - `require_email_verification` → `"Require email verification before login."`
  - `invite_generation_per_user_limit` → `"Per-user invite cap (0 = unlimited)."`
  Enum value lists are NOT inlined in the description — operators discover
  legal values by cycling with Space (consistent with Modal.Form's enum
  field rendering). Plan-phase may revisit if SiteForm rendering does not
  visibly advertise the cycle affordance.

### INVITES Row Focus + `[X] Revoke`

- **D-24:** Focused INVITES row is rendered using existing
  `theme.selected.fg`/`theme.selected.bg` slots — the same pattern UsersView
  uses at `users_view.ex:131-135`. No new theme slots are added. Plan-phase
  audits whether `ConsoleTable` (today at `invites_surface.ex:83`) renders
  selection visibly at 80×24 SSH; if not, the legacy raw-map render path at
  `invites_surface.ex:112-118` wraps the focused row's cells with
  `text(..., fg: theme.selected.fg, bg: theme.selected.bg)`.
- **D-25:** Pressing Enter on a focused INVITES row whose status is not
  `:revoked` adds an `[X] Revoke` group to the Sysop command bar. Pressing
  `X` dispatches the existing revoke side effect through
  `Foglet.TUI.Screens.Shared.InvitesActions` (today at
  `invites_actions.ex:41-50, 86-88`). Pressing Enter on a `:revoked` row
  does NOT advertise `[X] Revoke`. No commands beyond `[X] Revoke` are added
  in Phase 29 (Resend, Regenerate, Copy code remain out of scope).

### `1-N Jump` Consistency

- **D-26:** A small helper computes the literal `"1-N"` from a tab-count
  integer. Each screen calls it with `length(tab_labels(state))`:
  - **Account** (`account.ex:42-48`, `73`, `178-182`): `@key_bar` module
    attribute is replaced with a render-time function that builds the bar
    list, inserting `{"1-N", "Jump"}` between `{"←/→", "Tab"}` and
    `{"Tab", "Field"}`.
  - **Moderation** (`moderation.ex:44`, `126`): `@key_list` module attribute
    is replaced with a render-time function. The literal `{"1-6", "Jump"}`
    is removed (verified by grep test).
  - **Sysop** (`sysop.ex:61`): existing `jump_hint` `if`-expression is
    refactored to `"1-#{length(State.tab_labels(ss))}"` — same outcome,
    no special-case for INVITES visibility.
- **D-27:** Each screen emits the exact substring `"1-N Jump"` in its
  rendered command bar (chrome formatting per existing patterns). Verified
  at both 64×22 and 80×24 SSH and across INVITES-visible and INVITES-hidden
  actor contexts (Sysop only — Account does not vary, Moderation does).

### Folded Todos

None — `gsd-sdk query todo.match-phase 29` returned 0 matches.
</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase Definition
- `.planning/phases/29-sysop-tab-lifecycle-bodies/29-SPEC.md` — Locked
  Phase 29 requirements (SYSOP-01..07), boundaries, constraints, acceptance
  criteria, ambiguity gate. Note: SYSOP-03 acceptance criterion regarding
  the "discard status row" is amended by D-20/D-21 in this CONTEXT.md.
- `.planning/ROADMAP.md` — v1.4 phase sequencing; Phase 29 success criteria;
  dependencies on Phase 28.
- `.planning/REQUIREMENTS.md` — SYSOP-01..07 traceability and v1.4 milestone
  scope.
- `.planning/PROJECT.md` — SSH/TUI-first product boundary, v1.4 stabilization
  scope, terminal-size constraints, theme routing rules.

### Cross-Phase Substrate
- `.planning/phases/28-modal-form-substrate/28-CONTEXT.md` — Phase 28
  decisions D-01..D-21. Phase 29 sits on top of D-08 (Saved/Error status
  row), D-10..D-12 (no Esc discard copy), D-17..D-21 (SiteForm migration
  shape). **D-08 satisfies SYSOP-03's confirmation row; D-12 amends
  SYSOP-03's discard row.**
- `.planning/phases/28-modal-form-substrate/28-01-PLAN.md` through
  `28-04-PLAN.md` — Phase 28's executable plans; Phase 29 assumes Phase 28
  is shipped (or shipped-up-to-the-substrate-changes-it-needs) before
  Phase 29 execution.

### Sysop Source Modules (modified by Phase 29)
- `lib/foglet_bbs/tui/screens/sysop.ex` — Tab dispatch, `delegate_to_active_tab/3`,
  `delegate_to_submodule/5`, `render_tab_body/3`, `maybe_load_invites_on_entry/2`,
  `jump_hint`, `@key_list`. Specific lines: `:61`, `:120-153`, `:170-192`,
  `:220-228`, `:234-238`.
- `lib/foglet_bbs/tui/screens/sysop/state.ex` — Sysop screen state struct;
  the four lifecycle slots are at `:34-44`. Tagged enum typespec lands here.
- `lib/foglet_bbs/tui/screens/sysop/site_form.ex` — Becomes a thin Modal.Form
  wrapper per Phase 28 D-17..D-21. Phase 29 only refines the `on_submit`
  flow (D-18) and verifies `on_cancel` reseed (D-20). Existing lines:
  `:51-63` (init seed), `:79-98` (handle_key today), `:213-280` (submit
  flow), `:304-336` (render).
- `lib/foglet_bbs/tui/screens/sysop/users_view.ex` — Footer/keybind gating
  per D-15, from→to copy per D-16. Specific lines: `:23, 100` (footer),
  `:60-78` (handle_key), `:204-208` (success_message), `:213` (error_message).
- `lib/foglet_bbs/tui/screens/sysop/boards_view.ex`,
  `lib/foglet_bbs/tui/screens/sysop/limits_form.ex`,
  `lib/foglet_bbs/tui/screens/sysop/system_snapshot.ex` — Existing submodule
  structs become the third element of `{:loaded, struct}`. Their `init/1`
  is the unit of work the new App load operations execute.

### App and Command (modified by Phase 29)
- `lib/foglet_bbs/tui/app.ex` — `do_update/2` gains four sysop-load clauses
  (modeled on `:507-527`). Result-handler clauses for the four
  `{:sysop_*_loaded, _}` tuples land near `:911-917, :942-952`. Helpers
  `put_sysop_loading|loaded|error` at `:1049-1091` style.
  `process_screen_commands/2` at `:1310-1329` is the auto-router (no change
  needed beyond adding the new tuple shapes).
- `lib/foglet_bbs/tui/command.ex` — `task/2` API at `:23-38` is unchanged;
  used by App, never directly by Sysop.

### Domain Boundaries (modified by Phase 29)
- `lib/foglet_bbs/accounts.ex` — Gains `valid_status_transitions/1` per
  D-14. Existing `permit_status_transition/2` at `:187-191` and
  `transition_user_status/3` at `:184, :246-274` are unchanged but
  authoritative.
- `lib/foglet_bbs/config/schema.ex` — Field `description:` strings at
  `:51-124` (the five `@site_keys`) are rewritten per D-22/D-23.

### Shared Surfaces (modified by Phase 29)
- `lib/foglet_bbs/tui/screens/account.ex` — `@key_bar` at `:42-48` →
  render-time function with `1-N Jump` group per D-26. `tab_labels/1` at
  `:178-182` is the source.
- `lib/foglet_bbs/tui/screens/moderation.ex` — `@key_list` at `:44` →
  render-time function per D-26. `Moderation.State.tab_labels/1` is the
  source.
- `lib/foglet_bbs/tui/screens/shared/invites_state.ex`,
  `lib/foglet_bbs/tui/screens/shared/invites_actions.ex`,
  `lib/foglet_bbs/tui/screens/shared/invites_surface.ex` — Row focus and
  Revoke contextual command per D-24/D-25. Existing revoke action at
  `invites_actions.ex:41-50, 86-88`.

### Conventions
- `AGENTS.md` — TUI section: `Foglet.TUI.Command.task/2` is the only
  sanctioned task wrapper; theme-routing requirements; screen-vs-widget
  boundaries; context-as-public-boundary rule (D-14 follows this).
- `lib/foglet_bbs/tui/widgets/README.md` — Theme slots, stateful/stateless
  widget contracts.

### Tests
- `test/foglet_bbs/tui/screens/sysop/` — Existing harness; new tests for
  lifecycle round-trip, retry dispatch, forbidden panel, USERS gating,
  from→to copy, INVITES focus + Revoke land here.
- `test/foglet_bbs/tui/layout_smoke_test.exs` — 64×22 / 80×24 layout guard
  patterns; `1-N Jump` substring assertions and INVITES focus highlight
  assertions follow these.
- `test/foglet_bbs/accounts_test.exs` — `valid_status_transitions/1`
  unit tests live alongside `transition_user_status/3` tests.
</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **App-level dispatch pattern** (`app.ex:507-527, 911-917, 942-952, 1310-1329`):
  Moderation's `{:load_moderation_workspace}` → `Command.task` →
  `{:moderation_workspace_loaded, _}` → `put_moderation_*` is the structural
  twin Phase 29 follows for the four sysop loads.
- **Existing submodule structs** (`%BoardsView{}`, `%LimitsForm{}`,
  `%SystemSnapshot{}`, `%UsersView{}`): become the `{:loaded, struct}`
  payload verbatim — no envelope wrapper, no schema change.
- **Phase 28 Modal.Form substrate** (D-08 Saved row, D-10..D-12 no-discard-copy,
  D-17..D-21 SiteForm wrapper): Sysop Site sits on top — Phase 29 only
  refines `on_submit` and verifies `on_cancel`.
- **`Foglet.Accounts.permit_status_transition/2`** (`accounts.ex:187-191`):
  the four canonical transitions; D-14 exposes a read function over the same
  predicate so UsersView gating cannot drift.
- **`theme.selected.fg`/`theme.selected.bg`** (already in use at
  `users_view.ex:131-135`): no new theme slots needed for INVITES focus.
- **`InvitesActions` revoke path** (`invites_actions.ex:41-50, 86-88`):
  Phase 29 adds the contextual command surface — does NOT add new revoke
  logic.
- **Existing `"Loading…"` literal** (`invites_surface.ex:61`,
  `moderation.ex:218`): reused for the four lifecycle tabs' loading panel.

### Established Patterns
- Sysop already computes `jump_hint` dynamically based on INVITES visibility
  (`sysop.ex:61`); Phase 29 generalises this to `"1-#{length(...)}"` and
  applies the pattern to Account and Moderation.
- Module attributes for command-bar lists (Account `@key_bar`, Moderation
  `@key_list`) are converted to render-time functions to enable dynamic
  Jump hints — the SPEC's grep-test acceptance forces the move.
- Submodule `delegate_to_*` patterns require the slot to be `{:loaded, sub}`
  before invocation; this is the architectural fix that ends "Press any key
  to load" gating.
- AGENTS.md context boundary rule: domain predicates live in `Foglet.*`
  contexts. D-14 places `valid_status_transitions/1` in `Foglet.Accounts`,
  not in `UsersView`.

### Integration Points
- App ↔ Sysop: dispatch tuples flow via `process_screen_commands/2`; result
  tuples flow via `do_update/2` clauses; state mutation flows via
  `put_sysop_*` helpers. No new App-level abstraction; Phase 29 adds clauses
  to existing dispatch and result tables.
- SiteForm ↔ Modal.Form: Phase 28's wrapper layer; Phase 29 only refines
  callbacks. No structural change to the wrapper.
- UsersView ↔ Foglet.Accounts: D-14's new `valid_status_transitions/1`
  function is consulted at render time; the boundary call
  `transition_user_status/3` is unchanged.
- INVITES surface ↔ command bar: Enter on a focused row mutates Sysop's
  command-bar group list; `X` keypress dispatches existing
  `InvitesActions.revoke/1` (no new domain code).

### Tests
- New unit tests for `Foglet.Accounts.valid_status_transitions/1` (D-14).
- New unit tests on `Foglet.TUI.Screens.Sysop.State` for tagged enum
  round-tripping and `nil` rejection (D-10).
- New render-smoke tests at 80×24 for: tab-switch auto-load, retry on
  injected error, forbidden panel + retry suppression, USERS gating with
  focused `:active` row, USERS from→to copy, INVITES focus highlight,
  INVITES Enter→`[X] Revoke`→`X` revoke, `1-N Jump` on Account/Moderation/Sysop
  across INVITES-visible/hidden contexts.
- New grep tests: no `"Press any key"` in `sysop.ex`; no
  `Raxol.Core.Runtime.Command.task` in `Foglet.TUI.Screens.Sysop.*`; no
  `(D-\d+|REQ-[A-Z]+-\d+|Phase \d+|Pitfall \d+|deliverable)/i` in
  `config/schema.ex` `@site_keys` description lines; no `{"1-6", "Jump"}`
  in `moderation.ex` or `account.ex`.
</code_context>

<specifics>
## Specific Ideas

### SPEC SYSOP-03 amendment (locked here, captured for SPEC update)

D-20/D-21 honor Phase 28 D-10/D-12 verbatim and amend SPEC SYSOP-03's
"discard status row" acceptance criterion. The visible signal of Esc on
Sysop Site is field-value reversion on the next render — no inline status
row. SiteForm gains no `status_message` field; Phase 28's `:cancelled`/`:reset`
submit-state is not introduced. Phase 28 CONTEXT.md "Specifics" anticipates
this conflict and explicitly authorises proceeding with D-12 over the SPEC
text. Plan-phase treats D-20/D-21 as the locked behaviour contract.
Updating the SPEC text is non-blocking.

### Saved confirmation row reused from Phase 28 D-08

D-19 explicitly reuses Phase 28 D-08's `Saved.` row. No SiteForm-specific
confirmation copy is added in Phase 29. The acceptance test for SYSOP-03's
"inline confirmation row" asserts the substring `"Saved."` — exactly what
Modal.Form already emits.

### Active-tab-only retry advertising

D-13 locks the interpretation that `[R] Retry` is advertised only when the
*active* tab is in `{:error, _}` (reason ≠ `:forbidden`). Errors on
non-active tabs do not surface a retry hint. This is a deliberate UX
choice: a global retry would let the operator press R while viewing a
healthy SITE and silently reload BOARDS — confusing. SPEC §SYSOP-02 acceptance
tests are written from the active-tab POV and pass under this interpretation.

### `valid_status_transitions/1` lives in Foglet.Accounts

D-14 places the read predicate in the context, not in `UsersView`. AGENTS.md
boundary rule: domain truth lives in `Foglet.*`. This avoids a future drift
bug where `permit_status_transition/2` gains a clause but `UsersView`'s
mirror does not. The cost is a single new public function on `Foglet.Accounts`
— pure, value-only, no scope shape change, no new authorization.
</specifics>

<deferred>
## Deferred Ideas

### Out of scope (per SPEC Boundaries)
- `Foglet.TUI.Screens.Sysop.SiteForm` → `Modal.Form` migration substrate —
  owned by Phase 28 (D-17..D-21).
- New schematized `@site_keys` or new `Foglet.Config.Schema` keys — only
  existing key descriptions are rewritten.
- New status transitions, new role types, or new error atoms in
  `Foglet.Accounts` — Phase 29 only consumes the existing transition surface
  and exposes a read predicate over it.
- INVITES `Resend` / `Regenerate` / `Copy code` / `Show full code` — only
  `[X] Revoke` is added.
- Account Profile / Preferences edits — Phase 30 (`ACCT-01..05`).
- Auth flow, reset-token UX, `:reset_consume` sub-state — Phase 31
  (`AUTH-01..04`).
- Main Menu Navigation/Oneliners chrome — Phase 32 (`MENU-01..05`).
- Composer wrap, Boards expand/collapse — Phase 33 (`POST-02`, `BOARD-01`).
- Webhook notifications, email digests, browser admin — out of v1.4 scope
  per REQUIREMENTS.md (SEED-001, SEED-002 dormant).

### Considered and explicitly rejected
- **Lifecycle envelope struct** (`%Foglet.TUI.Screens.Sysop.Lifecycle{}`):
  rejected in favour of bare tagged values per D-07. Re-evaluate only if
  retry telemetry, staleness tracking, or last-loaded-at metadata becomes
  load-bearing.
- **Global `[R] Retry` advertising** (re-dispatching all error tabs at
  once): rejected per D-13 in favour of active-tab-only advertising.
- **Mirroring `permit_status_transition/2` in `UsersView`**: rejected per
  D-14 in favour of exposing `valid_status_transitions/1` from
  `Foglet.Accounts`.
- **Re-introducing a SiteForm `status_message` field for the Esc discard
  signal**: rejected per D-20/D-21 in favour of honoring Phase 28 D-12.
- **Sysop-specific richer Saved copy** (e.g. `"Saved 5 keys."`): rejected
  per D-19 in favour of reusing Phase 28 D-08's `Saved.`.
- **Inlining enum value lists in field descriptions**: rejected per D-23
  in favour of short single-sentence descriptions; operators discover
  legal values by cycling with Space.
- **Leading `▸` marker on focused INVITES row**: rejected per D-24 in
  favour of existing `theme.selected.*` slots; avoids ConsoleTable column
  reflow.

### Reviewed Todos (not folded)

None — todo matcher returned 0.
</deferred>
</content>
</invoke>