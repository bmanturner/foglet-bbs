---
phase: 21-board-directory-facelift
plan: 01
subsystem: boards
tags: [boards, context, query, last-post-at, data-layer]

requires:
  - phase: 02
    provides: board, category, subscription, thread, and post persistence
provides:
  - Board directory entries include actor-independent last_post_at values.
  - Board-rooted aggregate for max non-deleted thread last_post_at per board.
  - SUBS-01 coverage for max, empty, soft-deleted, and actor-independent cases.
affects: [board-directory-facelift, board-tree, tui-board-list]

tech-stack:
  added: []
  patterns:
    - Board-rooted LEFT JOIN aggregate for actor-independent board metadata
    - ID-based board directory test lookup helper

key-files:
  created:
    - .planning/phases/21-board-directory-facelift/21-01-SUMMARY.md
  modified:
    - lib/foglet_bbs/boards.ex
    - test/foglet_bbs/boards/boards_test.exs

key-decisions:
  - "Implemented last_post_at as a private Board-rooted aggregate instead of joining from Subscription, so subscribed and unsubscribed actors receive identical values."
  - "Kept directory tests resilient by locating entries by board.id rather than destructuring the full directory."

patterns-established:
  - "Board directory aggregate helpers should batch per-board derived fields once per board_directory_for/1 call."
  - "Board directory tests should use id-based entry lookup when fixture growth could alter category or board ordering."

requirements-completed: [BOARDS-03]

duration: 25min
completed: 2026-04-25
---

# Phase 21 Plan 01: Board Directory Last Post Summary

**Board directory entries now expose actor-independent last_post_at from a single Board-rooted aggregate over non-deleted threads.**

## Performance

- **Duration:** 25 min
- **Started:** 2026-04-25T21:41:00Z
- **Completed:** 2026-04-25T22:06:02Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments

- Added `:last_post_at` to `Foglet.Boards.directory_board`.
- Added private `last_post_ats/0`, rooted on `Board`, with a `LEFT JOIN` to `Foglet.Threads.Thread` and `is_nil(t.deleted_at)` in the join condition.
- Wired `board_directory_for/1` so every board entry includes `last_post_at: Map.get(last_post_ats, board.id)`.
- Added four SUBS-01 tests covering max non-deleted thread timestamp, empty boards, soft-deleted thread exclusion, and identical values for subscribed/unsubscribed actors.
- Added `find_board_entry/2` for id-based directory lookup in tests.

## Task Commits

1. **Task 2 RED: last_post_at board directory tests** - `1848794` (test)
2. **Task 1 GREEN: board directory last_post_at aggregate and wiring** - `cbd8ca1` (feat)

## Files Created/Modified

- `lib/foglet_bbs/boards.ex` - Added typespec field, doc note, aggregate helper, and directory entry wiring.
- `test/foglet_bbs/boards/boards_test.exs` - Added id-based lookup helper and BOARDS-03 coverage.
- `.planning/phases/21-board-directory-facelift/21-01-SUMMARY.md` - Execution summary.

## Decisions Made

- Used a separate private aggregate helper rather than folding into `unread_counts/1`, because `last_post_at` is actor-independent and must include unsubscribed boards.
- Kept the soft-delete filter in the join condition, preserving `nil` results for boards with only deleted threads.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

- The fresh worktree had no fetched Hex dependencies, so `rtk mix deps.get` was required before tests could run.
- Full-project `rtk mix format --check-formatted` fails on pre-existing unrelated formatting in `test/foglet_bbs/tui/widgets/composer/editor_frame_test.exs`. Scoped formatting for the touched plan files passes.

## Verification

- `rtk mix test test/foglet_bbs/boards/boards_test.exs --only board_directory` - passed, 6 tests, 0 failures.
- `rtk mix compile --warnings-as-errors` - passed.
- `rtk mix format --check-formatted lib/foglet_bbs/boards.ex test/foglet_bbs/boards/boards_test.exs` - passed.
- `rtk mix credo lib/foglet_bbs/boards.ex` - passed, no issues.
- `rtk mix credo test/foglet_bbs/boards/boards_test.exs` - passed, no issues.
- `rtk rg -c "last_post_at" lib/foglet_bbs/boards.ex` - reported `7`.
- Sanity checked `last_post_ats/0` window: helper roots on `from b in Board`, not `Subscription`.

## Known Stubs

None.

## Threat Flags

None. The new surface is the planned Repo query to directory map boundary from the plan threat model.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

Plan 21-02 can consume `:last_post_at` from every board directory entry for the BoardTree age column. The value is available for subscribed and unsubscribed actors and excludes soft-deleted threads.

## Self-Check: PASSED

- Summary file exists.
- Task commits `1848794` and `cbd8ca1` exist.
- No tracked file deletions were introduced by task commits.

---
*Phase: 21-board-directory-facelift*
*Completed: 2026-04-25*
