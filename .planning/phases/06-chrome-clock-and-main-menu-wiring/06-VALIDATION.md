---
phase: 06
slug: chrome-clock-and-main-menu-wiring
status: draft
nyquist_compliant: true
wave_0_complete: false
created: 2026-04-24
---

# Phase 06 - Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | ExUnit |
| **Config file** | `test/test_helper.exs` |
| **Quick run command** | `mix test test/foglet_bbs/tui/widgets/chrome/status_bar_test.exs test/foglet_bbs/tui/app_test.exs test/foglet_bbs/tui/screens/main_menu_test.exs` |
| **Full suite command** | `mix precommit` |
| **Estimated runtime** | ~180 seconds |

---

## Sampling Rate

- **After every task commit:** Run the focused test command for the changed TUI module/test pair.
- **After every plan wave:** Run `mix test test/foglet_bbs/tui/app_test.exs test/foglet_bbs/tui/screens/main_menu_test.exs test/foglet_bbs/tui/layout_smoke_test.exs`.
- **Before `$gsd-verify-work`:** `mix precommit` must be green.
- **Max feedback latency:** 180 seconds for focused checks; precommit can exceed this at phase gate.

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 06-01-01 | 01 | 0 | MENU-01 | T-06-02 / T-06-03 | Invalid or missing clock preferences fall back without render-time persistence reads. | unit/render | `mix test test/foglet_bbs/tui/widgets/chrome/status_bar_test.exs` | ❌ W0 | ⬜ pending |
| 06-01-02 | 01 | 0 | MENU-02 | — | Clock tick rerenders without changing navigation, modal, or loaded screen state. | unit | `mix test test/foglet_bbs/tui/app_test.exs` | ✅ | ⬜ pending |
| 06-01-03 | 01 | 0 | MENU-01 | T-06-01 | Account, Moderation, and Sysop render/key behavior remains delegated to `ShellVisibility`. | unit/render | `mix test test/foglet_bbs/tui/screens/main_menu_test.exs` | ✅ | ⬜ pending |
| 06-02-01 | 02 | 1 | MENU-01 | T-06-02 / T-06-03 | Main-menu chrome renders compact preference-aware clock text and keeps non-main-menu chrome unchanged. | unit/render | `mix test test/foglet_bbs/tui/widgets/chrome/status_bar_test.exs test/foglet_bbs/tui/layout_smoke_test.exs` | ❌ W0 / ✅ | ⬜ pending |
| 06-03-01 | 03 | 1 | MENU-02 | — | Main-menu-only interval exists at no slower than 60 seconds and no off-screen timer is added. | unit | `mix test test/foglet_bbs/tui/app_test.exs` | ✅ | ⬜ pending |
| 06-04-01 | 04 | 1 | MENU-01 | T-06-01 | Rendered entries, key bar entries, and accepted keys match `ShellVisibility` for user, moderator, and sysop roles. | unit/render | `mix test test/foglet_bbs/tui/screens/main_menu_test.exs` | ✅ | ⬜ pending |
| 06-05-01 | 05 | 2 | MENU-01, MENU-02 | T-06-01 / T-06-02 / T-06-03 | Integrated phase remains stable under layout smoke and precommit checks. | integration | `mix precommit` | ✅ | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `test/foglet_bbs/tui/widgets/chrome/status_bar_test.exs` - deterministic clock formatting and right-side chrome behavior for MENU-01.
- [ ] `test/foglet_bbs/tui/app_test.exs` - main-menu-only clock subscription and no-op tick behavior for MENU-02.
- [ ] `test/foglet_bbs/tui/screens/main_menu_test.exs` - role-table consistency with `ShellVisibility` for rendered menu entries, key-bar entries, and accepted keys.

---

## Manual-Only Verifications

All phase behaviors have automated verification.

---

## Threat References

| Threat Ref | Threat | Required Mitigation |
|------------|--------|---------------------|
| T-06-01 | Role/menu drift exposes hidden Account, Moderation, or Sysop surfaces. | Keep render and key handling delegated to `ShellVisibility`; test user/moderator/sysop matrices. |
| T-06-02 | Render-time database access causes chrome failures or leaks timing into screen rendering. | Use `state.current_user` and `state.session_context`; no persistence reads in widgets. |
| T-06-03 | Invalid or missing preference data crashes status-bar rendering. | Fallback invalid/missing timezone to `"Etc/UTC"` and invalid/missing time format to `"12h"`. |

---

## Validation Sign-Off

- [x] All tasks have `<automated>` verify or Wave 0 dependencies
- [x] Sampling continuity: no 3 consecutive tasks without automated verify
- [x] Wave 0 covers all MISSING references
- [x] No watch-mode flags
- [x] Feedback latency < 180s for focused checks
- [x] `nyquist_compliant: true` set in frontmatter

**Approval:** approved 2026-04-24
