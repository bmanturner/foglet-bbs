---
phase: 11-posting-policy-enforcement
plan: 01
subsystem: domain
tags: [posting-policy, threads, boards, authorization]
requires: []
provides:
  - Shared Foglet.PostingPolicy.can_post?/2 contract
  - Thread creation posting-policy preflight before board-server writes
  - POST-01 role matrix and no-side-effect regression coverage
affects: [posts, tui-posting-errors, posting-policy-enforcement]
tech-stack:
  added: []
  patterns:
    - Pure policy helper over persisted user and board records
    - Context preflight before board-server message-number allocation
key-files:
  created:
    - lib/foglet_bbs/posting_policy.ex
  modified:
    - lib/foglet_bbs/boards/board.ex
    - lib/foglet_bbs/threads.ex
    - test/foglet_bbs/threads/threads_test.exs
key-decisions:
  - "Posting eligibility is centralized in Foglet.PostingPolicy.can_post?/2 and called from context mutations."
  - "Thread creation reloads persisted user and board records before delegating to Foglet.Boards.Server."
patterns-established:
  - "Rejected posting attempts return {:error, :posting_not_allowed} before board-server allocation."
  - "No-side-effect tests assert database counts, persisted board counters, and board-server next_number remain unchanged."
requirements-completed: [POST-01]
duration: unknown
completed: 2026-04-24
---

# Phase 11: Posting Policy Enforcement Summary

**Thread creation now enforces active-user and board postability policy before board-server message-number allocation.**

## Performance

- **Duration:** Unknown
- **Started:** 2026-04-24
- **Completed:** 2026-04-24
- **Tasks:** 2
- **Files modified:** 4

## Accomplishments

- Added `Foglet.PostingPolicy.can_post?/2` for active, non-deleted users and `:members` / `:mods_only` / `:sysop_only` board policy checks.
- Updated `Foglet.Threads.create_thread/3` to load the persisted user and board, reject denied posters with `{:error, :posting_not_allowed}`, and only call `Foglet.Boards.Server.create_thread/3` after the policy gate passes.
- Added POST-01 tests for the thread role matrix, inactive/deleted/missing users, and side-effect-free rejection behavior.

## Task Commits

Each task was committed atomically:

1. **Task 1: Add thread policy regression tests** - `434aee1` (test)
2. **Task 2: Enforce thread policy before board-server delegation** - `7c2e68b` (feat)

**Plan metadata:** created by orchestrator recovery after executor completed code commits without writing the summary.

## Files Created/Modified

- `lib/foglet_bbs/posting_policy.ex` - Shared posting-policy helper for persisted user and board records.
- `lib/foglet_bbs/threads.ex` - Thread creation preflight before board-server delegation.
- `lib/foglet_bbs/boards/board.ex` - Board schema enum support needed for planned posting policies.
- `test/foglet_bbs/threads/threads_test.exs` - POST-01 policy matrix and no-side-effect regression tests.

## Decisions Made

- Denied thread attempts use the structured `{:error, :posting_not_allowed}` result reserved for Phase 11 TUI presentation.
- Thread policy checks stay in the context layer and do not add caller-settable foreign keys or direct thread/post inserts.

## Deviations from Plan

The implementation also updated `lib/foglet_bbs/boards/board.ex` to support the planned `postable_by` enum values used by Phase 11 tests and policy checks.

## Issues Encountered

The executor completed the test and implementation commits but did not create `11-01-SUMMARY.md`; the orchestrator recovered this summary before merging the worktree branch.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

Plan 11-02 can extend `Foglet.PostingPolicy` with locked-thread bypass logic and enforce the same board posting policy in reply creation.

---
*Phase: 11-posting-policy-enforcement*
*Completed: 2026-04-24*
