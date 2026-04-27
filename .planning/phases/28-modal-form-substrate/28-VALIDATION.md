---
phase: 28
slug: modal-form-substrate
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-04-27
---

# Phase 28 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | ExUnit (Elixir 1.16+, OTP 26+) |
| **Config file** | `test/test_helper.exs`, `mix.exs` |
| **Quick run command** | `rtk mix test test/foglet_bbs/tui/widgets/modal_form_test.exs` |
| **Full suite command** | `rtk mix test` |
| **Estimated runtime** | ~30s quick / ~3 min full suite |

---

## Sampling Rate

- **After every task commit:** Run quick run command for the touched module
- **After every plan wave:** Run `rtk mix test` (full suite)
- **Before `/gsd-verify-work`:** Full suite must be green and `rtk mix precommit` passes (compile-as-error, format, Credo, Sobelow, Dialyzer)
- **Max feedback latency:** ~30 seconds for unit tests

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| TBD | TBD | TBD | FORM-01..06 | — | N/A (TUI substrate, no auth surface) | unit | `rtk mix test` | ❌ W0 | ⬜ pending |

*Per-task rows will be filled by the planner. Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `test/foglet_bbs/tui/widgets/modal_form_test.exs` — unit tests for Modal.Form widget (FORM-01..06)
- [ ] `test/foglet_bbs/tui/widgets/modal_form_field_test.exs` — field component tests (text, password, select)
- [ ] Existing `test/test_helper.exs` already configures ExUnit for Foglet BBS — no framework install needed

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Visual layout / box rendering of modal form on real terminal | FORM-01 | Layout engine output is best confirmed visually | `rtk mix foglet.tui.render <screen-using-modal-form>` and visually confirm framed modal, focused field highlight, error tray |
| Keyboard interaction (Tab, Shift+Tab, Enter, Esc) over real SSH | FORM-02, FORM-03 | Real terminal key encoding can differ from synthetic input | Connect via `ssh` to a dev daemon, navigate a modal form, confirm focus cycling and submission |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
