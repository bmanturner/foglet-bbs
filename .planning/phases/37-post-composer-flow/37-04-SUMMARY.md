---
phase: 37-post-composer-flow
plan: "04"
subsystem: ui
tags: [tui, raxol, new-thread, thread-list, screen-contract, task-effects]

requires:
  - phase: 37-post-composer-flow
    provides: [PostComposer reducer ownership and generic App task-result routing]
  - phase: 36-board-thread-directory-flow
    provides: [ThreadList reducer ownership and route-entry load effects]
provides:
  - NewThread local board picker, compose draft, validation, load, and submit lifecycle state
  - NewThread init/update/render screen contract over Foglet.TUI.Context
  - Async new-thread creation through Effect.task/3 and ThreadList route handoff
  - ThreadList select_thread_id route intent consumed after load
affects: [phase-37-post-composer-flow, phase-39-app-shell-cleanup, tui-new-thread, tui-thread-list]

tech-stack:
  added: []
  patterns: [screen-owned new-thread reducer, submit task effect, route selection intent]

key-files:
  created:
    - .planning/phases/37-post-composer-flow/37-04-SUMMARY.md
  modified:
    - lib/foglet_bbs/tui/screens/new_thread.ex
    - lib/foglet_bbs/tui/screens/new_thread/state.ex
    - lib/foglet_bbs/tui/screens/thread_list.ex
    - lib/foglet_bbs/tui/screens/thread_list/state.ex
    - test/foglet_bbs/tui/screens/new_thread_test.exs
    - test/foglet_bbs/tui/screens/thread_list_test.exs
    - test/foglet_bbs/tui/app_test.exs

key-decisions:
  - "NewThread.State owns route origin, routed board identity, board-load status, submit status, and submit result data."
  - "NewThread requests board loads and create-thread writes through Effect.task/3 while Foglet.Boards and Foglet.Threads remain authoritative for durable behavior."
  - "Successful new-thread creation navigates to ThreadList with board route params and select_thread_id; ThreadList applies and clears that intent after its own reload."

patterns-established:
  - "NewThread reducer tests assert local state, effect payloads, task closures, route params, and App generic routing instead of App current_board mutation."
  - "ThreadList one-shot route selection intents are stored in local state and cleared after load so future reloads preserve normal selection."

requirements-completed: [SCREEN-04]

duration: 11min
completed: 2026-04-29
---

# Phase 37 Plan 04: New Thread Screen Contract Summary

**NewThread now owns board loading, draft composition, async thread creation, and ThreadList selection handoff through the screen reducer contract.**

## Performance

- **Duration:** 11 min
- **Started:** 2026-04-29T00:31:41Z
- **Completed:** 2026-04-29T00:42:21Z
- **Tasks:** 4
- **Files modified:** 7 implementation/test files plus this summary/tracking metadata

## Accomplishments

- Expanded `NewThread.State` with board-load and submit lifecycle fields plus `from_context/1`.
- Added `NewThread.init/1`, `update/3`, and `render/2` over local state plus `%Foglet.TUI.Context{}`.
- Moved subscribed-board loading and create-thread submission to `Effect.task/3` with local task-result handling.
- Routed successful thread creation to ThreadList with board params and `select_thread_id`.
- Added ThreadList one-shot selection intent support after load, with reducer and App coverage.

## Task Commits

Each task was committed atomically:

1. **Task 1: Expand NewThread.State and add from_context/1** - `df34c2f` (feat)
2. **Task 2: Add NewThread init/update/render and async board loading** - `c662e20` (feat)
3. **Task 3: Move create-thread submit to task result flow** - `5e2181a` (feat)
4. **Task 4: Add ThreadList selection intent for new-thread success** - `1b5047b` (feat)

**Plan metadata:** this summary commit

## Files Created/Modified

- `lib/foglet_bbs/tui/screens/new_thread/state.ex` - Adds route-derived state, load status, submit status, and submit result ownership.
- `lib/foglet_bbs/tui/screens/new_thread.ex` - Adds the new screen contract, board-load task effects, reducer key handling, create-thread task effects, result handling, and local render entry.
- `lib/foglet_bbs/tui/screens/thread_list/state.ex` - Adds `select_thread_id` route intent storage.
- `lib/foglet_bbs/tui/screens/thread_list.ex` - Applies and clears selection intent after sorted thread loads.
- `test/foglet_bbs/tui/screens/new_thread_test.exs` - Covers NewThread route initialization, load effects/results, local editing, validation, create-thread tasks/results, and render smoke.
- `test/foglet_bbs/tui/screens/thread_list_test.exs` - Covers ThreadList selection intent extraction and post-load selection.
- `test/foglet_bbs/tui/app_test.exs` - Proves NewThread create-thread task results route through local screen state without direct App `current_board` mutation.

## Decisions Made

- Kept legacy `render/1` and `handle_key/2` compatibility while adding the new NewThread reducer contract, matching the Phase 37 migration pattern.
- Kept durable authorization and message-number allocation inside `Foglet.Threads.create_thread/3`; NewThread only builds explicit title/body attrs and requests work through a task effect.
- Used `select_thread_id` as a one-shot ThreadList route parameter instead of pre-writing ThreadList selection from NewThread or App.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

- Existing unrelated dirty files were present throughout execution and were left unstaged: `AGENTS.md`, `LOGIN.md`, and `.claude/worktrees/`.
- Focused App tests emit existing ShellVisibility sandbox warning logs from unrelated sysop/account render paths, but the suite passes.
- `rtk mix compile --warnings-as-errors` prints dependency warnings from `raxol`, but exits 0 and the `foglet_bbs` compile succeeds.

## Known Stubs

None. Stub scan found only existing editor placeholders, empty-state checks, and test assertions; no goal-blocking placeholder data or unwired UI stubs were introduced.

## Threat Flags

None. The declared trust boundaries stay within board-load reads through `Foglet.Boards`, create-thread writes through `Foglet.Threads.create_thread/3`, and explicit route params between NewThread and ThreadList.

## Verification

- `rtk mix test test/foglet_bbs/tui/screens/new_thread_test.exs` - passed, 57 tests after Task 1; 66 tests after Task 2
- `rtk mix test test/foglet_bbs/tui/screens/new_thread_test.exs test/foglet_bbs/tui/app_test.exs` - passed, 206 tests after Task 3
- `rtk mix test test/foglet_bbs/tui/screens/thread_list_test.exs` - passed, 22 tests after Task 4
- `rtk mix test test/foglet_bbs/tui/screens/new_thread_test.exs test/foglet_bbs/tui/screens/thread_list_test.exs test/foglet_bbs/tui/app_test.exs` - passed, 228 tests
- `rtk mix compile --warnings-as-errors` - passed

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

Plan 37-05 can finish post/composer flow cleanup with PostReader, PostComposer, NewThread, and ThreadList now using screen-owned reducer/task-result handoffs for their Phase 37 local flows. Phase 39 should remove the remaining explicit legacy NewThread compatibility callbacks after all screens are migrated.

## Self-Check: PASSED

- Summary file exists at `.planning/phases/37-post-composer-flow/37-04-SUMMARY.md`.
- Task commits `df34c2f`, `c662e20`, `5e2181a`, and `1b5047b` are visible in git history.
- Focused tests and warnings-as-errors compile passed.
- No unrelated `AGENTS.md`, `LOGIN.md`, or `.claude/worktrees/` files were staged.

---
*Phase: 37-post-composer-flow*
*Completed: 2026-04-29*
