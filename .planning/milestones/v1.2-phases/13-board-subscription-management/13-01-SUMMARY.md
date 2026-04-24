---
phase: 13-board-subscription-management
plan: 1
subsystem: boards
tags: [ecto, postgres, subscriptions, context-api]

requires:
  - phase: 13-board-subscription-management
    provides: Phase 13 specification and context decisions
provides:
  - Required-subscription board persistence with DB and changeset validation
  - Context-owned active board directory snapshots
  - Context-owned subscribe and unsubscribe mutation APIs
affects: [board-subscriptions, board-directory, mix-task-subscription-management, tui-board-list]

tech-stack:
  added: []
  patterns:
    - Ecto check constraint plus changeset validation for board policy invariants
    - Context-owned subscription row mutations with active-board guards

key-files:
  created:
    - priv/repo/migrations/20260424130100_add_required_subscription_to_boards.exs
  modified:
    - docs/DATA_MODEL.md
    - lib/foglet_bbs/boards.ex
    - lib/foglet_bbs/boards/board.ex
    - priv/repo/seeds.exs
    - test/foglet_bbs/boards/boards_test.exs

key-decisions:
  - "Required subscriptions are valid only for default-subscription boards, enforced in both Ecto changesets and Postgres."
  - "Subscription management callers use Foglet.Boards APIs rather than direct Repo mutations."

patterns-established:
  - "Board directory snapshots group active boards by category and annotate per-user subscription state."
  - "Unsubscribe allows zero remaining subscriptions; required_subscription is the only board-level blocker."

requirements-completed: [SUBS-01, SUBS-02, SUBS-03]

duration: 18min
completed: 2026-04-24
---

# Phase 13 Plan 1: Board Subscription Domain Foundation Summary

**Required-subscription board policy plus shared Foglet.Boards directory, subscribe, and unsubscribe APIs.**

## Performance

- **Duration:** 18 min
- **Started:** 2026-04-24T17:13:00Z
- **Completed:** 2026-04-24T17:31:05Z
- **Tasks:** 2
- **Files modified:** 6

## Accomplishments

- Added `boards.required_subscription` with a Postgres check constraint named `boards_required_subscription_requires_default_subscription`.
- Added `Board.changeset/2` validation so required boards must also be default subscription boards.
- Added `Foglet.Boards.board_directory_for/1`, `subscribe_user_to_board/2`, and `unsubscribe_user_from_board/2`.
- Added focused domain tests for active directory visibility, idempotent subscribe, allowed unsubscribe-to-zero, archived-board rejection, and required-board unsubscribe blocking.

## Task Commits

1. **Task 13-01-01 RED:** `151cf7c` test(13-01): add failing required subscription policy tests
2. **Task 13-01-01 GREEN:** `0280cf3` feat(13-01): persist required subscription policy
3. **Task 13-01-02 RED:** `12d974b` test(13-01): add failing subscription context tests
4. **Task 13-01-02 GREEN:** `cf193cf` feat(13-01): add board subscription context APIs

## Files Created/Modified

- `docs/DATA_MODEL.md` - Documents the required-subscription board field and check constraint.
- `lib/foglet_bbs/boards.ex` - Adds directory snapshot and subscription mutation APIs.
- `lib/foglet_bbs/boards/board.ex` - Adds `required_subscription` schema field, cast, validation, and check constraint mapping.
- `priv/repo/migrations/20260424130100_add_required_subscription_to_boards.exs` - Adds the column and DB constraint.
- `priv/repo/seeds.exs` - Keeps the seeded General board explicitly non-required.
- `test/foglet_bbs/boards/boards_test.exs` - Covers required policy and subscription context behavior.

## Decisions Made

- Existing seeded boards remain non-required unless a later operator action explicitly sets that policy.
- Missing subscription rows are treated as successful unsubscribe results for allowed active boards, preserving the row-presence model while allowing zero subscriptions.
- Archived boards and boards in archived categories both return `{:error, :board_archived}` for subscription mutations.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

- The fresh worktree initially lacked dependencies; resolved with `rtk mix deps.get`.
- `rtk mix precommit` formatted four unrelated TUI files; those formatter-only side effects were reverted before summary creation and were not committed.

## User Setup Required

None - no external service configuration required.

## Verification

- `rtk mix test test/foglet_bbs/boards/boards_test.exs` - passed, 53 tests.
- `rtk mix precommit` - passed successfully.
- `rg -n "required_subscription" lib/foglet_bbs/boards/board.ex docs/DATA_MODEL.md priv/repo/migrations priv/repo/seeds.exs test/foglet_bbs/boards/boards_test.exs` - confirmed schema, docs, migration, seeds, and tests.
- `rg -n "board_directory_for|subscribe_user_to_board|unsubscribe_user_from_board|required_subscription" lib/foglet_bbs/boards.ex test/foglet_bbs/boards/boards_test.exs` - confirmed APIs and tests.

## Known Stubs

None.

## Threat Flags

None.

## Self-Check: PASSED

- Created summary exists at `.planning/phases/13-board-subscription-management/13-01-SUMMARY.md`.
- Task commits exist on branch `gsd/13-01-board-subscription-management`.
- No `STATE.md` or `ROADMAP.md` changes were made or committed; orchestrator-owned state updates were intentionally skipped.

## Next Phase Readiness

The domain and persistence foundation is ready for later TUI board-directory work and the break-glass Mix task. Later plans can consume the `Foglet.Boards` APIs without duplicating subscription rules.

---
*Phase: 13-board-subscription-management*
*Completed: 2026-04-24*
