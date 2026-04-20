---
phase: 3
plan: "04"
status: complete
started: "2026-04-20"
completed: "2026-04-20"
---

# Plan 04 — Screen Integration: Summary

## What was built

Wired the three Wave 1 artifacts (GREATEST fix, list_threads/2 annotation, ListRow.render_with_metadata/6) into the TUI flow for end-to-end read-pointer correctness and thread-row enrichment.

## Key changes

- **`lib/foglet_bbs/tui/screens/thread_list.ex`**: Thread rows now use `render_with_metadata/6` with `@handle · N posts · time-ago` metadata. Q dispatches `{:load_boards}` for first-phase refresh. `load_threads/2` prefers 2-arity for `has_unread` annotation. Nil-safe `sort_threads` for map-based thread data.
- **`lib/foglet_bbs/tui/screens/post_reader.ex`**: `load_posts/2` seeds `read_position` from post 0 on entry (D-05) — "if you saw it, you read it."
- **`lib/foglet_bbs/tui/app.ex`**: `{:read_pointers_flushed, _}` dispatches `{:load_boards}` when `current_screen == :board_list` (D-06 second-phase refresh). `{:load_threads, _}` passes `user_id` via `load_threads_for_user/2` helper.

## Test additions

- ThreadList: +7 tests (metadata rendering, domain dispatch, Q dispatches {:load_boards})
- PostReader: +4 tests (read-on-entry seeding, flush integration)
- App: +5 tests (second-phase refresh on :board_list, no-refresh on other screens)

## Key decisions

- Two-phase board refresh (D-06): immediate `{:load_boards}` on Q + conditional `{:load_boards}` on `{:read_pointers_flushed, _}` when on :board_list
- `annotate_fallback/1` for backwards compat with test fakes that only implement `list_threads/1`
- Moved `load_threads_for_user/2` helper after all `do_update` clauses to avoid compiler warning about non-grouped clauses

## Key files

- `lib/foglet_bbs/tui/screens/thread_list.ex` — metadata rows, Q refresh, load_threads/2 user dispatch
- `lib/foglet_bbs/tui/screens/post_reader.ex` — read-on-entry seeding
- `lib/foglet_bbs/tui/app.ex` — post-flush board refresh, load_threads user dispatch
- `test/foglet_bbs/tui/screens/thread_list_test.exs` — 7 new tests
- `test/foglet_bbs/tui/screens/post_reader_test.exs` — 4 new tests
- `test/foglet_bbs/tui/app_test.exs` — 5 new tests

## Self-Check: PASSED
