---
status: partial
phase: 28-modal-form-substrate
source: [28-VERIFICATION.md]
started: 2026-04-27T20:30:00Z
updated: 2026-04-27T20:30:00Z
---

## Current Test

[awaiting human testing]

## Tests

### 1. FORM-06 Esc UX at 64×22 and 80×24 SSH (all three form-bearing screens)
expected: Pressing Esc after editing a field reseeds the draft to the saved value on the next render; field values visibly revert. Per CONTEXT D-10/D-11/D-12 amendment to SPEC FORM-06, NO "discarded" status copy should appear — the field reversion is the only visible signal. Verify on Account Profile, Account Preferences, and Sysop Site at both terminal sizes.
result: [pending]

### 2. FORM-03 footer count at 64×22 and 80×24 SSH
expected: Each form-bearing screen shows exactly one [Enter]/[Esc] hint group. Account Profile and Account Preferences show only the global command bar's hint. Sysop Site shows only Modal.Form's footer (D-29: SiteForm opts INTO `show_footer: true` because Sysop's command bar advertises Q/Tabs/Jump but NOT Enter/Esc per Plan 04 SUMMARY).
result: [pending]

### 3. BL-01 live-SSH reproduction (oneliner / hide-oneliner Esc dismiss)
expected: After a doomed oneliner submit (validation failure), pressing Esc dismisses the modal cleanly through CLIHandler key translation. No permanent lock, no follow-up input swallowed.
result: [pending]

### 4. BL-02 live-SSH reproduction (Sysop Site Ctrl+S submit)
expected: On Sysop Site, Ctrl+S renders "Saved." on success / "Error: validation" on failure. Held Ctrl+S calls `Foglet.Config.put` exactly once (no double-submit). Verify status row is visible during the brief :submitting → terminal transition.
result: [pending]

## Summary

total: 4
passed: 0
issues: 0
pending: 4
skipped: 0
blocked: 0

## Gaps
