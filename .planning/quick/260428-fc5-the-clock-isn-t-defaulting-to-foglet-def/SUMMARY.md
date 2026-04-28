---
status: complete
quick_id: 260428-fc5
slug: the-clock-isn-t-defaulting-to-foglet-def
completed: 2026-04-28
---

# Summary

Fixed unauthenticated chrome clock fallback behavior so `ClockFormatter` uses the runtime `:foglet_bbs, :default_timezone` value before falling back to `"Etc/UTC"`.

## Changed

- Updated `Foglet.TUI.Widgets.Chrome.ClockFormatter` to resolve a configured, valid default timezone for nil or invalid user timezone input.
- Preserved the existing UTC fallback when the configured default is absent or invalid.
- Removed the new tests that were initially added at user request; existing status bar tests remain unchanged.

## Verification

- `rtk mix test test/foglet_bbs/tui/widgets/chrome/status_bar_test.exs` — passed, 14 tests.
- `rtk mix precommit` — passed.
