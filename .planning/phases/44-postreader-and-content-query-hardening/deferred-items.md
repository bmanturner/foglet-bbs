# Deferred Items

## 2026-04-30 - Precommit Blocked By Unrelated NewThread Credo Issue

- **Found during:** Plan 44-01 final `rtk mix precommit`
- **Issue:** Credo reported `Foglet.TUI.Screens.NewThread.State.from_context/1` has cyclomatic complexity 10 with max 9.
- **File:** `lib/foglet_bbs/tui/screens/new_thread/state.ex`
- **Disposition:** Out of scope for 44-01. This plan only modified `Foglet.Posts` reader-window behavior and `test/foglet_bbs/posts/posts_test.exs`; the NewThread file is unrelated parallel work and was not changed here.
- **Local verification for plan files:** `rtk mix credo lib/foglet_bbs/posts.ex test/foglet_bbs/posts/posts_test.exs` passed with no issues.

## 2026-04-30 - Precommit Blocked By Existing Dialyzer Findings

- **Found during:** Plan 44-02 final `rtk mix precommit`
- **Issue:** Dialyzer reported an unknown type reference in prior-wave `lib/foglet_bbs/posts/reader_window.ex` (`Foglet.Posts.Post.t/0`) and an impossible guard in pre-existing `lib/foglet_bbs/tui/screens/post_reader/render.ex`.
- **Disposition:** Out of scope for 44-02. This plan modified PostReader bounded-window reducer behavior, state metadata, and screen reducer tests; the required plan verification commands passed.
- **Local verification for plan files:** `rtk mix test test/foglet_bbs/tui/screens/post_reader_test.exs` passed with 81 tests, and `rtk mix compile --warnings-as-errors` exited 0 for `foglet_bbs`.

## 2026-04-30 - Precommit Still Blocked By Existing Dialyzer Findings

- **Found during:** Plan 44-03 final `rtk mix precommit`
- **Issue:** Dialyzer still reports the prior-wave unknown type reference in `lib/foglet_bbs/posts/reader_window.ex` (`Foglet.Posts.Post.t/0`) and the pre-existing impossible guard in `lib/foglet_bbs/tui/screens/post_reader/render.ex`.
- **Disposition:** Out of scope for 44-03. This plan changed reducer-side cache eviction and PostReader render-purity tests only; it did not modify the render module behavior or reader-window type definitions.
- **Local verification for plan files:** `rtk mix test test/foglet_bbs/tui/screens/post_reader_test.exs` passed with 82 tests, and `rtk mix compile --warnings-as-errors` exited 0 for `foglet_bbs`.
