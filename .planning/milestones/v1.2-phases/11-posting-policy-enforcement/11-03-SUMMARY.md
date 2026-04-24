---
phase: 11-posting-policy-enforcement
plan: 03
subsystem: tui
tags: [posting-policy, tui, error-copy, post-composer]
requires:
  - phase: 11-01
    provides: Structured thread create posting-policy errors
  - phase: 11-02
    provides: Structured reply posting-policy and locked-thread errors
provides:
  - New-thread posting-policy denial copy
  - Reply posting-policy denial copy
  - Reply locked-thread denial copy
affects: [ssh-tui, posting-policy-enforcement]
tech-stack:
  added: []
  patterns:
    - Screen-local format_error/1 clauses for structured domain errors
    - TUI tests with fake domain adapters for context error results
key-files:
  created: []
  modified:
    - lib/foglet_bbs/tui/screens/new_thread.ex
    - lib/foglet_bbs/tui/screens/post_composer.ex
    - test/foglet_bbs/tui/screens/new_thread_test.exs
    - test/foglet_bbs/tui/screens/post_composer_test.exs
key-decisions:
  - "TUI screens only format structured context errors; authorization and posting policy remain in domain contexts."
  - "Locked-thread copy is exactly `This thread is locked`; posting-policy copy is exactly `You are not allowed to post on this board.`"
patterns-established:
  - "Unknown post composer errors fall back to inspect output instead of the old generic `Failed to create post.` copy."
requirements-completed: [POST-04]
duration: unknown
completed: 2026-04-24
---

# Phase 11: Posting Policy Enforcement Summary

**TUI posting screens now map structured policy and lock denials to clear terminal copy without success navigation.**

## Performance

- **Duration:** Unknown
- **Started:** 2026-04-24
- **Completed:** 2026-04-24
- **Tasks:** 3
- **Files modified:** 4

## Accomplishments

- Added POST-04 tests for new-thread posting-policy denial and reply posting-policy / locked-thread denial.
- Updated `Foglet.TUI.Screens.NewThread` to format `:posting_not_allowed` and `:thread_locked`.
- Updated `Foglet.TUI.Screens.PostComposer` to preserve structured reply-create reasons and format them into exact terminal copy.
- Ran the full Phase 11 targeted quick validation across thread, reply, and TUI screen suites.

## Task Commits

Each task was committed atomically:

1. **Task 1: Add TUI rejection-copy tests** - `50ca617` (test)
2. **Task 2: Format structured posting errors in TUI screens** - `e501984` (feat)
3. **Task 3: Run Phase 11 quick validation** - no code commit; validation passed with `109 tests, 0 failures`

**Plan metadata:** this summary commit.

## Files Created/Modified

- `lib/foglet_bbs/tui/screens/new_thread.ex` - Adds posting-policy and locked-thread error copy clauses.
- `lib/foglet_bbs/tui/screens/post_composer.ex` - Preserves structured reply errors and formats modal copy.
- `test/foglet_bbs/tui/screens/new_thread_test.exs` - Adds POST-04 new-thread denial coverage.
- `test/foglet_bbs/tui/screens/post_composer_test.exs` - Adds POST-04 reply denial coverage and removes old generic failure expectation.

## Decisions Made

- Kept policy enforcement out of screens; screens only present errors returned by contexts.
- Preserved successful reply navigation to `:post_reader` and `{:load_posts, thread.id, jump_last: true}`.

## Deviations from Plan

None - plan executed as written.

## Issues Encountered

The isolated worktree needed `rtk mix deps.get` before tests because dependencies were not materialized in the fresh checkout.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

Phase 11 has targeted coverage for domain posting-policy enforcement and TUI denial copy.

---
*Phase: 11-posting-policy-enforcement*
*Completed: 2026-04-24*
