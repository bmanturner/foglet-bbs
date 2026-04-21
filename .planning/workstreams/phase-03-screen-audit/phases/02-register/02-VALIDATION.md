---
phase: 2
slug: register
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-04-21
---

# Phase 2 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | ExUnit (built-in, no install) |
| **Config file** | `test/foglet_bbs/tui/screens/register_test.exs` |
| **Quick run command** | `mix test test/foglet_bbs/tui/screens/register_test.exs` |
| **Full suite command** | `mix test` |
| **Estimated runtime** | ~15 seconds |

---

## Sampling Rate

- **After every task commit:** Run `mix test test/foglet_bbs/tui/screens/register_test.exs`
- **After every plan wave:** Run `mix test`
- **Before `/gsd-verify-work`:** Full suite must be green + `mix precommit` green
- **Max feedback latency:** 15 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 02-01-01 | 01 | 0 | REGISTER-01, REGISTER-06 | — | N/A | unit | `mix test test/foglet_bbs/tui/screens/register_test.exs` | ❌ W0 | ⬜ pending |
| 02-01-02 | 01 | 1 | REGISTER-01 | — | N/A | unit | `mix test test/foglet_bbs/tui/screens/register_test.exs` | ✅ | ⬜ pending |
| 02-01-03 | 01 | 1 | REGISTER-02, REGISTER-06 | — | N/A | unit | `mix test test/foglet_bbs/tui/screens/register_test.exs` | ✅ | ⬜ pending |
| 02-01-04 | 01 | 1 | REGISTER-03 | — | N/A | unit | `mix test test/foglet_bbs/tui/screens/register_test.exs` | ✅ | ⬜ pending |
| 02-01-05 | 01 | 1 | REGISTER-04 | — | N/A | unit | `mix compile --warnings-as-errors` | ✅ | ⬜ pending |
| 02-01-06 | 01 | 2 | REGISTER-05 | — | N/A | integration | `mix test && mix precommit` | ✅ | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `test/foglet_bbs/tui/screens/register_test.exs` — rewrite all existing tests to use `screen_state[:register]` shape; add new wizard-flow tests covering: full happy path (handle→email→password→confirm→submit), cancel-during-step flow, confirm-password mismatch, invite_only mode (invite_code step first)
- [ ] Remove all references to `state.register_wizard` from fixtures and assertions (293-line rewrite per RESEARCH.md)

*All existing register tests reference `state.register_wizard` directly — Wave 0 must rewrite the test file before any implementation tasks run.*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| AUDIT-16 line count gate | REGISTER-05 | Requires human inspection of final LoC | `wc -l lib/foglet_bbs/tui/screens/register.ex` — must be < 294 |
| AUDIT-17 no protected-region fill | REGISTER-05 | Visual layout check | Render screen and verify no content below error line |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 15s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
