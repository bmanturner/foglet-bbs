---
phase: 23-composer-facelift
plan: 3
subsystem: ui
tags: [tui, raxol, composer, new-thread, editor-frame]

requires:
  - phase: 23-composer-facelift
    provides: Shared stateless Composer.EditorFrame shell primitive
provides:
  - NewThread compose rendering through the shared Composer.EditorFrame shell
  - Screen tests for NewThread shell labels, board/title context, counters, and markdown preview
  - Source-level preservation checks for TextInput, MultiLineInput, and Threads.create_thread boundaries
affects: [composer-facelift, new-thread, tui-screens]

tech-stack:
  added: []
  patterns:
    - Screen-owned input state and submit behavior with shared render-only composer shell
    - Width-capped board/title context rows via Foglet.TUI.TextWidth.truncate/2

key-files:
  created:
    - .planning/phases/23-composer-facelift/23-03-SUMMARY.md
  modified:
    - lib/foglet_bbs/tui/screens/new_thread.ex
    - test/foglet_bbs/tui/screens/new_thread_test.exs

key-decisions:
  - "NewThread uses EditorFrame only for presentation; title input, body input, key routing, and thread creation remain screen-owned."
  - "NewThread body budget uses the existing max_post_length configuration path so the display counter follows the existing post body limit."

patterns-established:
  - "Composer screen migrations pass pre-rendered title/body/preview children into Composer.EditorFrame."
  - "Source assertions protect load-bearing composer boundaries during facelift refactors."

requirements-completed: [COMPOSER-01, COMPOSER-02, COMPOSER-03, COMPOSER-04, COMPOSER-05]

duration: 13min
completed: 2026-04-25
---

# Phase 23 Plan 3: NewThread Composer Facelift Summary

**New-thread composition now renders inside the shared EditorFrame shell while preserving title/body input and create-thread behavior**

## Performance

- **Duration:** 13min
- **Started:** 2026-04-25T21:53:00Z
- **Completed:** 2026-04-25T22:06:01Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments

- Extended `NewThread` tests to cover the composer shell, visible `Edit`/`Preview` labels, board context, title value, title/body counters, and markdown preview content.
- Migrated `NewThread.render_compose_step/2` to `Foglet.TUI.Widgets.Composer.EditorFrame`.
- Preserved existing `TextInput.render/2`, `TextInput.handle_event/2`, `Compose.translate_key/1`, `MultiLineInput.update/2`, and `Threads.create_thread/3` paths.

## Task Commits

Each task was committed atomically:

1. **Task 1: Extend NewThread compose render tests** - `efe39f4` (test)
2. **Task 2: Render NewThread compose step through EditorFrame** - `2aa48de` (feat)

**Plan metadata:** this docs summary commit

_Note: Task 1 followed the TDD RED gate; `rtk mix test test/foglet_bbs/tui/screens/new_thread_test.exs` failed with 4 expected failures before Task 2 implemented the shared shell._

## Files Created/Modified

- `test/foglet_bbs/tui/screens/new_thread_test.exs` - Added render and source assertions for the NewThread composer shell and preservation contracts.
- `lib/foglet_bbs/tui/screens/new_thread.ex` - Delegates compose rendering to `EditorFrame.render/1`, with board/title context rows, title/body budgets, title input child, and edit/preview body child.
- `.planning/phases/23-composer-facelift/23-03-SUMMARY.md` - Execution summary for this plan.

## Decisions Made

- Kept `EditorFrame` render-only for NewThread. All key handling, validation, and domain mutation behavior remains in `NewThread`.
- Used `max_post_length` for the NewThread body counter because it is the existing post body limit available in runtime configuration.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

- The worktree already had unrelated local changes in `AGENTS.md`, `CLAUDE.md`, and untracked files. They were left untouched and not included in plan commits.
- Verification automation touched `.planning/ROADMAP.md`; that shared artifact change was restored before the summary commit per the worktree instructions.

## Known Stubs

None. The scan found existing input placeholder text and validation empty-string checks only; no new stubbed UI data source was introduced.

## Threat Flags

None. No new network endpoints, auth paths, file access patterns, schema changes, or mutation boundaries were introduced.

## User Setup Required

None - no external service configuration required.

## Verification

- `rtk mix test test/foglet_bbs/tui/screens/new_thread_test.exs` - failed during RED as expected, 49 tests, 4 failures.
- `rtk mix test test/foglet_bbs/tui/screens/new_thread_test.exs test/foglet_bbs/tui/widgets/composer/editor_frame_test.exs` - passed, 54 tests, 0 failures.
- Acceptance grep confirmed `EditorFrame.render`, `TextInput.render`, `TextInput.handle_event`, `Compose.translate_key`, `MultiLineInput.update`, and `threads_mod.create_thread(board.id, user_id, %{title: title, body: body})` remain present.

## Next Phase Readiness

Plan 4 can add layout smoke coverage for the facelifted composers at the canonical terminal sizes. NewThread now uses the same shell boundary as the reply composer path.

## Self-Check: PASSED

- Found `lib/foglet_bbs/tui/screens/new_thread.ex`.
- Found `test/foglet_bbs/tui/screens/new_thread_test.exs`.
- Found `.planning/phases/23-composer-facelift/23-03-SUMMARY.md`.
- Found task commits `efe39f4` and `2aa48de` in git history.
- Confirmed no changes were made to `.planning/STATE.md` or `.planning/ROADMAP.md`.

---
*Phase: 23-composer-facelift*
*Completed: 2026-04-25*
