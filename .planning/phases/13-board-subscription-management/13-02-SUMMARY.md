---
phase: 13-board-subscription-management
plan: 2
subsystem: tui-board-directory
tags:
  - tui
  - board-subscriptions
key-files:
  created: []
  modified:
    - lib/foglet_bbs/tui/app.ex
    - lib/foglet_bbs/tui/screens/board_list.ex
    - lib/foglet_bbs/tui/screens/board_list/state.ex
    - lib/foglet_bbs/tui/screens/new_thread.ex
    - lib/foglet_bbs/tui/screens/new_thread/state.ex
    - test/foglet_bbs/tui/screens/board_list_test.exs
    - test/foglet_bbs/tui/screens/new_thread_test.exs
metrics:
  tests: 52
  failures: 0
---

# Plan 13-02 Summary: Terminal Board Directory Subscribe/Unsubscribe Workflow

## What Changed

Replaced the subscribed-only board listing with a category tree backed by `Boards.board_directory_for/1`. Board leaves show `[subscribed]`, `[unsubscribed]`, or `[required]`, preserve unread counts for subscribed boards, and keep Enter as the open-board action.

Added focused board actions: `s` subscribes to an unsubscribed board, and `u` unsubscribes from a subscribed non-required board. Required boards render inline feedback instead of dispatching a mutation. `Foglet.TUI.App` now routes these actions through `Boards.subscribe_user_to_board/2` and `Boards.unsubscribe_user_from_board/2`, then reloads the directory after successful mutations.

Updated NewThread empty states so users with active unsubscribed boards see `Subscribe from Boards`, while sites with no active boards see `No active boards are available`.

## Commits

| Commit | Description |
|--------|-------------|
| `19a9988` | test(13-02): add failing board directory tree tests |
| `c0eccda` | feat(13-02): render board directory tree |
| `7348e3d` | feat(13-02): wire board subscription actions |

## Verification

| Check | Result |
|-------|--------|
| `rtk mix test test/foglet_bbs/tui/screens/board_list_test.exs test/foglet_bbs/tui/screens/new_thread_test.exs` | Passed, 52 tests |

## Deviations

The executor agent initially left Task 13-02-02 as uncommitted failing tests. The orchestrator completed the app/screen wiring in the same worktree and committed the final implementation.

## Self-Check: PASSED

The TUI board directory now satisfies SUBS-01, SUBS-02, SUBS-03, and SUBS-05 without adding browser workflow or out-of-scope Sysop user subscription management.
