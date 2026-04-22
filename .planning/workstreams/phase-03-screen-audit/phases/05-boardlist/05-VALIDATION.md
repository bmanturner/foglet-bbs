---
phase: 05
slug: boardlist
status: draft
nyquist_compliant: false
wave_0_complete: true
created: 2026-04-22
---

# Phase 05 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | ExUnit |
| **Config file** | `mix.exs` |
| **Quick run command** | `mix test test/foglet_bbs/tui/screens/board_list_test.exs` |
| **Full suite command** | `mix precommit` |
| **Estimated runtime** | ~50 seconds |

---

## Sampling Rate

- **After every task commit:** Run `mix test test/foglet_bbs/tui/screens/board_list_test.exs`
- **After every plan wave:** Run `mix precommit`
- **Before `$gsd-verify-work`:** Full suite must be green
- **Max feedback latency:** 50 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 05-01-01 | 01 | 1 | BOARDS-01, BOARDS-02, BOARDS-03, BOARDS-04 | T-05-01 | Loading state only reflects real in-flight board load; no render-path mutation | unit + grep | `mix test test/foglet_bbs/tui/screens/board_list_test.exs` | ✅ | ⬜ pending |
| 05-01-02 | 01 | 1 | BOARDS-05, AUDIT-05, AUDIT-12, AUDIT-16, AUDIT-17, AUDIT-18, AUDIT-19 | T-05-02 | Scope fence + quality gates hold; no protected-region additions | grep + full suite | `mix precommit` | ✅ | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [x] Existing infrastructure covers all phase requirements.

---

## Manual-Only Verifications

All phase behaviors have automated verification.

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references
- [x] No watch-mode flags
- [x] Feedback latency < 50s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
