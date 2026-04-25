---
phase: 20-rich-rows-and-thread-flow
plan: 03
subsystem: testing
tags: [tui, layout-smoke, test-scaffold, thread-list]
requires:
  - phase: 18-chrome-v2
    provides: Chrome V2 frame and standard size-contract dimensions
provides:
  - Row-isolated ThreadList positioned-render smoke contract at 64x22, 80x24, and 132x50
  - RED target for the Wave 2 ThreadList rich-row migration
affects: [thread-list, rich-row, layout-smoke]
tech-stack:
  added: []
  patterns:
    - Positioned Raxol render assertions with row isolation by y-coordinate
key-files:
  created:
    - .planning/phases/20-rich-rows-and-thread-flow/20-03-SUMMARY.md
  modified:
    - test/foglet_bbs/tui/layout_smoke_test.exs
key-decisions:
  - "ThreadList row content assertions isolate positioned text by row y-coordinate before checking glyphs, metadata, truncation, and width."
patterns-established:
  - "Layout smoke tests may use a named ExUnit tag for intentionally RED scaffold blocks while preserving excluded GREEN coverage."
requirements-completed: [RICHROW-01, THREADS-01]
duration: 4min
completed: 2026-04-25
---

# Phase 20 Plan 03: ThreadList Layout Smoke Scaffold Summary

**Row-isolated ThreadList size-contract tests now encode the rich-row glyph, metadata, truncation, and width budget target before the production migration.**

## Performance

- **Duration:** 4 min
- **Started:** 2026-04-25T20:53:05Z
- **Completed:** 2026-04-25T20:57:23Z
- **Tasks:** 1
- **Files modified:** 2

## Accomplishments

- Added `ThreadList` to the existing layout smoke screen alias block.
- Added `describe "thread_list — size contract"` covering `{64,22}`, `{80,24}`, and `{132,50}`.
- Added three inline `%Foglet.Threads.ThreadEntry{}` fixtures for sticky+unread, locked, and plain rows.
- Added row-isolation helpers that anchor on fixture title text, collect all positioned elements at that y-coordinate, and assert per-row content instead of using whole-screen text.

## Task Commits

1. **Task 1: Add thread_list — size contract describe block with row-isolation helper** - `3ca4edc` (test)

## Files Created/Modified

- `test/foglet_bbs/tui/layout_smoke_test.exs` - Added approximately 173 lines for the ThreadList layout smoke RED scaffold.
- `.planning/phases/20-rich-rows-and-thread-flow/20-03-SUMMARY.md` - Plan execution summary.

## Verification

- `rtk mix compile --warnings-as-errors` - passed.
- `rtk mix test test/foglet_bbs/tui/layout_smoke_test.exs --only "thread_list — size contract"` - RED as expected: 3 tests, 3 failures.
- `rtk mix test test/foglet_bbs/tui/layout_smoke_test.exs --exclude "thread_list — size contract"` - passed: 23 tests, 0 failures, 3 excluded.
- Static acceptance checks passed for the describe block, `ThreadList` alias, three `ThreadEntry` fixtures, standard size triple, `ThreadList.render(state)`, row-isolation helpers, single locked-glyph literal, and `[S]` per-row refute.

## RED Failure Modes

- `64x22`: sticky row renders `> [S] Sticky ... @alice · 5 posts · 0s ago`, so the unread glyph assertion for `◆` fails.
- `80x24`: sticky row renders `> [S] Sticky ... @alice · 5 posts · 0s ago`, so the unread glyph assertion for `◆` fails.
- `132x50`: sticky row renders `> [S] Sticky ... @alice · 5 posts · 0s ago`, so the unread glyph assertion for `◆` fails.

The dominant failure mode is the expected pre-migration ThreadList renderer still using `ListRow.render_with_metadata/6` with the legacy `> ` marker and `[S] ` sticky prefix instead of the Phase 20 rich-row glyph cluster.

## Decisions Made

None beyond the plan: row assertions intentionally operate on isolated y-coordinate rows, while the whole-screen positioned element width check remains a separate sanity check.

## Deviations from Plan

None - plan executed as written.

## Issues Encountered

- The generated ExUnit size loop needed static module attributes for `width` and `height` instead of `unquote/1` in non-quoted positions. This was corrected before verification and did not change the planned test behavior.

## Known Stubs

None.

## Threat Flags

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

Wave 2 can use this tagged layout smoke block as a GREEN target once `ThreadList` migrates to the rich-row glyph cluster and removes the `[S] ` prefix.

## Self-Check: PASSED

- Found `test/foglet_bbs/tui/layout_smoke_test.exs`.
- Found `.planning/phases/20-rich-rows-and-thread-flow/20-03-SUMMARY.md`.
- Found task commit `3ca4edc` in git log.

Self-check will be updated after the task and summary commits are created.

---
*Phase: 20-rich-rows-and-thread-flow*
*Completed: 2026-04-25*
