---
phase: 10
slug: user-status-administration
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-04-24
---

# Phase 10 - Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | ExUnit |
| **Config file** | `mix.exs` |
| **Quick run command** | `rtk mix test test/foglet_bbs/accounts test/foglet_bbs/authorization_test.exs test/mix/tasks/foglet_user_status_test.exs` |
| **Full suite command** | `rtk mix precommit` |
| **Estimated runtime** | ~180 seconds |

---

## Sampling Rate

- **After every task commit:** Run `rtk mix test` scoped to the files touched by the task.
- **After every plan wave:** Run `rtk mix test test/foglet_bbs/accounts test/foglet_bbs/tui/screens test/mix/tasks`
- **Before `$gsd-verify-work`:** Full suite must be green.
- **Max feedback latency:** 180 seconds for targeted test runs.

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 10-01-01 | 01 | 1 | USER-02, USER-03 | T-10-01 | Non-sysop actors cannot change user status. | unit | `rtk mix test test/foglet_bbs/accounts test/foglet_bbs/authorization_test.exs` | W0 | pending |
| 10-01-02 | 01 | 1 | USER-02, USER-03 | T-10-02 | Invalid transitions do not mutate persisted status. | unit | `rtk mix test test/foglet_bbs/accounts` | W0 | pending |
| 10-02-01 | 02 | 1 | USER-01, USER-02, USER-03 | T-10-03 | Sysop USERS actions call Accounts APIs and surface tagged failures. | screen | `rtk mix test test/foglet_bbs/tui/screens/sysop_test.exs` | W0 | pending |
| 10-03-01 | 03 | 2 | USER-04 | T-10-04 | Break-glass task uses Accounts transition validation and reports delivery outcome. | task | `rtk mix test test/mix/tasks/foglet_user_status_test.exs` | W0 | pending |
| 10-04-01 | 04 | 2 | MAIL-07, USER-05 | T-10-05 | Login and notification copy reflects pending, rejected, suspended, active, and reactivated states. | integration | `rtk mix test test/foglet_bbs/tui/screens/login_test.exs test/foglet_bbs/tui/screens/register_test.exs test/foglet_bbs/accounts` | W0 | pending |

*Status: pending, green, red, flaky*

---

## Wave 0 Requirements

- [ ] `test/foglet_bbs/accounts/user_status_test.exs` - status enum and transition graph tests for USER-02 and USER-03.
- [ ] `test/foglet_bbs/tui/screens/sysop_test.exs` - USERS tab render and action tests for USER-01 through USER-03.
- [ ] `test/mix/tasks/foglet_user_status_test.exs` - operator task tests for USER-04.
- [ ] Existing ExUnit infrastructure covers this phase; no new test framework is required.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| SSH terminal ergonomics for USERS key bindings | USER-01, USER-02, USER-03 | Automated screen tests can assert text and commands, but not full operator feel over SSH. | Run the app locally, enter the Sysop USERS tab as a sysop, and approve, reject, suspend, and reactivate fixture users. |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies.
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify.
- [ ] Wave 0 covers all MISSING references.
- [ ] No watch-mode flags.
- [ ] Feedback latency < 180s.
- [ ] `nyquist_compliant: true` set in frontmatter.

**Approval:** pending
