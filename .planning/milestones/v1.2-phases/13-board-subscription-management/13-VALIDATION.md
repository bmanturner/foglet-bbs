---
phase: 13
slug: board-subscription-management
status: draft
nyquist_compliant: true
wave_0_complete: false
created: 2026-04-24
---

# Phase 13 - Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | ExUnit + Ecto SQL Sandbox |
| **Config file** | `test/test_helper.exs`, `test/support/data_case.ex` |
| **Quick run command** | `rtk mix test test/foglet_bbs/boards/boards_test.exs test/foglet_bbs/tui/screens/board_list_test.exs` |
| **Full suite command** | `rtk mix test` |
| **Estimated runtime** | ~60 seconds for focused runs, project-dependent for full suite |

---

## Sampling Rate

- **After every task commit:** Run the focused test file(s) named by that task.
- **After every plan wave:** Run `rtk mix test` or all files modified by the wave.
- **Before `$gsd-verify-work`:** `rtk mix precommit` must be green.
- **Max feedback latency:** One focused ExUnit run per task; no task should wait until phase end for its first automated check.

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 13-01-01 | 01 | 1 | SUBS-03 | T-13-01 | Required subscription invariant cannot be bypassed by invalid board attrs | schema/context | `rtk mix test test/foglet_bbs/boards/boards_test.exs` | W0 | pending |
| 13-01-02 | 01 | 1 | SUBS-02, SUBS-03 | T-13-02 | Subscription mutations route through `Foglet.Boards` and enforce active/required rules | context | `rtk mix test test/foglet_bbs/boards/boards_test.exs` | W0 | pending |
| 13-02-01 | 02 | 2 | SUBS-01, SUBS-02, SUBS-03, SUBS-05 | T-13-03 | TUI cannot open or mutate unauthorized/inactive boards outside context result state | screen/app | `rtk mix test test/foglet_bbs/tui/screens/board_list_test.exs test/foglet_bbs/tui/screens/new_thread_test.exs` | W0 | pending |
| 13-03-01 | 03 | 2 | SUBS-04 | T-13-04 | Operator task uses context APIs and cannot bypass required-board unsubscribe enforcement | mix task | `rtk mix test test/mix/tasks/foglet.board_subscriptions_test.exs` | W0 | pending |
| 13-04-01 | 04 | 3 | SUBS-01, SUBS-02, SUBS-03, SUBS-04, SUBS-05 | T-13-05 | Whole phase remains compile/formatted/static-analysis clean | integration | `rtk mix precommit` | W0 | pending |

*Status: pending, green, red, flaky*

---

## Wave 0 Requirements

- [ ] `test/foglet_bbs/boards/boards_test.exs` - context/schema coverage for SUBS-02 and SUBS-03.
- [ ] `test/foglet_bbs/tui/screens/board_list_test.exs` - board-directory tree, subscribe, unsubscribe, and empty-state coverage for SUBS-01 through SUBS-03 and SUBS-05.
- [ ] `test/foglet_bbs/tui/screens/new_thread_test.exs` - honest new-thread empty-state coverage for SUBS-05.
- [ ] `test/mix/tasks/foglet.board_subscriptions_test.exs` - break-glass task coverage for SUBS-04.

Existing ExUnit infrastructure covers all phase requirements.

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Terminal interaction feel for key bindings and feedback copy | SUBS-01, SUBS-02, SUBS-03, SUBS-05 | Automated tests prove state and rendering strings, but not real SSH ergonomics | Run the app over SSH or the existing TUI harness, navigate to Boards, expand/collapse categories, subscribe/unsubscribe a board, and confirm `Enter` still opens the thread list. |

---

## Validation Sign-Off

- [x] All tasks have automated verify commands or Wave 0 dependencies.
- [x] Sampling continuity: no 3 consecutive tasks without automated verify.
- [x] Wave 0 covers all MISSING references.
- [x] No watch-mode flags.
- [x] Feedback latency is bounded by focused ExUnit file runs.
- [x] `nyquist_compliant: true` set in frontmatter.

**Approval:** approved 2026-04-24
