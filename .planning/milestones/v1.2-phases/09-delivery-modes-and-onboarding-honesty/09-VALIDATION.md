---
phase: 09
slug: delivery-modes-and-onboarding-honesty
status: draft
nyquist_compliant: true
wave_0_complete: false
created: 2026-04-24
---

# Phase 09 - Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | ExUnit |
| **Config file** | `config/test.exs` |
| **Quick run command** | `rtk mix test test/foglet_bbs/config test/foglet_bbs/accounts/accounts_test.exs test/foglet_bbs/tui/screens/verify_test.exs` |
| **Full suite command** | `rtk mix precommit` |
| **Estimated runtime** | ~120 seconds |

---

## Sampling Rate

- **After every task commit:** Run the narrowest affected ExUnit file, prefixed with `rtk`.
- **After every plan wave:** Run `rtk mix test test/foglet_bbs/config test/foglet_bbs/accounts test/foglet_bbs/tui/screens test/mix/tasks`.
- **Before `$gsd-verify-work`:** `rtk mix precommit` must be green.
- **Max feedback latency:** 180 seconds for wave-level tests; full precommit may exceed this.

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 09-01-01 | 01 | 1 | MAIL-01 | T-09-01 | Delivery mode is a schematized non-secret enum with typed accessor. | unit | `rtk mix test test/foglet_bbs/config` | W0 | pending |
| 09-01-02 | 01 | 1 | MAIL-01, MAIL-02 | T-09-02 | Swoosh mailer uses runtime adapter config and test adapter in ExUnit. | unit | `rtk mix test test/foglet_bbs/accounts/accounts_test.exs` | W0 | pending |
| 09-02-01 | 02 | 1 | MAIL-02, MAIL-03, MAIL-05 | T-09-03 | Verification delivery attempts email only in email mode and never claims delivery in no-email mode. | unit | `rtk mix test test/foglet_bbs/accounts/accounts_test.exs test/foglet_bbs/tui/screens/verify_test.exs test/foglet_bbs/tui/screens/register_test.exs` | W0 | pending |
| 09-03-01 | 03 | 2 | MAIL-04, MAIL-05 | T-09-04 | Password reset request gives enumeration-safe outward response and no browser reset URL. | unit | `rtk mix test test/foglet_bbs/accounts/accounts_test.exs test/foglet_bbs/tui/screens/login_test.exs` | W0 | pending |
| 09-04-01 | 04 | 2 | MAIL-01, MAIL-06 | T-09-05 | Sysop config exposes delivery mode and blocks or clearly flags no-email plus required verification. | unit | `rtk mix test test/foglet_bbs/tui/screens/sysop` | W0 | pending |
| 09-05-01 | 05 | 3 | MAIL-04, MAIL-05, MAIL-06 | T-09-06 | Break-glass reset task remains operator-only and mode-honest. | unit | `rtk mix test test/mix/tasks/foglet_user_reset_password_test.exs` | W0 | pending |
| 09-06-01 | 06 | 3 | MAIL-01, MAIL-02, MAIL-03, MAIL-04, MAIL-05, MAIL-06 | T-09-07 | All user-facing copy avoids false delivery claims. | integration | `rtk mix test test/foglet_bbs/tui/screens test/mix/tasks` | W0 | pending |

*Status: pending, green, red, flaky*

---

## Wave 0 Requirements

- [ ] Existing ExUnit infrastructure covers all phase requirements.
- [ ] `config/test.exs` configures `Foglet.Mailer` with `Swoosh.Adapters.Test` once Swoosh is introduced.
- [ ] New or updated tests that mutate runtime `Foglet.Config` state are `async: false` and restore or invalidate config explicitly.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| SSH terminal reset-request ergonomics | MAIL-04 | Automated screen tests can verify state/copy, but not full operator feel. | Run a local SSH/TUI session, open Login, request password reset in email mode and no-email mode, and confirm navigation/copy are understandable. |

---

## Validation Sign-Off

- [x] All tasks have automated verify commands or Wave 0 dependencies.
- [x] Sampling continuity: no 3 consecutive tasks without automated verify.
- [x] Wave 0 covers all MISSING references.
- [x] No watch-mode flags.
- [x] Feedback latency target documented.
- [x] `nyquist_compliant: true` set in frontmatter.

**Approval:** pending
