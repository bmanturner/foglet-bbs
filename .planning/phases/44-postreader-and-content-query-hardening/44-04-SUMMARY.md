---
phase: 44-postreader-and-content-query-hardening
plan: 44-04
subsystem: testing
tags: [posts, threads, boards, soft-delete, unread-counts, query-helpers]
requires:
  - phase: 44-postreader-and-content-query-hardening
    provides: Tombstone-capable reader/history queries and bounded reader windows.
provides:
  - Automated coverage for tombstone-capable post reader/history APIs.
  - Automated coverage that thread list APIs hide soft-deleted threads.
  - Automated coverage that board unread and directory summaries hide soft-deleted content.
affects: [posts, threads, boards, soft-delete-policy]
tech-stack:
  added: []
  patterns:
    - Structural soft-delete assertions over ids, timestamps, message numbers, and summary fields.
    - Query-boundary coverage keeps reader/history tombstones separate from list/summary filters.
key-files:
  created:
    - .planning/phases/44-postreader-and-content-query-hardening/44-04-SUMMARY.md
  modified:
    - test/foglet_bbs/posts/posts_test.exs
    - test/foglet_bbs/threads/threads_test.exs
    - test/foglet_bbs/boards/boards_test.exs
key-decisions:
  - "Reader/history tests assert soft-deleted post rows and original message numbers without checking rendered tombstone text."
  - "Thread list tests cover `list_threads/1`, `list_threads/2`, and nil-user delegation through the shared not-deleted filter."
  - "Board summary tests cover both single and batch unread count APIs plus directory last-post summaries at the context boundary."
patterns-established:
  - "Soft-delete visibility tests should target context return values instead of TUI-rendered copy."
requirements-completed: [POST-04]
duration: 4min
completed: 2026-04-30
---

# Phase 44 Plan 44-04: Soft-Delete Query Policy Summary

**Soft-delete policy coverage now protects reader/history tombstones while keeping list, unread, and directory summaries filtered.**

## Performance

- **Duration:** 4 min
- **Started:** 2026-04-30T00:47:17Z
- **Completed:** 2026-04-30T00:51:27Z
- **Tasks:** 3
- **Files modified:** 3

## Accomplishments

- Added post tests proving `list_posts/1` and `list_reader_window/2` retain soft-deleted rows with the original `message_number`.
- Expanded thread list coverage so `list_threads/1`, `list_threads/2`, and `list_threads(board.id, nil)` all hide deleted threads.
- Added board summary coverage proving soft-deleted unread posts are excluded from `unread_count/2`, `unread_counts/1`, and subscribed board directory entries, and deleted threads do not drive directory `last_post_at`.

## Task Commits

Each task was committed atomically:

1. **Task 44-04-01: Cover tombstone-capable post readers** - `07ee298d` (test)
2. **Task 44-04-02: Cover deleted thread list filters** - `2bd5eba1` (test)
3. **Task 44-04-03: Cover board soft-delete summaries** - `86126ed7` (test)

**Plan metadata:** captured in this docs commit.

## Files Created/Modified

- `test/foglet_bbs/posts/posts_test.exs` - Adds reader/history tombstone visibility and message-number preservation coverage.
- `test/foglet_bbs/threads/threads_test.exs` - Expands deleted-thread list coverage across all public thread list entry points.
- `test/foglet_bbs/boards/boards_test.exs` - Adds unread count and board directory summary tests for deleted posts and deleted threads.
- `.planning/phases/44-postreader-and-content-query-hardening/44-04-SUMMARY.md` - Captures plan outcome, verification, and self-check.

## Decisions Made

- Kept `Foglet.Posts.list_posts/1` and `Foglet.Posts.list_reader_window/2` tombstone-capable, matching the reader/history contract from earlier Phase 44 work.
- Did not refactor existing thread or board query implementations because the active query boundaries already use `QueryHelpers.not_deleted/1` or explicit deleted-row predicates with focused tests.
- Kept tests structural and context-level; no assertions depend on rendered tombstone text or TUI screen output.

## Deviations from Plan

None - plan executed exactly as written.

**Total deviations:** 0 auto-fixed.
**Impact on plan:** No scope change.

## Issues Encountered

- Unrelated sysop TUI files were modified in the worktree by other work during execution. They were left unstaged and untouched by this plan.

## Verification

- `rtk rg -n "soft-deleted posts remain visible.*list_posts|list_reader_window.*deleted|deleted.*list_reader_window" test/foglet_bbs/posts/posts_test.exs` - passed.
- `rtk rg -n "message_number" test/foglet_bbs/posts/posts_test.exs` - passed.
- `rtk rg -n "not_deleted" lib/foglet_bbs/posts.ex` - passed with no matches.
- `rtk mix test test/foglet_bbs/posts/posts_test.exs` - passed, 23 tests, 0 failures.
- `rtk rg -n "delete_thread\\(|list_threads\\(board\\.id\\).*deleted|deleted.*list_threads\\(board\\.id" test/foglet_bbs/threads/threads_test.exs` - passed.
- `rtk rg -n "QueryHelpers\\.not_deleted\\(\\)" lib/foglet_bbs/threads.ex` - passed.
- `rtk mix test test/foglet_bbs/threads/threads_test.exs` - passed, 31 tests, 0 failures.
- `rtk rg -n "unread_count\\(|unread_counts\\(|board_directory_for\\(" test/foglet_bbs/boards/boards_test.exs` - passed.
- `rtk rg -n "delete_post\\(|delete_thread\\(|deleted.*last_post_at|last_post_at.*deleted" test/foglet_bbs/boards/boards_test.exs` - passed.
- `rtk rg -n "is_nil\\(p\\.deleted_at\\)|is_nil\\(t\\.deleted_at\\)|QueryHelpers" lib/foglet_bbs/boards.ex` - passed.
- `rtk mix test test/foglet_bbs/boards/boards_test.exs` - passed, 61 tests, 0 failures.
- `rtk mix test test/foglet_bbs/posts/posts_test.exs test/foglet_bbs/threads/threads_test.exs test/foglet_bbs/boards/boards_test.exs` - passed, 115 tests, 0 failures.
- `rtk mix compile --warnings-as-errors` - passed for `foglet_bbs`; dependency warnings from `raxol` were emitted.

## Known Stubs

None.

## Threat Flags

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

Phase 44 now has coverage for the full POST-04 split: reader/history APIs keep tombstones, while thread lists and board summaries hide soft-deleted content from user-visible list surfaces.

## Self-Check: PASSED

- Found `.planning/phases/44-postreader-and-content-query-hardening/44-04-SUMMARY.md`.
- Found `test/foglet_bbs/posts/posts_test.exs`.
- Found `test/foglet_bbs/threads/threads_test.exs`.
- Found `test/foglet_bbs/boards/boards_test.exs`.
- Found task commits `07ee298d`, `2bd5eba1`, and `86126ed7` in git history.
- Stub scan found no placeholder/stub patterns in plan-modified test files.
- Threat surface scan found no new endpoints, auth paths, file access patterns, migrations, or schema changes.

---
*Phase: 44-postreader-and-content-query-hardening*
*Completed: 2026-04-30*
