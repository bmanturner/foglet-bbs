---
phase: 03
slug: verify
status: approved
nyquist_compliant: true
wave_0_complete: true
created: 2026-04-21
---

# Phase 03 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | ExUnit |
| **Config file** | `mix.exs`, `test/test_helper.exs` |
| **Quick run command** | `mix test test/foglet_bbs/tui/screens/verify_test.exs test/foglet_bbs/tui/layout_smoke_test.exs` |
| **Full suite command** | `mix test` and `mix precommit` |
| **Estimated runtime** | ~60 seconds |

---

## Sampling Rate

- **After every task commit:** Run `mix test test/foglet_bbs/tui/screens/verify_test.exs`
- **After every plan wave:** Run `mix test test/foglet_bbs/tui/screens/verify_test.exs test/foglet_bbs/tui/layout_smoke_test.exs`
- **Before `$gsd-verify-work`:** Full suite must be green
- **Max feedback latency:** 60 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 03-01-01 | 01 | 0 | VERIFY-05 | T-03-01 | Verify tests assert against `screen_state[:verify]` rather than top-level `verify_state` | unit | `mix test test/foglet_bbs/tui/screens/verify_test.exs` | ✅ | ⬜ pending |
| 03-01-02 | 01 | 0 | VERIFY-05 | T-03-01 | Layout smoke fixtures seed migrated verify state including `resend_cooldown_until` | smoke | `mix test test/foglet_bbs/tui/layout_smoke_test.exs` | ✅ | ⬜ pending |
| 03-02-01 | 02 | 1 | VERIFY-01 | T-03-02 | `verify.ex` still renders the hand-rolled `[ABC___]` slot path and cites the keep-hand-rolled rationale | unit | `mix test test/foglet_bbs/tui/screens/verify_test.exs` | ✅ | ⬜ pending |
| 03-02-02 | 02 | 1 | VERIFY-02 | T-03-03 | All default verify-state reads/writes route through `default_verify_state/0` and `screen_state[:verify]` helpers | unit | `mix test test/foglet_bbs/tui/screens/verify_test.exs` | ✅ | ⬜ pending |
| 03-02-03 | 02 | 1 | VERIFY-03 | T-03-01 / T-03-02 | Attempt lockout and resend cooldown stay independent and behaviorally identical | unit | `mix test test/foglet_bbs/tui/screens/verify_test.exs` | ✅ | ⬜ pending |
| 03-03-01 | 03 | 2 | VERIFY-04 | T-03-01 / T-03-02 / T-03-03 | Audit gates, line-count reduction, and full precommit suite pass without regressions | static + suite | `mix precommit` | ✅ | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [x] `test/foglet_bbs/tui/screens/verify_test.exs` — rewrite assertions and fixtures away from top-level `verify_state`
- [x] `test/foglet_bbs/tui/layout_smoke_test.exs` — migrate Verify smoke fixtures to `screen_state[:verify]` and include `resend_cooldown_until`

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Verify screen still reads as a minimal gateway with no rows added below the status/error region | VERIFY-04 | Protected-region and row-count checks are partly visual even after automated grep gates | Launch the TUI over SSH, enter the Verify screen, confirm the content remains instruction line + slot line + status line with modal-only blocked-action feedback |

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references
- [x] No watch-mode flags
- [x] Feedback latency < 60s
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** approved 2026-04-21
