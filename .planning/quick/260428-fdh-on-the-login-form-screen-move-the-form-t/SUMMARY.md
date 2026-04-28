---
status: complete
completed: 2026-04-28
quick_id: 260428-fdh
slug: on-the-login-form-screen-move-the-form-t
---

# Summary

Moved the login form into a centered Raxol panel titled `Identify Yourself`.

## Changes

- Added a fixed-size login panel using the same `type: :panel` widget shape used by the main menu.
- Centered the panel within the login screen content area while preserving existing form key handling.
- Added one-column body padding and `gap: 2` between the handle and password field rows.
- Added render coverage asserting the panel title, width budget, and height budget.

## Verification

- `rtk mix format lib/foglet_bbs/tui/screens/login.ex test/foglet_bbs/tui/screens/login_test.exs`
- `rtk mix test test/foglet_bbs/tui/screens/login_test.exs test/foglet_bbs/tui/layout_smoke_test.exs`
- `rtk mix run --no-start -e '...'` visual render of the login form
- `rtk mix precommit`
