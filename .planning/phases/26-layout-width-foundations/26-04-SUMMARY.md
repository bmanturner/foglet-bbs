---
phase: 26-layout-width-foundations
plan: 04
subsystem: ui
tags: [tui, markdown, verification, elixir, raxol]

requires:
  - phase: 26-layout-width-foundations
    provides: [drawable width contracts, compact layout smoke patterns, boards viewport fit]
provides:
  - Paragraph-preserving shared post markdown rendering
  - Markdown tuple contract that preserves consecutive paragraph newline separators
  - Phase 26 human SSH UAT checklist with pending manual scenarios
  - Final Phase 26 automated verification record
affects: [phase-26, phase-33, post-reader, markdown-rendering, tui-width]

tech-stack:
  added: []
  patterns:
    - Preserve Markdown newline tuple runs before widget-level grouping.
    - Render blank paragraph groups as themed empty text nodes, never literal newline content.
    - Record manual SSH visual verification separately from automated render tests.

key-files:
  created:
    - .planning/phases/26-layout-width-foundations/26-HUMAN-UAT.md
    - .planning/phases/26-layout-width-foundations/26-04-SUMMARY.md
  modified:
    - lib/foglet_bbs/markdown.ex
    - lib/foglet_bbs/tui/widgets/post/markdown_body.ex
    - test/foglet_bbs/markdown_test.exs
    - test/foglet_bbs/tui/widgets/post/markdown_body_test.exs
    - test/foglet_bbs/tui/widgets/post/post_card_test.exs
    - test/foglet_bbs/tui/screens/post_reader_test.exs

key-decisions:
  - "Preserve consecutive newline tuples in `Foglet.Markdown.render/1`; MarkdownBody owns clamping paragraph separators to one blank visible row."
  - "Keep list-item rendering to one logical line per item by stripping MDEx list container structural newlines."
  - "Leave Phase 26 human SSH verification pending when real fixed-size terminal checks are not run in the execution session."

patterns-established:
  - "Markdown parsing preserves source paragraph separators; widgets decide display grouping."
  - "Manual UAT artifacts use explicit scenario statuses plus automated verification results."

requirements-completed:
  - POST-01
  - LAYOUT-01
  - LAYOUT-02
  - LAYOUT-03
  - LAYOUT-04
  - LAYOUT-05
  - LAYOUT-06

duration: 6min
completed: 2026-04-26
---

# Phase 26 Plan 04: Markdown Verification Summary

**Paragraph-preserving post markdown rendering plus Phase 26 SSH UAT and automated verification evidence**

## Performance

- **Duration:** 6 min
- **Started:** 2026-04-26T22:23:37Z
- **Completed:** 2026-04-26T22:29:35Z
- **Tasks:** 3
- **Files modified:** 7 implementation/test/UAT files, plus this summary

## Accomplishments

- Fixed shared post markdown paragraph rendering so soft breaks render as adjacent lines, while two-or-more newline separators render exactly one blank visible line.
- Preserved consecutive newline tuples in `Foglet.Markdown.render/1` and kept MarkdownBody responsible for display-level blank-line clamping.
- Added focused coverage for Markdown, MarkdownBody, PostCard, and PostReader so the shared rendering path stays consistent.
- Created `.planning/phases/26-layout-width-foundations/26-HUMAN-UAT.md` with exact 64x22 and 80x24 manual SSH scenarios.
- Recorded final focused verification passes and the known out-of-scope `rtk mix precommit` Dialyzer failure.

## Task Commits

1. **Task 1: Preserve blank paragraph lines in MarkdownBody** - `f1c3859` (fix)
2. **Task 2: Record human SSH verification for Phase 26** - `5446433` (docs)
3. **Task 3: Run final focused and precommit verification** - `2cc617c` (docs)

## Files Created/Modified

- `lib/foglet_bbs/markdown.ex` - Preserves consecutive paragraph newline tuples and strips list-container structural newlines.
- `lib/foglet_bbs/tui/widgets/post/markdown_body.ex` - Counts newline runs and emits one themed blank row for paragraph separators.
- `test/foglet_bbs/markdown_test.exs` - Covers preserved consecutive newline tuples.
- `test/foglet_bbs/tui/widgets/post/markdown_body_test.exs` - Covers soft breaks, paragraph blank rows, clamped longer newline runs, line counts, and no literal newline content.
- `test/foglet_bbs/tui/widgets/post/post_card_test.exs` - Updates body-line and scroll expectations for preserved blank rows.
- `test/foglet_bbs/tui/screens/post_reader_test.exs` - Covers PostReader inheritance of MarkdownBody paragraph grouping.
- `.planning/phases/26-layout-width-foundations/26-HUMAN-UAT.md` - Lists pending manual SSH scenarios and automated verification outcomes.

## Decisions Made

- Preserve newline runs in the Markdown tuple contract rather than trying to infer paragraph separators after they were collapsed.
- Strip list container structural whitespace so bullet lists keep the existing one-line-per-bullet behavior after paragraph newline preservation.
- Keep all manual SSH scenarios pending because the execution session did not run real fixed-size terminal verification.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Preserved newline runs in the Markdown parser**
- **Found during:** Task 1 verification
- **Issue:** `Foglet.Markdown.render/1` deduplicated consecutive newline tuples before MarkdownBody received them, making it impossible for `MarkdownBody.group_by_newline/1` to distinguish soft breaks from paragraph separators.
- **Fix:** Removed newline deduplication, added parser coverage for consecutive newline tuples, and adjusted list-container cleanup so bullet lists stayed one logical line per bullet.
- **Files modified:** `lib/foglet_bbs/markdown.ex`, `test/foglet_bbs/markdown_test.exs`
- **Verification:** `rtk mix test test/foglet_bbs/markdown_test.exs test/foglet_bbs/tui/widgets/post/markdown_body_test.exs test/foglet_bbs/tui/widgets/post/post_card_test.exs test/foglet_bbs/tui/screens/post_reader_test.exs`
- **Committed in:** `f1c3859`

**2. [Rule 1 - Bug] Updated PostCard and PostReader expectations for preserved blank rows**
- **Found during:** Task 1 verification
- **Issue:** Existing PostCard scroll and line-count tests assumed paragraph blank rows were collapsed; one PostReader UAT smoke fixture needed a taller test terminal to include all now-preserved body rows.
- **Fix:** Updated expectations to count/render preserved blank rows and increased the smoke fixture terminal height.
- **Files modified:** `test/foglet_bbs/tui/widgets/post/post_card_test.exs`, `test/foglet_bbs/tui/screens/post_reader_test.exs`
- **Verification:** `rtk mix test test/foglet_bbs/markdown_test.exs test/foglet_bbs/tui/widgets/post/markdown_body_test.exs test/foglet_bbs/tui/widgets/post/post_card_test.exs test/foglet_bbs/tui/screens/post_reader_test.exs`
- **Committed in:** `f1c3859`

---

**Total deviations:** 2 auto-fixed bugs.
**Impact on plan:** Both fixes were required to make the planned MarkdownBody behavior observable through the shared markdown pipeline. No architectural changes.

## Issues Encountered

- `rtk mix precommit` failed in Dialyzer on out-of-scope files also documented by Phase 26 Plans 02 and 03. Compile, formatter, Credo, and Sobelow completed; Dialyzer reported 101 total errors including `lib/foglet_bbs/mix_task_helpers.ex`, login/register/verify state specs, `lib/mix/tasks/foglet.board_subscriptions.ex`, and `lib/mix/tasks/foglet.user.status.ex`.
- Manual SSH verification was not run in this execution session. The UAT artifact leaves each scenario `pending` with exact instructions and records the blocker.
- Unrelated worktree changes in `lib/foglet_bbs/tui/screens/login.ex`, `lib/mix/tasks/foglet.board_subscriptions.ex`, `.claude/worktrees/`, and `REFACTORING.md` were left unstaged.

## Known Stubs

None introduced by this plan.

## Threat Flags

None. This plan changed presentation-only markdown/TUI rendering and documentation artifacts; it introduced no new network endpoints, auth paths, file access patterns, persistence writes, schema changes, or trust-boundary surfaces.

## Verification

- `rtk mix test test/foglet_bbs/markdown_test.exs test/foglet_bbs/tui/widgets/post/markdown_body_test.exs test/foglet_bbs/tui/widgets/post/post_card_test.exs test/foglet_bbs/tui/screens/post_reader_test.exs` - passed, 135 tests.
- `rtk mix test test/foglet_bbs/tui/widgets/post/markdown_body_test.exs test/foglet_bbs/tui/screens/post_reader_test.exs` - passed, 78 tests.
- `rtk rg -n "64x22 Account|64x22 Moderation LOG|64x22 Boards|80x24 Sysop INVITES|Post Reader" .planning/phases/26-layout-width-foundations/26-HUMAN-UAT.md` - passed, matches found.
- `rtk rg -n "^Status:" .planning/phases/26-layout-width-foundations/26-HUMAN-UAT.md` - passed, 9 scenario statuses found.
- `rtk mix test test/foglet_bbs/tui/text_width_test.exs test/foglet_bbs/tui/widgets/display/table_test.exs test/foglet_bbs/tui/widgets/display/console_table_test.exs` - passed, 52 tests.
- `rtk mix test test/foglet_bbs/tui/widgets/input/tabs_test.exs test/foglet_bbs/tui/screens/moderation_test.exs test/foglet_bbs/tui/screens/board_list_test.exs test/foglet_bbs/tui/widgets/post/markdown_body_test.exs test/foglet_bbs/tui/layout_smoke_test.exs` - passed, 182 tests.
- `rtk mix precommit` - failed in out-of-scope Dialyzer warnings after compile, formatter, Credo, and Sobelow; see Issues Encountered.

## User Setup Required

Manual SSH visual verification remains required. See `.planning/phases/26-layout-width-foundations/26-HUMAN-UAT.md` for exact 64x22 and 80x24 scenarios.

## Next Phase Readiness

Phase 26 automated rendering/layout coverage is complete except for the known out-of-scope Dialyzer debt. Human verification still needs to run the pending SSH UAT scenarios before terminal-fit acceptance can be fully signed off.

## Self-Check: PASSED

- Found `.planning/phases/26-layout-width-foundations/26-04-SUMMARY.md`.
- Found `.planning/phases/26-layout-width-foundations/26-HUMAN-UAT.md`.
- Found task commit `f1c3859`.
- Found task commit `5446433`.
- Found task commit `2cc617c`.

---
*Phase: 26-layout-width-foundations*
*Completed: 2026-04-26*
