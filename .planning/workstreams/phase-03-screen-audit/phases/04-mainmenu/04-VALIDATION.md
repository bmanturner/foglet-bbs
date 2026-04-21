---
phase: 04
slug: mainmenu
status: draft
nyquist_compliant: false
wave_0_complete: true
created: 2026-04-21
---

# Phase 04 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | ExUnit |
| **Config file** | `mix.exs` |
| **Quick run command** | `mix test test/foglet_bbs/tui/screens/main_menu_test.exs` |
| **Full suite command** | `mix precommit` |
| **Estimated runtime** | ~45 seconds |

---

## Sampling Rate

- **After every task commit:** Run `mix test test/foglet_bbs/tui/screens/main_menu_test.exs`
- **After every plan wave:** Run `mix precommit`
- **Before `$gsd-verify-work`:** Full suite must be green
- **Max feedback latency:** 45 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 04-01-01 | 01 | 1 | MENU-01, MENU-02, MENU-03, MENU-05 | — | Stateless route handling preserved; no dead helper injection | unit + grep | `mix test test/foglet_bbs/tui/screens/main_menu_test.exs` | ✅ | ⬜ pending |
| 04-01-02 | 01 | 1 | MENU-04, AUDIT-05, AUDIT-16, AUDIT-17, AUDIT-18, AUDIT-19 | — | No inline `{80, 24}`; no new reserved-region content; moduledoc states intentional statelessness | grep + full suite | `mix precommit` | ✅ | ⬜ pending |

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
- [x] Feedback latency < 45s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
