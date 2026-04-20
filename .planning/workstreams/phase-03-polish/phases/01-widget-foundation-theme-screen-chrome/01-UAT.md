---
status: testing
phase: 01-widget-foundation-theme-screen-chrome
source: 01-01-SUMMARY.md, 01-02-SUMMARY.md, 01-03-SUMMARY.md, 01-04-SUMMARY.md
started: 2026-04-20T00:00:00Z
updated: 2026-04-20T00:00:00Z
---

## Current Test

number: 1
name: Consistent Screen Chrome
expected: |
  Open the app (SSH in). Every screen — login, main menu, board list, thread list,
  post reader, post composer, new thread — is wrapped in a bordered outer box.
  At the top of that box sits a status bar row. At the bottom sits a key hints row.
  All three layers (border, status bar, key bar) appear on every screen without exception.
awaiting: user response

## Tests

### 1. Consistent Screen Chrome
expected: Every screen is wrapped in a bordered outer box with a status bar row at the top and a key hints row at the bottom.
result: [pending]

### 2. StatusBar Username Display
expected: After logging in, the status bar on every screen reads "Foglet BBS — {Screen Title} | @{your_handle}". On the login screen (before auth), the handle portion shows "@guest".
result: [pending]

### 3. KeyBar Shows Screen-Specific Hints
expected: The key hints bar at the bottom of each screen shows the shortcuts relevant to that screen (e.g., login screen shows login/register bindings; board list shows navigate/select bindings). Hints are styled in an accent color, distinct from body text.
result: [pending]

### 4. Board List Selection Highlighting
expected: Navigate to the board list. The selected board row shows a ">" prefix and is visually distinct (highlighted color) from unselected rows which show "  " (two spaces). Pressing up/down moves the selection marker to the adjacent row.
result: [pending]

### 5. Thread List Selection Highlighting
expected: Enter any board to see the thread list. Same behavior as board list: selected thread shows ">" prefix with highlight color; unselected threads show "  " prefix in a dimmer style. Navigation moves the highlight correctly.
result: [pending]

## Summary

total: 5
passed: 0
issues: 0
pending: 5
skipped: 0
blocked: 0

## Gaps

[none yet]
