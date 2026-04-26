---
status: complete
phase: 25-operator-console-conversion
source:
  - 25-01-SUMMARY.md
  - 25-02-SUMMARY.md
  - 25-03-SUMMARY.md
  - 25-04-SUMMARY.md
  - 25-05-SUMMARY.md
  - 25-06-SUMMARY.md
started: 2026-04-26T13:59:25Z
updated: 2026-04-26T14:00:15Z
---

## Current Test

[testing complete]

## Tests

### 1. Account Profile and Preferences Forms
expected: In the Account screen, PROFILE and PREFS tabs render as compact modal-style forms. Editing profile fields and preference fields keeps focus movement predictable; cycling the theme preference previews the candidate theme before saving, and submitting persists or reports field-specific errors inline.
result: pass

### 2. Account SSH Keys Table
expected: In the Account screen, SSH_KEYS renders as a console table with Label, Fingerprint, Created, and Last used columns. Moving up and down changes the selected key without visual overflow, and revoke actions still target the selected key.
result: pass

### 3. Moderation Console Tabs
expected: In the Moderation screen, LOG, USERS, BOARDS, and INVITES render as dense operator-console views using scope/status summaries and tables. Each tab is readable at the minimum terminal size, uses honest empty states, and INVITES still supports row selection.
result: pass

### 4. Sysop Site and Limits Forms
expected: In the Sysop screen, SITE and LIMITS tabs render as compact forms with visible submit controls. Editing settings preserves field visibility and focus behavior, and validation or save feedback appears inline without breaking the terminal layout.
result: pass

### 5. Sysop Boards, Users, and System Views
expected: In the Sysop screen, BOARDS and USERS render as console tables and SYSTEM renders as a key/value system snapshot. User status actions such as approve, reject, suspend, and reactivate operate on the selected user, and SYSTEM refresh updates the displayed snapshot.
result: pass

### 6. Minimum Terminal Layout and Theme Hygiene
expected: At 64x22 and 80x24 terminal sizes, all converted Account, Moderation, and Sysop tabs stay within bounds, avoid overlapping text, and render themed colors without leaking raw color atoms into visible text.
result: pass

## Summary

total: 6
passed: 6
issues: 0
pending: 0
skipped: 0
blocked: 0

## Gaps

[none yet]
