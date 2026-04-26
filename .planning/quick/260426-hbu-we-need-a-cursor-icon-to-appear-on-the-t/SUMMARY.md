---
status: complete
quick_id: 260426-hbu
slug: we-need-a-cursor-icon-to-appear-on-the-t
completed: 2026-04-26
commit: 9a9fedc
---

# Quick Task Summary

Added a visible cursor marker to active single-line text inputs.

Changes:
- Added `focused:` rendering support to `Foglet.TUI.Widgets.Input.TextInput`.
- Rendered the active marker as a theme-routed `▌ ` prefix.
- Passed focused state from login, registration, new-thread title, and modal form text/integer fields.
- Added widget tests for focused and unfocused rendering.

Validation:
- `rtk mix test test/foglet_bbs/tui/widgets/input/text_input_test.exs` passed.
- `rtk mix test test/foglet_bbs/tui/widgets/modal/form_test.exs test/foglet_bbs/tui/screens/login_test.exs test/foglet_bbs/tui/screens/register_test.exs test/foglet_bbs/tui/screens/new_thread_test.exs` passed.
- `rtk mix credo lib/foglet_bbs/tui/widgets/input/text_input.ex lib/foglet_bbs/tui/screens/login.ex lib/foglet_bbs/tui/screens/register.ex lib/foglet_bbs/tui/screens/new_thread.ex lib/foglet_bbs/tui/widgets/modal/form.ex test/foglet_bbs/tui/widgets/input/text_input_test.exs` passed.

Notes:
- `rtk mix precommit` did not pass because of an unrelated existing Credo issue in `test/foglet_bbs/tui/widgets/chrome/screen_frame_test.exs:37`.
