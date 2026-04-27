---
status: diagnosed
phase: 28-modal-form-substrate
source: [28-VERIFICATION.md]
started: 2026-04-27T20:30:00Z
updated: 2026-04-27T21:30:00Z
---

## Current Test

[testing complete]

## Tests

### 1. FORM-06 Esc UX at 64×22 and 80×24 SSH (all three form-bearing screens)
expected: Pressing Esc after editing a field reseeds the draft to the saved value on the next render; field values visibly revert. Per CONTEXT D-10/D-11/D-12 amendment to SPEC FORM-06, NO "discarded" status copy should appear — the field reversion is the only visible signal. Verify on Account Profile, Account Preferences, and Sysop Site at both terminal sizes.
result: issue
reported: "It does reset the field, but I'm unable to save any fields on the profile tab of the account screen."
severity: major
notes: "Esc-reset behavior (the actual FORM-06 expected) passes. Issue surfaced is orthogonal: submit/save path broken on Account → Profile tab."

### 2. FORM-03 footer count at 64×22 and 80×24 SSH
expected: Each form-bearing screen shows exactly one [Enter]/[Esc] hint group. Account Profile and Account Preferences show only the global command bar's hint. Sysop Site shows only Modal.Form's footer (D-29: SiteForm opts INTO `show_footer: true` because Sysop's command bar advertises Q/Tabs/Jump but NOT Enter/Esc per Plan 04 SUMMARY).
result: pass

### 3. BL-01 live-SSH reproduction (oneliner / hide-oneliner Esc dismiss)
expected: After a doomed oneliner submit (validation failure), pressing Esc dismisses the modal cleanly through CLIHandler key translation. No permanent lock, no follow-up input swallowed.
result: pass

### 4. BL-02 live-SSH reproduction (Sysop Site Ctrl+S submit)
expected: On Sysop Site, Ctrl+S renders "Saved." on success / "Error: validation" on failure. Held Ctrl+S calls `Foglet.Config.put` exactly once (no double-submit). Verify status row is visible during the brief :submitting → terminal transition.
result: issue
reported: "It does, but nothing on the screen tells me that Ctrl+S is what saves the form. It just says [Enter] Submit   [Esc] Cancel, also it seems to save if I hold Enter, but not press Enter , which is really weird and wrong"
severity: major
notes: "Two distinct defects surfaced: (a) Sysop Site footer advertises [Enter] Submit but actual save is Ctrl+S — affordance mismatch (likely D-29/Plan 04 SUMMARY discrepancy in SiteForm footer copy); (b) Press-Enter does NOT save, but hold-Enter DOES save — submission only fires on key-repeat / release rather than initial keydown."

## Summary

total: 4
passed: 2
issues: 2
pending: 0
skipped: 0
blocked: 0

## Gaps

- truth: "Account → Profile tab form should save edited fields when submitted."
  status: failed
  reason: "User reported: It does reset the field, but I'm unable to save any fields on the profile tab of the account screen."
  severity: major
  test: 1
  root_cause: |
    TWO COMPOUNDING DEFECTS — both must be fixed.

    (A) Modal.Form Enter contract: `lib/foglet_bbs/tui/widgets/modal/form.ex:277-288`
    Clause 4 only fires `on_submit` when `focus_index == last_idx`; on every other field
    Enter is a focus-advance. ProfileForm lands the user on `location` (idx 0) with 3
    text fields, so a single Enter press goes to `tagline`, never submits. The user
    perceives this as "nothing saves on press Enter."

    (B) SubmitStash key mismatch (latent since Phase 25 commit `4a289d7`):
    `state.ex:202`/`state.ex:235` use `SubmitStash.stash(__MODULE__, ...)` inside
    closures defined in `Foglet.TUI.Screens.Account.State`, capturing key
    `{SubmitStash, Account.State}`. But `profile_form.ex:45` and `prefs_form.ex:57`
    pop with key `{SubmitStash, Account.ProfileForm/PrefsForm}`. Pop returns nil →
    pattern match `{:profile, payload} = nil` raises `MatchError` BEFORE
    `:account_save_profile` is dispatched. Empirically reproduced by Agent A via
    `rtk mix run` script. Existing test at `account_test.exs:342-414` bypasses the
    keyboard path, hiding the defect.

    Note: Agent C suggested only (A), believing the save would execute once the user
    walked focus to the last field. Agent A's empirical reproduction shows that even
    on the last field, the SubmitStash MatchError crashes the form before save fires.
    Both fixes are needed.
  artifacts:
    - path: "lib/foglet_bbs/tui/widgets/modal/form.ex:277-288"
      issue: "Modal.Form handle_event Clause 4 — Enter on non-last field is focus-advance, not submit"
    - path: "lib/foglet_bbs/tui/screens/account/state.ex:202"
      issue: "on_submit closure stashes under {SubmitStash, Account.State} (wrong module captured by __MODULE__)"
    - path: "lib/foglet_bbs/tui/screens/account/state.ex:235"
      issue: "Same stash-key defect for prefs form"
    - path: "lib/foglet_bbs/tui/screens/account/profile_form.ex:45"
      issue: "SubmitStash.pop(__MODULE__) — pops with Account.ProfileForm key, never set; MatchError"
    - path: "lib/foglet_bbs/tui/screens/account/prefs_form.ex:57"
      issue: "Same pop-key defect for prefs form"
    - path: "test/foglet_bbs/tui/screens/account_test.exs:342-414"
      issue: "Save test bypasses keyboard path, masking the bug"
  missing:
    - "Decide Modal.Form Enter contract (Option A: Enter-from-any-field submits, OR Option B: keep focus-advance + add Ctrl+S to all forms)"
    - "Fix SubmitStash key alignment — pick one stable identifier and use on both sides of stash/pop"
    - "Add end-to-end keyboard-driven test that exercises Account.handle_key(:enter) all the way through to :account_save_profile dispatch"
    - "Render account.ex status_message to surface :submitted feedback (compound defect noted by Agent C)"
  debug_sessions:
    - .planning/debug/account-profile-save-broken.md
    - .planning/debug/press-enter-not-submitting.md

- truth: "Sysop Site form footer must accurately advertise the save key. Current footer reads `[Enter] Submit  [Esc] Cancel` but actual save is bound to Ctrl+S — discoverability defect."
  status: failed
  reason: "User reported: nothing on the screen tells me that Ctrl+S is what saves the form. It just says [Enter] Submit   [Esc] Cancel"
  severity: major
  test: 4
  root_cause: |
    Substrate gap: `Modal.Form.render/2` (form.ex:451-456) hardcodes the footer
    string `"[Enter] Submit   [Esc] Cancel"` with no caller-supplied label option.
    `Modal.Form.init/1` (form.ex:158-187) and the struct (form.ex:114-124) accept
    no `submit_label`/`submit_key`/`footer_hints` knob. SiteForm (the sole
    `show_footer: true` opt-in caller per D-29) cannot tell the substrate that
    its primary submit binding is Ctrl+S (per D-19). The hardcoded copy was
    inherited verbatim from the legacy SiteForm; SPEC FORM-03 only checked
    footer COUNT (no duplicates), never footer ACCURACY.
  artifacts:
    - path: "lib/foglet_bbs/tui/widgets/modal/form.ex:451-456"
      issue: "Hardcoded footer string with no caller override"
    - path: "lib/foglet_bbs/tui/widgets/modal/form.ex:114-124,158-187"
      issue: "Struct + init opts omit any submit-label/footer-text option"
    - path: "lib/foglet_bbs/tui/screens/sysop/site_form/state.ex:131-152"
      issue: "Opts into show_footer:true but cannot supply Ctrl+S copy because no option exists"
    - path: "lib/foglet_bbs/tui/screens/sysop/site_form.ex:75-78"
      issue: "Ctrl+S is documented primary submit (D-19) but unmentioned anywhere on screen"
  missing:
    - "Extend Modal.Form.init/1 with :footer_hints (keyword list of {key, label} pairs) — defaults to [{Enter, Submit}, {Esc, Cancel}] for back-compat"
    - "SiteForm.State.build_modal_form/1 passes footer_hints: [{Ctrl+S, Save}, {Esc, Cancel}]"
    - "Modal.Form.render/2 footer cond branch interpolates from footer_hints instead of hardcoded literal"
  debug_session: .planning/debug/sysop-site-footer-mismatch.md

- truth: "Press-Enter on Sysop Site form should submit (or be consistently bound). Currently only hold-Enter triggers submit while a discrete Enter press does not — input dispatch defect."
  status: failed
  reason: "User reported: it seems to save if I hold Enter, but not press Enter, which is really weird and wrong"
  severity: major
  test: 4
  root_cause: |
    Same Modal.Form Clause 4 precondition as Gap 1 (A). `Modal.Form.handle_event/2`
    (form.ex:277-288) routes Enter to focus-advance UNLESS focus_index == last_idx.
    SiteForm has 5 visible fields starting at focus 0; a brief Enter tap advances
    one field. "Holding Enter" produces N OS-level auto-repeat bytes; each one
    advances focus by 1, and the final repeat lands on the last field and
    submits — which is why hold appears to "work."

    SSH delivers Enter as a single byte (\\r) per keystroke; CLIHandler dispatches
    each byte as one :key event. There are zero :key_press/:key_release/:key_repeat
    filters anywhere in lib/foglet_bbs — the original "key-event-type filter"
    hypothesis is conclusively eliminated.

    Ctrl+S works on Sysop Site (BL-02) precisely because site_form.ex:111-133
    `submit/1` programmatically forces `focus_index = last_idx` before dispatching
    :enter, satisfying Clause 4 deterministically.

    This is the documented Phase 28 SPEC contract (D-05, CONTEXT.md:39-43): "Enter
    on the last field transitions :idle → :submitting." The behavior matches the
    spec; the defect is that the spec conflicts with the user's "Enter saves"
    mental model AND the SiteForm footer copy lies about what Enter does.
  artifacts:
    - path: "lib/foglet_bbs/tui/widgets/modal/form.ex:277-288"
      issue: "Enter on non-last field is focus-advance; the single point where user-visible behavior is decided"
    - path: "lib/foglet_bbs/tui/screens/sysop/site_form/state.ex:32-89"
      issue: "5 fields, focused: 0 init — brief Enter from default landing position cannot submit"
    - path: "lib/foglet_bbs/tui/screens/sysop/site_form.ex:111-133"
      issue: "submit/1 forces focus to last_idx before :enter — proves the Clause 4 precondition is the choke point"
  missing:
    - "Same decision as Gap 1 missing[0]: Modal.Form Enter contract change"
    - "If Option B chosen: SiteForm footer copy update (covered by Gap 2 fix); add Ctrl+S to ProfileForm/PrefsForm key handlers"
  debug_session: .planning/debug/press-enter-not-submitting.md
