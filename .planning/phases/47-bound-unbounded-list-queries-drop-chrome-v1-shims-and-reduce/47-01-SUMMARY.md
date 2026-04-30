---
phase: 47-bound-unbounded-list-queries-drop-chrome-v1-shims-and-reduce
plan: 01
subsystem: posts/tui-post-reader
tags: [bounded-queries, deletion, tui, post-reader]
requires:
  - Phase 44 list_reader_window/2 (`Foglet.Posts.list_reader_window/2`)
  - Phase 44 PostReader window-anchor helpers (`load_direction/1`,
    `selected_index_after_window_load/3`)
provides:
  - Bounded `PostReader.load_posts/2` via `list_reader_window/2` with
    read-pointer / jump_last / initial anchor mapping
  - Deletion of `Foglet.Posts.list_posts/1` (SPEC R1 grep gate clean)
affects:
  - All consumers of `PostReader.load_posts/2` (App callback path)
  - Test fixtures that previously stubbed `list_posts/1` (post_reader_test,
    app_test, posts_test)
tech-stack:
  added: []
  patterns:
    - Anchor-mapping conditional via tiny multi-clause private helper
      (`load_window_opts/2`)
    - `index_of_message_number/2` pure helper for landing selection on a
      known message_number after a windowed load
key-files:
  created: []
  modified:
    - lib/foglet_bbs/posts.ex
    - lib/foglet_bbs/tui/screens/post_reader.ex
    - test/foglet_bbs/posts/posts_test.exs
    - test/foglet_bbs/tui/app_test.exs
    - test/foglet_bbs/tui/screens/post_reader_test.exs
decisions:
  - D-02 anchor mapping: read-pointer present → :around, jump_last → :last,
    otherwise → :initial
  - D-03 read-pointer source stays the screen-owned
    `pending_read_positions[thread_id].last_read_message_number`; no DB call
    from `load_posts/2`, no new `:read_pointer` direction added to Posts
  - D-04 reuse `selected_index_after_window_load/3` as a fallback; the new
    `index_of_message_number/2` lands selection on the read-pointer post
    when one is known
  - D-22 fixture mods migrated by deletion of `list_posts/1` clauses (no
    new fixture surface beyond R2 tests)
  - D-23 tombstone-semantics tests for the deleted API removed outright;
    Phase 44 D-13/D-14 already covers tombstone behavior through
    `list_reader_window/2`
metrics:
  duration: ~25 minutes
  completed: 2026-04-30
---

# Phase 47 Plan 01: Bound `PostReader.load_posts/2` and delete `Posts.list_posts/1` Summary

Migrated `Foglet.TUI.Screens.PostReader.load_posts/2` off the eager unbounded
`Foglet.Posts.list_posts/1` and onto the windowed `list_reader_window/2` with
read-pointer-aware anchor mapping; then deleted `list_posts/1` and every
remaining call site so SPEC R1's grep gate is clean.

## Tasks Completed

| # | Task                                                      | Commit    | Type     |
| - | --------------------------------------------------------- | --------- | -------- |
| 1 | Add failing R2 tests for windowed load_posts/2            | bb6c1afc  | test     |
| 1 | Migrate load_posts/2 to list_reader_window/2 (R2 GREEN)   | 6b714cde  | feat     |
| 2 | Delete Posts.list_posts/1 + remove all call sites (R1)    | a28c222b  | feat     |
| 1 | Extract load_posts/2 helpers to satisfy credo complexity  | 7a9d0dde  | refactor |

## What Changed

### `Foglet.TUI.Screens.PostReader.load_posts/2`

The function used to call `posts_mod.list_posts(thread_id)` and return every
post in the thread. It now calls `posts_mod.list_reader_window(thread_id, opts)`
where `opts` is computed by a tiny anchor-mapping helper:

- **Read pointer present** (i.e. `pending_read_positions[thread_id].last_read_message_number`
  is a positive integer) → `[direction: :around, around_message_number: <pointer>]`
- **`load_intent: :jump_last`** → `[direction: :last]`
- **Otherwise** → `[direction: :initial]`

After the window returns, the screen state is updated with the window's
position metadata (`window_first_message_number`, `window_last_message_number`,
`window_has_previous?`, `window_has_next?`) so the navigation helpers
(`advance_local_post`, etc.) have correct boundary information for n/p/page
keys. Selection is placed on the post matching the read pointer's
`message_number` (D-04) when a read pointer drove the load — this is what
makes the "200 posts + pointer at 150" acceptance assertion pass. When no
read pointer is set, selection falls through to the existing
`selected_index_after_window_load/3` Phase 44 helper.

The render-cache and viewport warmup logic was also retargeted to warm the
**selected** post (rather than always post 0) so that on a read-pointer entry,
the user sees the read-pointer post fully rendered with no parse cost on the
first frame.

### `Foglet.Posts.list_posts/1`

Deleted. The function's `@doc`, `@spec`, and body are gone from
`lib/foglet_bbs/posts.ex`. Tombstone behavior — preservation of soft-deleted
posts in the reader stream — is now the sole responsibility of
`list_reader_window/2`, which Phase 44 D-13/D-14 already covers.

### Tests

- **`test/foglet_bbs/tui/screens/post_reader_test.exs`** — added a new
  describe block "load_posts/2 — windowed migration (Phase 47 R2)" with the
  four behaviors the plan called for. Deleted `def list_posts/1` clauses
  from the four fixture mods (`FakePosts`, `EmptyPosts`, `FakePostsForLoad`,
  `BoundedFakePosts`); migrated three remaining call sites that were using
  `FakePosts.list_posts("t1")` to `FakePosts.list_reader_window("t1", []).posts`.
  Notably, deleting `BoundedFakePosts.list_posts/1` removes its `raise`
  regression-guard clause — the regression-guard semantic is preserved
  because `Foglet.Posts.list_posts/1` no longer exists at all.
- **`test/foglet_bbs/tui/app_test.exs`** — deleted the two `list_posts/1`
  clauses from `FakePosts` and inlined the post fixtures into the surviving
  `list_reader_window/2` clauses.
- **`test/foglet_bbs/posts/posts_test.exs`** — deleted the two `list_posts/1`
  tombstone-semantics tests outright per D-23, leaving a brief comment
  pointing to the equivalent `list_reader_window/2` coverage from Phase 44.

## SPEC Acceptance

| Gate                                                         | Status |
| ------------------------------------------------------------ | ------ |
| `grep -rn "\.list_posts\b" lib/ test/` returns zero (R1)     | PASS   |
| `def list_posts` returns zero across `lib/` and `test/` (R1) | PASS   |
| 200-post thread + pointer at 150 lands selection on 150 (R2) | PASS   |
| 5-post small thread load still succeeds (R2)                 | PASS   |
| `load_intent: :jump_last` → `direction: :last` (R2 / D-02)   | PASS   |
| No pointer + no jump_last → `direction: :initial` (R2 / D-02)| PASS   |
| `mix compile --warnings-as-errors` succeeds                  | PASS   |
| `mix credo --strict` clean on `post_reader.ex`               | PASS   |
| Phase 44 render-purity guard test still passes (R2)          | PASS   |
| `mix test` for changed scopes — 231 tests, 0 failures        | PASS   |
| Full `mix test` — 2226 tests, 0 failures                     | PASS   |

The "render-purity guard" referenced in the plan is the
`decomposition contract` describe block in `post_reader_test.exs` (lines 390+)
which verifies `PostReader.render/2` delegates to `Render.render/2`. That
test was untouched and still passes.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Selection landing logic needed a new helper to support read-pointer message_number anchoring**

- **Found during:** Task 1 GREEN
- **Issue:** The plan's stated approach was to "reuse `selected_index_after_window_load/3` to land the selected index on the read pointer's message_number." But that helper relies on `selected_post(state)`, which reads from `state.posts` + `state.selected_post_index` — both of which are empty/default on a fresh load. As a result, the helper returned 0 on read-pointer-driven loads and the "lands on 150" acceptance assertion would fail.
- **Fix:** Added a small private helper `index_of_message_number/2` that finds the index of a post in the loaded window by its `message_number`. `place_selection_after_load/4` now uses this helper when a read-pointer message_number is known, and falls back to `selected_index_after_window_load/3` otherwise (preserving the helper's value for `:jump_last` and `:initial` flows).
- **Files modified:** `lib/foglet_bbs/tui/screens/post_reader.ex`
- **Commit:** 6b714cde (initial), 7a9d0dde (refactored into `place_selection_after_load/4`)

### Refactor Notes

**2. [Rule 1 - Code-quality / lint] Refactor `load_posts/2` to satisfy credo complexity gate**

- **Found during:** post-Task-2 verification (`mix credo --strict`)
- **Issue:** After the R2 migration, `load_posts/2`'s cyclomatic complexity rose to 17 (max 9). Credo failed.
- **Fix:** Extracted six pure helpers — `resolve_posts_mod/1`, `read_pointer_message_number/2`, `load_window_opts/2`, `apply_window_to_screen_state/4`, `place_selection_after_load/4`, `warm_selected_post_artifacts/4` — keeping `load_posts/2` as a 12-line orchestrator. No behavior change.
- **Files modified:** `lib/foglet_bbs/tui/screens/post_reader.ex`
- **Commit:** 7a9d0dde

## TDD Gate Compliance

- **RED gate:** `bb6c1afc — test(47-01): add failing R2 tests for load_posts/2 windowed migration` (3 of 4 new tests failed against the unbounded baseline)
- **GREEN gate:** `6b714cde — feat(47-01): migrate PostReader.load_posts/2 to list_reader_window/2 (R2)`
- **REFACTOR gate:** `7a9d0dde — refactor(47-01): extract load_posts/2 helpers to satisfy credo complexity`

## Self-Check: PASSED

- File `lib/foglet_bbs/posts.ex` exists; FOUND
- File `lib/foglet_bbs/tui/screens/post_reader.ex` exists; FOUND
- File `test/foglet_bbs/posts/posts_test.exs` exists; FOUND
- File `test/foglet_bbs/tui/app_test.exs` exists; FOUND
- File `test/foglet_bbs/tui/screens/post_reader_test.exs` exists; FOUND
- File `.planning/phases/47-bound-unbounded-list-queries-drop-chrome-v1-shims-and-reduce/47-01-SUMMARY.md` exists; FOUND (this file)
- Commit `bb6c1afc` exists; FOUND
- Commit `6b714cde` exists; FOUND
- Commit `a28c222b` exists; FOUND
- Commit `7a9d0dde` exists; FOUND
