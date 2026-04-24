---
phase: 07
slug: oneliners-and-main-menu-social-strip
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-04-23
---

# Phase 07 - Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | ExUnit / Phoenix.ConnTest |
| **Config file** | `mix.exs` |
| **Quick run command** | `mix test test/foglet_bbs/tui test/foglet_bbs/oneliners_test.exs test/foglet_bbs_web/live/main_menu_live_test.exs` |
| **Full suite command** | `mix test` |
| **Estimated runtime** | ~30-90 seconds |

---

## Sampling Rate

- **After every task commit:** Run `mix test test/foglet_bbs/tui test/foglet_bbs/oneliners_test.exs test/foglet_bbs_web/live/main_menu_live_test.exs`
- **After every plan wave:** Run `mix test`
- **Before `$gsd-verify-work`:** Full suite must be green
- **Max feedback latency:** 90 seconds for targeted tests, full suite at wave boundaries

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 07-01-01 | 01 | 1 | ONEL-01 | T-07-01 | Oneliner data is read through bounded query paths only | unit/integration | `mix test test/foglet_bbs/oneliners_test.exs` | W0 if missing | pending |
| 07-01-02 | 01 | 1 | ONEL-03 | T-07-02 | Stored text is length-bounded and validated before persistence | unit/integration | `mix test test/foglet_bbs/oneliners_test.exs` | W0 if missing | pending |
| 07-02-01 | 02 | 2 | ONEL-01 | T-07-03 | Main menu renders recent posts without exposing unsafe markup | LiveView/TUI | `mix test test/foglet_bbs_web/live/main_menu_live_test.exs test/foglet_bbs/tui` | W0 if missing | pending |
| 07-02-02 | 02 | 2 | ONEL-02 | T-07-04 | Posting flow enforces max length and rejects empty content | LiveView/TUI | `mix test test/foglet_bbs_web/live/main_menu_live_test.exs test/foglet_bbs/tui` | W0 if missing | pending |
| 07-03-01 | 03 | 3 | ONEL-01, ONEL-02, ONEL-03 | T-07-05 | End-to-end flow persists across restart and remains bounded | integration | `mix test test/foglet_bbs_web/live/main_menu_live_test.exs test/foglet_bbs/oneliners_test.exs` | W0 if missing | pending |

*Status: pending / green / red / flaky*

---

## Wave 0 Requirements

- [ ] `test/foglet_bbs/oneliners_test.exs` - storage, retrieval, validation, and persistence tests for ONEL-01 and ONEL-03 if no equivalent test exists
- [ ] `test/foglet_bbs_web/live/main_menu_live_test.exs` or closest existing main-menu LiveView/TUI integration test - render and post-flow tests for ONEL-01 and ONEL-02 if no equivalent test exists
- [ ] Existing fixtures or setup helpers for users/sessions/rooms reused from nearby tests

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Social strip feels alive without becoming chat-like noise | ONEL-01, ONEL-02 | Qualitative UX pacing and density are hard to fully prove with automated tests | Run the main menu locally, seed or post several oneliners, and confirm the strip is persistent, bounded, readable, and not visually dominant |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 90s for targeted checks
- [ ] `nyquist_compliant: true` set in frontmatter once Wave 0 and automated coverage are complete

**Approval:** pending
