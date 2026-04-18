---
phase: 2
slug: domain-core
status: draft
nyquist_compliant: false
wave_0_complete: false
created: 2026-04-18
---

# Phase 2 — Validation Strategy

> Per-phase validation contract for feedback sampling during execution.

---

## Test Infrastructure

| Property | Value |
|----------|-------|
| **Framework** | ExUnit (built-in Elixir) |
| **Config file** | `test/test_helper.exs` |
| **Quick run command** | `mix test test/foglet_bbs/boards/ test/foglet_bbs/threads/ test/foglet_bbs/posts/ test/foglet_bbs/markdown_test.exs` |
| **Full suite command** | `mix test` |
| **Estimated runtime** | ~30 seconds (property tests add ~10s) |

---

## Sampling Rate

- **After every task commit:** Run `mix precommit && mix test test/foglet_bbs/boards/ test/foglet_bbs/threads/ test/foglet_bbs/posts/`
- **After every plan wave:** Run `mix precommit && mix test`
- **Before `/gsd-verify-work`:** Full suite must be green
- **Max feedback latency:** ~30 seconds

---

## Per-Task Verification Map

| Task ID | Plan | Wave | Requirement | Threat Ref | Secure Behavior | Test Type | Automated Command | File Exists | Status |
|---------|------|------|-------------|------------|-----------------|-----------|-------------------|-------------|--------|
| 2-01-01 | 01 | 1 | BOARD-01 | — | N/A | unit | `mix test test/foglet_bbs/boards/boards_test.exs` | ❌ W0 | ⬜ pending |
| 2-01-02 | 01 | 1 | BOARD-01 | — | N/A | unit | `mix test test/foglet_bbs/boards/boards_test.exs` | ❌ W0 | ⬜ pending |
| 2-02-01 | 02 | 1 | BOARD-06 | T-2-01 | GenServer serializes message-number allocation | unit | `mix test test/foglet_bbs/boards/board_server_test.exs` | ❌ W0 | ⬜ pending |
| 2-02-02 | 02 | 1 | BOARD-06 | T-2-01 | Message numbers monotonically sequential under concurrency | property | `mix test test/foglet_bbs/boards/board_server_test.exs` | ❌ W0 | ⬜ pending |
| 2-03-01 | 03 | 2 | BOARD-02 | — | N/A | unit | `mix test test/foglet_bbs/threads/threads_test.exs` | ❌ W0 | ⬜ pending |
| 2-03-02 | 03 | 2 | BOARD-03 | — | N/A | unit | `mix test test/foglet_bbs/posts/posts_test.exs` | ❌ W0 | ⬜ pending |
| 2-03-03 | 03 | 2 | BOARD-04 | — | Edit history preserved; only author can edit | unit | `mix test test/foglet_bbs/posts/posts_test.exs` | ❌ W0 | ⬜ pending |
| 2-03-04 | 03 | 2 | BOARD-07 | — | N/A | unit | `mix test test/foglet_bbs/boards/boards_test.exs` | ❌ W0 | ⬜ pending |
| 2-03-05 | 03 | 2 | BOARD-08 | — | N/A | unit | `mix test test/foglet_bbs/boards/boards_test.exs` | ❌ W0 | ⬜ pending |
| 2-03-06 | 03 | 2 | BOARD-09 | — | N/A | unit | `mix test test/foglet_bbs/threads/threads_test.exs` | ❌ W0 | ⬜ pending |
| 2-03-07 | 03 | 2 | BOARD-10 | — | N/A | unit | `mix test test/foglet_bbs/boards/boards_test.exs` | ❌ W0 | ⬜ pending |
| 2-03-08 | 03 | 2 | BOARD-11 | T-2-02 | Deleted post body not exposed; message number preserved | unit | `mix test test/foglet_bbs/posts/posts_test.exs` | ❌ W0 | ⬜ pending |
| 2-03-09 | 03 | 2 | BOARD-12 | — | N/A | unit | `mix test test/foglet_bbs/threads/threads_test.exs` | ❌ W0 | ⬜ pending |
| 2-04-01 | 04 | 3 | BOARD-05 | T-2-03 | ANSI output from parsed AST; user cannot inject raw escape codes | unit | `mix test test/foglet_bbs/markdown_test.exs` | ❌ W0 | ⬜ pending |

*Status: ⬜ pending · ✅ green · ❌ red · ⚠️ flaky*

---

## Wave 0 Requirements

- [ ] `test/foglet_bbs/boards/boards_test.exs` — stubs for BOARD-01, BOARD-07, BOARD-08, BOARD-10
- [ ] `test/foglet_bbs/boards/board_server_test.exs` — stubs for BOARD-06 (unit + property)
- [ ] `test/foglet_bbs/threads/threads_test.exs` — stubs for BOARD-02, BOARD-09, BOARD-12
- [ ] `test/foglet_bbs/posts/posts_test.exs` — stubs for BOARD-03, BOARD-04, BOARD-11
- [ ] `test/foglet_bbs/markdown_test.exs` — stubs for BOARD-05
- [ ] `test/support/boards_fixtures.ex` — shared category, board, thread, post creation helpers
- [ ] `{Registry, keys: :unique, name: Foglet.BoardRegistry}` started in test support if Board Server tests run in isolation

---

## Manual-Only Verifications

| Behavior | Requirement | Why Manual | Test Instructions |
|----------|-------------|------------|-------------------|
| MDEx NIF loads without error at application start | BOARD-05 | NIF compilation is environment-dependent | Run `iex -S mix` and verify MDEx available: `MDEx.to_html!("# test")` returns HTML string |
| Board Servers start for all active boards at application boot | BOARD-06 | Requires full application start | Run `iex -S mix` and verify: `DynamicSupervisor.count_children(Foglet.Boards.Supervisor)` shows N workers where N = count of non-archived boards in seeds |

---

## Validation Sign-Off

- [ ] All tasks have `<automated>` verify or Wave 0 dependencies
- [ ] Sampling continuity: no 3 consecutive tasks without automated verify
- [ ] Wave 0 covers all MISSING references
- [ ] No watch-mode flags
- [ ] Feedback latency < 30s
- [ ] `nyquist_compliant: true` set in frontmatter

**Approval:** pending
