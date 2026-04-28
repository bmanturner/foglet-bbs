---
status: complete
quick_id: 260428-eug
slug: remove-the-guest-handle-from-the-chrome-
completed: 2026-04-28
commit: 43e2c9e
---

# Quick Task Summary

Removed the unauthenticated `guest` handle from the chrome status bar.

Changes:
- Changed guest status atoms to return only the formatted clock.
- Updated the status bar moduledoc copywriting contract to describe clock-only
  guest chrome.
- Added render coverage proving unauthenticated chrome has no `guest` label and
  no `|` separator.

Validation:
- `rtk mix test test/foglet_bbs/tui/widgets/chrome/status_bar_test.exs` passed.
- `rtk mix format lib/foglet_bbs/tui/widgets/chrome/status_bar.ex test/foglet_bbs/tui/widgets/chrome/status_bar_test.exs` passed.
- `rtk mix precommit` passed.
- `rtk mix foglet.tui.render login --no-frame` passed after sandbox escalation
  for Mix's local PubSub socket and showed a clock-only top-right chrome.

Notes:
- Other modified files and an unrelated quick-task directory were already
  present in the worktree during finalization and were not staged.
