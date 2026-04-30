---
status: testing
phase: 45-ssh-and-session-runtime-hardening
source:
  - 45-01-SUMMARY.md
  - 45-02-SUMMARY.md
  - 45-03-SUMMARY.md
started: 2026-04-29T20:30:00Z
updated: 2026-04-29T20:30:00Z
---

## Current Test

number: 1
name: Cold Start Smoke Test
expected: |
  Boot the app cleanly from scratch. `iex -S mix phx.server` (or
  `mix phx.server`) starts without errors. The SSH daemon comes up
  on its configured port. No crash logs from `Foglet.SSH.*`,
  `Foglet.Sessions.*`, or `Foglet.TUI.*`. A telemetry/IEx probe of
  `Foglet.SSH.ConnectionCounter` (or whatever exposes the global
  active-connection count) reports 0.
awaiting: user response

## Tests

### 1. Cold Start Smoke Test
expected: |
  Boot the app cleanly from scratch. SSH daemon starts; no crash
  logs from Foglet.SSH/Sessions/TUI; active-connection counter = 0.
result: [pending]

### 2. SSH Login With Registered Pubkey Resolves To User
expected: |
  Connect via SSH using a key registered to a known user (e.g.
  sysop). The TUI greets the authenticated user (no "guest" banner),
  message-of-the-day shows the user's handle, and the screen renders
  the authenticated main menu. Internally this exercises the
  PubkeyStash put → pop path with peer descriptor still working
  after the TTL/sweep refactor.
result: [pending]

### 3. SSH Login With Unregistered Key Falls Back To Guest
expected: |
  Connect via SSH using a key NOT associated with any user. The TUI
  presents the guest login/welcome flow (not an error or disconnect).
  Confirms the missing/expired-stash → guest fallback path still
  works after the TTL changes.
result: [pending]

### 4. Guest → User Promotion Emits Structured Audit Log
expected: |
  Start a guest session, then complete login/promotion to a known
  user from inside the TUI. The application log contains a single
  Logger.info line tagged `event: :guest_promoted` with structured
  metadata: session_pid, user_id, handle, ssh_peer, and replacement
  (e.g., :none, :same_session, or {:replaced, _pid}). No template
  string — keyword metadata.
result: [pending]

### 5. One-Session-Per-User Replacement Still Works
expected: |
  With user A logged in via SSH session #1, open SSH session #2 as
  the same user A. Session #1 is terminated (its TUI exits or shows
  a "replaced" notice), session #2 takes over. The promotion log
  for session #2 records `replacement: {:replaced, <old_pid>}`.
result: [pending]

### 6. SSH Active-Connection Counter Balances After Disconnect
expected: |
  From a clean state (counter = 0): open one SSH session — counter
  reads 1. Open a second — counter reads 2. Close both cleanly —
  counter returns to 0. Forcibly kill a third session (Ctrl+C/EOF
  from client side, kill the channel) — counter still returns to 0.
  Verifies cleanup/2 is idempotent and counter_counted? gates a
  single decrement per channel.
result: [pending]

## Summary

total: 6
passed: 0
issues: 0
pending: 6
skipped: 0

## Gaps

[none yet]
