---
status: partial
phase: 07-oneliners-and-main-menu-social-strip
source:
  - 07-VERIFICATION.md
started: 2026-04-24T03:47:52Z
updated: 2026-04-24T03:47:52Z
---

# Phase 07 Human UAT

## Current Test

[awaiting human testing]

## Tests

### 1. First Render Visual Check

expected: The first main-menu render shows the Oneliners strip with recent rows, keeps the normal menu/key bar visible, and does not show timestamps or hide controls.
result: [pending]

Steps:
- SSH into the TUI as an authenticated user with existing visible oneliners.
- Inspect the first main-menu render before navigating or posting.

### 2. Composer Interaction Check

expected: The composer is focused, valid submit returns to the main menu with a refreshed strip, and invalid submit keeps the modal open with visible error copy.
result: [pending]

Steps:
- Press O from the main menu.
- Type and submit a valid oneliner.
- Try an invalid or same-user consecutive post.

## Summary

total: 2
passed: 0
issues: 0
pending: 2
skipped: 0
blocked: 0

## Gaps
