---
phase: 08
slug: moderation-workspace-population-and-scope-aware-operations
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-04-24
---

# Phase 08 - Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | ExUnit / Phoenix DataCase |
| **Config file** | `mix.exs` |
| **Quick run command** | `mix test test/foglet_bbs/oneliners/oneliners_test.exs test/foglet_bbs/tui/app_test.exs test/foglet_bbs/tui/screens/main_menu_test.exs test/foglet_bbs/tui/screens/moderation_test.exs` |
| **Full suite command** | `mix test` |
| **Estimated runtime** | ~30-90 seconds targeted, full suite at wave boundaries |

---

## Sampling Rate

- **After every task commit:** Run `mix test test/foglet_bbs/oneliners/oneliners_test.exs test/foglet_bbs/tui/app_test.exs test/foglet_bbs/tui/screens/main_menu_test.exs test/foglet_bbs/tui/screens/moderation_test.exs`
- **After every plan wave:** Run `mix test`
- **Before `$gsd-verify-work`:** Full suite and `mix precommit` must be green
- **Max feedback latency:** 90 seconds for targeted checks, full suite at wave boundaries

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 08-01-01 | 01 | 1 | MODR-05 | T-08-01 | Unauthorized actors cannot mutate oneliners or create audit rows | unit/integration | `mix test test/foglet_bbs/oneliners/oneliners_test.exs test/foglet_bbs/moderation/moderation_test.exs` | W0 if missing | pending |
| 08-01-02 | 01 | 1 | MODR-05 | T-08-02 | Blank hide reasons fail before persistence | unit/integration | `mix test test/foglet_bbs/oneliners/oneliners_test.exs` | W0 if missing | pending |
| 08-01-03 | 01 | 1 | MODR-05 | T-08-03 | Successful hides create exactly one narrow audit action | integration | `mix test test/foglet_bbs/oneliners/oneliners_test.exs test/foglet_bbs/moderation/moderation_test.exs` | W0 if missing | pending |
| 08-02-01 | 02 | 2 | MODR-05 | T-08-04 | Moderation tabs render loaded scoped state without fake mutation commands | TUI/unit | `mix test test/foglet_bbs/tui/app_test.exs test/foglet_bbs/tui/screens/moderation_test.exs` | W0 if missing | pending |
| 08-03-01 | 03 | 2 | MODR-05 | T-08-05 | Main-menu hide modal uses current actor and required reason only | TUI/unit | `mix test test/foglet_bbs/tui/app_test.exs test/foglet_bbs/tui/screens/main_menu_test.exs` | W0 if missing | pending |
| 08-04-01 | 04 | 3 | MODR-05 | T-08-06 | Final verification covers domain, audit, TUI, and precommit gates | integration | `mix precommit` | existing | pending |

*Status: pending / green / red / flaky*

---

## Wave 0 Requirements

- [ ] `test/foglet_bbs/moderation/moderation_test.exs` - create if no moderation context test file exists.
- [ ] Existing `test/foglet_bbs/oneliners/oneliners_test.exs` - extend for hide authorization, validation, recent-visible exclusion, and audit side effects.
- [ ] Existing `test/foglet_bbs/tui/app_test.exs` - extend fake domain modules for moderation and oneliner hide command paths.
- [ ] Existing `test/foglet_bbs/tui/screens/main_menu_test.exs` and `test/foglet_bbs/tui/screens/moderation_test.exs` - extend render assertions.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Focused hide affordance feels usable in the terminal layout | MODR-05 | Exact keyboard feel and visual density are better verified in a running TUI | Run the main menu as a moderator with several oneliners, select a row, open the hide modal, cancel, then hide with a reason and confirm the row disappears |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 90s for targeted checks
- [ ] `nyquist_compliant: true` set in frontmatter once Wave 0 and automated coverage are complete

**Approval:** pending
