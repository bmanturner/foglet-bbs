---
status: partial
phase: 27-cursor-breadcrumb-polish
source: [27-VERIFICATION.md]
started: 2026-04-26T18:20:00-05:00
updated: 2026-04-26T18:20:00-05:00
---

## Current Test

[awaiting human testing]

## Tests

### 1. Live SSH cursor behavior
expected: The `▌` marker appears at the active insertion point (after the last typed character, not before the whole field). After typing "hello" and pressing backspace twice, cursor appears after "hel".
result: [pending]

### 2. Live breadcrumb navigation
expected: Breadcrumb text updates correctly as user navigates between Login sub-states — Login menu shows "Foglet / Login", Register shows "Foglet / Login / Register", Forgot Password shows "Foglet / Login / Forgot Password". Pressing Escape back to menu returns to bare "Foglet / Login".
result: [pending]

## Summary

total: 2
passed: 0
issues: 0
pending: 2
skipped: 0
blocked: 0

## Gaps
