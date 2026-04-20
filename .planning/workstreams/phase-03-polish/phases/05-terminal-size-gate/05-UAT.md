---
status: testing
phase: 05-terminal-size-gate
source: [05-01-SUMMARY.md]
started: 2026-04-20T19:00:00Z
updated: 2026-04-20T19:00:00Z
---

## Current Test
<!-- OVERWRITE each test - shows where we are -->

number: 1
name: Gate triggers when terminal is too small
expected: |
  SSH into the BBS. Resize your terminal to something smaller than 64 columns
  OR smaller than 22 rows (e.g. drag your terminal window to a narrow width).
  You should see a centered message appear — no ScreenFrame border, no StatusBar,
  no KeyBar — just the size gate message telling you the terminal is too small.
  The message should be roughly centered in the available space.
awaiting: user response

## Tests

### 1. Gate triggers when terminal is too small
expected: SSH into the BBS. Resize your terminal to something smaller than 64 columns OR smaller than 22 rows (e.g. drag your terminal window to a narrow width). You should see a centered message appear — no ScreenFrame border, no StatusBar, no KeyBar — just the size gate message telling you the terminal is too small. The message should be roughly centered in the available space.
result: [pending]

### 2. Normal TUI restored on resize back up
expected: While the gate message is visible (terminal too small), resize your terminal back to 64×22 or larger. The normal BBS interface (with ScreenFrame border, StatusBar, KeyBar) should reappear immediately without requiring any keypress or action.
result: [pending]

### 3. Exact minimum size passes through (64×22)
expected: Resize your terminal to exactly 64 columns × 22 rows. The normal TUI (not the gate message) should be visible — at exactly 64×22 the gate should NOT trigger. Only terminals strictly smaller than 64 columns OR strictly smaller than 22 rows show the gate.
result: [pending]

### 4. Gate takes precedence over an open modal
expected: Open a modal (e.g. press 'n' to open the New Thread dialog). While the modal is visible, resize the terminal below 64 columns OR below 22 rows. The gate message should replace the modal — you should NOT see a half-rendered modal overlaid on a broken screen.
result: [pending]

### 5. Gate disappears when resizing back with modal still open
expected: With the gate visible (terminal too small, modal was open when you shrank), resize back to 64×22 or larger. The modal that was open before should reappear correctly, as if you never resized.
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
