---
phase: 09
slug: postreader
status: draft
nyquist_compliant: true
wave_0_complete: true
created: 2026-04-22
---

# Phase 09 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | ExUnit |
| **Config file** | `mix.exs` |
| **Quick run command** | `mix test test/foglet_bbs/tui/screens/post_reader_test.exs --max-failures 1` |
| **Full suite command** | `mix precommit` |
| **Estimated runtime** | ~25 seconds (quick run), ~60 seconds (full suite) |

---

## Sampling Rate

- **During task loop:** Run fast checks first:
  - `rg -n 'Loading…|Loading posts\\.\\.\\.' test/foglet_bbs/tui/screens/post_reader_test.exs`
  - `rg -n 'load_posts/2|flush_read_pointers/2|intentional callback|contract surface' test/foglet_bbs/tui/screens/post_reader_test.exs`
  - `rg -n 'render helper purity|defp render_|put_in\\(|%\\{state \\||Map\\.put\\(|absorb' test/foglet_bbs/tui/screens/post_reader_test.exs`
  - `mix test test/foglet_bbs/tui/screens/post_reader_test.exs --max-failures 1`
- **After every plan wave:** Run `mix precommit`
- **Before `$gsd-verify-work`:** Full suite must be green
- **Max feedback latency:** 30 seconds (fast loop), 60 seconds (final gate)

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 09-01-01 | 01 | 1 | READER-01, READER-02, READER-03, READER-04 | T-09-01, T-09-02 | Domain helper parity, spinner loading state, and render-path purity constraints are enforced without pipeline drift | unit + grep | `mix test test/foglet_bbs/tui/screens/post_reader_test.exs` | ✅ | ⬜ pending |
| 09-01-02 | 01 | 1 | READER-05, READER-06, READER-07, AUDIT-05, AUDIT-15, AUDIT-16, AUDIT-17, AUDIT-18, AUDIT-19 | T-09-03 | Public callback contract and load-absorb moduledoc guarantees remain explicit and verifiable while rubric gates stay green | unit + grep + full suite | `rg` assertions + `mix test ... --max-failures 1`, then `mix precommit` as final gate | ✅ | ⬜ pending |

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
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
