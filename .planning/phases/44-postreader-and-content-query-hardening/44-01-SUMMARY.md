---
phase: 44-postreader-and-content-query-hardening
plan: 44-01
subsystem: domain
tags: [posts, ecto, reader-window, soft-delete, message-number]
requires:
  - phase: 43-large-screen-decomposition
    provides: PostReader decomposition context for later bounded-window integration.
provides:
  - Tombstone-capable `Foglet.Posts.list_reader_window/2` API.
  - `Foglet.Posts.ReaderWindow` metadata struct.
  - Board Server-backed tests for bounded reader cursor navigation.
affects: [postreader, posts, soft-delete-policy]
tech-stack:
  added: []
  patterns:
    - Context-owned message-number cursor query with sentinel rows.
    - Reader/history APIs intentionally preserve tombstones.
key-files:
  created:
    - lib/foglet_bbs/posts/reader_window.ex
    - .planning/phases/44-postreader-and-content-query-hardening/deferred-items.md
  modified:
    - lib/foglet_bbs/posts.ex
    - test/foglet_bbs/posts/posts_test.exs
key-decisions:
  - "Reader windows use `message_number` cursors scoped by `thread_id` rather than offsets or inserted timestamps."
  - "Reader/history query paths remain tombstone-capable; no `QueryHelpers.not_deleted/1` filtering was added."
patterns-established:
  - "Return bounded reader data as `%Foglet.Posts.ReaderWindow{}` with first/last cursor and previous/next metadata."
requirements-completed: [POST-01, POST-04]
duration: 5min
completed: 2026-04-30
---

# Phase 44 Plan 44-01: Context-Owned Bounded Reader Window Summary

**Tombstone-capable post reader windows with message-number cursors and navigation metadata.**

## Performance

- **Duration:** 5 min
- **Started:** 2026-04-30T00:12:59Z
- **Completed:** 2026-04-30T00:17:33Z
- **Tasks:** 2
- **Files modified:** 4

## Accomplishments

- Added `%Foglet.Posts.ReaderWindow{}` as a named result shape for bounded reader/history queries.
- Added `Foglet.Posts.list_reader_window/2` with `:initial`, `:next`, `:previous`, `:last`, and `:around` directions, bounded limits, `:user` preloads, ascending reader output, and tombstone visibility.
- Added domain tests that prove bounded cursor navigation, navigation metadata, newest-window loading, and soft-deleted row inclusion.

## Task Commits

Each task was committed atomically:

1. **Task 44-01-01: Add bounded reader-window API** - `72b2cc86` (feat)
2. **Task 44-01-02: Add reader-window domain tests** - `601b195c` (test)

**Plan metadata:** captured in this docs commit.

## Files Created/Modified

- `lib/foglet_bbs/posts/reader_window.ex` - Defines the bounded reader result struct and metadata type.
- `lib/foglet_bbs/posts.ex` - Adds tombstone-capable message-number cursor windows while leaving `list_posts/1` behavior intact.
- `test/foglet_bbs/posts/posts_test.exs` - Adds Board Server-backed coverage for bounded navigation and deleted-row reader visibility.
- `.planning/phases/44-postreader-and-content-query-hardening/deferred-items.md` - Logs the out-of-scope precommit blocker in unrelated NewThread work.

## Decisions Made

- Used `message_number` as the cursor and ordering field because it is the stable per-board reader sequence.
- Used sentinel rows (`limit + 1`) and normalized descending internal queries back to ascending output for reader display.
- Kept both `list_posts/1` and `list_reader_window/2` tombstone-capable for reader/history semantics.

## Deviations from Plan

None - plan executed exactly as written.

**Total deviations:** 0 auto-fixed.
**Impact on plan:** No scope change.

## Issues Encountered

- `rtk mix precommit` failed on an out-of-scope Credo complexity finding in `lib/foglet_bbs/tui/screens/new_thread/state.ex`. The issue is documented in `deferred-items.md`. Plan-local Credo passed for `lib/foglet_bbs/posts.ex` and `test/foglet_bbs/posts/posts_test.exs`.

## Verification

- `rtk rg -n "defmodule Foglet\\.Posts\\.ReaderWindow" lib/foglet_bbs/posts/reader_window.ex` - passed.
- `rtk rg -n "def list_reader_window" lib/foglet_bbs/posts.ex` - passed.
- `rtk rg -n "preload: \\[:user\\]" lib/foglet_bbs/posts.ex` - passed.
- `rtk rg -n "message_number" lib/foglet_bbs/posts.ex` - passed.
- `rtk rg -n "list_reader_window.*not_deleted|not_deleted.*list_reader_window" lib/foglet_bbs/posts.ex` - passed with no matches.
- `rtk rg -n "list_reader_window" test/foglet_bbs/posts/posts_test.exs` - passed.
- `rtk rg -n "has_previous\\?|has_next\\?|last_message_number|first_message_number" test/foglet_bbs/posts/posts_test.exs` - passed.
- `rtk rg -n "delete_post\\(.*\\).*list_reader_window|list_reader_window.*delete_post" test/foglet_bbs/posts/posts_test.exs` - passed.
- `rtk mix test test/foglet_bbs/posts/posts_test.exs` - passed, 22 tests, 0 failures.
- `rtk mix compile --warnings-as-errors` - passed for `foglet_bbs`; existing vendor Raxol warnings were emitted.
- `rtk mix format --check-formatted lib/foglet_bbs/posts.ex lib/foglet_bbs/posts/reader_window.ex test/foglet_bbs/posts/posts_test.exs` - passed.
- `rtk mix credo lib/foglet_bbs/posts.ex test/foglet_bbs/posts/posts_test.exs` - passed with no issues.
- `rtk mix precommit` - failed due to unrelated NewThread Credo complexity; deferred.

## Known Stubs

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

Plan 44-02 can consume `Foglet.Posts.list_reader_window/2` from PostReader without changing historical `list_posts/1` semantics. The active query contract now provides bounded rows plus first/last cursor and previous/next metadata for reducer integration.

## Self-Check: PASSED

- Found `lib/foglet_bbs/posts/reader_window.ex`.
- Found `.planning/phases/44-postreader-and-content-query-hardening/44-01-SUMMARY.md`.
- Found task commits `72b2cc86` and `601b195c` in git history.
- Stub scan found no placeholder/stub patterns in plan-created or plan-modified source/test files.
- Threat surface scan found no new endpoints, auth paths, file access patterns, migrations, or schema changes.

---
*Phase: 44-postreader-and-content-query-hardening*
*Completed: 2026-04-30*
