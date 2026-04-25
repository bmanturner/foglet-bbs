---
plan: 24-04
phase: 24
status: complete
key-files:
  created:
    - lib/foglet_bbs/tui/widgets/workspace/inspector.ex
    - test/foglet_bbs/tui/widgets/workspace/inspector_test.exs
  modified: []
---

## Summary

Created `Foglet.TUI.Widgets.Workspace.Inspector`, a wide-terminal detail/action panel for selected operator-console rows.

## What Changed

- Added board, user, invite, no-selection, compact-collapse, and theme-hygiene tests.
- Implemented a render-only Inspector that collapses below the wide-terminal threshold and composes details through `Display.KvGrid`.
- Rendered only caller-supplied action descriptors, with role-based theme slots and no inferred domain actions.

## Verification

- `rtk mix test test/foglet_bbs/tui/widgets/workspace/inspector_test.exs`

## Self-Check: PASSED

- Wide details/actions render at 132 columns.
- 64 and 80 column renders intentionally collapse.
- No domain calls or hardcoded terminal color atom leaks were introduced.
