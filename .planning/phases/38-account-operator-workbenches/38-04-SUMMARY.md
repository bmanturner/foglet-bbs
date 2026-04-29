---
phase: 38-account-operator-workbenches
plan: "04"
subsystem: tui
tags: [app, screen-contract, cleanup, task-effects]
provides:
  - Generic route-entry dispatch for MainMenu, Moderation, and Sysop
  - App preference snapshot session-effect handling
  - Removal of App-owned Account, Moderation, and Sysop workbench task/result clauses
key-files:
  created:
    - .planning/phases/38-account-operator-workbenches/38-04-SUMMARY.md
  modified:
    - lib/foglet_bbs/tui/app.ex
    - lib/foglet_bbs/tui/screens/account.ex
    - lib/foglet_bbs/tui/screens/main_menu.ex
    - test/foglet_bbs/tui/app_test.exs
    - test/foglet_bbs/tui/screens/account_test.exs
completed: 2026-04-29
---

# Phase 38 Plan 04 Summary

The App shell now interprets generic screen effects for Account, Moderation, and Sysop instead of owning workbench-specific persistence/load/result clauses.

## Verification

- `rtk mix test test/foglet_bbs/tui/screens/main_menu_test.exs test/foglet_bbs/tui/app_test.exs` - passed, 182 tests
- `rtk mix test test/foglet_bbs/tui/screens/account_test.exs test/foglet_bbs/tui/screens/moderation_test.exs test/foglet_bbs/tui/screens/sysop_test.exs test/foglet_bbs/tui/screens/main_menu_test.exs test/foglet_bbs/tui/app_test.exs` - 395 passed, 2 known pre-existing BL-01 Account modal-lock failures

## Commit

- Committed with the Phase 38 Plan 04 cleanup changes.
