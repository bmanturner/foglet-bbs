---
phase: 06
slug: threadlist
status: draft
nyquist_compliant: false
wave_0_complete: true
created: 2026-04-21
---

# Phase 06 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | ExUnit |
| **Config file** | `mix.exs` |
| **Quick run command** | `mix test test/foglet_bbs/tui/screens/thread_list_test.exs` |
| **Contract run command** | `mix test test/foglet_bbs/threads_test.exs` |
| **Full suite command** | `mix precommit` |
| **Estimated runtime** | ~60-120 seconds |

---

## Sampling Rate

- **After every task commit:** `mix test test/foglet_bbs/tui/screens/thread_list_test.exs`
- **After data-contract task:** `mix test test/foglet_bbs/threads_test.exs`
- **After plan wave:** `mix precommit`
- **Before `$gsd-verify-work`:** full suite must be green

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 06-01-01 | 01 | 1 | THREADS-01, THREADS-02, THREADS-03, THREADS-05, THREADS-06 | T-06-01 | Module probe and loading state behavior are explicit and safe | unit + grep | `mix test test/foglet_bbs/tui/screens/thread_list_test.exs` | ✅ | ⬜ pending |
| 06-01-02 | 01 | 1 | THREADS-04, THREADS-07, AUDIT-05, AUDIT-16, AUDIT-17, AUDIT-18, AUDIT-19 | T-06-02 | Preload contract and quality/scope gates hold | unit + full suite | `mix test test/foglet_bbs/threads_test.exs && mix precommit` | ✅ | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [x] Existing infrastructure covers all phase requirements.

---

## Manual-Only Verifications

- Confirm summary documents dead-code audit disposition for `load_threads/2` with command evidence.

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies
- [x] Sampling continuity has no long blind segments
- [x] Wave 0 covers required commands
- [x] No watch-mode flags
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
