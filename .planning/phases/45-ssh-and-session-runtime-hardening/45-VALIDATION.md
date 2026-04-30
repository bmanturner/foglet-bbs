---
phase: 45
slug: ssh-and-session-runtime-hardening
status: draft
nyquist_compliant: true
wave_0_complete: true
created: 2026-04-30
---

# Phase 45 - Validation Strategy

## Test Infrastructure

| Property | Value |
|----------|-------|
| Framework | ExUnit |
| Config file | `test/test_helper.exs`, `config/test.exs` |
| Quick run command | `rtk mix test test/foglet_bbs/ssh/cli_handler_test.exs test/foglet_bbs/sessions/supervisor_test.exs test/foglet_bbs/sessions/session_test.exs` |
| Full suite command | `rtk mix precommit` |
| Estimated runtime | Quick: under 60 seconds; full: project-dependent |

## Sampling Rate

- After every task commit: run the focused test file touched by that task.
- After every plan wave: run the quick run command.
- Before `$gsd-verify-work`: `rtk mix precommit` must pass.
- Max feedback latency: one focused test file per task unless the task touches cross-module promotion flow.

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 45-01-01 | 01 | 1 | SSH-01 | T-45-01 | Expired pubkey offers cannot promote stale identity | unit | `rtk mix test test/foglet_bbs/ssh/cli_handler_test.exs` | yes | pending |
| 45-01-02 | 01 | 1 | SSH-01 | T-45-02 | Fresh pubkey offers still pop exactly once | unit | `rtk mix test test/foglet_bbs/ssh/cli_handler_test.exs` | yes | pending |
| 45-02-01 | 02 | 1 | SSH-02 | T-45-03 | Peer metadata reaches promotion boundary without changing auth | unit | `rtk mix test test/foglet_bbs/ssh/cli_handler_test.exs test/foglet_bbs/tui/app_test.exs` | yes | pending |
| 45-02-02 | 02 | 1 | SSH-02, SESS-01 | T-45-04 | Promotion audit reports replacement context while preserving one-session semantics | unit | `rtk mix test test/foglet_bbs/sessions/supervisor_test.exs test/foglet_bbs/sessions/session_test.exs` | yes | pending |
| 45-03-01 | 03 | 2 | SSH-03 | T-45-05 | Cleanup side effects are centralized and idempotent | unit | `rtk mix test test/foglet_bbs/ssh/cli_handler_test.exs` | yes | pending |
| 45-03-02 | 03 | 2 | SSH-04 | T-45-06 | Counter returns to expected value on all listed lifecycle paths | unit | `rtk mix test test/foglet_bbs/ssh/cli_handler_test.exs` | yes | pending |

## Wave 0 Requirements

Existing infrastructure covers all phase requirements.

## Manual-Only Verifications

All phase behaviors have automated verification.

## Validation Sign-Off

- [x] All tasks have automated verify commands.
- [x] Sampling continuity: no three consecutive tasks without automated verify.
- [x] Wave 0 covers all missing references.
- [x] No watch-mode flags.
- [x] `nyquist_compliant: true` set in frontmatter.

Approval: pending
