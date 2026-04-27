# Phase 28: Modal.Form Substrate — Specification

**Created:** 2026-04-27
**Ambiguity score:** 0.11 (gate: ≤ 0.20)
**Requirements:** 6 locked

## Goal

`Foglet.TUI.Widgets.Modal.Form` becomes the single shared form substrate for every form-bearing TUI screen (Account Profile, Account Preferences, and Sysop Site): keystrokes route deterministically to the focused field, navigation accepts `Tab` / `Shift+Tab` / `:backtab` / `Up` / `Down` / `Esc` / `Enter`, double-Enter cannot invoke a boundary call twice, and `Esc` honors its advertised cancel hint visibly.

## Background

`Foglet.TUI.Widgets.Modal.Form` already exists as a stateful widget exposing `init/1 + handle_event/2 + render/2` (D-14). Its `handle_event/2` clauses today recognize `:escape`, `:tab`, `%{key: :tab, shift: true}`, `:shift_tab`, and `:enter`; everything else dispatches to the focused field via `dispatch_to_field/3`. It exposes a `focus_index`, per-field `field_states`, an `errors` map, and `on_submit`/`on_cancel` callbacks; submit payloads are captured out-of-band through `Foglet.TUI.Widgets.Modal.Form.SubmitStash`.

The widget renders inline inside two consuming tabs today — `Foglet.TUI.Screens.Account.ProfileForm` and `Foglet.TUI.Screens.Account.PrefsForm` — and is also wired through `Foglet.TUI.App.render_modal_overlay/2` for true overlay use. `Foglet.TUI.Screens.Sysop.SiteForm` is the only tab-body form not yet on Modal.Form: it carries its own `handle_key/2`, its own `focused` index, and its own draft store, and it already handles `:tab`, `:shift_tab`, and `:backtab` while Modal.Form does not handle `:backtab`.

Today's gaps relative to v1.4 verification:

- `Up`/`Down` on a text field is dispatched into `TextInput.handle_event/2` (no-op for cursor) instead of moving focus between fields. Only `:enum` fields use `Up`/`Down` — and they cycle values, not focus.
- `Modal.Form` has no `:backtab` clause, so the SiteForm convention (`:backtab` ≡ Shift+Tab) is not portable.
- `Modal.Form.render/2` always emits `text("[Enter] Submit   [Esc] Cancel", ...)` as its last row. On Account and Sysop, the global command bar already advertises the same hints, producing duplicate footer copy.
- There is no `submit_state` field; `on_submit` is invoked synchronously inside `handle_event(%{key: :enter}, ...)` with no re-entry guard, so a second Enter (or an Enter while a redraw is mid-flight) calls the boundary again.
- `on_cancel` exists but consuming screens do not always honor it visibly: Sysop Site (which does not use Modal.Form) has an `[Esc] Cancel` hint in its command bar that does not produce a visible draft-discard signal.

This phase locks the substrate so every Account and Sysop edit fix downstream (Phase 29 Sysop Site editability lifecycle, Phase 30 Account Workflow) can be built on a single, verified form contract.

## Requirements

1. **Up/Down inter-field focus on text/integer/textarea fields, enum cycling preserved**: Modal.Form treats `Up`/`Down` as focus movement on non-enum fields and as value cycling on enum fields.
   - Current: `Modal.Form.handle_event/2` has no `:up`/`:down` clauses; events fall through to `dispatch_to_field/3`. `TextInput.handle_event/2` ignores them; `:enum` fields cycle their index. Net effect: `Up`/`Down` on a focused text field is a no-op for focus.
   - Target: With the form focused on a `:text` / `:integer` / `:textarea` field, `Down` advances `focus_index` by 1 (with wrap) and `Up` retreats by 1 (with wrap). On an `:enum` field, `Up`/`Down` continue to cycle the field value and do not change focus. Wrap direction matches Tab/Shift+Tab (last → 0 / 0 → last).
   - Acceptance: A unit/integration test with a `[text, text, enum]` form starting on field 0 asserts that one `Down` event moves `focus_index` to 1; another `Down` moves it to 2 (the enum); subsequent `Up`/`Down` events on the enum mutate `field_states` but leave `focus_index` at 2.

2. **`:backtab` accepted as Shift+Tab equivalent**: Modal.Form treats `:backtab` identically to `:shift_tab` and `%{key: :tab, shift: true}`.
   - Current: `Modal.Form.handle_event/2` has clauses for `%{key: :tab, shift: true}` and `%{key: :shift_tab}` only; `%{key: :backtab}` falls through to per-field dispatch. `Foglet.TUI.Screens.Sysop.SiteForm.handle_key/2` already accepts `:backtab` directly, so the convention exists in the codebase but is not portable.
   - Target: A `%{key: :backtab}` event produces the same focus retreat (with wrap) as `%{key: :shift_tab}`. Modal.Form's `@moduledoc` documents `:backtab`, `:shift_tab`, and `%{key: :tab, shift: true}` as equivalent.
   - Acceptance: A unit test on Modal.Form starting at `focus_index: 1` asserts that both `%{key: :shift_tab}` and `%{key: :backtab}` produce `focus_index: 0`; a second event on each reproduces the same final state. Wrap direction is asserted at boundaries (`focus_index: 0` + `:backtab` → last index).

3. **Configurable footer suppressed by default, opt-in for true overlays**: Modal.Form no longer emits the `[Enter] Submit / [Esc] Cancel` footer unconditionally.
   - Current: `Modal.Form.render/2` always appends a footer text row. Account Profile, Account Preferences, and Sysop Site (after migration) all surface duplicate copy because the global command bar already advertises Enter/Esc.
   - Target: Modal.Form takes an `init/1` (or `render/2`) option that controls footer rendering; the default is **off**. True modal overlays invoked via `Foglet.TUI.App.render_modal_overlay/2` opt in. Account Profile/Prefs and Sysop Site render no Modal.Form-side footer.
   - Acceptance: A render test with the default option asserts the rendered output contains no `"[Enter] Submit"` substring; a second render with footer enabled asserts the substring is present. A 64×22 SSH check of Account Profile, Account Preferences, and Sysop Site shows exactly one Enter/Esc hint group (the command bar's), not two.

4. **Single-source-of-truth focus routing**: Keystrokes are routed only to the field at `Modal.Form`'s `focus_index`; switching focus updates the destination of the next keystroke deterministically; leaf widgets carry no parallel focus state.
   - Current: Modal.Form already routes per-field events through `dispatch_to_field/3` based on `focus_index`. Per AGENTS.md, `Foglet.TUI.Widgets.Input.TextInput`, `RadioGroup`, `Checkbox`, and the embedded `MultiLineInput` must not carry their own focus flag — they receive `focused?: bool` from Modal.Form. (Modal.Form itself, as a stateful overlay/substrate widget, owns `focus_index` per D-14.)
   - Target: Modal.Form's `focus_index` is the single source of truth for which field consumes the next keystroke; no leaf input widget exposes or persists a focus flag in its struct. After a `Tab`/`Shift+Tab`/`:backtab`/`Up`/`Down` (on non-enum) event, the next character event lands in the new focused field's buffer.
   - Acceptance: A unit test asserting a `:tab :tab :char "x"` sequence on a `[text, text, text]` form lands `"x"` in the second field's buffer, not the first or any default field. A grep across `lib/foglet_bbs/tui/widgets/input/` asserts no focus-state field on `TextInput`, `RadioGroup`, or `Checkbox` structs.

5. **Submit-state machine prevents double-submit and shows in-flight state**: Modal.Form maintains an explicit `submit_state :: :idle | :submitting | :saved | {:error, term}`; only `:idle` accepts Enter; `:submitting` is visible in the rendered output and locks input.
   - Current: `Modal.Form.handle_event(%{key: :enter}, ...)` invokes `state.on_submit.(payload)` synchronously and returns `{state, :submitted}` with no submit-state field. A second Enter (e.g. fired during a redraw, double-keypress, or held key) re-invokes the callback.
   - Target: The struct gains a `submit_state` field initialised to `:idle`. Enter on the last field while `:idle` transitions to `:submitting`, invokes `on_submit` exactly once, and renders a visible "Saving…" (or equivalent) status row in place of/alongside the Modal.Form footer hint. While `submit_state == :submitting`, all events (`Tab`, `Shift+Tab`, `:backtab`, `Up`, `Down`, `:char`, `:backspace`, `Enter`, `Esc`) are swallowed (no field mutation, no focus change, no callback re-entry). Transition back to `:idle`/`:saved`/`{:error, term}` is driven by the consuming screen via a public setter; `:saved` and `:error` accept input again.
   - Acceptance: A unit test asserts that two `%{key: :enter}` events fired back-to-back on a submittable form invoke `on_submit` exactly once; the form's `submit_state` is `:submitting` after the first event; a `%{key: :char, char: "x"}` event fired while `:submitting` does not mutate any `field_states`. A render test asserts that when `submit_state == :submitting`, the rendered output contains the in-flight status row.

6. **Honest Esc on Account Profile, Account Preferences, and Sysop Site**: `Esc` on each form-bearing tab body produces a visible draft-discard signal that matches the command bar's advertised behavior.
   - Current: Modal.Form fires `on_cancel` on `:escape`. `Foglet.TUI.Screens.Account.ProfileForm` reseeds drafts via `State.seed_from_user/2` and sets `status_message: "Profile changes discarded."`, but `Foglet.TUI.Screens.Sysop.SiteForm` has no `:escape` handler — its command bar `[Esc] Cancel` hint produces no visible effect, and Sysop Site is not yet on Modal.Form.
   - Target: `Esc` on Account Profile, Account Preferences, and Sysop Site (which is migrated onto Modal.Form per the Boundaries In-scope item) reseeds drafts to the saved values and flashes a visible inline status row (e.g. `Changes discarded.` or equivalent honest copy) for approximately 2 seconds. No screen pop or tab unmount is required. Drafts are unchanged after the flash window.
   - Acceptance: An integration/render test for each of Account Profile, Account Preferences, and Sysop Site asserts that after editing a field and pressing `Esc`, (a) the field's underlying draft equals the saved value and (b) a status row containing the discard copy is present in the next render. A 64×22 and 80×24 SSH check of all three screens confirms the flash is visible after `Esc`.

## Boundaries

**In scope:**
- `Foglet.TUI.Widgets.Modal.Form` substrate changes: `Up`/`Down` focus movement (with enum cycling preserved), `:backtab` clause, configurable footer (default off), single-source-of-truth focus routing, `submit_state` machine with input lock during `:submitting`, public setter for `submit_state` transitions out of `:submitting`.
- Migration of `Foglet.TUI.Screens.Sysop.SiteForm` onto Modal.Form: SiteForm becomes a Modal.Form-backed module structurally analogous to `Foglet.TUI.Screens.Account.ProfileForm` / `PrefsForm`; SiteForm's existing `Foglet.Config.put/3` boundary call is preserved as the form's `on_submit` payload handler.
- Removal of widget-internal focus state from leaf input widgets (`TextInput`, `RadioGroup`, `Checkbox`) if present, replaced by the `focused?: bool` parameter pattern Modal.Form already passes.
- Wire-up of honest Esc copy + status flash for Account Profile, Account Preferences, and Sysop Site, gated through Modal.Form's `on_cancel`.
- Test coverage: unit tests for Modal.Form's new event clauses and submit-state transitions; integration/render tests for the three consuming screens; SSH human verification at 64×22 and 80×24 for FORM-03 (no duplicate footer) and FORM-06 (visible Esc flash).
- `@moduledoc` updates documenting `:backtab` ≡ `:shift_tab` ≡ `%{key: :tab, shift: true}`, the wrap direction, and the submit-state contract.

**Out of scope:**
- Sysop Site editability lifecycle, draft echo, and Config persistence per `SYSOP-03` — Phase 29 owns the lifecycle wiring; Phase 28 only locks the substrate Sysop Site rides on.
- Sysop Site field subtitles, copy, or REQ-ID scrubbing per `SYSOP-04` — Phase 29.
- Account Profile persistence + flash row (`ACCT-01`), redundant Profile heading (`ACCT-02`), Preferences widget reachability (`ACCT-03`), IANA timezone selector (`ACCT-04`), multi-line SSH key paste (`ACCT-05`) — Phase 30 owns the Account workflow fixes; Phase 28 verifies only the substrate behaviors below.
- TextInput cursor rendering — Phase 27 owns `CURSOR-01`.
- Composer soft-wrap, Boards Enter toggling — Phase 33.
- Tab wrap direction policy beyond what Modal.Form already does (last → 0 / 0 → last) — locked here as the documented direction; not a renegotiation.
- True modal overlay invocations (e.g. confirmation dialogs not currently in the codebase) — out of scope; only the configurable-footer opt-in path is delivered.
- New authorization scopes, new boundary calls beyond what consuming screens already invoke (`Foglet.Config.put/3`, `Foglet.Accounts.*`).
- Browser-based form workflows or Phoenix endpoints — Foglet remains SSH-first.

## Constraints

- 64×22 remains the hard minimum terminal size; 80×24 remains the compact verification target.
- All Modal.Form colors and styles route through `Foglet.TUI.Theme` slots (D-07/D-09); no hardcoded color literals.
- Modal.Form continues to expose only `init/1`, `handle_event/2`, `render/2`, `field_value/2`, `set_errors/2` plus the new submit-state setter and footer option; no new public API beyond what these requirements need (D-14, D-19 spirit).
- `Modal.Form` body render must remain bare-column body-only (no outer box/border) to preserve compatibility with both inline tab-body use (Account Profile/Prefs, Sysop Site) and `App.render_modal_overlay/2` chrome (Plan 01.1 Pitfall 4).
- `submit_state == :submitting` swallows ALL events (Tab, Shift+Tab, `:backtab`, Up, Down, char, backspace, Enter, Esc) until the consuming screen explicitly transitions `submit_state` to `:idle`, `:saved`, or `{:error, term}`.
- Tab/Shift+Tab/`:backtab`/Up/Down focus wraps deterministically: last field → first on forward; first field → last on backward. Documented in `Modal.Form` `@moduledoc`.
- Phase 28 must not regress existing Modal.Form consumers (Account Profile, Account Preferences) — their `:tab`, `:shift_tab`, `:enter` (advance vs submit), `:escape`, char, and enum cycling behaviors continue to pass after the changes.
- SSH human verification is required for FORM-03 (no duplicate footer) and FORM-06 (visible Esc flash); automated tests cover deterministic substrate behavior.

## Acceptance Criteria

- [ ] `Up`/`Down` on a focused `:text` / `:integer` / `:textarea` field moves `Modal.Form.focus_index` by ±1 with wrap; `Up`/`Down` on a focused `:enum` field cycles the value and does NOT change `focus_index`.
- [ ] `%{key: :backtab}` produces the same focus retreat (with wrap) as `%{key: :shift_tab}` on Modal.Form; both are documented as equivalents in `@moduledoc`.
- [ ] `Modal.Form.render/2` emits no `[Enter] Submit / [Esc] Cancel` footer by default; an opt-in option restores the footer for true overlay use; Account Profile, Account Preferences, and Sysop Site render no Modal.Form-side footer at 64×22 and 80×24.
- [ ] A `:tab :tab :char "x"` sequence on a `[text, text, text]` form lands `"x"` in the second field's buffer; no leaf input widget struct (`TextInput`, `RadioGroup`, `Checkbox`) carries a focus-state field.
- [ ] Two `%{key: :enter}` events fired back-to-back on a submittable form invoke `on_submit` exactly once; `submit_state` is `:submitting` between the first event and the consuming screen's transition call.
- [ ] While `submit_state == :submitting`, no event (`Tab`/`Shift+Tab`/`:backtab`/`Up`/`Down`/`:char`/`:backspace`/`Enter`/`Esc`) mutates `field_states`, `focus_index`, `errors`, or invokes `on_submit`/`on_cancel`.
- [ ] When `submit_state == :submitting`, the rendered output contains a visible in-flight status row (e.g. `Saving…`).
- [ ] Pressing `Esc` on Account Profile, Account Preferences, and Sysop Site reseeds drafts to saved values and produces a visible inline status flash (e.g. `Changes discarded.`) at 64×22 and 80×24 SSH.
- [ ] `Foglet.TUI.Screens.Sysop.SiteForm` is migrated to render and dispatch through `Foglet.TUI.Widgets.Modal.Form`; SiteForm's `Foglet.Config.put/3` boundary call is preserved as the Modal.Form `on_submit` payload handler.
- [ ] `mix precommit` passes (compile with warnings as errors, formatter, Credo, Sobelow, Dialyzer).

## Ambiguity Report

| Dimension          | Score | Min  | Status | Notes                                                  |
|--------------------|-------|------|--------|--------------------------------------------------------|
| Goal Clarity       | 0.95  | 0.75 | ✓      | Substrate scope locked; Sysop Site migration in scope  |
| Boundary Clarity   | 0.88  | 0.70 | ✓      | Phase 29/30/27/33 explicitly carved out                |
| Constraint Clarity | 0.80  | 0.65 | ✓      | Input-lock contract + wrap direction + theme routing   |
| Acceptance Criteria| 0.88  | 0.70 | ✓      | 10 pass/fail criteria                                  |
| **Ambiguity**      | 0.11  | ≤0.20| ✓      |                                                        |

Status: ✓ = met minimum, ⚠ = below minimum (planner treats as assumption)

## Interview Log

| Round | Perspective     | Question summary                                                | Decision locked                                                                 |
|-------|-----------------|-----------------------------------------------------------------|---------------------------------------------------------------------------------|
| 1     | Researcher      | Where does focus state physically live after Phase 28?          | Modal.Form (the overlay/substrate) owns `focus_index` and per-field buffers; leaf widgets carry no focus state |
| 1     | Researcher      | What does `:submitting` look like visually?                     | Footer / status-row swap to "Saving…" (or equivalent); submit hint disappears   |
| 1     | Researcher      | What does "honest Esc" require on Account / Sysop Site?         | Reseed drafts to saved values + visible inline status flash (~2s); no screen pop |
| 2     | Boundary Keeper | Does Sysop Site migrate to Modal.Form in this phase?            | Yes — SiteForm becomes Modal.Form-backed; FORM-01..06 verified at the substrate |
| 2     | Boundary Keeper | What happens to input while `submit_state == :submitting`?      | Lock all events (Tab/Up/Down/char/Esc/Enter swallowed) until terminal state    |
| 2     | Boundary Keeper | Is Tab/Shift+Tab wrap the documented direction?                 | Yes — last → 0 forward, 0 → last backward; documented in `Modal.Form` `@moduledoc` |

---

*Phase: 28-modal-form-substrate*
*Spec created: 2026-04-27*
*Next step: /gsd-discuss-phase 28 — implementation decisions (submit-state public setter shape, status-flash duration constant, SiteForm migration sequencing, etc.)*
