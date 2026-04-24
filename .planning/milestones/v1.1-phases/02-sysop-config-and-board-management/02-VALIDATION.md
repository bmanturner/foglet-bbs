---
phase: 2
slug: sysop-config-and-board-management
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-04-23
---

# Phase 2 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | ExUnit (Elixir, mix test) |
| **Config file** | `test/test_helper.exs` |
| **Quick run command** | `mix test path/to/changed_test.exs` |
| **Full suite command** | `mix test` |
| **Estimated runtime** | ~30–60 seconds |

---

## Sampling Rate

- **After every task commit:** Run the focused `mix test path/to/test.exs` for the file(s) touched
- **After every plan wave:** Run `mix test`
- **Before `/gsd-verify-work`:** Full suite must be green and `mix precommit` clean
- **Max feedback latency:** 60 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| TBD — planner to populate from PLAN.md tasks | — | — | — | — | — | — | — | — | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] Planner to declare any new test files/fixtures per plan

*If none: "Existing infrastructure covers all phase requirements."*

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| TUI interaction spot-checks | SYSO-02, SYSO-03, SYSO-04 | Terminal rendering / keyboard flow is not covered by ExUnit | `iex -S mix foglet_bbs.tui` and exercise `SYSTEM`/`BOARDS` tabs |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 60s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
