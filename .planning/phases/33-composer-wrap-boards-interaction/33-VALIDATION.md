---
phase: 33
slug: composer-wrap-boards-interaction
status: draft
nyquist_compliant: true
wave_0_complete: true
created: 2026-04-28
---

# Phase 33 - Validation Strategy

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | ExUnit |
| **Config file** | `mix.exs` |
| **Quick run command** | `rtk mix test test/foglet_bbs/tui/screens/post_composer_test.exs test/foglet_bbs/tui/screens/new_thread_test.exs test/foglet_bbs/tui/screens/board_list_test.exs` |
| **Full suite command** | `rtk mix precommit` |
| **Estimated runtime** | ~120 seconds |

## Sampling Rate

- **After every task commit:** Run the focused ExUnit file for changed behavior.
- **After every plan wave:** Run the quick run command.
- **Before `$gsd-verify-work`:** `rtk mix precommit` must pass.
- **Max feedback latency:** 120 seconds.

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 33-01-01 | 01 | 1 | POST-02 | T-33-01 | Render-only wrapping does not mutate submitted content | unit | `rtk mix test test/foglet_bbs/tui/widgets/compose_test.exs` | optional | pending |
| 33-02-01 | 02 | 2 | POST-02 | T-33-01 | Reply and new-thread submit use logical body value | screen | `rtk mix test test/foglet_bbs/tui/screens/post_composer_test.exs test/foglet_bbs/tui/screens/new_thread_test.exs` | yes | pending |
| 33-03-01 | 03 | 1 | BOARD-01 | T-33-02 | Category toggling stays UI-local and command-free | screen | `rtk mix test test/foglet_bbs/tui/screens/board_list_test.exs` | yes | pending |

## Wave 0 Requirements

Existing ExUnit infrastructure covers all phase requirements.

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| SSH resize from 80x24 to 64x22 mid-compose | POST-02 | Terminal resize is difficult to prove fully with pure render tests | Start SSH TUI, compose a long single logical line, resize from 80x24 to 64x22, confirm reflow and unchanged submitted text |
| Boards category Enter at 64x22 SSH | BOARD-01 | ExUnit covers state and glyphs; SSH confirms terminal interaction | Focus category on Boards, press Enter twice, confirm `▸` then `▾` and no board navigation |

## Validation Sign-Off

- [x] All tasks have automated verify commands or focused manual checks.
- [x] Sampling continuity: no 3 consecutive tasks without automated verify.
- [x] Wave 0 covers all missing references.
- [x] No watch-mode flags.
- [x] Feedback latency target is under 120 seconds.
- [x] `nyquist_compliant: true` set in frontmatter.

**Approval:** pending
