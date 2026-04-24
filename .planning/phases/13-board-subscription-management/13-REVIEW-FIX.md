---
phase: 13-board-subscription-management
review: 13-REVIEW.md
fixed: 2026-04-24T21:33:00Z
status: fixed
commit: dded8a3
---

# Phase 13 Review Fixes

## Fixed Findings

### WR-01: Board Directory Tree Keeps Stale Subscription Data After Reload

Fixed in `lib/foglet_bbs/tui/app.ex`.

`{:boards_loaded, boards}` now stores the refreshed directory and clears the cached `BoardList.State.tree` while preserving feedback. This forces the BoardList screen to rebuild labels and focused-node metadata from the fresh subscription snapshot after subscribe/unsubscribe reloads.

Regression coverage: `test/foglet_bbs/tui/app_test.exs` asserts that `{:boards_loaded, boards}` clears the cached tree and preserves feedback.

### WR-02: Marking A Board Required Does Not Ensure Existing Users Are Subscribed

Fixed in `lib/foglet_bbs/boards.ex`.

`update_board/3` now runs inside `Repo.transact/1` and backfills missing `board_subscriptions` rows for existing non-deleted users whenever the updated board is required. Inserts still route through the context subscription helper, preserving the existing idempotent `on_conflict: :nothing` behavior.

Regression coverage: `test/foglet_bbs/boards/boards_test.exs` asserts that toggling an optional board to required subscribes existing users.

## Verification

- `rtk mix test test/foglet_bbs/boards/boards_test.exs test/foglet_bbs/tui/app_test.exs:993` passed in the review-fix worktree.
- `rtk mix precommit` passed in the review-fix worktree.
- Main-line focused Phase 13 regression suite passed after merge: 160 tests, 0 failures.
- Main-line `rtk mix precommit` passed after merge.
