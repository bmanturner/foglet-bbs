---
status: complete
quick_id: 260428-ezr
slug: on-the-login-screen-remove-actions-from-
completed: 2026-04-28
commit: b4a911b
---

# Quick Task Summary

Removed the `Actions` label from the login screen command bar.

Changes:
- Changed the login menu footer metadata to emit one explicit unlabeled command
  group through `ScreenFrame`.
- Left the underlying login menu commands intact; this change only affects the
  group label shown in chrome.

Validation:
- `rtk mix test test/foglet_bbs/tui/screens/login_test.exs` passed.
- `rtk mix foglet.tui.render login --no-frame` passed after sandbox escalation
  for Mix's local PubSub socket and showed:
  `L Login  F Forgot password  T Reset token  R Register`.
- `rtk mix precommit` passed.

Notes:
- The login command-bar change is included in `b4a911b`, which also contains
  the adjacent login exit-key cleanup that was already in progress.
