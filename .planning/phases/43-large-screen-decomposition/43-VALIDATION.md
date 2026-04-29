---
phase: 43
slug: large-screen-decomposition
status: draft
nyquist_compliant: false
wave_0_complete: true
created: 2026-04-29
---

# Phase 43 - Validation Strategy

## Test Infrastructure

| Property | Value |
|----------|-------|
| Framework | ExUnit |
| Config file | `mix.exs`, `config/test.exs`, `test/test_helper.exs` |
| Quick run command | `rtk mix test test/foglet_bbs/tui/screens/<screen>_test.exs` |
| Full suite command | `rtk mix precommit` |
| Estimated runtime | Project-dependent; use focused screen suites during execution and full precommit at completion |

## Sampling Rate

- After every task commit: run the focused screen test file named in that task.
- After every plan wave: run all screen tests modified or affected in that wave plus `test/foglet_bbs/tui/layout_smoke_test.exs`.
- Before `$gsd-verify-work`: `rtk mix precommit` must pass.
- Max feedback latency: one focused screen suite per extraction task.

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 43-01-01 | 43-01 | 1 | TUI-05 | N/A | N/A | docs/source contract | `rtk mix test test/foglet_bbs/tui/screens/new_thread_test.exs test/foglet_bbs/tui/screens/login_test.exs` | yes | pending |
| 43-02-01 | 43-02 | 2 | TUI-05 | N/A | N/A | reducer/render contract | `rtk mix test test/foglet_bbs/tui/screens/main_menu_test.exs` | yes | pending |
| 43-03-01 | 43-03 | 2 | TUI-05 | N/A | N/A | reducer/render contract | `rtk mix test test/foglet_bbs/tui/screens/sysop_test.exs test/foglet_bbs/tui/screens/account_test.exs` | yes | pending |
| 43-04-01 | 43-04 | 3 | TUI-05 | N/A | N/A | reducer/render contract | `rtk mix test test/foglet_bbs/tui/screens/post_reader_test.exs` | yes | pending |
| 43-05-01 | 43-05 | 4 | TUI-05 | N/A | N/A | smoke/finish line | `rtk mix test test/foglet_bbs/tui/layout_smoke_test.exs` | yes | pending |

## Wave 0 Requirements

Existing infrastructure covers all phase requirements:

- `test/foglet_bbs/tui/screens/new_thread_test.exs`
- `test/foglet_bbs/tui/screens/login_test.exs`
- `test/foglet_bbs/tui/screens/main_menu_test.exs`
- `test/foglet_bbs/tui/screens/sysop_test.exs`
- `test/foglet_bbs/tui/screens/account_test.exs`
- `test/foglet_bbs/tui/screens/post_reader_test.exs`
- `test/foglet_bbs/tui/layout_smoke_test.exs`
- `rtk mix foglet.tui.render`

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| Visual inspection of all six rendered screens | TUI-05 | CLI render output is evidence, not the primary behavior assertion | Run `rtk mix foglet.tui.render login --no-frame`, `main_menu`, `new_thread`, `account`, `sysop`, and `post_reader` variants after extraction and inspect for obvious layout breakage |

## Validation Sign-Off

- [ ] All tasks have automated verify commands or explicit CLI render evidence.
- [ ] Sampling continuity: no three consecutive tasks skip focused automated checks.
- [ ] Render modules are covered by source-shape or structural tests, not text-presence-only assertions.
- [ ] `rtk mix precommit` passes.
- [ ] `nyquist_compliant: true` set in frontmatter after execution verification.

Approval: pending

