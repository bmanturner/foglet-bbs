---
status: partial
phase: 07-migrate-hand-rolled-ui-components-to-raxol-widgets
source: [07-VERIFICATION.md]
started: 2026-04-20T22:05:00Z
updated: 2026-04-20T22:05:00Z
---

## Current Test

[awaiting human testing]

## Tests

### 1. Modal color rendering under SSH
expected: Modal message text is hex-colored from theme slots; no hardcoded ANSI red/yellow/green visible. SSH into the running BBS, trigger an invalid-login modal (error type) and confirm the message color is the theme error hex (#ff5555) — not terminal `:red`. Trigger `/help` (info type) and confirm neutral color.
result: [pending]

### 2. Viewport scroll UX — j/k smoothness, N/P reset, terminal resize
expected: j advances one line at a time; k retreats one line, clamped at 0; N/P reset scroll to top of new post; terminal resize recalculates visible height without border fragments or jitter. SSH in, open a seeded post with more than 10 lines, press j/k line-by-line, press N/P to switch posts, and resize the terminal window.
result: [pending]

## Summary

total: 2
passed: 0
issues: 0
pending: 2
skipped: 0
blocked: 0

## Gaps
