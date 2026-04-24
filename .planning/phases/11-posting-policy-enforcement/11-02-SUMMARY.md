---
phase: 11-posting-policy-enforcement
plan: 02
subsystem: domain
tags: [posting-policy, replies, locked-threads, authorization]
requires:
  - phase: 11-01
    provides: Shared Foglet.PostingPolicy.can_post?/2
provides:
  - Reply creation posting-policy preflight before board-server writes
  - Locked-thread bypass predicate based on stable authorization scopes
  - POST-02/POST-03 policy, lock, and no-side-effect regression coverage
affects: [tui-posting-errors, moderation, posting-policy-enforcement]
tech-stack:
  added: []
  patterns:
    - Context preflight over persisted user, board, and thread records
    - Lock bypass uses Foglet.Authorization.scopes_for/2 scope shapes
key-files:
  created: []
  modified:
    - lib/foglet_bbs/posting_policy.ex
    - lib/foglet_bbs/posts.ex
    - test/foglet_bbs/posts/posts_test.exs
key-decisions:
  - "Reply creation rejects board-policy denials before locked-thread bypass checks."
  - "Lock bypass permits sysops and scoped moderators but never overrides board postable_by policy."
patterns-established:
  - "Missing user, board, thread, or mismatched thread/board IDs return {:error, :posting_not_allowed} before board-server delegation."
  - "Locked thread denial returns {:error, :thread_locked} without reply side effects."
requirements-completed: [POST-02, POST-03]
duration: unknown
completed: 2026-04-24
---

# Phase 11: Posting Policy Enforcement Summary

**Reply creation now enforces board posting policy and locked-thread rules before board-server message-number allocation.**

## Performance

- **Duration:** Unknown
- **Started:** 2026-04-24
- **Completed:** 2026-04-24
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments

- Added `Foglet.PostingPolicy.can_bypass_thread_lock?/2` using `Foglet.Authorization.scopes_for(user, :lock_thread)`.
- Updated `Foglet.Posts.create_reply/4` to reload persisted user, board, and thread records and reject policy, mismatch, and lock denials before calling `Foglet.Boards.Server.create_post/4`.
- Added POST-02/POST-03 tests for reply policy matrix, locked-thread bypass, lock-bypass board-policy independence, and side-effect-free rejection.

## Task Commits

Each task was committed atomically:

1. **Task 1: Add reply policy and lock regression tests** - `9cb2e62` (test)
2. **Task 2: Enforce reply policy and locked-thread preflight** - `b3e8f9a` (feat)

**Plan metadata:** this summary commit.

## Files Created/Modified

- `lib/foglet_bbs/posting_policy.ex` - Adds locked-thread bypass predicate.
- `lib/foglet_bbs/posts.ex` - Adds reply preflight before board-server delegation.
- `test/foglet_bbs/posts/posts_test.exs` - Adds POST-02/POST-03 policy and lock coverage.

## Decisions Made

- Board posting policy runs before lock checks, so moderator/sysop lock bypass cannot override `:sysop_only` posting restrictions.
- Thread/board mismatch is treated as posting denial to avoid leaking extra policy detail.

## Deviations from Plan

None - plan executed as written.

## Issues Encountered

The isolated worktree needed `rtk mix deps.get` before running tests because dependencies were not materialized in the fresh checkout.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

Plan 11-03 can consume `{:error, :posting_not_allowed}` and `{:error, :thread_locked}` from thread/reply contexts and map them to terminal copy.

---
*Phase: 11-posting-policy-enforcement*
*Completed: 2026-04-24*
