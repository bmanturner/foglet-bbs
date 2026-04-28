---
status: complete
created: 2026-04-28
quick_id: 260428-eug
slug: remove-the-guest-handle-from-the-chrome-
---

Remove the guest handle from the chrome for unauthenticated users, leaving only
the clock and no separator.

Plan:
1. Update `Foglet.TUI.Widgets.Chrome.StatusBar.status_atoms/1` so guest state
   returns only the formatted clock atom.
2. Update status bar tests to assert unauthenticated render output has no
   `guest` handle and no `|` separator.
3. Run focused chrome tests, precommit, and a TUI render smoke check.

Result:
- Implemented in commit `43e2c9e`.
