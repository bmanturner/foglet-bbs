# Deferred Items

## 2026-04-30 - Precommit Blocked By Unrelated NewThread Credo Issue

- **Found during:** Plan 44-01 final `rtk mix precommit`
- **Issue:** Credo reported `Foglet.TUI.Screens.NewThread.State.from_context/1` has cyclomatic complexity 10 with max 9.
- **File:** `lib/foglet_bbs/tui/screens/new_thread/state.ex`
- **Disposition:** Out of scope for 44-01. This plan only modified `Foglet.Posts` reader-window behavior and `test/foglet_bbs/posts/posts_test.exs`; the NewThread file is unrelated parallel work and was not changed here.
- **Local verification for plan files:** `rtk mix credo lib/foglet_bbs/posts.ex test/foglet_bbs/posts/posts_test.exs` passed with no issues.
