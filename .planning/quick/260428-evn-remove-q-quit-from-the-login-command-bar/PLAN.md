---
status: in_progress
created: 2026-04-28
quick_id: 260428-evn
slug: remove-q-quit-from-the-login-command-bar
---

Remove `Q Quit` from the Login screen command bar and stop treating bare `q`/`Q`
as Login-screen exit keys.

Plan:
1. Update `Foglet.TUI.Screens.Login` so the menu command list advertises only
   login, register when enabled, forgot password, and reset-token actions.
2. Remove Login's bare `q`/`Q` terminate handling and the App fallback that
   quits on bare `q` when Login returns `:no_match`.
3. Add Login-screen Ctrl+C quit handling without advertising it in the command
   bar.
4. Update focused Login/App behavior tests so bare `q`/`Q` is ignored and
   Ctrl+C exits.

Validation:
- `rtk mix test test/foglet_bbs/tui/screens/login_test.exs test/foglet_bbs/tui/app_test.exs`
