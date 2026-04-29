---
phase: 35
slug: auth-home-screens
status: draft
nyquist_compliant: true
wave_0_complete: true
created: 2026-04-28
---

# Phase 35 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | ExUnit |
| **Config file** | `test/test_helper.exs` |
| **Quick run command** | `rtk mix test test/foglet_bbs/tui/screens/login_test.exs test/foglet_bbs/tui/screens/register_test.exs test/foglet_bbs/tui/screens/verify_test.exs test/foglet_bbs/tui/screens/main_menu_test.exs test/foglet_bbs/tui/app_test.exs` |
| **Full suite command** | `rtk mix test test/foglet_bbs/tui/screens/login_test.exs test/foglet_bbs/tui/screens/register_test.exs test/foglet_bbs/tui/screens/verify_test.exs test/foglet_bbs/tui/screens/main_menu_test.exs test/foglet_bbs/tui/app_test.exs test/foglet_bbs/tui/layout_smoke_test.exs && rtk mix compile --warnings-as-errors` |
| **Estimated runtime** | ~120 seconds |

---

## Sampling Rate

- **After every task commit:** Run the targeted test file named in the task.
- **After every plan wave:** Run the quick run command.
- **Before `$gsd-verify-work`:** Full suite must be green.
- **Max feedback latency:** 120 seconds.

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 35-01-01 | 01 | 1 | SCREEN-01 | T-35-01 | Auth task results stay screen-owned; no authorization change | reducer | `rtk mix test test/foglet_bbs/tui/screens/login_test.exs` | yes | pending |
| 35-02-01 | 02 | 1 | SCREEN-01 | T-35-02 | Registration/verification side effects stay in Accounts contexts | reducer | `rtk mix test test/foglet_bbs/tui/screens/register_test.exs test/foglet_bbs/tui/screens/verify_test.exs` | yes | pending |
| 35-03-01 | 03 | 1 | SCREEN-02 | T-35-03 | Oneliner hide gating remains Bodyguard-backed | reducer | `rtk mix test test/foglet_bbs/tui/screens/main_menu_test.exs` | yes | pending |
| 35-04-01 | 04 | 2 | SCREEN-01, SCREEN-02 | T-35-04 | App routes effects/results generically and preserves modal/session precedence | integration | `rtk mix test test/foglet_bbs/tui/app_test.exs test/foglet_bbs/tui/layout_smoke_test.exs` | yes | pending |

*Status: pending until executor updates this file or summarizes results in plan summaries.*

---

## Wave 0 Requirements

Existing infrastructure covers all phase requirements.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| None | SCREEN-01, SCREEN-02 | All phase behaviors have automated verification. | N/A |

---

## Validation Sign-Off

- [x] All tasks have automated verify commands or existing infrastructure.
- [x] Sampling continuity: no 3 consecutive tasks without automated verify.
- [x] Wave 0 covers all missing references.
- [x] No watch-mode flags.
- [x] Feedback latency target documented.
- [x] `nyquist_compliant: true` set in frontmatter.

**Approval:** pending execution
