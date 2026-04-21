---
status: testing
phase: 06-email-verification-toggle-resend
source: [06-01-SUMMARY.md, 06-02-SUMMARY.md, 06-03-SUMMARY.md]
started: 2026-04-20T20:30:00Z
updated: 2026-04-20T20:30:00Z
---

## Current Test

number: 1
name: Cold Start Smoke Test
expected: |
  Kill any running server. Run `mix run priv/repo/seeds.exs` from scratch.
  Both `require_email_verification` and `email_verify_resend_cooldown_seconds`
  seeds insert on first run, print "already present" on re-run (idempotent).
  Start the app (`mix phx.server` or equivalent). No errors on boot.
awaiting: user response

## Tests

### 1. Cold Start Smoke Test
expected: Kill any running server. Run `mix run priv/repo/seeds.exs` from scratch. Both `require_email_verification` and `email_verify_resend_cooldown_seconds` seeds insert on first run, print "already present" on re-run (idempotent). Start the app (`mix phx.server` or equivalent). No errors on boot.
result: [pending]

### 2. Login with verification enabled → verify screen
expected: With `require_email_verification = true` (default), log in as an unconfirmed user. After entering correct credentials you should be taken to the verify screen (not the main menu). A verification code is emailed/logged in dev.
result: [pending]

### 3. Login with verification disabled → main menu bypass
expected: Set `require_email_verification = false` (via admin or seeds). Log in as an unconfirmed user. You should be taken directly to the main menu — no verify screen appears at all.
result: [pending]

### 4. Registration with verification enabled → verify screen
expected: With `require_email_verification = true`, complete registration (handle → email → password). After success you should land on the verify screen, not the main menu.
result: [pending]

### 5. Registration with verification disabled → main menu bypass
expected: With `require_email_verification = false`, complete registration. After success you should land directly on the main menu — no verify screen.
result: [pending]

### 6. Invalid-attempts cooldown does NOT block Resend
expected: On the verify screen, enter a wrong code 5 times to trigger the invalid-attempts lockout (code entry is blocked). The Resend button should still be clickable/active — hitting Resend should send a new code and the resend cooldown timer starts. The invalid-attempts lockout is independent of the resend button.
result: [pending]

### 7. Resend cooldown does NOT block code entry
expected: After a successful resend (resend cooldown is now active), you should still be able to type characters into the code input field and submit. The resend cooldown only blocks pressing Resend again — it does not lock code entry.
result: [pending]

### 8. Successful resend resets state
expected: After pressing Resend: the code input buffer clears to empty, the attempt counter resets to 0 (invalid-attempt lockout is gone), and the resend button shows a cooldown timer (default 60s, or whatever `email_verify_resend_cooldown_seconds` is set to).
result: [pending]

## Summary

total: 8
passed: 0
issues: 0
pending: 8
skipped: 0
blocked: 0

## Gaps

[none yet]
