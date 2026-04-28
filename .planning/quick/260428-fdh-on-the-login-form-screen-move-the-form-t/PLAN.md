---
status: planned
created: 2026-04-28
quick_id: 260428-fdh
slug: on-the-login-form-screen-move-the-form-t
---

On the login form screen, move the form into a centered panel titled `Identify Yourself`.

## Plan

1. Update `Foglet.TUI.Screens.Login.render_login_form/2` to return a centered panel widget titled `Identify Yourself`.
2. Size the panel with enough inner width for labels plus a 20-character handle field.
3. Add focused render coverage that checks the panel title and form contents.
4. Run the relevant login/TUI tests and render the login screen for visual inspection.
