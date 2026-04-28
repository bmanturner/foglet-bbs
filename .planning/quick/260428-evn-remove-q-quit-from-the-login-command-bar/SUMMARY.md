---
status: complete
quick_id: 260428-evn
slug: remove-q-quit-from-the-login-command-bar
completed: 2026-04-28
commit: this-commit
---

# Quick Task Summary

Removed `Q Quit` from the Login screen exit path and made Ctrl+C quit Login.

Changes:
- Removed `Q Quit` from the Login menu command definitions.
- Stopped bare `q`/`Q` from terminating Login.
- Added Login-level Ctrl+C handling before form input delegation, so it exits
  from the menu and Login form substates.
- Removed the App-level bare-`q` fallback for Login.
- Kept tests behavior-focused: Ctrl+C emits terminate/quit, and bare `q`/`Q`
  does not.

Validation:
- `rtk mix test test/foglet_bbs/tui/screens/login_test.exs test/foglet_bbs/tui/app_test.exs` passed.
- `rtk mix precommit` passed.
