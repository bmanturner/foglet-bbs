---
status: partial
phase: 03-ssh-server-tui
source: [03-VERIFICATION.md]
started: 2026-04-19T16:22:25Z
updated: 2026-04-19T16:22:25Z
---

## Current Test

[awaiting human testing]

## Tests

### 1. SSH host key persistence
expected: Connect twice to the SSH server; host key survives between connections (no "host key changed" warning) and TUI appears on second connection
result: [pending]

### 2. SSH public key auth chain
expected: Connect with a registered public key; PubkeyStash → CLIHandler → get_user_by_public_key/1 resolves correctly and StatusBar shows the correct handle after login
result: [pending]

### 3. Terminal resize rendering
expected: Resize the terminal window during an active session; TUI redraws to new dimensions — Raxol Rendering Engine re-layouts, not just state.terminal_size updating
result: [pending]

### 4. Full registration + email verification flow
expected: Press R from login menu → step through registration wizard → receive and enter email code → login successfully; no KeyError at any step, user status transitions to :active
result: [pending]

### 5. Board browsing + read pointer DB flush
expected: Login → press B → select a board → navigate into a thread → press Q; screens populate with real data (command_result re-dispatcher working end-to-end) and read pointers are written to the database
result: [pending]

## Summary

total: 5
passed: 0
issues: 0
pending: 5
skipped: 0
blocked: 0

## Gaps
