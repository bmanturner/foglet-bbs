---
phase: 44
slug: postreader-and-content-query-hardening
status: draft
nyquist_compliant: true
wave_0_complete: true
created: 2026-04-30
---

# Phase 44 - Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | ExUnit bundled with Elixir 1.19.5; StreamData is available but not required. |
| **Config file** | `test/test_helper.exs` and `config/test.exs` |
| **Quick run command** | `rtk mix test test/foglet_bbs/tui/screens/post_reader_test.exs` |
| **Full suite command** | `rtk mix test test/foglet_bbs/posts/posts_test.exs test/foglet_bbs/threads/threads_test.exs test/foglet_bbs/boards/boards_test.exs test/foglet_bbs/tui/screens/post_reader_test.exs` |
| **Estimated runtime** | ~60 seconds with local Postgres running |

---

## Sampling Rate

- **After every task commit:** Run `rtk mix test test/foglet_bbs/tui/screens/post_reader_test.exs` for TUI reducer/cache tasks, or the relevant context test file for domain-only tasks.
- **After every plan wave:** Run `rtk mix test test/foglet_bbs/posts/posts_test.exs test/foglet_bbs/threads/threads_test.exs test/foglet_bbs/boards/boards_test.exs test/foglet_bbs/tui/screens/post_reader_test.exs`.
- **Before `$gsd-verify-work`:** `rtk mix precommit` must pass.
- **Max feedback latency:** 60 seconds for focused tests before full precommit.

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 44-01-01 | 44-01 | 1 | POST-01, POST-04 | T-44-01 | Reader/history query remains tombstone-capable and bounded. | domain | `rtk mix test test/foglet_bbs/posts/posts_test.exs` | Yes | pending |
| 44-01-02 | 44-01 | 1 | POST-01 | T-44-01 | Query contract returns `:has_previous?`, `:has_next?`, and bounded posts. | domain | `rtk mix test test/foglet_bbs/posts/posts_test.exs` | Yes | pending |
| 44-02-01 | 44-02 | 2 | POST-01 | T-44-02 | PostReader cannot ask the fake domain for `list_posts/1` on large-thread route entry. | reducer | `rtk mix test test/foglet_bbs/tui/screens/post_reader_test.exs` | Yes | pending |
| 44-02-02 | 44-02 | 2 | POST-01 | T-44-02 | `%PostReader.State{}.posts` never contains all 1000 fake posts. | reducer | `rtk mix test test/foglet_bbs/tui/screens/post_reader_test.exs` | Yes | pending |
| 44-02-03 | 44-02 | 2 | POST-01 | T-44-03 | Window metadata preserves next/previous boundary navigation. | reducer | `rtk mix test test/foglet_bbs/tui/screens/post_reader_test.exs` | Yes | pending |
| 44-02-04 | 44-02 | 2 | POST-01 | T-44-04 | `load_intent: :jump_last` lands on newest bounded window without full load. | reducer | `rtk mix test test/foglet_bbs/tui/screens/post_reader_test.exs` | Yes | pending |
| 44-03-01 | 44-03 | 3 | POST-02 | T-44-05 | Active render cache contains only current terminal width after warming. | reducer | `rtk mix test test/foglet_bbs/tui/screens/post_reader_test.exs` | Yes | pending |
| 44-03-02 | 44-03 | 3 | POST-03 | T-44-06 | Static guard covers `post_reader/render.ex` render helpers. | static | `rtk mix test test/foglet_bbs/tui/screens/post_reader_test.exs` | Yes | pending |
| 44-04-01 | 44-04 | 4 | POST-04 | T-44-07 | Thread list APIs hide soft-deleted thread/list rows. | domain | `rtk mix test test/foglet_bbs/threads/threads_test.exs` | Yes | pending |
| 44-04-02 | 44-04 | 4 | POST-04 | T-44-08 | Board directory and unread summaries hide deleted posts/threads. | domain | `rtk mix test test/foglet_bbs/boards/boards_test.exs` | Yes | pending |

*Status: pending, green, red, or flaky.*

---

## Wave 0 Requirements

Existing infrastructure covers all phase requirements:

- `test/foglet_bbs/tui/screens/post_reader_test.exs`
- `test/foglet_bbs/posts/posts_test.exs`
- `test/foglet_bbs/threads/threads_test.exs`
- `test/foglet_bbs/boards/boards_test.exs`
- `FogletBbs.DataCase`
- `FogletBbs.BoardsFixtures`

---

## Manual-Only Verifications

All phase behaviors have automated verification.

---

## Validation Sign-Off

- [x] All tasks have automated verify commands or existing Wave 0 dependencies.
- [x] Sampling continuity has no 3 consecutive tasks without automated verification.
- [x] Wave 0 covers all missing references.
- [x] No watch-mode flags.
- [x] Feedback latency target is under 60 seconds for focused tests.
- [x] `nyquist_compliant: true` set in frontmatter.

**Approval:** pending execution
