# Phase 28: modal-form-substrate - Context

**Gathered:** 2026-04-27 (assumptions mode)
**Status:** Ready for planning

<domain>
## Phase Boundary

Phase 28 locks `Foglet.TUI.Widgets.Modal.Form` as the single shared form
substrate for every form-bearing TUI screen (Account Profile, Account
Preferences, and Sysop Site). The substrate gains: `Up`/`Down` inter-field
focus on text/integer/textarea fields (enum cycling preserved), `:backtab`
≡ `:shift_tab`, configurable footer (default off), single-source-of-truth
focus routing, an explicit `submit_state` machine with input lock during
`:submitting`, and an honest-Esc cancel path. Sysop Site (`SiteForm`) is
migrated onto Modal.Form in this phase. Sysop tab lifecycle, draft echo, and
Account workflow fixes belong to Phases 29 and 30.
</domain>

<decisions>
## Implementation Decisions

### Submit-State Machine

- **D-01:** `Modal.Form` struct gains a `submit_state` field initialised to
  `:idle`. Allowed values: `:idle | :submitting | :saved | {:error, term}`.
- **D-02:** A first-clause guard `handle_event(_event, %{submit_state:
  :submitting} = state)` swallows every event (Tab, Shift+Tab, `:backtab`,
  Up, Down, char, backspace, Enter, Esc) and returns `{state, nil}` until
  the consuming screen explicitly transitions out via the public setter.
- **D-03:** Public setter is `Modal.Form.set_submit_state(form,
  new_state)`. It accepts only `:idle | :saved | {:error, term}` from
  callers — the `:submitting` transition is reserved for the internal
  Enter-on-last clause and is rejected if requested externally.
- **D-04:** `:saved` and `{:error, _}` auto-reset to `:idle` on the next
  user event after the lock-clause check (see D-02). Screens do not need
  to call a reset; the next non-locked keystroke clears the terminal-state
  badge so the form is editable again.
- **D-05:** `Modal.Form.handle_event(%{key: :enter}, ...)` on the last
  field transitions `:idle → :submitting`, invokes `on_submit` exactly
  once, and returns `{state, :submitted}`. Existing
  `Modal.Form.SubmitStash` capture remains the payload-handoff mechanism
  for consuming screens.

### Footer Opt-In

- **D-06:** `Modal.Form.init/1` accepts `:show_footer` (boolean, default
  `false`). The default-off setting suppresses the
  `[Enter] Submit / [Esc] Cancel` row on `ProfileForm`, `PrefsForm`, and
  `SiteForm`. `App.render_modal_overlay/2` opts in for true overlay use
  by passing `show_footer: true` at form construction.
- **D-07:** The footer option is set at `init/1`, not `render/2`. Forms
  re-initialised per render (e.g. SiteForm's pattern at site_form.ex:316)
  pass `show_footer: false` at every re-init.

### In-Flight Status Row

- **D-08:** When `submit_state == :submitting`, `render/2` always emits a
  status row reading `Saving…` (theme `dim.fg`) as the form's last row,
  regardless of `:show_footer`. When `submit_state == :saved`, the row
  reads `Saved.` for one render cycle (auto-clears on next event per
  D-04). When `{:error, msg}`, the row reads `Error: <msg>` in
  `theme.error.fg`.
- **D-09:** The status row replaces (does not duplicate) the footer when
  both would render. Layout math at 64×22 stays unchanged versus pre-D-06.

### Honest Esc — No Flash

- **D-10:** Esc fires `on_cancel`; the consuming screen reseeds drafts to
  the saved values. **No "Changes discarded." status row is rendered.**
  The visible signal that Esc did something is the field values
  themselves reverting on the next render. This drops the "flash row"
  affordance and amends SPEC FORM-06 acceptance criterion (b) — see the
  Specifics section.
- **D-11:** `Foglet.TUI.Screens.Account.ProfileForm` and
  `PrefsForm` have their existing `status_message: "Profile changes
  discarded."` (and equivalent for Prefs) **removed** as part of this
  phase. Tests asserting that copy update to assert field reversion only.
- **D-12:** `SiteForm` does not gain a `status_message` field. Esc on
  Sysop Site reseeds drafts via `Foglet.Config.get!/1` and triggers a
  redraw — no inline copy.

### Up/Down Focus Movement

- **D-13:** `Modal.Form.handle_event/2` gains `%{key: :up}` and
  `%{key: :down}` clauses placed before the catch-all dispatch clause.
  They inspect `Enum.at(state.fields, state.focus_index).type`:
  - `:enum` → fall through to `dispatch_to_field/3` (preserves cycling).
  - `:text | :integer | :textarea` → advance/retreat `focus_index` with
    wrap matching Tab/Shift+Tab (last → 0 forward, 0 → last backward).
- **D-14:** Wrap direction is locked and documented in
  `Modal.Form.@moduledoc`: forward (Tab/Down) wraps last → 0; backward
  (Shift+Tab/`:backtab`/Up) wraps 0 → last.

### `:backtab` Acceptance

- **D-15:** Add a single `handle_event(%{key: :backtab}, state)` clause
  adjacent to the existing `:shift_tab` clause (form.ex:119), with
  identical body. `@moduledoc` documents `:backtab` ≡ `:shift_tab` ≡
  `%{key: :tab, shift: true}`.

### Single-Source-of-Truth Focus

- **D-16:** No leaf widget code changes are required. `TextInput` accepts
  `focused?` as a render keyword only; its struct (`[:raxol_state,
  :validator, :on_submit, last_action: nil]`) carries no focus field.
  `RadioGroup` and `Checkbox` are stateless render-only modules with no
  defstruct. The "remove widget-internal focus state" Boundaries item is
  verified by a grep test asserting no `:focused` / `:focus_index` /
  `focused?` field on any leaf input widget defstruct.

### SiteForm Migration

- **D-17:** `Foglet.TUI.Screens.Sysop.SiteForm` is restructured as a thin
  wrapper module structurally analogous to `ProfileForm`/`PrefsForm`. A
  sibling `state.ex` (`Foglet.TUI.Screens.Sysop.SiteForm.State`) holds
  the bespoke struct (`current_user`, `drafts`, `errors`, `focused`).
  The `Modal.Form` instance is built fresh per render — matching the
  existing "re-init on change" pattern documented at site_form.ex:316.
- **D-18:** SiteForm's bespoke "▸ key: value" + description-line render
  is **dropped** in favor of Modal.Form's standard rendering. Field
  labels and descriptions are sourced from
  `Foglet.Config.Schema.fetch_spec/1`. Tests asserting on the bespoke
  format are rewritten to assert on Modal.Form's rendering.
- **D-19:** SiteForm's existing `Ctrl+S` submit shortcut is **preserved**
  but moved to the screen-level event handler (same level as
  ProfileForm's submit callback). The shortcut routes to the same
  validate → `Foglet.Config.put/3` → `SubmitStash` path that Enter-on-
  last-field uses.
- **D-20:** SiteForm's `validate_delivery_verification_pair/1`
  pre-flight check runs inside the `on_submit` callback, before any
  `Foglet.Config.put/3` call. Validation failures call
  `Modal.Form.set_errors/2` and transition `submit_state` back to
  `:idle` (or directly to `{:error, msg}`) without invoking the boundary.
- **D-21:** Conditional visibility — `invite_generation_per_user_limit`
  hidden unless `invite_code_generators == "any_user"` — is preserved.
  The visible-keys filter runs inside the screen wrapper's render path
  before constructing the per-render Modal.Form `:fields` list.

### Folded Todos

None — `gsd-sdk query todo.match-phase 28` returned 0 matches.
</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase Definition
- `.planning/phases/28-modal-form-substrate/28-SPEC.md` — Locked
  requirements (FORM-01..FORM-06), boundaries, constraints, acceptance
  criteria, and interview decisions for Phase 28.
- `.planning/ROADMAP.md` — v1.4 phase sequencing, Phase 28 success
  criteria, and dependencies (Phases 26, 27).
- `.planning/REQUIREMENTS.md` — FORM-01..FORM-06 traceability.
- `.planning/PROJECT.md` — SSH/TUI-first product boundary, v1.4
  milestone scope, terminal-size constraints, Modal.Form theming
  routing rules.

### TUI Substrate Source
- `lib/foglet_bbs/tui/widgets/modal/form.ex` — Current Modal.Form
  implementation. Phase 28 modifies handle_event/2 clauses, init/1
  options, render/2, struct fields.
- `lib/foglet_bbs/tui/widgets/modal/form/submit_stash.ex` — Existing
  payload capture pattern; preserved as the on_submit handoff mechanism.
- `lib/foglet_bbs/tui/widgets/input/text_input.ex` — TextInput render
  contract (focused? keyword, no struct focus field).
- `lib/foglet_bbs/tui/widgets/input/radio_group.ex` — Stateless
  RadioGroup render.
- `lib/foglet_bbs/tui/widgets/input/checkbox.ex` — Stateless Checkbox
  render.

### Consuming Screens
- `lib/foglet_bbs/tui/screens/account/profile_form.ex` — Reference
  Modal.Form consumer. ProfileForm's status_message removal lands here.
- `lib/foglet_bbs/tui/screens/account/prefs_form.ex` — Reference
  Modal.Form consumer with enum cycling and theme preview.
- `lib/foglet_bbs/tui/screens/account/state.ex` — Account screen state;
  `status_message` field referenced for D-11 cleanup.
- `lib/foglet_bbs/tui/screens/sysop/site_form.ex` — Migration target.
  Becomes a thin Modal.Form wrapper plus sibling `state.ex`.
- `lib/foglet_bbs/tui/app.ex` — `render_modal_overlay/2` (app.ex:187, 197)
  is the opt-in caller for `:show_footer`.

### Conventions
- `lib/foglet_bbs/tui/widgets/README.md` — Foglet widget catalog,
  theme-routing requirements, and stateful/stateless widget contracts.
- `docs/raxol/getting-started/WIDGET_GALLERY.md` — Raxol primitive
  reference.
- `AGENTS.md` — TUI/Modal.Form section: focus state ownership rules,
  render purity, theme routing, screen vs widget boundaries.
</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `Foglet.TUI.Widgets.Modal.Form` — Already exposes `init/1`,
  `handle_event/2`, `render/2`, `field_value/2`, `set_errors/2`. Phase
  28 extends this surface minimally with `set_submit_state/2`, a
  `:show_footer` init option, and one new struct field (`submit_state`).
- `Foglet.TUI.Widgets.Modal.Form.SubmitStash` — Existing per-process
  payload stash; preserved verbatim. SiteForm's migrated `on_submit`
  uses the same `stash`/`pop` pattern as ProfileForm/PrefsForm.
- `Foglet.Config.Schema.fetch_spec/1` — Existing schema lookup feeds
  Modal.Form `:fields` for SiteForm. Field type, label, description,
  and enum choices are already on the spec.
- `Foglet.Config.put/3` — Existing actor-aware writer; preserved as
  SiteForm's boundary call inside `on_submit`.
- `Foglet.TUI.Theme` — Existing slot map (`title.fg`, `accent.fg`,
  `primary.fg`, `dim.fg`, `error.fg`, `border.fg`); status row colors
  route through these per D-07/D-09 of v1.3.

### Established Patterns
- Modal.Form clauses are written in dispatch order with named
  comments (Clause 1: Esc / Clause 2: Shift-Tab / etc.). New clauses
  (`:up`, `:down`, `:backtab`, the `:submitting` lock guard) follow the
  same convention.
- The `:shift_tab` and `%{key: :tab, shift: true}` clauses are
  intentionally adjacent (form.ex:107-123) with a comment explaining
  CLIHandler key translation. The new `:backtab` clause sits adjacent
  to those for the same reason.
- ProfileForm/PrefsForm pass the Modal.Form struct as `state.profile_form`
  / `state.prefs_form` and route key events through the screen's
  `handle_key/3`. SiteForm's wrapper follows this shape.
- Stateful widgets implementing the D-14 contract own their own state;
  leaf input widgets render with explicit `focused?` parameters.
- Forms re-init their Modal.Form per render when the field list is
  conditional (SiteForm's pattern at site_form.ex:316). This keeps the
  bespoke screen state as the source of truth and avoids stateful
  re-sync logic.

### Integration Points
- `Foglet.TUI.App.render_modal_overlay/2` (app.ex:187, 197) is the
  single caller that opts into `show_footer: true`.
- Account screens consume Modal.Form inline (no overlay chrome) — the
  default `show_footer: false` matches their command-bar advertised
  Enter/Esc keybinds, eliminating duplicate footer copy.
- SiteForm is reached through the Sysop screen's tab lifecycle. Phase
  29 wires the Sysop tab `Foglet.TUI.Command` load path; Phase 28's
  SiteForm migration is functionally complete inside the existing
  Sysop Site tab body.

### Tests
- `test/foglet_bbs/tui/widgets/modal/form_test.exs` is the unit-test
  home for Modal.Form clauses (Up/Down focus, `:backtab`, lock guard,
  submit-state transitions, `:show_footer` rendering, status row).
- `test/foglet_bbs/tui/screens/account/profile_form_test.exs` and
  `prefs_form_test.exs` cover existing consuming-screen integration;
  these update for D-11 status_message removal.
- A new `test/foglet_bbs/tui/screens/sysop/site_form_test.exs` (or
  rewritten existing) covers SiteForm-on-Modal.Form behavior.
- `test/foglet_bbs/tui/layout_smoke_test.exs` patterns guard 64×22 /
  80×24 layout. Add coverage that asserts no duplicate footer on
  Account / Sysop Site at both sizes.
- A grep test asserts no leaf input widget defstruct carries a focus
  field (D-16).
</code_context>

<specifics>
## Specific Ideas

### SPEC FORM-06 amendment (locked here, captured for SPEC update)

Phase 28 intentionally drops the visible "Changes discarded." status row
on Esc. The user's directive: the field values themselves reverting on
the next render is the sufficient visible signal — an explicit copy row
adds chrome noise on Account screens and conflicts with the milestone's
duplicate-footer cleanup intent.

This requires amending SPEC FORM-06 acceptance criterion (b) — currently
"a status row containing the discard copy is present in the next render"
— to either drop the criterion or restate it as "the field's rendered
value reflects the saved value (no draft echo)." Criterion (a) — "the
field's underlying draft equals the saved value" — stands.

Planner: Treat D-10..D-12 as the locked behavior contract. SPEC text
should be updated when next touched; do not block on the SPEC text.

### SubmitStash is preserved

D-05 explicitly preserves `Foglet.TUI.Widgets.Modal.Form.SubmitStash` as
the payload-handoff mechanism. The submit-state machine layers on top
of (not replaces) the existing stash/pop pattern. Consumers using
SubmitStash today (ProfileForm, PrefsForm) need no callback changes —
they only update if they want to react to the new `:saved` /
`{:error, _}` terminal states.

### Wrap direction documentation (locked)

Forward (Tab, Down on non-enum): last → 0.
Backward (Shift+Tab, `:backtab`, Up on non-enum): 0 → last.
Documented in `Modal.Form.@moduledoc`. This is a confirmation, not a
renegotiation, of the existing Tab/Shift+Tab behavior.
</specifics>

<deferred>
## Deferred Ideas

### Out of scope (per SPEC Boundaries)
- Sysop Site editability lifecycle, draft echo, Config persistence
  errors-to-copy, and `[R] Retry` keybind — Phase 29 (`SYSOP-03`).
- Sysop Site field subtitle copy / REQ-ID scrubbing — Phase 29
  (`SYSOP-04`).
- Account Profile persistence + Saved flash — Phase 30 (`ACCT-01`).
- Account Preferences widget reachability, IANA timezone selector,
  multi-line SSH key paste — Phase 30 (`ACCT-03`/`-04`/`-05`).
- TextInput cursor rendering — Phase 27 (`CURSOR-01`, complete).
- Composer soft-wrap, Boards Enter toggling — Phase 33.
- True modal overlay confirmation dialogs (new product surfaces) —
  out of scope; only the configurable-footer opt-in path is delivered.
- Real timer-driven flash window (e.g. `Process.send_after/3` with a
  ~2s clear) — superseded by D-10 (no flash) and out of scope either
  way.

### Reviewed Todos (not folded)

None — todo matcher returned 0.
</deferred>
