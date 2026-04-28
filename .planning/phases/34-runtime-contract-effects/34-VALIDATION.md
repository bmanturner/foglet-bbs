---
phase: 34
slug: runtime-contract-effects
status: draft
nyquist_compliant: true
wave_0_complete: true
created: 2026-04-28
---

# Phase 34 - Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | ExUnit |
| **Config file** | `mix.exs` |
| **Quick run command** | `rtk mix test test/foglet_bbs/tui/screen_test.exs test/foglet_bbs/tui/context_test.exs test/foglet_bbs/tui/effect_test.exs test/foglet_bbs/tui/app_runtime_contract_test.exs test/foglet_bbs/tui/app_test.exs` |
| **Full suite command** | `rtk mix precommit` |
| **Estimated runtime** | ~60 seconds targeted, project precommit varies |

---

## Sampling Rate

- **After every task commit:** Run `rtk mix test test/foglet_bbs/tui/screen_test.exs test/foglet_bbs/tui/context_test.exs test/foglet_bbs/tui/effect_test.exs test/foglet_bbs/tui/app_runtime_contract_test.exs test/foglet_bbs/tui/app_test.exs`
- **After every plan wave:** Run the targeted suite plus any existing touched-file tests.
- **Before `$gsd-verify-work`:** `rtk mix precommit` must be green or any pre-existing blocker must be documented in the phase summary.
- **Max feedback latency:** 90 seconds for targeted checks.

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 34-01-01 | 01 | 1 | RUNTIME-01 | T-34-01 | New screen contract does not expose full App state to new callbacks | unit | `rtk mix test test/foglet_bbs/tui/screen_test.exs` | W0 | pending |
| 34-01-02 | 01 | 1 | RUNTIME-03 | T-34-02 | Context excludes screen-specific App storage | unit | `rtk mix test test/foglet_bbs/tui/context_test.exs` | W0 | pending |
| 34-01-03 | 01 | 1 | EFFECT-01 | T-34-03 | Effects are explicit values and cannot execute work by construction | unit | `rtk mix test test/foglet_bbs/tui/effect_test.exs` | W0 | pending |
| 34-02-01 | 02 | 2 | RUNTIME-02 | T-34-04 | App routes only normalized messages through screen update | integration | `rtk mix test test/foglet_bbs/tui/app_runtime_contract_test.exs` | W0 | pending |
| 34-02-02 | 02 | 2 | EFFECT-02 | T-34-05 | Task effects become `Foglet.TUI.Command.task/2` commands | integration | `rtk mix test test/foglet_bbs/tui/app_runtime_contract_test.exs` | W0 | pending |
| 34-02-03 | 02 | 2 | EFFECT-03 | T-34-06 | Task success and failure route back to the requesting screen update | integration | `rtk mix test test/foglet_bbs/tui/app_runtime_contract_test.exs` | W0 | pending |
| 34-02-04 | 02 | 2 | EFFECT-04 | T-34-07 | Navigation params are available through context after init | integration | `rtk mix test test/foglet_bbs/tui/app_runtime_contract_test.exs` | W0 | pending |
| 34-03-01 | 03 | 3 | STATE-01 | T-34-08 | State convention avoids leaking screen-owned fields into Context | unit | `rtk mix test test/foglet_bbs/tui/screen_test.exs test/foglet_bbs/tui/context_test.exs` | W0 | pending |
| 34-03-02 | 03 | 3 | RUNTIME-01,EFFECT-02 | T-34-09 | Existing App behavior remains compatible while new path lands | regression | `rtk mix test test/foglet_bbs/tui/app_test.exs` | W0 | pending |

---

## Wave 0 Requirements

Existing infrastructure covers all phase requirements.

---

## Manual-Only Verifications

All phase behaviors have automated verification.

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references
- [x] No watch-mode flags
- [x] Feedback latency < 90 seconds for targeted checks
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
