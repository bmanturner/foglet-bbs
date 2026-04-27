---
status: partial
phase: 29-sysop-tab-lifecycle-bodies
source: [29-VERIFICATION.md]
started: 2026-04-27T21:50:00Z
updated: 2026-04-27T21:50:00Z
---

## Current Test

[awaiting human testing]

## Tests

### 1. Sysop tab auto-load on entry (no "Press any key" gating)
expected: SSH in as a sysop user, navigate to Sysop, switch through Boards / Limits / System / Users tabs. Each tab auto-loads on entry without any "Press any key to load" gating; loaded data renders with no manual key required.
result: [pending]

### 2. Forbidden vs generic error panel distinction
expected: Force a load failure on a Sysop tab (e.g. simulate transient DB error or run as a non-sysop). Non-forbidden errors render "Could not load <tab>. Press R to retry." with `[R] Retry` in the command bar; pressing R re-dispatches and clears the error. `:forbidden` errors render "Insufficient role to view this tab." with no `[R] Retry` advertising. Color distinction (theme.warning.fg vs theme.error.fg) visible.
result: [pending]

### 3. Sysop Site draft echo + Saved./Esc reseed
expected: On Sysop Site, focus a field, type/cycle to a draft value — displayed value echoes draft (not saved Config). Press Enter and observe a `Saved.` confirmation row for one render cycle, then idle. Press Esc on a dirtied field — displayed value reverts to saved Config value with no `discarded` copy and Esc does not navigate.
result: [pending]

### 4. Sysop Users keybind gating + from→to error copy
expected: Focus a row whose status is `:active`. `[A] Approve` is NOT advertised (only `[S] Suspend` shows). Pressing A is a no-op (status_message stays nil, no boundary call). Triggering a stale-row `:invalid_transition` boundary error renders `Cannot change @<handle> from <from> to <to>.` — never the substring `invalid_transition`.
result: [pending]

### 5. Sysop Invites focus highlight + armed [X] Revoke
expected: At 80×24 SSH, move focus across rows; the focused row is highlighted via theme.selected.fg/bg (visibly distinguishable from unfocused rows). Enter on a non-:revoked focused row reveals `[X] Revoke` in the command bar. X dispatches the revoke. Moving focus or switching tabs clears the armed state and `[X] Revoke` disappears.
result: [pending]

### 6. 1-N Jump consistency across screens (64×22 + 80×24)
expected: Open Account, Moderation, and Sysop screens at both 64×22 and 80×24 SSH. Each screen's command bar advertises a `1-N Jump` group where N matches the visible tab count for the actor. No hardcoded `1-6` literal appears when only 5 tabs are visible. The `←/→ Tab` and `1-N Jump` pair survive at 64×22.
result: [pending]

## Summary

total: 6
passed: 0
issues: 0
pending: 6
skipped: 0
blocked: 0

## Gaps
