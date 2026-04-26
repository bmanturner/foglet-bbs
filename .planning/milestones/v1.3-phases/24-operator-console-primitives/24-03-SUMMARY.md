---
plan: 24-03
phase: 24
status: complete
key-files:
  created:
    - lib/foglet_bbs/tui/widgets/display/console_table.ex
    - test/foglet_bbs/tui/widgets/display/console_table_test.exs
  modified: []
---

## Summary

Created `Foglet.TUI.Widgets.Display.ConsoleTable`, a dense operator-console facade over the existing `Display.Table`.

## What Changed

- Added operator-shaped fixture tests for moderation logs, users, boards, SSH keys, invites, sysop users, and sysop boards.
- Implemented compact column normalization, caller-provided empty states, selection handling, and render delegation through `Display.Table`.
- Kept behavior presentation-only with no domain context calls or mutations.

## Verification

- `rtk mix test test/foglet_bbs/tui/widgets/display/console_table_test.exs test/foglet_bbs/tui/widgets/display/table_test.exs`

## Self-Check: PASSED

- ConsoleTable wraps `Display.Table` instead of forking table behavior.
- Empty state, row selection, fixture rendering, and theme hygiene tests pass.
