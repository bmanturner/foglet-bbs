---
phase: 31
slug: auth-flow
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-04-27
---

# Phase 31 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | ExUnit |
| **Config file** | `mix.exs` |
| **Quick run command** | `rtk mix test test/foglet_bbs/accounts/verification_test.exs test/foglet_bbs/tui/screens/login_test.exs test/foglet_bbs/tui/layout_smoke_test.exs` |
| **Full suite command** | `rtk mix precommit` |
| **Estimated runtime** | ~60 seconds quick, longer for precommit |

---

## Sampling Rate

- **After every task commit:** Run the narrow quick command for the touched auth/TUI test files.
- **After every plan wave:** Run `rtk mix precommit`.
- **Before `$gsd-verify-work`:** Full suite must be green.
- **Max feedback latency:** 60 seconds for narrow feedback.

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 31-01-01 | 01 | 1 | AUTH-04 | T-31-01 | Raw reset token consumption is single-use and atomic. | domain | `rtk mix test test/foglet_bbs/accounts/verification_test.exs` | yes | pending |
| 31-01-02 | 01 | 1 | AUTH-03 | T-31-02 | Sysop contact helper exposes only active non-deleted sysop emails. | domain | `rtk mix test test/foglet_bbs/accounts/verification_test.exs` | yes | pending |
| 31-02-01 | 02 | 2 | AUTH-01, AUTH-03 | T-31-03 | Forgot Password is reachable in email and no-email modes; invalid email shapes do not trigger reset delivery. | TUI state | `rtk mix test test/foglet_bbs/tui/screens/login_test.exs` | yes | pending |
| 31-03-01 | 03 | 3 | AUTH-02, AUTH-03, AUTH-04 | T-31-04 | Compact copy wraps and raw tokens never leak outside the input field. | TUI render | `rtk mix test test/foglet_bbs/tui/layout_smoke_test.exs` | yes | pending |
| 31-04-01 | 04 | 4 | AUTH-01, AUTH-02, AUTH-03, AUTH-04 | T-31-05 | Integrated auth flow passes narrow and full checks. | integration | `rtk mix precommit` | yes | pending |

*Status: pending · green · red · flaky*

---

## Wave 0 Requirements

Existing ExUnit infrastructure covers all phase requirements.

---

## Manual-Only Verifications

All phase behaviors have automated verification.

---

## Validation Sign-Off

- [ ] All tasks have automated verify commands.
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify.
- [ ] Existing tests cover all phase requirements.
- [ ] No watch-mode flags.
- [ ] Feedback latency < 60s for narrow checks.
- [ ] `nyquist_compliant: true` set in frontmatter after execution validation proves coverage.

**Approval:** pending
