---
phase: 37
slug: post-composer-flow
status: draft
nyquist_compliant: true
wave_0_complete: true
created: 2026-04-28
---

# Phase 37 - Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | ExUnit |
| **Config file** | `mix.exs` |
| **Quick run command** | `rtk mix test test/foglet_bbs/tui/screens/post_reader_test.exs test/foglet_bbs/tui/screens/post_composer_test.exs test/foglet_bbs/tui/screens/new_thread_test.exs` |
| **Full suite command** | `rtk mix precommit` |
| **Estimated runtime** | project-dependent |

## Sampling Rate

- **After every task commit:** Run the targeted test file for the touched screen or App runtime path.
- **After every plan wave:** Run the quick run command above plus relevant App/layout tests.
- **Before `$gsd-verify-work`:** `rtk mix precommit` must be green or have a documented pre-existing blocker.
- **Max feedback latency:** one task.

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 37-01-01 | 01 | 1 | SCREEN-04 | N/A | Read-pointer pending state is not discarded after failed flush | reducer/unit | `rtk mix test test/foglet_bbs/tui/screens/post_reader_test.exs` | yes | pending |
| 37-02-01 | 02 | 1 | SCREEN-04 | N/A | PostReader active-thread refresh uses route/local identity | reducer/unit | `rtk mix test test/foglet_bbs/tui/screens/post_reader_test.exs test/foglet_bbs/tui/app_test.exs` | yes | pending |
| 37-03-01 | 03 | 2 | SCREEN-04 | N/A | Reply submission remains authorized through `Foglet.Posts.create_reply/4` | reducer/unit | `rtk mix test test/foglet_bbs/tui/screens/post_composer_test.exs` | yes | pending |
| 37-04-01 | 04 | 2 | SCREEN-04 | N/A | Thread creation remains authorized through `Foglet.Threads.create_thread/3` | reducer/unit | `rtk mix test test/foglet_bbs/tui/screens/new_thread_test.exs` | yes | pending |
| 37-05-01 | 05 | 3 | SCREEN-04 | N/A | App routes task results generically without owning screen-local state | integration | `rtk mix test test/foglet_bbs/tui/app_runtime_contract_test.exs test/foglet_bbs/tui/app_test.exs test/foglet_bbs/tui/layout_smoke_test.exs` | yes | pending |

## Wave 0 Requirements

Existing infrastructure covers all phase requirements.

## Manual-Only Verifications

All phase behaviors have automated verification.

## Validation Sign-Off

- [x] All tasks have automated verify commands or existing test infrastructure.
- [x] Sampling continuity: no 3 consecutive tasks without automated verify.
- [x] Wave 0 covers all missing references.
- [x] No watch-mode flags.
- [x] Feedback latency is bounded by task.
- [x] `nyquist_compliant: true` set in frontmatter.

**Approval:** approved 2026-04-28
