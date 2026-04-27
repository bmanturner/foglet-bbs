---
phase: 28-modal-form-substrate
verified: 2026-04-27T18:39:34Z
status: gaps_found
score: 6/9 must-haves verified
overrides_applied: 0
gaps:
  - truth: "FORM-05 lock prevents double-submit on every form-bearing screen — consuming screens (in-scope per SPEC: Account Profile, Account Preferences, Sysop Site) inherit the :submitting lock guarantee."
    status: failed
    reason: "Sysop SiteForm rebuilds the Modal.Form from scratch on every keystroke via SState.build_modal_form/1 (site_form.ex:60-65, 79-83) and sync_back/2 (site_form.ex:189-193) only writes drafts and focused back to SState; submit_state is dropped per-event. The FORM-05 lock guard never engages on this consumer — a second Enter sees a freshly-built :idle form and re-invokes Foglet.Config.put/3 (BL-02). The protective intent of FORM-05 D-02 is silently nullified on the only Sysop in-scope consumer."
    artifacts:
      - path: "lib/foglet_bbs/tui/screens/sysop/site_form.ex"
        issue: "render/2 (line 60-65) and handle_key/2 (line 79-83) rebuild the Modal.Form on every event/render via SState.build_modal_form/1; persist_payload/3 (line 180-183) sets submit_state: :saved but sync_back/2 (line 189-193) discards it; finalize_submit/2 (line 124) sets {:error, \"validation\"} but the same sync_back call drops it. `submit_state` is never persisted across events."
    missing:
      - "Persist submit_state on SState (or persist the full Modal.Form struct) so the lock survives across keystrokes — without this, FORM-05 lock has zero effect on SiteForm and a held/double Enter will call Foglet.Config.put/3 multiple times."
      - "Add a regression test that fires two `%{key: :enter}` events back-to-back through `SiteForm.handle_key/2` and asserts Foglet.Config.put/3 was invoked exactly once for each visible key (currently no such test exists in site_form_test.exs)."

  - truth: "When submit_state == :submitting (or :saved or {:error, _}), the rendered output contains a visible status row — across every consuming screen, including Sysop Site."
    status: failed
    reason: "Same root cause as the lock failure (BL-02): SiteForm's per-event Modal.Form rebuild discards `submit_state`. After a successful Config.put cascade, persist_payload/3 sets ModalForm.set_submit_state(form, :saved); sync_back/2 drops it; the next render (using a fresh SState.build_modal_form/1) shows :idle. \"Saved.\"/\"Error: validation\" status rows never reach the operator. The D-08/D-09 status-row contract is silently broken for the Sysop SITE form."
    artifacts:
      - path: "lib/foglet_bbs/tui/screens/sysop/site_form.ex"
        issue: "Lines 124 and 182 set submit_state, but sync_back/2 (line 189-193) only persists drafts and focused — submit_state is never carried through. Test surface (test/foglet_bbs/tui/screens/sysop/site_form_test.exs) asserts on Config.get! after submit but never on the rendered status row."
    missing:
      - "Add `submit_state: :idle` field to SiteForm.State and have render/2 / handle_key/2 re-apply it after build_modal_form, OR cache the constructed Modal.Form on SState so submit_state survives."
      - "Add tests that drive Ctrl+S successfully and assert the rendered tree contains \"Saved.\", and drive a validation failure and assert \"Error: validation\" appears."

  - truth: "Existing Modal.Form consumers do not regress — the Account oneliner / hide-oneliner :form modals continue to be dismissable after a failed submit (SPEC Constraints: \"Phase 28 must not regress existing Modal.Form consumers\")."
    status: failed
    reason: "BL-01: After Phase 28 added the FORM-05 lock guard (form.ex:164-166), `ModalForm.handle_event/2` swallows every event when submit_state == :submitting. The Account oneliner composer (app.ex `do_update({:open_oneliner_composer}, ...)`) and hide-oneliner modal drive the form through the Enter-on-last-field transition, which sets submit_state == :submitting. When the resulting backend call fails ({:oneliner_created, {:error, %Ecto.Changeset{}}} / {:oneliner_hidden, {:error, :forbidden}}), the error handlers funnel through put_oneliner_form_errors/2 and put_hide_oneliner_form_errors/2 (app.ex:1023-1052), which call only ModalForm.set_errors/2 and never ModalForm.set_submit_state/2. The form stays in :submitting forever. Every subsequent key — including :escape, the only documented dismissal path for :form modals — is short-circuited by the lock clause and dropped. The user cannot edit, retry, or close the modal; only escape is to close the SSH session."
    artifacts:
      - path: "lib/foglet_bbs/tui/app.ex"
        issue: "put_oneliner_form_errors/2 (lines 1023-1029) and put_hide_oneliner_form_errors/2 (lines 1036-1042) call ModalForm.set_errors/2 only — never ModalForm.set_submit_state/2. handle_modal_key(:form, ...) at line 1369-1398 dispatches via ModalForm.handle_event/2, which now lock-swallows :escape when submit_state == :submitting."
      - path: "lib/foglet_bbs/tui/widgets/modal/form.ex"
        issue: "Lock clause at line 164-166 is correct per spec; the regression is in the consumers that don't drive set_submit_state/2 on error. This consumer surface MUST have been updated as part of Phase 28's substrate change."
    missing:
      - "Reset submit_state to {:error, msg} (or :idle) in put_oneliner_form_errors/2 and put_hide_oneliner_form_errors/2 — minimal patch documented in 28-REVIEW.md BL-01."
      - "Add a regression test that posts a doomed oneliner via the modal-key path (handle_modal_key/3 entry) and asserts a subsequent %{key: :escape} dismisses the modal."

deferred: []

human_verification:
  - test: "Acceptance Criterion 7: visible Esc behavior at 64×22 and 80×24 SSH on all three form-bearing screens (Account Profile, Account Preferences, Sysop Site)"
    expected: "Pressing Esc after editing a field reseeds the draft to the saved value on the next render; field values visibly revert. Per CONTEXT D-10/D-11/D-12 amendment to SPEC FORM-06, NO 'discarded' status copy should appear (the field-reversion is the visible signal)."
    why_human: "The amendment to FORM-06 acceptance criterion (b) drops the explicit flash row in favor of field-reversion-only signaling. Whether the field reversion is sufficiently visible to a human operator at 64×22 SSH (smallest target) is a UX judgment. Programmatic tests assert state.profile_draft == saved values but cannot assert the SSH-rendered output is sufficiently obvious."
  - test: "Acceptance Criterion 3: no duplicate footer copy at 64×22 and 80×24 SSH on Account Profile, Account Preferences, and Sysop Site"
    expected: "Each screen shows exactly one [Enter]/[Esc] hint group. Account screens show only the global command bar's hint. Sysop Site shows only Modal.Form's footer (D-29: SiteForm.State opts INTO show_footer: true at site_form/state.ex:129 because Sysop's command bar advertises Q/Tabs/Jump but NOT Enter/Esc per Plan 04 SUMMARY)."
    why_human: "Visual count of duplicate hint groups across two terminal sizes — programmatic substring count would catch obvious duplication but not subtle layout/styling issues."
  - test: "BL-01 reproduction: oneliner modal lockup after failed submit"
    expected: "After the BLOCKER fix (gap above) lands, fire a doomed oneliner submit and confirm Esc dismisses the modal in a live SSH session at 64×22 and 80×24."
    why_human: "Validates the user's escape path in the actual SSH client where keystrokes flow through CLIHandler — programmatic tests can mock the events but not the full key-translation path."
---

# Phase 28: Modal.Form Substrate — Verification Report

**Phase Goal:** Modal.Form routes keystrokes to the focused field as a single source of truth, accepts the navigation gestures users expect (Tab/Shift+Tab/`:backtab`/Up/Down/Esc/Enter), and prevents double-submits — unblocking every Account and Sysop edit fix downstream.

**Verified:** 2026-04-27T18:39:34Z
**Status:** gaps_found
**Re-verification:** No — initial verification

## Goal Achievement

### Observable Truths (from ROADMAP Success Criteria + SPEC)

| #   | Truth (FORM ID)                                                                                                                                                                            | Status     | Evidence                                                                                                                                                                                                                  |
| --- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ---------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1   | FORM-01: Down moves focus on text fields; Up/Down on enum cycles values without changing focus.                                                                                            | ✓ VERIFIED | Modal.Form.handle_event/2 clauses at form.ex:251-273 implement type-branch (text-like → focus_index, else → dispatch_event_to_field). Tests at form_test.exs:616, 635, 652, 671, 688, 707 assert behavior.               |
| 2   | FORM-02: Shift+Tab and `:backtab` retreat focus from field 2 → field 1; wrap deterministic.                                                                                                | ✓ VERIFIED | Three byte-equivalent clauses at form.ex:195, 204, 213 for `%{key: :tab, shift: true}` / `:shift_tab` / `:backtab`. Wrap math `rem(focus_index - 1 + n, n)`. Tests at form_test.exs:585, 594, 601, 473, 482, 508 assert. |
| 3   | FORM-03: Footer suppressed by default; opt-in for true overlays.                                                                                                                           | ✓ VERIFIED | `show_footer: false` default in defstruct (form.ex:98). Conditional at form.ex:381-386. Tests at form_test.exs:759, 770, 781, 789. Sysop SiteForm intentionally opts INTO show_footer:true (state.ex:129) per Plan 04.    |
| 4   | FORM-05: Two Enter events back-to-back invoke on_submit exactly once; :submitting visible.                                                                                                 | ✗ FAILED   | Substrate behavior is correct (form.ex:164-166 lock guard + form_test.exs:873, 905). However, the lock is silently nullified on Sysop SiteForm because the consumer rebuilds the form per event (BL-02). See gap above.   |
| 5   | FORM-04 routing: `:tab :tab :char "x"` lands x in third field's buffer.                                                                                                                    | ✓ VERIFIED | form.ex:282-288 dispatches to focused field; test at form_test.exs:797. Leaf widgets (TextInput, RadioGroup, Checkbox) carry no focus state — test/foglet_bbs/tui/widgets/input_focus_state_test.exs asserts grep-level. |
| 6   | FORM-06: Esc on Account Profile, Account Preferences, Sysop Site reseeds drafts to saved values.                                                                                           | ✓ VERIFIED | profile_form.ex:56-62 (`State.seed_from_user`); prefs_form.ex:73-78; site_form.ex:73-76 (`SState.reseed_drafts`). Per CONTEXT D-10/D-11/D-12, no flash row — visible signal is field reversion (needs human SSH check).   |
| 7   | Existing Modal.Form consumers (Account oneliner, hide-oneliner :form modals) do not regress.                                                                                               | ✗ FAILED   | BL-01: Lock guard wedges `:form`-typed modals after a failed submit because put_oneliner_form_errors/2 and put_hide_oneliner_form_errors/2 (app.ex:1023-1052) never drive set_submit_state/2. See gap above.            |
| 8   | Status row visible across every consuming screen when submit_state ≠ :idle (D-08/D-09 cross-screen guarantee).                                                                             | ✗ FAILED   | Substrate is correct (form.ex:394-403). On SiteForm, `set_submit_state(:saved)` and `{:error, "validation"}` calls (site_form.ex:124, 182) are immediately discarded by sync_back/2. Status row never renders on SITE.    |
| 9   | Sysop SiteForm migrated to Modal.Form-backed wrapper structurally analogous to ProfileForm/PrefsForm; Foglet.Config.put/3 boundary preserved.                                              | ✓ VERIFIED | site_form.ex is a thin wrapper delegating to ModalForm.render and ModalForm.handle_event; site_form/state.ex defines the sibling state; Config.put preserved at site_form.ex:150; Ctrl+S preserved at site_form.ex:68.   |

**Score:** 6/9 truths verified (3 FAILED — all BLOCKER per code review)

### Required Artifacts

| Artifact                                                       | Expected                                                                          | Status                          | Details                                                                                                                                                                                                                                  |
| -------------------------------------------------------------- | --------------------------------------------------------------------------------- | ------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `lib/foglet_bbs/tui/widgets/modal/form.ex`                     | Up/Down clauses, :backtab clause, :show_footer init option, submit_state machine, set_submit_state/2 setter, status row | ✓ VERIFIED (Levels 1-3)         | All required code present. Lock clause at 164. Auto-reset at 178-184. Setter at 329-342. Status row at 394-403. show_footer at 98, 141, 381. **Missing:** init/1 does not validate `fields != []` (BL-03 — latent crash, no current trigger). |
| `lib/foglet_bbs/tui/widgets/modal/form.ex` (description field) | Optional :description rendered as dim row beneath widget                          | ✓ VERIFIED                       | render_field/5 at form.ex:563-568 emits dim row when spec carries :description.                                                                                                                                                          |
| `lib/foglet_bbs/tui/screens/account/profile_form.ex`           | Status_message removal on cancel; "discarded" copy gone                           | ✓ VERIFIED                       | Line 56-62 sets `status_message: nil` on `:cancelled`; grep confirms no "discarded" string. **Caveat:** WR-01: handle_key guard (line 33) lacks `:backtab` — drops the CLIHandler-translated key on this screen.                       |
| `lib/foglet_bbs/tui/screens/account/prefs_form.ex`             | Status_message removal on cancel; "discarded" copy gone                           | ✓ VERIFIED                       | Line 73-78 sets `status_message: nil`; no "discarded" string. **Caveat:** WR-01: handle_key guard (line 35) lacks `:backtab`.                                                                                                          |
| `lib/foglet_bbs/tui/screens/sysop/site_form.ex`                | Modal.Form wrapper; no `▸` glyph; Ctrl+S preserved; Esc reseeds                   | ⚠️ HOLLOW (Level 4 fail on FORM-05) | Wrapper structure correct (Levels 1-3 pass). Level 4 (data flow): submit_state SET by wrapper at 124, 182 but DROPPED by sync_back/2 at 189-193 — the visible "Saved./Error" output never reaches the renderer. BL-02.                  |
| `lib/foglet_bbs/tui/screens/sysop/site_form/state.ex`          | Sibling state, build_modal_form/1, visible_keys/1, validate_delivery_verification_pair/1 | ✓ VERIFIED                       | All present at state.ex:74-81 (new), 100-108 (visible_keys), 117-139 (build_modal_form), 149-162 (validate). **Note:** WR-03 dead `on_cancel` callback at line 137 — never fires because wrapper intercepts Esc directly.              |
| `lib/foglet_bbs/tui/app.ex` (`render_modal_overlay` comment)   | Documenting comment for future :form modal callers                                | ✓ VERIFIED                       | Line 198 comment present per Plan 01 Task 2.                                                                                                                                                                                            |
| `test/foglet_bbs/tui/widgets/modal/form_test.exs`              | Unit tests for FORM-01..05 substrate behaviors                                    | ✓ VERIFIED                       | 62+ tests; covers backtab, Up/Down focus + enum cycle, show_footer default, lock guard, set_submit_state, auto-reset, status row.                                                                                                       |
| `test/foglet_bbs/tui/widgets/input_focus_state_test.exs`       | Grep test pinning no leaf-widget focus state                                      | ✓ VERIFIED                       | File exists; 1 test covering text_input.ex / radio_group.ex / checkbox.ex.                                                                                                                                                              |
| `test/foglet_bbs/tui/screens/sysop/site_form_test.exs`         | Tests for Modal.Form wrapper behavior, Ctrl+S, Esc reseed, validation, visibility | ⚠️ ORPHANED (gap)                | Tests exist but do NOT assert "Saved." status row appears, do NOT assert double-Enter only invokes Config.put once, and do NOT assert oneliner modal lockup is prevented. The defects (BL-01, BL-02) are uncaught.                       |

### Key Link Verification

| From                                                | To                                                  | Via                                                   | Status      | Details                                                                                                                                                                                |
| --------------------------------------------------- | --------------------------------------------------- | ----------------------------------------------------- | ----------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Modal.Form.handle_event/2 lock clause               | submit_state guard                                  | head match `%__MODULE__{submit_state: :submitting}`   | ✓ WIRED     | Verified at form.ex:164-166.                                                                                                                                                          |
| Modal.Form.handle_event/2 Enter-on-last             | :idle → :submitting                                 | single on_submit invocation gated on :idle            | ✓ WIRED     | Verified at form.ex:233-244.                                                                                                                                                          |
| Modal.Form.set_submit_state/2                       | consuming screens (:saved / {:error,_})             | public boundary                                       | ⚠️ PARTIAL   | Substrate exposes setter (form.ex:329-342). SiteForm CALLS it (lines 124, 182) but the value is dropped on next render (BL-02). Account oneliner consumers in app.ex DO NOT call it (BL-01). |
| SiteForm.render/2                                   | Modal.Form.render/2                                 | per-render build_modal_form → ModalForm.render        | ✓ WIRED     | site_form.ex:60-65.                                                                                                                                                                   |
| SiteForm.handle_key/2                               | Modal.Form.handle_event/2                           | wrapper builds form, dispatches event, syncs back     | ⚠️ PARTIAL   | Wired structurally (site_form.ex:78-92) but `submit_state` is not in the sync-back contract — see BL-02.                                                                              |
| Modal.Form on_submit closure (SiteForm)             | Foglet.Config.put/3                                 | validate → coerce → Config.put with current_user      | ✓ WIRED     | site_form/state.ex:131-138 + site_form.ex:150.                                                                                                                                        |
| App.render_modal_overlay (oneliner :form modals)    | Modal.Form lock guard release on error              | put_oneliner_form_errors/2 should call set_submit_state/2 | ✗ NOT_WIRED | BL-01: app.ex:1023-1052 only call set_errors/2 — lock never releases.                                                                                                                  |

### Data-Flow Trace (Level 4)

| Artifact                                           | Data Variable                            | Source                                                  | Produces Real Data | Status                                                              |
| -------------------------------------------------- | ---------------------------------------- | ------------------------------------------------------- | ------------------ | ------------------------------------------------------------------- |
| Modal.Form.render/2 (status row)                   | `state.submit_state`                     | Mutated by lock-clause / Enter-on-last / set_submit_state | ✓ Yes (substrate)  | ✓ FLOWING within Modal.Form                                          |
| SiteForm.render/2 (delegates to ModalForm.render)  | submit_state of the per-render Modal.Form | `SState.build_modal_form/1` always returns :idle (state.ex:122-138) | ✗ No                | ✗ DISCONNECTED — submit_state is dropped per render (BL-02 root cause) |
| App `:form` modal render path                      | submit_state of stored Modal.Form        | put_oneliner_form_errors/2 only sets errors, not submit_state | Partial             | ⚠️ HOLLOW — value persists but no caller transitions out of :submitting on error (BL-01) |

### Behavioral Spot-Checks

| Behavior                                                     | Command                                                                                                  | Result                                                                          | Status |
| ------------------------------------------------------------ | -------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------- | ------ |
| Modal.Form unit tests pass                                   | `rtk mix test test/foglet_bbs/tui/widgets/modal/form_test.exs`                                           | (suite-level: 141 tests across 4 files, 0 failures)                             | ✓ PASS  |
| Account screen Esc tests pass                                | `rtk mix test test/foglet_bbs/tui/screens/account_test.exs`                                              | passes                                                                          | ✓ PASS  |
| Sysop SiteForm tests pass                                    | `rtk mix test test/foglet_bbs/tui/screens/sysop/site_form_test.exs`                                      | passes                                                                          | ✓ PASS  |
| Input focus state grep test passes                           | `rtk mix test test/foglet_bbs/tui/widgets/input_focus_state_test.exs`                                    | passes                                                                          | ✓ PASS  |
| Full suite green (pre-existing claim)                        | `rtk mix test`                                                                                            | 1884 tests, 0 failures (per task context)                                       | ✓ PASS  |
| Double-Enter on SiteForm invokes Config.put once             | (no test exists)                                                                                          | N/A — no test in site_form_test.exs covers FORM-05 single-fire on this consumer | ✗ FAIL (test gap matches BL-02) |
| Oneliner :form modal Esc-after-failed-submit dismisses modal | (no test exists)                                                                                          | N/A — no test exercises put_oneliner_form_errors/2 via handle_modal_key/3 entry  | ✗ FAIL (test gap matches BL-01) |

### Requirements Coverage

| Requirement | Source Plan(s)        | Description                                                         | Status                  | Evidence                                                                                                       |
| ----------- | --------------------- | ------------------------------------------------------------------- | ----------------------- | -------------------------------------------------------------------------------------------------------------- |
| FORM-01     | 28-01                 | Up/Down inter-field movement; enum cycle preserved                  | ✓ SATISFIED             | form.ex:251-273 + tests at form_test.exs:616-707                                                              |
| FORM-02     | 28-01                 | `:backtab` ≡ Shift+Tab                                              | ✓ SATISFIED             | form.ex:213-217 + tests at form_test.exs:585-601                                                              |
| FORM-03     | 28-01                 | Footer configurable, default off                                    | ✓ SATISFIED             | form.ex:98, 381-386 + tests at form_test.exs:759-789. Sysop SiteForm intentionally opts in (decision per Plan 04). |
| FORM-04     | 28-01, 28-04          | Single-source-of-truth focus routing; leaf widgets carry no focus state | ✓ SATISFIED             | form.ex:282-288 + form_test.exs:797 + input_focus_state_test.exs                                              |
| FORM-05     | 28-02, (consumer 28-04) | Submit-state machine prevents double-submit, shows in-flight state  | ⚠️ BLOCKED               | Substrate correct; consumer integration broken on Sysop SiteForm (BL-02) and Account oneliner :form modals (BL-01). |
| FORM-06     | 28-03, 28-04          | Honest Esc on Account Profile, Account Preferences, Sysop Site      | ✓ SATISFIED (with human SSH check pending) | profile_form.ex:56-62, prefs_form.ex:73-78, site_form.ex:73-76. Per CONTEXT D-10..D-12 the SPEC criterion (b) flash row was intentionally dropped. |

**Orphan check:** REQUIREMENTS.md maps FORM-01..FORM-06 to Phase 28 only; all six are claimed by at least one plan. No orphans.

### Anti-Patterns Found

| File                                                  | Line       | Pattern                                                       | Severity | Impact                                                                                                                                                       |
| ----------------------------------------------------- | ---------- | ------------------------------------------------------------- | -------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| lib/foglet_bbs/tui/screens/sysop/site_form.ex         | 60-65, 79-83, 189-193 | submit_state mutated then dropped via per-event rebuild       | 🛑 Blocker | BL-02: FORM-05 lock + status row contract silently nullified for SiteForm. Effects user-visible.                                                            |
| lib/foglet_bbs/tui/app.ex                             | 1023-1052  | put_*_form_errors/2 calls set_errors/2 only — never set_submit_state/2 | 🛑 Blocker | BL-01: oneliner / hide-oneliner modals lock permanently after failed submit. User cannot Esc out — only escape is closing SSH session.                      |
| lib/foglet_bbs/tui/widgets/modal/form.ex              | 129-143    | init/1 does not validate fields ≠ []                          | ⚠️ Warning | BL-03: future caller with empty visibility set will crash via `rem(_, 0)` ArithmeticError. No current trigger but latent.                                  |
| lib/foglet_bbs/tui/screens/account/profile_form.ex    | 33         | handle_key guard missing `:backtab`                           | ⚠️ Warning | WR-01: real terminal sending `ESC[Z` no-matches; CLIHandler-translated key dropped on PROFILE.                                                              |
| lib/foglet_bbs/tui/screens/account/prefs_form.ex      | 35         | handle_key guard missing `:backtab`                           | ⚠️ Warning | WR-01 (same).                                                                                                                                                |
| lib/foglet_bbs/tui/screens/sysop/site_form/state.ex   | 137        | Dead on_cancel callback (wrapper intercepts Esc directly)     | ℹ️ Info    | WR-03: harmless but misleads; moduledoc cancel-path comment is incorrect. Recommend dropping or routing Esc through Modal.Form.handle_event/2.            |
| lib/foglet_bbs/tui/screens/sysop/site_form.ex         | 141-187    | persist_payload/3 cascades non-transactionally                | ⚠️ Warning | WR-02: partial Config.put across multiple keys can leave delivery_mode and require_email_verification in invariant-violating state.                         |
| lib/foglet_bbs/tui/screens/sysop/site_form.ex         | 207-217    | apply_errors uses String.to_existing_atom on string-keyed errors | ℹ️ Info    | WR-04: safe today; latent risk if a future caller stores errors under unknown string keys.                                                                  |
| lib/foglet_bbs/tui/widgets/modal/form.ex              | 301-308    | field_value/2 silently returns first match on duplicate names | ℹ️ Info    | WR-05: no validation in init/1 against duplicate :name fields.                                                                                              |
| lib/foglet_bbs/tui/widgets/modal/form.ex              | 169-184    | Auto-reset preamble runs before Esc cancel clause             | ℹ️ Info    | WR-06: subtle FSM issue; doc-only fix recommended.                                                                                                           |

### Human Verification Required

See `human_verification:` in frontmatter. Three items:

1. **FORM-06 Esc UX at 64×22 / 80×24 SSH** — verify field reversion alone is a sufficient visible signal across all three form-bearing screens (per amended SPEC FORM-06(b) / CONTEXT D-10..D-12).
2. **FORM-03 duplicate-footer cleanup at 64×22 / 80×24 SSH** — verify each screen shows exactly one [Enter]/[Esc] hint group, including the deliberate Sysop SiteForm opt-in to Modal.Form's footer (state.ex:129).
3. **BL-01 reproduction after fix** — once the gap closure lands, verify a doomed oneliner submit followed by Esc dismisses the modal in a real SSH client.

### Gaps Summary

Three BLOCKER gaps prevent the Phase 28 goal from being achieved end-to-end despite the substrate code being well-shaped:

1. **BL-02 (Sysop SiteForm)** — FORM-05 lock and status-row guarantees are silently nullified on the only Sysop in-scope consumer because the wrapper rebuilds the Modal.Form fresh per render and `sync_back/2` discards `submit_state`. The user-visible effects are: (a) double-Ctrl+S or double-Enter on Sysop Site can call `Foglet.Config.put/3` twice, and (b) the operator never sees "Saved." or "Error: validation" status rows on the SITE form. The substrate's protective intent is fully bypassed for this consumer. SPEC explicitly puts SiteForm in scope ("SiteForm is migrated to render and dispatch through Modal.Form"), so the substrate-level test surface alone is insufficient evidence of phase completion.

2. **BL-01 (Account oneliner :form modals)** — The newly-added FORM-05 lock guard wedges these existing Modal.Form consumers after any failed submit. The SPEC Constraints section explicitly states "Phase 28 must not regress existing Modal.Form consumers" — and `:form`-typed modals invoked via `App.handle_modal_key/3` ARE existing consumers that pre-date Phase 28. The error handlers `put_oneliner_form_errors/2` and `put_hide_oneliner_form_errors/2` were not updated to release the lock. Result: a user who submits a doomed oneliner (validation failure or `:forbidden`) cannot press Esc to dismiss the modal — only closing the SSH session escapes.

3. **BL-03 (defensive coding)** — `Modal.Form.init/1` does not validate `fields != []`. The lock guards / focus-wrap math compute `rem(_, 0)` which raises `ArithmeticError`. No current caller passes empty fields, and `SiteForm.State.visible_keys/1` could in principle hide every key under future visibility rules. Lower urgency than BL-01/BL-02 but still a substrate-correctness gap easily fixed at init time.

**Group note:** BL-01 and BL-02 share a root cause — the FORM-05 lock contract was added to Modal.Form without auditing every caller for the lifecycle obligation it imposes. A focused closure plan should (a) document the contract (consumer MUST drive `set_submit_state/2` on async terminal states, OR rebuild forms with a persisted `submit_state`), (b) wire the missing call sites in app.ex, and (c) persist `submit_state` on `SiteForm.State`.

Six WARNINGs (WR-01..WR-06) are documented in `28-REVIEW.md`; WR-01 (`:backtab` missing from Account form guards) is the most user-facing and worth fixing in the same closure plan as BL-01/BL-02.

---

_Verified: 2026-04-27T18:39:34Z_
_Verifier: Claude (gsd-verifier)_
