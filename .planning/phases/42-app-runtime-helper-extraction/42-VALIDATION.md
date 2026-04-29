---
phase: 42
slug: app-runtime-helper-extraction
status: draft
nyquist_compliant: true
wave_0_complete: true
created: 2026-04-29
---

# Phase 42 - Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | ExUnit / Mix |
| **Config file** | `mix.exs` |
| **Quick run command** | `rtk mix test test/foglet_bbs/tui/app_runtime_contract_test.exs test/foglet_bbs/tui/app_test.exs test/foglet_bbs/tui/app` |
| **Full suite command** | `rtk mix precommit` |
| **Estimated runtime** | ~180 seconds |

---

## Sampling Rate

- **After every task commit:** Run `rtk mix test test/foglet_bbs/tui/app_runtime_contract_test.exs test/foglet_bbs/tui/app_test.exs test/foglet_bbs/tui/app`
- **After every plan wave:** Run `rtk mix precommit`
- **Before `$gsd-verify-work`:** Full suite must be green
- **Max feedback latency:** 180 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 42-01-01 | 01 | 1 | TUI-04 | - | N/A | helper unit/integration | `rtk mix test test/foglet_bbs/tui/app/routing_test.exs test/foglet_bbs/tui/app_runtime_contract_test.exs` | yes | pending |
| 42-02-01 | 02 | 2 | TUI-04 | - | N/A | helper unit/integration | `rtk mix test test/foglet_bbs/tui/app/modal_test.exs test/foglet_bbs/tui/app_test.exs` | yes | pending |
| 42-03-01 | 03 | 3 | TUI-04 | - | N/A | helper unit/integration | `rtk mix test test/foglet_bbs/tui/app/effects_test.exs test/foglet_bbs/tui/app_runtime_contract_test.exs` | yes | pending |
| 42-04-01 | 04 | 4 | TUI-04 | - | N/A | helper unit/integration | `rtk mix test test/foglet_bbs/tui/app/subscriptions_test.exs test/foglet_bbs/tui/app_test.exs` | yes | pending |
| 42-05-01 | 05 | 5 | TUI-04 | - | N/A | integration/regression | `rtk mix precommit` | yes | pending |

*Status: pending / green / red / flaky*

---

## Wave 0 Requirements

Existing ExUnit infrastructure covers all phase requirements.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| None | TUI-04 | All phase behaviors have automated verification. | N/A |

---

## Validation Sign-Off

- [x] All tasks have automated verify commands or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references
- [x] No watch-mode flags
- [x] Feedback latency < 180s
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
