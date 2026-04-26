---
status: partial
phase: 19-main-menu-dashboard
source: [19-VERIFICATION.md]
started: 2026-04-25T15:42:00Z
updated: 2026-04-25T15:42:00Z
---

## Current Test

[awaiting human testing]

## Tests

### 1. Navigate the main menu at 64x22 over a real SSH session — press B, C, A, Q; confirm each hotkey still works.
expected: Each destination key navigates immediately without requiring selection-cursor movement. The Navigation panel renders two boxed panels side by side, not stacked. Key letters are right-aligned against the panel edge.
why_human: The Raxol layout engine is exercised by positioned-render tests, but real SSH rendering depends on terminal emulator cell-width interpretation of Unicode glyphs (●, ✎, ◇, ⚑, ▣, ↯). The panel right-align math can pass CI while still producing misaligned columns in terminals that measure glyph width differently.
result: [pending]

### 2. Post an oneliner and observe the main menu refreshes with the new entry visible without page reload.
expected: Oneliners panel shows the new entry in the `> @handle  body` row format within the 5-row display limit.
why_human: PubSub subscription wiring is not exercised by unit or layout-smoke tests — only a live SSH session with a connected user confirms real-time update.
result: [pending]

## Summary

total: 2
passed: 0
issues: 0
pending: 2
skipped: 0
blocked: 0

## Gaps
