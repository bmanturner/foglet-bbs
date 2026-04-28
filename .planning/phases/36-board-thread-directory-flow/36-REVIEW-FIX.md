---
phase: 36-board-thread-directory-flow
source_review: .planning/phases/36-board-thread-directory-flow/36-REVIEW.md
status: fixed
findings_fixed:
  critical: 2
  warning: 0
  info: 0
completed: 2026-04-28
---

# Phase 36 Review Fix Summary

## Fixed Findings

### CR-01: Opening a Board Leaves ThreadList Permanently Loading

Fixed in `Foglet.TUI.App.apply_effect/2` by dispatching `ThreadList.update(:load, ...)`
after navigation initializes ThreadList local state. Added an App-level test that applies
the navigation effect and verifies a `:load_threads` task command is queued.

### CR-02: Opening a Thread Never Loads Posts or Sets PostReader Context

Fixed in `Foglet.TUI.App.apply_effect/2` by seeding the Phase 37 compatibility fields
`current_board`, `current_thread`, and `posts` when navigating to PostReader, then
dispatching `{:load_posts, thread_id}`. Added an App-level test that verifies the legacy
context is set and post loading is queued.

## Verification

- `rtk mix test test/foglet_bbs/tui/app_test.exs` - passed, 130 tests.
- `rtk mix test test/foglet_bbs/tui/screens/board_list_test.exs test/foglet_bbs/tui/screens/thread_list_test.exs test/foglet_bbs/tui/screens/main_menu_test.exs test/foglet_bbs/tui/app_runtime_contract_test.exs test/foglet_bbs/tui/app_test.exs test/foglet_bbs/tui/layout_smoke_test.exs` - passed, 311 tests.
- `rtk mix compile --warnings-as-errors` - passed.
