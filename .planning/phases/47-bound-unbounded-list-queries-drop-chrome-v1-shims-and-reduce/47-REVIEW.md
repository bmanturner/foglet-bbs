---
phase: 47-bound-unbounded-list-queries-drop-chrome-v1-shims-and-reduce
reviewed: 2026-04-30T16:05:00Z
depth: standard
iteration: 7
files_reviewed: 36
files_reviewed_list:
  - .dialyzer_ignore.exs
  - lib/foglet_bbs/posts.ex
  - lib/foglet_bbs/threads.ex
  - lib/foglet_bbs/tui/app.ex
  - lib/foglet_bbs/tui/app/routing.ex
  - lib/foglet_bbs/tui/app/screen_states.ex
  - lib/foglet_bbs/tui/app/session_alias.ex
  - lib/foglet_bbs/tui/screens/account/render.ex
  - lib/foglet_bbs/tui/screens/board_list.ex
  - lib/foglet_bbs/tui/screens/login.ex
  - lib/foglet_bbs/tui/screens/login/login_form.ex
  - lib/foglet_bbs/tui/screens/login/menu.ex
  - lib/foglet_bbs/tui/screens/login/render.ex
  - lib/foglet_bbs/tui/screens/login/reset_consume.ex
  - lib/foglet_bbs/tui/screens/login/reset_request.ex
  - lib/foglet_bbs/tui/screens/moderation.ex
  - lib/foglet_bbs/tui/screens/new_thread/render.ex
  - lib/foglet_bbs/tui/screens/post_composer.ex
  - lib/foglet_bbs/tui/screens/post_reader.ex
  - lib/foglet_bbs/tui/screens/post_reader/render.ex
  - lib/foglet_bbs/tui/screens/register.ex
  - lib/foglet_bbs/tui/screens/thread_list.ex
  - lib/foglet_bbs/tui/screens/verify.ex
  - lib/foglet_bbs/tui/widgets/README.md
  - lib/foglet_bbs/tui/widgets/chrome/screen_frame.ex
  - lib/foglet_bbs/tui/widgets/chrome/status_bar.ex
  - test/foglet_bbs/posts/posts_test.exs
  - test/foglet_bbs/threads/threads_test.exs
  - test/foglet_bbs/tui/app/screen_states_test.exs
  - test/foglet_bbs/tui/app/session_alias_test.exs
  - test/foglet_bbs/tui/app_test.exs
  - test/foglet_bbs/tui/layout_smoke_test.exs
  - test/foglet_bbs/tui/screens/post_reader_test.exs
  - test/foglet_bbs/tui/widgets/chrome/breadcrumb_migration_test.exs
  - test/foglet_bbs/tui/widgets/chrome/screen_frame_test.exs
  - test/foglet_bbs/tui/widgets/chrome/status_bar_test.exs
findings:
  blocker: 0
  warning: 0
  info: 0
  total: 0
status: clean
---

# Phase 47: Code Review Report (Iteration 7 — fresh pass)

**Reviewed:** 2026-04-30T16:05:00Z
**Depth:** standard
**Status:** clean

## Summary

All iteration-6 findings (WR-01 LoginForm catch-all, WR-02 Verify
resend/submit catch-alls, WR-03 ResetRequest delivery_mode catch-all,
IN-01 Moderation `jump_hint/1` fallback, IN-02 Account `jump_hint/1`
fallback) have landed in the source files reviewed here. IN-03 was
explicitly accepted as no-action in iteration 6.

Verified fix landings:

- `lib/foglet_bbs/tui/screens/login/login_form.ex:207-214` — `other ->`
  catch-all on `deliver_verification_code/1` with logged warning, falling
  back to `:delivery_failed`.
- `lib/foglet_bbs/tui/screens/verify.ex:249-263` —
  `handle_verify_submit_result(other, vs, %Context{})` catch-all degrades
  to the generic verification-failed modal with logged breadcrumb.
- `lib/foglet_bbs/tui/screens/verify.ex:303-314` —
  `handle_verify_resend_result({:ok, _other}, vs)` catch-all degrades to
  the optimistic `:attempted` modal with logged breadcrumb.
- `lib/foglet_bbs/tui/screens/login/reset_request.ex:135-153` — `other ->`
  catch-all on `Foglet.Config.delivery_mode()` falls back to the
  no-email operator-assisted path with logged warning.
- `lib/foglet_bbs/tui/screens/moderation.ex:222-229` — `defp
  jump_hint(_), do: "1"` fallback in place.
- `lib/foglet_bbs/tui/screens/account/render.ex:70-76` — `defp
  jump_hint(_), do: "1"` fallback in place.

Fresh adversarial sweep across the 36 files in scope produced no new
demonstrable defects against the strict bar (logic bugs, security
issues, crash paths reachable in production, data-integrity violations,
broken test arrange/act/assert, cross-file signature drift):

- `Foglet.Threads.list_threads_query/3` and `normalize_limit/1` correctly
  apply `@page_size` (50) and `@max_page_size` (500) at the SQL `LIMIT`
  parameter slot for both the binary-`user_id` and `nil`-`user_id`
  branches; the bound-test assertions pin clamp behavior at the SQL
  boundary.
- `Foglet.Posts.list_reader_window/2` direction handling is exhaustive
  over the documented set with a logged-warning fallback in
  `normalize_reader_direction/1`; `reader_rows_around/3` has a logged
  fallback for non-integer/non-nil cursors. The `:previous` branch's
  `has_next?` derivation correctly guards on `is_integer(cursor) and
  cursor > 0` (BL-01/IN-04 history).
- `Foglet.TUI.App.Routing` resolves screen modules with a documented
  no-op return when the route is unknown and inactive — defensive
  callers (`route_screen_update/3`, `render_screen/2`,
  `init_route_screen_state/3`) all guard `Code.ensure_loaded?(module)`
  before dispatch, so the implicit `nil` return is safe (this was
  iteration-3 IN-01 and remains accepted).
- `Foglet.TUI.Screens.Login.ResetConsume.handle_task_result/3` covers
  the full `consume_reset_token/2` return surface
  (`{:ok, {:ok, _user}}`, `{:ok, {:error, :invalid_or_expired}}`,
  `{:ok, {:error, %Ecto.Changeset{}}}`) plus a `{:error, _reason}`
  catch-all for outer task failures.
- Authorization gating is intact at the actor-aware arities of
  `Foglet.Threads.{lock_thread, move_thread}/2,3` and
  `Foglet.Posts.delete_post/3` via `Bodyguard.permit/4` before the
  trusted internal variant runs.
- Per-board message-number allocation routes through `Boards.Server` for
  both `Foglet.Threads.create_thread/3` and `Foglet.Posts.create_reply/4`
  (the latter folds the thread-existence/board-mismatch/non-`%Thread{}`
  cases into a single `:posting_not_allowed` to avoid existence probes).
- `Foglet.Threads.move_thread/2` retains its `Repo.transact/1` boundary
  and the deliberate hard-pattern-match on `{_count, nil}` from
  `Repo.update_all` to surface contract drift loudly.
- The bounded-list test suite asserts the correct properties: page-size
  bound (50), `[desc: sticky, desc: last_post_at]` ordering preservation,
  SQL `LIMIT` parameterization for both query branches, explicit
  `:limit` override, non-positive/non-integer fallback to `@page_size`,
  and `@max_page_size` clamp at the SQL boundary for both branches.
- TUI chrome widgets and breadcrumb migration tests assert on stable
  rendered properties (frame layout, status bar segment composition),
  not arbitrary text fragments.

No security, authorization, data-loss, or crash defects identified. The
code is ready to ship.

---

_Reviewed: 2026-04-30T16:05:00Z_
_Reviewer: Claude (gsd-code-reviewer)_
_Depth: standard_
_Iteration: 7 — fresh pass against post-iteration-6 code state_
