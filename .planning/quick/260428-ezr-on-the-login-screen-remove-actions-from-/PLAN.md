---
status: complete
created: 2026-04-28
quick_id: 260428-ezr
slug: on-the-login-screen-remove-actions-from-
---

On the login screen, remove `Actions` from the command bar.

Plan:
1. Keep the login menu command hints, but provide them to `ScreenFrame` as an
   explicit unlabeled Chrome V2 command group instead of legacy flat key tuples.
2. Verify the login render output shows the menu hints without the `Actions`
   group label.
3. Run focused login tests and the project precommit check.

Result:
- Implemented in commit `b4a911b`.
