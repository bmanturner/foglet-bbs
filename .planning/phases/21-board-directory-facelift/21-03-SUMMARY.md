---
phase: 21-board-directory-facelift
plan: 03
subsystem: tui
tags: [tui, widget, board-tree, rich-row, raxol]

requires:
  - phase: 20-rich-rows-and-thread-flow
    provides: RichRow fixed cluster cells and metadata layout
  - phase: 21-board-directory-facelift
    provides: Plan 21-02 BoardTree widget test contract
provides:
  - Foglet.TUI.Widgets.List.BoardTree stateful facade
  - Category rows with expanded/collapsed glyphs and truncation
  - Board rows rendered through RichRow cluster cells and age metadata
affects: [board-list, tui-widgets, phase-21-plan-04]

tech-stack:
  added: []
  patterns: [stateful-widget-facade, rich-row-cluster-cells, focused-entry-api]

key-files:
  created:
    - lib/foglet_bbs/tui/widgets/list/board_tree.ex
  modified: []

key-decisions:
  - "BoardTree owns Display.Tree state and exposes focused_board_entry/1 instead of leaking tree internals."
  - "Subscription glyphs ride in RichRow state_cluster cells, with :locked used for required boards."
  - "Nil last_post_at renders as an em dash before calling Foglet.TimeAgo.format/1."

patterns-established:
  - "Board directory rows use RichRow only for board nodes; category nodes stay inline themed text."
  - "Flattened widget tests rely on explicit row separators from BoardTree while preserving RichRow row layout."

requirements-completed: [BOARDS-01, BOARDS-02]

duration: 8min
completed: 2026-04-25
---

# Phase 21 Plan 03: BoardTree Widget Summary

**BoardTree stateful facade with category glyphs, RichRow board rows, cluster-cell subscription glyphs, and nil-safe age metadata**

## Performance

- **Duration:** 8 min
- **Started:** 2026-04-25T22:08:00Z
- **Completed:** 2026-04-25T22:16:17Z
- **Tasks:** 1
- **Files modified:** 1 implementation file plus this summary

## Accomplishments

- Added `Foglet.TUI.Widgets.List.BoardTree` with `init/1`, `handle_event/2`, `render/2`, and public `focused_board_entry/1`.
- Wrapped `Foglet.TUI.Widgets.Display.Tree` for cursor/expanded state while rendering categories inline and board rows through `RichRow.render/1`.
- Encoded read state plus subscription state in `:state_cluster`: `:unread`, `:locked`, `%{key: :subscribed_board, glyph: "✓", slot: :info}`, and `%{key: :available_board, glyph: "+", slot: :dim}`.
- Implemented metadata as `"N unread  AGE"`, `"all read  AGE"`, or age-only, with `—` for nil `last_post_at`.

## Task Commits

1. **Task 1: Implement BoardTree widget** - `e273691` (feat)

## Files Created/Modified

- `lib/foglet_bbs/tui/widgets/list/board_tree.ex` - New stateful BoardTree widget facade and render helpers.
- `.planning/phases/21-board-directory-facelift/21-03-SUMMARY.md` - Execution summary.

## Decisions Made

- Followed the plan's revised D-02 encoding: subscription glyphs are cluster cells, not title prefixes.
- Added explicit row separators in BoardTree output so flattened widget assertions distinguish category and board rows; the RichRow row contract remains unchanged.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Preserved row boundaries in flattened render output**
- **Found during:** Task 1
- **Issue:** Initial render output placed category and board text adjacent in `flatten_text/1`, causing category-only and width assertions to read multiple visual rows as one line.
- **Fix:** Added `separate_rows/2` to intersperse themed newline text nodes between visible rows.
- **Files modified:** `lib/foglet_bbs/tui/widgets/list/board_tree.ex`
- **Verification:** `rtk mix test test/foglet_bbs/tui/widgets/list/board_tree_test.exs` passes with 29 tests.
- **Committed in:** `e273691`

---

**Total deviations:** 1 auto-fixed (1 bug)
**Impact on plan:** The fix preserves the intended widget contract and does not broaden scope.

## Issues Encountered

- `rtk mix format` initially failed because dependencies were not present in this worktree; `rtk mix deps.get` resolved the formatter import dependency.
- One post-edit test run failed under sandboxing because Mix could not open its local PubSub TCP socket (`:eperm`). The same targeted test was rerun with escalation and passed.
- `rtk mix compile --warnings-as-errors` exited 0, but dependency compilation emitted warnings from vendored/external packages (`toml`, `timex`, `uuid`, `raxol`). No warnings were emitted from `BoardTree`.

## Verification

- `rtk mix test test/foglet_bbs/tui/widgets/list/board_tree_test.exs` - PASS, 29 tests, 0 failures.
- `rtk mix compile --warnings-as-errors` - PASS, exit 0.
- `rtk mix format --check-formatted` - PASS.
- `rtk mix credo lib/foglet_bbs/tui/widgets/list/board_tree.ex` - PASS, no issues.
- `rtk rg "RichRow\\.render" lib/foglet_bbs/tui/widgets/list/board_tree.ex | wc -l` - PASS, exactly 1 dispatch site.
- `! rtk rg -n "@glyph_required|indent <> sub_glyph|compose_title\\(depth, sub_glyph, name\\)|fg: :(red|green|blue|yellow|cyan|magenta|white|black)|◇" lib/foglet_bbs/tui/widgets/list/board_tree.ex` - PASS.

## Known Stubs

None.

## Threat Flags

None. The new widget is pure render/state traversal over already-loaded directory maps and introduces no new network, persistence, auth, file, or schema boundary.

## Self-Check: PASSED

- Found `lib/foglet_bbs/tui/widgets/list/board_tree.ex`.
- Found implementation commit `e273691`.
- Found no file deletions in the implementation commit.

## User Setup Required

None.

## Next Phase Readiness

Plan 21-04 can migrate `BoardList` to consume `BoardTree.render/2`, `BoardTree.handle_event/2`, and `BoardTree.focused_board_entry/1`.

---
*Phase: 21-board-directory-facelift*
*Completed: 2026-04-25*
