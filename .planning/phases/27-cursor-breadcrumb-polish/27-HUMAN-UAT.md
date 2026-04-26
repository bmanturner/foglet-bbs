---
status: complete
phase: 27-cursor-breadcrumb-polish
source: [27-VERIFICATION.md]
started: 2026-04-26T18:20:00-05:00
updated: 2026-04-26T20:30:00-05:00
---

## Current Test

[testing complete]

## Tests

### 1. Live SSH cursor behavior
expected: The `▌` marker appears at the active insertion point (after the last typed character, not before the whole field). After typing "hello" and pressing backspace twice, cursor appears after "hel".
result: pass

### 2. Live breadcrumb navigation
expected: Breadcrumb text updates correctly as user navigates between Login sub-states — Login menu shows "Foglet / Login", Register shows "Foglet / Login / Register", Forgot Password shows "Foglet / Login / Forgot Password". Pressing Escape back to menu returns to bare "Foglet / Login".
result: issue
reported: "Login menu should read: Foglet. Register should read: Foglet / Register. Login should read: Foglet / Login. Forgot password should show Foglet / Forgot Password"
severity: major

## Summary

total: 2
passed: 1
issues: 1
pending: 0
skipped: 0
blocked: 0

## Gaps

- truth: "Login menu shows Foglet / Login, Register shows Foglet / Login / Register, Forgot Password shows Foglet / Login / Forgot Password"
  status: fixed
  reason: "User reported: Login menu should read: Foglet. Register should read: Foglet / Register. Login should read: Foglet / Login. Forgot password should show Foglet / Forgot Password"
  severity: major
  test: 2
  root_cause: "Phase 27 implemented nested auth breadcrumbs (Login > Register, Login > Forgot Password) but design intent is flat — each auth screen is a direct child of root. login_parts/1 mapped nil/menu sub to Foglet/Login; :register/:verify screens included Login as intermediate segment."
  artifacts:
    - path: "lib/foglet_bbs/tui/widgets/chrome/breadcrumb_bar.ex"
      issue: "nil/:menu sub returned [@root, Login]; :register and :verify included Login nesting"
  missing:
    - "login_parts/1: nil and :menu → [@root]; :reset_request/:reset_consume drop Login parent"
    - "parts_for_screen :register → [@root, Register]; :verify → [@root, Verify]"
  debug_session: ""
