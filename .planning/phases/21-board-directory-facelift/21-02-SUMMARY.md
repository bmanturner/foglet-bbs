---
phase: 21-board-directory-facelift
plan: 02
subsystem: testing
tags: [tui, widget, board-tree, red, contract-tests]

requires:
  - phase: 20-rich-rows-and-thread-flow
    provides: RichRow state cluster, focus marker, theme-slot routing, and width behavior
provides:
  - BoardTree RED contract tests for Plan 21-03 implementation
  - Cluster-cell encoding checks for read and subscription glyphs
  - focused_board_entry/1 public API expectations
affects: [phase-21-board-directory-facelift, board-directory, tui-widgets]

tech-stack:
  added: []
  patterns:
    - ExUnit widget RED scaffold beside sibling list widget tests
    - Runtime timestamp fixtures with regex age assertions

key-files:
  created:
    - test/foglet_bbs/tui/widgets/list/board_tree_test.exs
    - .planning/phases/21-board-directory-facelift/21-02-SUMMARY.md
  modified: []

key-decisions:
  - "BoardTree subscription state is locked as RichRow cluster cells, not title prefixes."
  - "Read boards are locked to whitespace read-state slots; the ◇ glyph is explicitly forbidden."
  - "Age assertions use regex magnitudes and nil last_post_at expects an em-dash."

patterns-established:
  - "BoardTree focused-row access goes through focused_board_entry/1 rather than exposing Display.Tree internals."
  - "Per-glyph subscription styling is verified via text_runs/1 against theme.warning/info/dim slots."

requirements-completed: [BOARDS-01, BOARDS-02]

duration: 32min
completed: 2026-04-25
---

# Phase 21 Plan 02: BoardTree RED Contract Summary

**BoardTree widget contract tests for cluster-cell glyphs, focused entry access, compact metadata, and width-safe rendering**

## Performance

- **Duration:** 32 min
- **Started:** 2026-04-25T21:33:00Z
- **Completed:** 2026-04-25T22:05:16Z
- **Tasks:** 1
- **Files modified:** 2

## Accomplishments

- Added `test/foglet_bbs/tui/widgets/list/board_tree_test.exs` with 29 RED tests covering `init/1`, `handle_event/2`, `render/2`, and `focused_board_entry/1`.
- Locked the revised row contract: category `▾`/`▸`, unread `◆`, no `◇`, subscription glyphs `⚿`/`✓`/`+` in RichRow cluster cells, and no title-prefix subscription glyphs.
- Added theme-routing checks for `⚿ -> theme.warning.fg`, `✓ -> theme.info.fg`, and `+ -> theme.dim.fg`.
- Added width and metadata checks for unread count, `all read`, age regex magnitudes, nil age as `—`, and long-name truncation.

## Task Commits

1. **Task 1: Create BoardTree RED contract matrix** - `c4ff6a7` (test)

## Files Created/Modified

- `test/foglet_bbs/tui/widgets/list/board_tree_test.exs` - RED contract tests for the not-yet-implemented `Foglet.TUI.Widgets.List.BoardTree`.
- `.planning/phases/21-board-directory-facelift/21-02-SUMMARY.md` - Execution summary and RED evidence.

## Verification

- `rtk mix test test/foglet_bbs/tui/widgets/list/board_tree_test.exs` - expected RED: `29 tests, 29 failures`.
- RED reason: `Foglet.TUI.Widgets.List.BoardTree` is not available; source-audit test also fails because `lib/foglet_bbs/tui/widgets/list/board_tree.ex` does not exist yet.
- `rtk mix format --check-formatted test/foglet_bbs/tui/widgets/list/board_tree_test.exs` - passed.
- Exact age literal audit passed: no `"10m"`, `"2h"`, or `"3d"` literals remain in the test file.
- Full `rtk mix format --check-formatted` was attempted but failed on unrelated pre-existing formatting in `test/foglet_bbs/tui/widgets/composer/editor_frame_test.exs`; this plan did not modify that file.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

- Initial formatter run could not load `:ecto_sql` because dependencies were absent in the isolated worktree. Ran `rtk mix deps.get`; no tracked files changed.
- Full repo format check is blocked by an unrelated file outside the allowed edit scope. The new BoardTree test file is format-clean.

## Known Stubs

None in files created by this plan. The RED tests intentionally reference the absent `BoardTree` module that Plan 21-03 owns.

## Threat Flags

None. This plan added only pure ExUnit fixtures and assertions; no production trust boundary changed.

## Next Phase Readiness

Plan 21-03 has a clear GREEN target: implement `Foglet.TUI.Widgets.List.BoardTree` so these 29 tests pass while preserving RichRow cluster-cell theme routing, whitespace read slots, and the focused-board API.

## Self-Check: PASSED

- Created test file exists.
- Test scaffold commit exists: `c4ff6a7`.
- Summary file exists.

---
*Phase: 21-board-directory-facelift*
*Completed: 2026-04-25*
