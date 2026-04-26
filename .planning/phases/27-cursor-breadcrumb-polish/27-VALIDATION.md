---
phase: 27
slug: cursor-breadcrumb-polish
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-04-26
---

# Phase 27 - Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | ExUnit via Mix |
| **Config file** | `mix.exs` |
| **Quick run command** | `rtk mix test test/foglet_bbs/tui/widgets/input/text_input_test.exs test/foglet_bbs/tui/widgets/chrome/breadcrumb_test.exs test/foglet_bbs/tui/screens/login_test.exs` |
| **Full suite command** | `rtk mix precommit` |
| **Estimated runtime** | ~180 seconds |

---

## Sampling Rate

- **After every task commit:** Run the most focused ExUnit file named by the task.
- **After every plan wave:** Run `rtk mix test test/foglet_bbs/tui/widgets/input/text_input_test.exs test/foglet_bbs/tui/widgets/chrome/breadcrumb_test.exs test/foglet_bbs/tui/layout_smoke_test.exs`.
- **Before `$gsd-verify-work`:** `rtk mix precommit` must be green.
- **Max feedback latency:** 180 seconds for focused checks; full precommit may exceed this.

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 27-01-01 | 01 | 1 | CURSOR-01 | T-27-01 / - | N/A | unit | `rtk mix test test/foglet_bbs/tui/widgets/input/text_input_test.exs` | yes | pending |
| 27-02-01 | 02 | 1 | BREAD-01 | T-27-02 / - | N/A | unit | `rtk mix test test/foglet_bbs/tui/widgets/chrome/breadcrumb_test.exs test/foglet_bbs/tui/screens/login_test.exs` | yes | pending |
| 27-03-01 | 03 | 2 | CURSOR-01, BREAD-01 | T-27-03 / - | N/A | integration | `rtk mix test test/foglet_bbs/tui/layout_smoke_test.exs` | yes | pending |

---

## Wave 0 Requirements

Existing ExUnit infrastructure covers all phase requirements.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| SSH visual cursor placement at 64x22 and 80x24 | CURSOR-01 | Render-tree tests can verify cells, but a terminal sanity pass catches visual regressions in the SSH surface. | Start the SSH TUI, focus Login/Register/Forgot/Verify/Account/Sysop inputs at 64x22 and 80x24, type five chars, backspace twice, and confirm the cursor visually lands after the third cell. |

---

## Validation Sign-Off

- [ ] All tasks have automated verify commands or explicit manual-only justification.
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify.
- [ ] Wave 0 covers all missing references.
- [ ] No watch-mode flags.
- [ ] Feedback latency < 180s for focused checks.
- [ ] `nyquist_compliant: true` set in frontmatter when execution validates coverage.

**Approval:** pending
