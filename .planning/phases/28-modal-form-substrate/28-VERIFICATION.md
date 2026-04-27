---
phase: 28-modal-form-substrate
verified: 2026-04-27T20:15:00Z
status: human_needed
score: 9/9 must-haves verified
overrides_applied: 0
re_verification:
  previous_status: gaps_found
  previous_score: 6/9
  gaps_closed:
    - "BL-01: Existing Modal.Form consumers do not regress (Account oneliner / hide-oneliner :form modals dismissable after failed submit)"
    - "BL-02: FORM-05 lock prevents double-submit on every form-bearing screen — SiteForm consumer inherits the :submitting lock guarantee"
    - "BL-02 (status-row half): submit_state ≠ :idle ⇒ visible status row across every consuming screen including Sysop Site"
  gaps_remaining: []
  regressions: []
  also_resolved:
    - "BL-03: Modal.Form.init/1 raises ArgumentError on empty :fields (latent rem(_,0) crash eliminated)"
    - "WR-01: Account ProfileForm/PrefsForm handle_key allow-lists accept :backtab"
gaps: []
deferred: []
human_verification:
  - test: "Acceptance Criterion 7: visible Esc behavior at 64×22 and 80×24 SSH on all three form-bearing screens (Account Profile, Account Preferences, Sysop Site)"
    expected: "Pressing Esc after editing a field reseeds the draft to the saved value on the next render; field values visibly revert. Per CONTEXT D-10/D-11/D-12 amendment to SPEC FORM-06, NO 'discarded' status copy should appear (the field-reversion is the visible signal)."
    why_human: "The amendment to FORM-06 acceptance criterion (b) drops the explicit flash row in favor of field-reversion-only signaling. Whether the field reversion is sufficiently visible to a human operator at 64×22 SSH (smallest target) is a UX judgment. Programmatic tests assert state.profile_draft == saved values but cannot assert the SSH-rendered output is sufficiently obvious."
  - test: "Acceptance Criterion 3: no duplicate footer copy at 64×22 and 80×24 SSH on Account Profile, Account Preferences, and Sysop Site"
    expected: "Each screen shows exactly one [Enter]/[Esc] hint group. Account screens show only the global command bar's hint. Sysop Site shows only Modal.Form's footer (D-29: SiteForm.State opts INTO show_footer: true at site_form/state.ex:142 because Sysop's command bar advertises Q/Tabs/Jump but NOT Enter/Esc per Plan 04 SUMMARY)."
    why_human: "Visual count of duplicate hint groups across two terminal sizes — programmatic substring count would catch obvious duplication but not subtle layout/styling issues."
  - test: "BL-01 reproduction in live SSH: oneliner / hide-oneliner modal Esc-after-failed-submit"
    expected: "After driving a doomed oneliner submit (validation failure or :forbidden) and a doomed hide-oneliner submit, pressing Esc dismisses the modal in a real SSH session at 64×22 and 80×24. The modal must NOT wedge."
    why_human: "Validates the user's escape path through CLIHandler with real terminal keystroke translation — programmatic tests now cover the App-level dispatch (account_test.exs:1143+ BL-01 block) but not the full key-translation path."
  - test: "BL-02 reproduction in live SSH: Sysop Site Ctrl+S status row + double-fire prevention"
    expected: "Pressing Ctrl+S on a valid Sysop Site form shows the literal 'Saved.' row briefly and the next keystroke clears it (auto-reset). Holding Ctrl+S or pressing it twice in quick succession invokes Foglet.Config.put exactly once. Setting delivery_mode=no_email + require_email_verification=true and pressing Ctrl+S shows 'Error: validation' and does NOT call Config.put."
    why_human: "End-to-end visual verification of the BL-02 fix in live SSH; programmatic tests cover state.submit_state and rendered-tree string content, but the operator-visible 'Saved.' / 'Error: …' row at 64×22 / 80×24 SSH is a UX judgment."
---

# Phase 28: Modal.Form Substrate — Verification Report (Re-verification)

**Phase Goal:** Modal.Form routes keystrokes to the focused field as a single source of truth, accepts the navigation gestures users expect (Tab/Shift+Tab/`:backtab`/Up/Down/Esc/Enter), and prevents double-submits — unblocking every Account and Sysop edit fix downstream.

**Verified:** 2026-04-27T20:15:00Z
**Status:** human_needed (all programmatic must-haves verified; live SSH spot-checks remain)
**Re-verification:** Yes — after gap closure (plans 28-05, 28-06, 28-07)

## Re-verification Summary

The previous run (2026-04-27T18:39:34Z) found 3 BLOCKER gaps (BL-01, BL-02, BL-03) and 1 WARNING (WR-01). All four have been closed by Wave 1 (28-06 + 28-07) and Wave 2 (28-05) gap-closure plans:

| Gap   | Plan  | Closure Evidence                                                                                                  | Status   |
| ----- | ----- | ----------------------------------------------------------------------------------------------------------------- | -------- |
| BL-01 | 28-05 | `app.ex:1023-1056` — both `put_oneliner_form_errors/2` and `put_hide_oneliner_form_errors/2` chain `set_submit_state({:error, summarize_form_errors(errors)})` after `set_errors/2`. 4 new tests at `account_test.exs:1143+`. | ✓ CLOSED |
| BL-02 | 28-06 | `state.ex:71` adds `submit_state: :idle` to defstruct; `state.ex:104` clears it on Esc reseed; `site_form.ex:70, 95, 119` seed Modal.Form via `Map.put(:submit_state, state.submit_state)`; `site_form.ex:215` persists `form.submit_state` back into SState. 4 new tests at `site_form_test.exs:484+`. | ✓ CLOSED |
| BL-03 | 28-07 | `form.ex:156-159` raises `ArgumentError "Modal.Form requires at least one field; received an empty :fields list"` when fields == []. 1 new test at `form_test.exs:1184+`. | ✓ CLOSED |
| WR-01 | 28-05 | `profile_form.ex:33` and `prefs_form.ex:35` allow-list guards now include `:backtab`. 3 new tests at `account_test.exs:1083+`. | ✓ CLOSED |

No regressions detected. Full suite (`rtk mix test`): **1 property, 1896 tests, 0 failures**.

## Goal Achievement

### Observable Truths (from ROADMAP Success Criteria + SPEC)

| #   | Truth (FORM ID)                                                                                                                                                                            | Status     | Evidence                                                                                                                                                                                                                  |
| --- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ---------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1   | FORM-01: Down moves focus on text fields; Up/Down on enum cycles values without changing focus.                                                                                            | ✓ VERIFIED | Modal.Form.do_handle_event/2 clauses at form.ex:281-303 implement type-branch (text-like → focus_index, else → dispatch_event_to_field). Tests in form_test.exs assert behavior. (Regression check: still passes after Wave 1/2.) |
| 2   | FORM-02: Shift+Tab and `:backtab` retreat focus from field 2 → field 1; wrap deterministic. Account ProfileForm / PrefsForm guards accept `:backtab`.                                      | ✓ VERIFIED | Three byte-equivalent clauses at form.ex:225, 234, 243 for `%{key: :tab, shift: true}` / `:shift_tab` / `:backtab`. Wrap math `rem(focus_index - 1 + n, n)`. Account guards at profile_form.ex:33 and prefs_form.ex:35 now include `:backtab` (WR-01 closure). |
| 3   | FORM-03: Footer suppressed by default; opt-in for true overlays.                                                                                                                           | ✓ VERIFIED | `show_footer: false` default in defstruct (form.ex:120). Conditional at form.ex:411-416. Sysop SiteForm intentionally opts INTO show_footer:true (state.ex:142) per Plan 04.    |
| 4   | FORM-05: Two Enter events back-to-back invoke on_submit exactly once; :submitting visible. Lock survives across consumer rebuild.                                                          | ✓ VERIFIED | Substrate behavior at form.ex:194-196 (lock guard). On SiteForm, the lock now holds across the per-render rebuild because state.ex:71 persists `submit_state` and site_form.ex:70/95/119 re-seed it (BL-02 closure). On `:form` modals, app.ex:1023+ now releases the lock on async failure (BL-01 closure). |
| 5   | FORM-04 routing: `:tab :tab :char "x"` lands x in third field's buffer.                                                                                                                    | ✓ VERIFIED | form.ex:306-308 + form.ex:312-318 dispatches to focused field. Leaf widgets (TextInput, RadioGroup, Checkbox) carry no focus state — `test/foglet_bbs/tui/widgets/input_focus_state_test.exs` asserts at grep level. |
| 6   | FORM-06: Esc on Account Profile, Account Preferences, Sysop Site reseeds drafts to saved values.                                                                                           | ✓ VERIFIED | profile_form.ex / prefs_form.ex (`State.seed_from_user`); site_form.ex:81-84 + state.ex:100-105 (`SState.reseed_drafts` — now also clears submit_state per D-12). Per CONTEXT D-10/D-11/D-12, no flash row — visible signal is field reversion (live SSH check pending in human verification). |
| 7   | Existing Modal.Form consumers (Account oneliner, hide-oneliner :form modals) do not regress.                                                                                               | ✓ VERIFIED | BL-01 closed: `put_oneliner_form_errors/2` (app.ex:1023-1037) and `put_hide_oneliner_form_errors/2` (app.ex:1044-1056) chain `set_submit_state({:error, _})` after `set_errors/2`. The lock releases, the auto-reset preamble collapses to `:idle` on the next event, and `:escape` reaches the cancel clause. 4 regression tests at account_test.exs:1143+. |
| 8   | Status row visible across every consuming screen when submit_state ≠ :idle (D-08/D-09 cross-screen guarantee).                                                                             | ✓ VERIFIED | Substrate at form.ex:423-433 (status row clauses). On SiteForm, `state.ex:71` defstruct field + `site_form.ex:215` sync_back persist `submit_state`; `site_form.ex:70` re-seeds it on render. "Saved." and "Error: validation" tests at site_form_test.exs:520, 545.    |
| 9   | Sysop SiteForm migrated to Modal.Form-backed wrapper structurally analogous to ProfileForm/PrefsForm; Foglet.Config.put/3 boundary preserved.                                              | ✓ VERIFIED | site_form.ex is a thin wrapper delegating to ModalForm.render and ModalForm.handle_event; site_form/state.ex defines the sibling state; Config.put preserved at site_form.ex:167; Ctrl+S preserved at site_form.ex:76-79. submit_state lifecycle now persists on SState (BL-02 closure).   |

**Score:** 9/9 truths verified (3 previously-FAILED truths now closed by gap-closure plans).

### Required Artifacts

| Artifact                                                       | Expected                                                                          | Status      | Details                                                                                                                                                                                                                                  |
| -------------------------------------------------------------- | --------------------------------------------------------------------------------- | ----------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/foglet_bbs/tui/widgets/modal/form.ex`                     | Up/Down clauses, :backtab clause, :show_footer init option, submit_state machine, set_submit_state/2 setter, status row, init/1 empty-fields guard, FORM-05 consumer obligation moduledoc | ✓ VERIFIED  | All required code present. Lock clause at 194-196. Auto-reset at 208-214. Setter at 358-372. Status row at 423-433. show_footer at 120, 411. **BL-03:** init/1 raises on empty fields (lines 156-159). **FORM-05 contract:** moduledoc lines 60-80 carry the literal "MUST drive `set_submit_state/2`" obligation. |
| `lib/foglet_bbs/tui/widgets/modal/form.ex` (description field) | Optional :description rendered as dim row beneath widget                          | ✓ VERIFIED  | render_field/5 at form.ex:593-598 emits dim row when spec carries :description.                                                                                                                                                          |
| `lib/foglet_bbs/tui/screens/account/profile_form.ex`           | Status_message removal on cancel; "discarded" copy gone; :backtab in guard         | ✓ VERIFIED  | Line 33 guard now includes `:backtab` (WR-01 closure). No "discarded" string. seed_from_user reseeds drafts on cancel.                                                                                                                  |
| `lib/foglet_bbs/tui/screens/account/prefs_form.ex`             | Status_message removal on cancel; "discarded" copy gone; :backtab in guard         | ✓ VERIFIED  | Line 35 guard now includes `:backtab` (WR-01 closure). No "discarded" string.                                                                                                                                                            |
| `lib/foglet_bbs/tui/screens/sysop/site_form.ex`                | Modal.Form wrapper; no `▸` glyph; Ctrl+S preserved; Esc reseeds; submit_state preserved across rebuild | ✓ VERIFIED  | Wrapper structure correct. **BL-02 closure:** render/2 (lines 60-73), handle_key/2 catch-all (86-106), submit/1 (110-130) all seed Modal.Form via `Map.put(:submit_state, state.submit_state)`; sync_back/2 (line 206-216) persists `form.submit_state` back to SState.                  |
| `lib/foglet_bbs/tui/screens/sysop/site_form/state.ex`          | Sibling state, build_modal_form/1, visible_keys/1, validate_delivery_verification_pair/1, submit_state field | ✓ VERIFIED  | All present. **BL-02 closure:** defstruct (line 67-71) carries `submit_state: :idle`; `@type t` (line 54-60) types it. reseed_drafts/1 (line 104) clears submit_state per D-12 honest-Esc.                                              |
| `lib/foglet_bbs/tui/app.ex` (`render_modal_overlay` comment + error handlers) | Documenting comment for future :form modal callers; error handlers release FORM-05 lock on async failure | ✓ VERIFIED  | **BL-01 closure:** put_oneliner_form_errors/2 (lines 1023-1037) and put_hide_oneliner_form_errors/2 (lines 1044-1056) chain `set_submit_state({:error, summarize_form_errors(errors)})` after `set_errors/2`. summarize_form_errors/1 helper at lines 1072-1077.                                                                                                                                            |
| `test/foglet_bbs/tui/widgets/modal/form_test.exs`              | Unit tests for FORM-01..05 substrate behaviors + BL-03 init guard                  | ✓ VERIFIED  | 62+ tests; covers backtab, Up/Down focus + enum cycle, show_footer default, lock guard, set_submit_state, auto-reset, status row. New `describe "init/1 input validation (Phase 28 BL-03)"` at line 1184. |
| `test/foglet_bbs/tui/widgets/input_focus_state_test.exs`       | Grep test pinning no leaf-widget focus state                                      | ✓ VERIFIED  | File exists; covers text_input.ex / radio_group.ex / checkbox.ex.                                                                                                                                                              |
| `test/foglet_bbs/tui/screens/sysop/site_form_test.exs`         | Tests for Modal.Form wrapper behavior, Ctrl+S, Esc reseed, validation, visibility, BL-02 lock+status row | ✓ VERIFIED  | New `describe "BL-02: FORM-05 lock + status row persistence on SiteForm"` at line 484 with 4 tests (double Ctrl+S submit_state persistence, "Saved." status row, "Error: validation" status row, auto-reset still collapses to :idle).                       |
| `test/foglet_bbs/tui/screens/account_test.exs`                 | Tests for BL-01 :form modal lock release + WR-01 :backtab                          | ✓ VERIFIED  | New `describe "FORM-02 :backtab on Account ProfileForm / PrefsForm (Phase 28 WR-01)"` at line 1083 (3 tests). New `describe "BL-01 :form modal lock release (Phase 28 FORM-05)"` at line 1143 (4 tests).                                  |

### Key Link Verification

| From                                                | To                                                  | Via                                                   | Status      | Details                                                                                                                                                                                |
| --------------------------------------------------- | --------------------------------------------------- | ----------------------------------------------------- | ----------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Modal.Form.handle_event/2 lock clause               | submit_state guard                                  | head match `%__MODULE__{submit_state: :submitting}`   | ✓ WIRED     | Verified at form.ex:194-196.                                                                                                                                                          |
| Modal.Form.handle_event/2 Enter-on-last             | :idle → :submitting                                 | single on_submit invocation gated on :idle            | ✓ WIRED     | Verified at form.ex:263-274.                                                                                                                                                          |
| Modal.Form.set_submit_state/2                       | consuming screens (:saved / {:error,_})             | public boundary                                       | ✓ WIRED     | Substrate exposes setter (form.ex:358-372). SiteForm calls it at site_form.ex:141, 199 (BL-02 setting); App calls it at app.ex:1034, 1053 (BL-01 setting).                       |
| SiteForm.render/2                                   | Modal.Form.render/2                                 | per-render build_modal_form → Map.put submit_state → ModalForm.render | ✓ WIRED     | site_form.ex:60-73.                                                                                                                                                   |
| SiteForm.handle_key/2                               | Modal.Form.handle_event/2                           | wrapper builds form, seeds submit_state, dispatches event, syncs back | ✓ WIRED     | site_form.ex:86-106 — `submit_state` is now seeded BEFORE dispatch (BL-02 closure) and persisted AFTER dispatch.                                                                                              |
| SiteForm.sync_back/2                                | SState.submit_state persistence                     | %{state | submit_state: ss}                            | ✓ WIRED     | site_form.ex:206-216. The missing half of the FORM-05 contract on this consumer.                                                                                                  |
| Modal.Form on_submit closure (SiteForm)             | Foglet.Config.put/3                                 | validate → coerce → Config.put with current_user      | ✓ WIRED     | site_form/state.ex:144-151 + site_form.ex:167.                                                                                                                                        |
| App.put_oneliner_form_errors/2                      | Modal.Form lock release on error                    | set_errors/2 |> set_submit_state({:error, _})         | ✓ WIRED     | BL-01 closure: app.ex:1023-1037.                                                                                                                                                     |
| App.put_hide_oneliner_form_errors/2                 | Modal.Form lock release on error                    | set_errors/2 |> set_submit_state({:error, _})         | ✓ WIRED     | BL-01 closure: app.ex:1044-1056.                                                                                                                                                     |
| Modal.Form.init/1                                   | ArgumentError on empty :fields                       | guard before defstruct construction                   | ✓ WIRED     | BL-03 closure: form.ex:156-159.                                                                                                                                                      |
| Account ProfileForm/PrefsForm handle_key/2 guards   | Modal.Form.handle_event/2 :backtab clause            | `:backtab` in allow-list                              | ✓ WIRED     | WR-01 closure: profile_form.ex:33, prefs_form.ex:35.                                                                                                                              |

### Data-Flow Trace (Level 4)

| Artifact                                           | Data Variable                            | Source                                                  | Produces Real Data | Status                                                              |
| -------------------------------------------------- | ---------------------------------------- | ------------------------------------------------------- | ------------------ | ------------------------------------------------------------------- |
| Modal.Form.render/2 (status row)                   | `state.submit_state`                     | Mutated by lock-clause / Enter-on-last / set_submit_state / wrapper Map.put seed | ✓ Yes              | ✓ FLOWING                                                           |
| SiteForm.render/2 (delegates to ModalForm.render)  | submit_state of the per-render Modal.Form | `SState.build_modal_form/1` returns :idle, then site_form.ex:70 seeds with `state.submit_state` (BL-02 closure) | ✓ Yes              | ✓ FLOWING — BL-02 root cause closed by Map.put + sync_back round-trip |
| App `:form` modal render path                      | submit_state of stored Modal.Form        | `put_oneliner_form_errors/2` and `put_hide_oneliner_form_errors/2` now drive `set_submit_state({:error, _})` (BL-01 closure) | ✓ Yes              | ✓ FLOWING — BL-01 root cause closed; lock guard releases on async failure |

### Behavioral Spot-Checks

| Behavior                                                     | Command                                                                                                  | Result                                                                          | Status |
| ------------------------------------------------------------ | -------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------- | ------ |
| Modal.Form unit tests pass                                   | `rtk mix test test/foglet_bbs/tui/widgets/modal/form_test.exs`                                           | passes (full suite green)                                                       | ✓ PASS |
| Account screen tests pass                                    | `rtk mix test test/foglet_bbs/tui/screens/account_test.exs`                                              | passes (BL-01 + WR-01 blocks)                                                   | ✓ PASS |
| Sysop SiteForm tests pass                                    | `rtk mix test test/foglet_bbs/tui/screens/sysop/site_form_test.exs`                                      | passes (BL-02 block)                                                            | ✓ PASS |
| Combined targeted run (form + account + site_form)           | `rtk mix test ...`                                                                                       | 152 tests, 0 failures                                                           | ✓ PASS |
| Full suite green                                             | `rtk mix test`                                                                                            | 1 property, 1896 tests, 0 failures                                              | ✓ PASS |
| Double-Enter on SiteForm preserves submit_state              | `rtk mix test test/foglet_bbs/tui/screens/sysop/site_form_test.exs` (BL-02 block test 1)                  | passes — first Enter sets :saved (or :submitting), second Enter is locked       | ✓ PASS |
| "Saved." status row appears on SiteForm after Ctrl+S         | site_form_test.exs:520                                                                                   | passes — substring "Saved." present in rendered tree                             | ✓ PASS |
| "Error: validation" status row appears on SiteForm           | site_form_test.exs:545                                                                                   | passes — substring "Error: validation" present in rendered tree                  | ✓ PASS |
| Doomed oneliner Esc dismisses modal                          | account_test.exs:1143+ (BL-01 block)                                                                     | passes — modal dismisses after `set_submit_state({:error, _})` releases the lock | ✓ PASS |
| Doomed hide-oneliner Esc dismisses modal                     | account_test.exs:1143+ (BL-01 block)                                                                     | passes                                                                          | ✓ PASS |
| `:backtab` on ProfileForm retreats focus                     | account_test.exs:1083+ (WR-01 block)                                                                     | passes                                                                          | ✓ PASS |
| `:backtab` on PrefsForm retreats focus                       | account_test.exs:1083+ (WR-01 block)                                                                     | passes                                                                          | ✓ PASS |
| Modal.Form.init(fields: [], …) raises ArgumentError          | form_test.exs:1184+ (BL-03 block)                                                                        | passes — `assert_raise ArgumentError, ~r/at least one field/`                    | ✓ PASS |

### Requirements Coverage

| Requirement | Source Plan(s)        | Description                                                         | Status                  | Evidence                                                                                                       |
| ----------- | --------------------- | ------------------------------------------------------------------- | ----------------------- | -------------------------------------------------------------------------------------------------------------- |
| FORM-01     | 28-01                 | Up/Down inter-field movement; enum cycle preserved                  | ✓ SATISFIED             | form.ex:281-303 + tests                                                                                        |
| FORM-02     | 28-01, 28-05          | `:backtab` ≡ Shift+Tab; consumer guards accept `:backtab`           | ✓ SATISFIED             | form.ex:243-247 + profile_form.ex:33 + prefs_form.ex:35 + tests at account_test.exs:1083+                       |
| FORM-03     | 28-01                 | Footer configurable, default off                                    | ✓ SATISFIED             | form.ex:120, 411-416 + tests. Sysop SiteForm intentionally opts in (state.ex:142) per Plan 04. |
| FORM-04     | 28-01, 28-04, 28-07   | Single-source-of-truth focus routing; leaf widgets carry no focus state; init/1 guards against empty fields | ✓ SATISFIED             | form.ex:306-308 + form.ex:156-159 (BL-03) + input_focus_state_test.exs                                          |
| FORM-05     | 28-02, 28-04, 28-05, 28-06 | Submit-state machine prevents double-submit, shows in-flight state; consumer obligation documented | ✓ SATISFIED             | Substrate correct; consumer integration verified on Sysop SiteForm (BL-02 closed via 28-06) and Account oneliner :form modals (BL-01 closed via 28-05). Moduledoc states the FORM-05 consumer obligation in grep-checkable form. |
| FORM-06     | 28-03, 28-04          | Honest Esc on Account Profile, Account Preferences, Sysop Site      | ✓ SATISFIED (with human SSH check pending) | profile_form.ex / prefs_form.ex / site_form.ex:81-84 + state.ex:100-105 (Esc also clears submit_state per D-12). Per CONTEXT D-10..D-12 the SPEC criterion (b) flash row was intentionally dropped. |

**Orphan check:** REQUIREMENTS.md maps FORM-01..FORM-06 to Phase 28 only; all six are claimed by at least one plan. No orphans. The gap-closure plans (28-05 declares [FORM-02, FORM-05]; 28-06 declares [FORM-05]; 28-07 declares [FORM-04]) reinforce existing claims.

### Anti-Patterns Found (post gap-closure)

| File                                                  | Line       | Pattern                                                       | Severity | Impact                                                                                                                                                       |
| ----------------------------------------------------- | ---------- | ------------------------------------------------------------- | -------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| lib/foglet_bbs/tui/screens/sysop/site_form.ex         | 152-155    | Defensive `_other` branch in finalize_submit/2 wedges submit_state at `:submitting` if reached | ⚠️ Warning | 28-REVIEW.md WR-01 (gap-closure delta): the `_other` branch passes `new_form` (with `submit_state: :submitting`) into sync_back, which then persists `:submitting` to SState. Unreachable in normal flow (SubmitStash always returns `{:site, {:ok, _}}` or `{:site, {:error, _}}`), but a future caller could trip it. Recommended fix is a one-line `ModalForm.set_submit_state(new_form, :idle)` before sync_back. |
| lib/foglet_bbs/tui/screens/sysop/site_form.ex         | 70, 95, 119 | Direct `Map.put(:submit_state, …)` bypasses `set_submit_state/2`'s `:submitting` guard | ⚠️ Warning | 28-REVIEW.md WR-02 (gap-closure delta): documented and intentional per BL-02 design (the wrapper must replay `:submitting`, which the public setter forbids), but breaks the public-API encapsulation contract. Suggested follow-up: add a `replay_submit_state/2` public escape hatch on Modal.Form. Not a goal-blocking issue. |
| lib/foglet_bbs/tui/widgets/modal/form.ex              | 68, 70     | Stale form.ex line references in moduledoc                    | ℹ️ Info    | 28-REVIEW.md IN-01: cited line ranges (164-166, 233-244, 178-184) are off by ~30 lines after recent edits. Documentation drift; no functional impact.                                                                                  |
| lib/foglet_bbs/tui/app.ex                             | 1069-1077  | summarize_form_errors/1 comment claims "shortest representative" but picks first by key order | ℹ️ Info    | 28-REVIEW.md IN-02: for single-error maps (current usage) this is fine. For multi-error maps the chosen status-row text is first-by-key-order, not shortest. Cosmetic.                                                                  |
| lib/foglet_bbs/tui/widgets/modal/form.ex              | 153-159    | init/1 does not validate `:fields` is a list (only that it is non-empty) | ℹ️ Info    | 28-REVIEW.md IN-03: BL-03 covers the empty-list case; non-list values still crash via `Enum.map`. No production caller passes non-list, but a defensive `is_list/1` guard would close the latent path entirely.                       |

The 6 prior WARNINGs from 28-REVIEW.md (the original review) — WR-02 non-transactional Config.put cascade, WR-03 dead on_cancel callback, WR-04 String.to_existing_atom usage, WR-05 duplicate-name field handling, WR-06 auto-reset/cancel ordering — were carried as `ℹ️ Info` in the prior verification and remain unaddressed. They are documentation/defensive concerns that do not block the phase goal.

### Human Verification Required

See `human_verification:` in frontmatter. Four items:

1. **FORM-06 Esc UX at 64×22 / 80×24 SSH** — verify field reversion alone is a sufficient visible signal across all three form-bearing screens (per amended SPEC FORM-06(b) / CONTEXT D-10..D-12).
2. **FORM-03 duplicate-footer cleanup at 64×22 / 80×24 SSH** — verify each screen shows exactly one [Enter]/[Esc] hint group, including the deliberate Sysop SiteForm opt-in to Modal.Form's footer (state.ex:142).
3. **BL-01 reproduction in live SSH** — verify a doomed oneliner / hide-oneliner submit followed by Esc dismisses the modal in a real SSH client.
4. **BL-02 reproduction in live SSH** — verify Sysop Site Ctrl+S shows "Saved." / "Error: validation" status rows correctly and double-Ctrl+S only invokes Config.put once.

### Gaps Summary

**No gaps remain.** All three blocker gaps from the prior verification (BL-01, BL-02, BL-03) and the watch-item (WR-01) are closed in code and covered by regression tests. Full suite is green (1896 tests, 0 failures).

The only remaining work is human verification of the user-visible UX behavior in live SSH at the two target terminal sizes (64×22 and 80×24). Items 3 and 4 are reproductions of the freshly-fixed BL-01 and BL-02 paths and should be exercised before marking the phase complete on the roadmap.

---

_Verified: 2026-04-27T20:15:00Z_
_Verifier: Claude (gsd-verifier)_
_Re-verification mode: previous gaps_found → human_needed (all programmatic gaps closed)_
