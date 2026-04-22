---
phase: 07
slug: newthread
status: draft
nyquist_compliant: false
wave_0_complete: true
created: 2026-04-22
---

# Phase 07 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | ExUnit |
| **Config file** | `mix.exs` |
| **Quick run command** | `mix test test/foglet_bbs/tui/screens/new_thread_test.exs` |
| **Full suite command** | `mix precommit` |
| **Estimated runtime** | ~60 seconds |

---

## Sampling Rate

- **After every task commit:** Run `mix test test/foglet_bbs/tui/screens/new_thread_test.exs`
- **After every plan wave:** Run `mix precommit`
- **Before `$gsd-verify-work`:** Full suite must be green
- **Max feedback latency:** 60 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 07-01-01 | 01 | 1 | NEWTHREAD-01, NEWTHREAD-02, NEWTHREAD-03, NEWTHREAD-04 | T-07-01, T-07-02 | Title-input migration preserves compose submit/cancel ordering and behavior | unit + grep | `mix test test/foglet_bbs/tui/screens/new_thread_test.exs` | ✅ | ⬜ pending |
| 07-01-02 | 01 | 1 | NEWTHREAD-05, AUDIT-05, AUDIT-15, AUDIT-16, AUDIT-17, AUDIT-18, AUDIT-19 | T-07-03 | Rubric/CI gates pass without adding reserved-region affordances | grep + full suite | `mix precommit` | ✅ | ⬜ pending |

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
- [x] Feedback latency < 60s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
