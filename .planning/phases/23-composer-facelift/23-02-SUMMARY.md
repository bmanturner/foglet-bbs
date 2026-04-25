---
phase: 23-composer-facelift
plan: 2
subsystem: ui
tags: [tui, raxol, composer, post-composer, markdown-preview]

requires:
  - phase: 23-composer-facelift
    provides: Shared stateless Composer.EditorFrame shell primitive
provides:
  - PostComposer render migration to the shared EditorFrame shell
  - Reply composer tests for shell labels, quote context, counters, preview, and behavior preservation
affects: [composer-facelift, post-composer, tui-screens]

tech-stack:
  added: []
  patterns:
    - Screen-owned input and submit behavior with shared stateless composer presentation
    - Compact width-aware reply quote context using Foglet.TUI.TextWidth

key-files:
  created:
    - .planning/phases/23-composer-facelift/23-02-SUMMARY.md
  modified:
    - lib/foglet_bbs/tui/screens/post_composer.ex
    - test/foglet_bbs/tui/screens/post_composer_test.exs

key-decisions:
  - "PostComposer now delegates presentation to Composer.EditorFrame while preserving existing key handling, max-length enforcement, and reply submission path."
  - "Preview mode remains an in-shell markdown preview; tests use the injectable markdown module and production fallback keeps MarkdownBody.render/3."

patterns-established:
  - "Reply composer context is capped to two quoted lines and truncated by display width before entering the editor shell."
  - "PostComposer render tests assert shell structure and source-level guardrails without replacing behavior tests."

requirements-completed: [COMPOSER-01, COMPOSER-02, COMPOSER-03, COMPOSER-04, COMPOSER-05]

duration: 12min
completed: 2026-04-25
---

# Phase 23 Plan 2: Post Composer Editor Frame Summary

**Reply composition now renders through the shared Composer.EditorFrame shell with visible Edit/Preview labels, compact quote context, markdown preview, and body budget counter**

## Performance

- **Duration:** 12min
- **Started:** 2026-04-25T21:54:18Z
- **Completed:** 2026-04-25T22:05:49Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments

- Extended `PostComposer` tests to cover the shared composer shell, visible mode labels, `0 / 1000 chars` body counter, compact quote context, fake markdown preview output, and source guardrails.
- Migrated `PostComposer.render/1` to `Foglet.TUI.Widgets.Composer.EditorFrame` while keeping `ScreenFrame.render/4`, key hints, input forwarding, max-length enforcement, cancel, and reply submission behavior unchanged.
- Added compact reply context rendering that shows `Replying to @handle` and at most two width-truncated quote lines before the editor body.

## Task Commits

Each task was committed atomically:

1. **Task 1: Extend PostComposer render tests** - `308b652` (test)
2. **Task 2: Render PostComposer through EditorFrame** - `2616376` (feat)

**Plan metadata:** this docs summary commit

_Note: Task 1 followed the TDD RED gate. The focused test run failed only on the new shell/source assertions before implementation._

## Files Created/Modified

- `lib/foglet_bbs/tui/screens/post_composer.ex` - Delegates reply composer presentation to `EditorFrame`, builds compact quote context, routes edit mode through `Compose.render_input/3`, and keeps preview in the markdown body path.
- `test/foglet_bbs/tui/screens/post_composer_test.exs` - Adds render contract tests for shell labels, counter, quote gutter, markdown preview, and source-level preservation checks.
- `.planning/phases/23-composer-facelift/23-02-SUMMARY.md` - Execution summary for the worktree plan.

## Decisions Made

- Used `MarkdownBody.render_tuples/3` for injected markdown test modules and kept `MarkdownBody.render(draft, width, theme)` for the production/default markdown path.
- Kept `PostCard.get_handle/1` for strict handle extraction only; preview rendering does not use `PostCard.render`.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

- Empty focused `MultiLineInput` renders a cursor rather than placeholder text, so the edit-mode tests assert the required empty counter separately from a non-empty body text render.
- Unrelated worktree changes and a separate `23-03` commit appeared during execution. They were not staged for this plan, and shared artifacts remain excluded from this plan summary commit.

## Known Stubs

None.

## Threat Flags

None.

## User Setup Required

None - no external service configuration required.

## Verification

- `rtk mix test test/foglet_bbs/tui/screens/post_composer_test.exs` - RED gate failed as expected before implementation with 3 new assertion failures.
- `rtk mix test test/foglet_bbs/tui/screens/post_composer_test.exs test/foglet_bbs/tui/widgets/composer/editor_frame_test.exs` - passed, 41 tests, 0 failures.

## TDD Gate Compliance

- RED commit present: `308b652` (`test(23-02): add failing post composer shell tests`).
- GREEN commit present after RED: `2616376` (`feat(23-02): render post composer in editor frame`).

## Next Phase Readiness

Plan 3 can continue the composer facelift on `NewThread` using the same `EditorFrame` shell pattern while preserving title/body focus rules and submit behavior.

## Self-Check: PASSED

- Found `lib/foglet_bbs/tui/screens/post_composer.ex`.
- Found `test/foglet_bbs/tui/screens/post_composer_test.exs`.
- Found `.planning/phases/23-composer-facelift/23-02-SUMMARY.md`.
- Found task commits `308b652` and `2616376` in git history.
- Confirmed no tracked file deletions in the task commits.

---
*Phase: 23-composer-facelift*
*Completed: 2026-04-25*
