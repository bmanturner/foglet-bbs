---
phase: 38-account-operator-workbenches
plan: "01"
subsystem: tui
tags: [account, screen-contract, task-effects]
provides:
  - Account init/update/render reducer contract over Foglet.TUI.Context
  - Task-backed profile, preference, SSH key, and invite operations
  - Session refresh effects for current-user and preference snapshots
key-files:
  modified:
    - lib/foglet_bbs/tui/screens/account.ex
    - test/foglet_bbs/tui/screens/account_test.exs
completed: 2026-04-29
---

# Phase 38 Plan 01 Summary

Account now owns its reducer contract and emits explicit effects for persistence, SSH key management, invite management, navigation, and session refreshes.

## Verification

- `rtk mix test test/foglet_bbs/tui/screens/account_test.exs:<focused reducer lines>` - passed
- Full account file still has the pre-existing BL-01 modal-lock failures unrelated to the Account reducer migration.

## Commit

- `89a25d3 feat(38-01): add account reducer contract`
