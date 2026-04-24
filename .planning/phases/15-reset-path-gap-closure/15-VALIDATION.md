---
phase: 15
slug: reset-path-gap-closure
status: draft
nyquist_compliant: true
wave_0_complete: false
created: 2026-04-24
---

# Phase 15 - Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | ExUnit with Mix aliases |
| **Config file** | `config/test.exs` |
| **Quick run command** | `rtk mix test test/mix/tasks/foglet_user_reset_password_test.exs test/foglet_bbs/accounts/accounts_test.exs test/foglet_bbs/tui/screens/delivery_copy_test.exs test/foglet_bbs/tui/screens/login_test.exs` |
| **Full suite command** | `rtk mix precommit` |
| **Estimated runtime** | ~90 seconds quick, full precommit varies with Dialyzer |

---

## Sampling Rate

- **After every task commit:** Run the narrowest affected command, usually `rtk mix test test/mix/tasks/foglet_user_reset_password_test.exs`
- **After every plan wave:** Run `rtk mix test test/mix/tasks/foglet_user_reset_password_test.exs test/foglet_bbs/accounts/accounts_test.exs test/foglet_bbs/tui/screens/delivery_copy_test.exs test/foglet_bbs/tui/screens/login_test.exs`
- **Before `$gsd-verify-work`:** `rtk mix precommit` must pass
- **Max feedback latency:** 120 seconds for quick checks

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 15-01-01 | 01 | 1 | MAIL-04 | T-15-01 | SMTP reset delivery sends terminal-native token email and break-glass remains available without email | unit/integration | `rtk mix test test/foglet_bbs/accounts/accounts_test.exs test/mix/tasks/foglet_user_reset_password_test.exs` | yes | pending |
| 15-01-02 | 01 | 1 | MAIL-06 | T-15-02 | No-email operator reset retrieval prints token/details without any browser URL | Mix task | `rtk mix test test/mix/tasks/foglet_user_reset_password_test.exs` | yes | pending |
| 15-02-01 | 02 | 1 | HYGN-02 | T-15-03 | Reset blocker tests cover happy path, forbidden path, and user/operator-facing copy | Mix task/copy audit | `rtk mix test test/mix/tasks/foglet_user_reset_password_test.exs test/foglet_bbs/tui/screens/delivery_copy_test.exs` | yes | pending |
| 15-02-02 | 02 | 1 | HYGN-03 | T-15-04 | README and Phase 14 blocker records agree about supported reset behavior | grep/manual docs audit | `rtk rg -n "/users/reset_password|operator reset URL|reset URL" README.md .planning/phases/14-launch-hygiene-and-operator-notes/14-BLOCKERS.md` | yes | pending |

---

## Wave 0 Requirements

- [ ] `test/mix/tasks/foglet_user_reset_password_test.exs` rejects browser URLs and validates raw-token round trip.
- [ ] `test/foglet_bbs/tui/screens/delivery_copy_test.exs` or equivalent copy audit ensures reset copy remains browser-free.
- [ ] Documentation verification checks `README.md` and `.planning/phases/14-launch-hygiene-and-operator-notes/14-BLOCKERS.md` consistency without reintroducing README-specific ExUnit tests.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| README/operator-note wording remains practical and non-contradictory | HYGN-03 | Phase 14 intentionally removed direct README-specific ExUnit tests by user request | Read `README.md` and `14-BLOCKERS.md`; confirm they do not claim a supported browser reset URL and describe only token/operator-assisted reset behavior. |

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references
- [x] No watch-mode flags
- [x] Feedback latency < 120s for quick checks
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
