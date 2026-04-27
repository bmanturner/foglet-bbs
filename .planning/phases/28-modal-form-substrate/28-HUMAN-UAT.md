---
status: complete
phase: 28-modal-form-substrate
source: [28-VERIFICATION.md]
started: 2026-04-27T20:30:00Z
updated: 2026-04-27T21:15:00Z
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
  artifacts: []
  missing: []

- truth: "Sysop Site form footer must accurately advertise the save key. Current footer reads `[Enter] Submit  [Esc] Cancel` but actual save is bound to Ctrl+S — discoverability defect."
  status: failed
  reason: "User reported: nothing on the screen tells me that Ctrl+S is what saves the form. It just says [Enter] Submit   [Esc] Cancel"
  severity: major
  test: 4
  artifacts: []
  missing: []

- truth: "Press-Enter on Sysop Site form should submit (or be consistently bound). Currently only hold-Enter triggers submit while a discrete Enter press does not — input dispatch defect."
  status: failed
  reason: "User reported: it seems to save if I hold Enter, but not press Enter, which is really weird and wrong"
  severity: major
  test: 4
  artifacts: []
  missing: []
