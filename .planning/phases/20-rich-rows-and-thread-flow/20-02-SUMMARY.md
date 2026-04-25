---
phase: 20-rich-rows-and-thread-flow
plan: 02
subsystem: testing
tags: [tui, screen, test-scaffold, thread-list]

requires:
  - phase: 20-rich-rows-and-thread-flow
    provides: Phase 20 RichRow and ThreadList visual contract planning
provides:
  - ThreadList THREADS-01 RED screen-test scaffold
  - FakeLockedThreads test adapter for locked row coverage
  - Row-isolated leading-cluster width assertion
affects: [thread-list, rich-row, THREADS-01]

tech-stack:
  added: []
  patterns:
    - Existing ThreadList fake domain adapters defined outside the test module
    - Describe-tagged RED scaffold for targeted ExUnit selection
    - TextWidth display-width assertions over row-isolated substrings

key-files:
  created:
    - .planning/phases/20-rich-rows-and-thread-flow/20-02-SUMMARY.md
  modified:
    - test/foglet_bbs/tui/screens/thread_list_test.exs

key-decisions:
  - "Anchored the plain-row cluster-width fixture on the existing FakeThreads title `Older non-sticky`."
  - "Added a describe tag matching the plan's exact ExUnit filter so the THREADS-01 block can be selected directly."

patterns-established:
  - "Screen-level Phase 20 RED tests isolate row leading clusters by title before comparing TextWidth display widths."

requirements-completed: [THREADS-01]

duration: 5 min
completed: 2026-04-25
---

# Phase 20 Plan 02: ThreadList Screen Glyph Scaffold Summary

**ThreadList THREADS-01 RED tests now pin unread, sticky, locked, legacy-prefix, metadata, and cluster-width behavior before production migration.**

## Performance

- **Duration:** 5 min
- **Started:** 2026-04-25T20:52:31Z
- **Completed:** 2026-04-25T20:57:07Z
- **Tasks:** 1
- **Files modified:** 2

## Accomplishments

- Added `Foglet.TUI.Screens.ThreadListTest.FakeLockedThreads` at approximately lines 104-123.
- Added `"render/1 — thread row state glyphs (THREADS-01)"` at approximately lines 324-421.
- Added six screen-level assertions covering unread `◆`, sticky `●`, locked `⚿`, `[S] ` absence, metadata preservation, and row-isolated leading-cluster width.
- Preserved the existing LIST-03 metadata tests unchanged.

## Task Commits

1. **Task 1: Add FakeLockedThreads adapter and THREADS-01 assertions** - `7b42325` (test)

**Plan metadata:** pending in docs commit

## Files Created/Modified

- `test/foglet_bbs/tui/screens/thread_list_test.exs` - Adds `FakeLockedThreads` and the THREADS-01 RED describe block.
- `.planning/phases/20-rich-rows-and-thread-flow/20-02-SUMMARY.md` - Documents execution, verification, and RED failure modes.

## RED Test Matrix

The targeted command `rtk mix test test/foglet_bbs/tui/screens/thread_list_test.exs --only "render/1 — thread row state glyphs"` exits non-zero with 6 tests, 5 failures:

- **Unread glyph**: RED. Expected `◆`; current `ThreadList` renders `Unread thread` without the glyph.
- **Sticky glyph**: RED. Expected `●`; current `ThreadList` still renders `[S] Old but sticky`.
- **Locked glyph**: RED. Expected `⚿`; current `ThreadList` renders `Locked thread` without a locked glyph.
- **`[S] ` absence**: RED. Current sticky row still contains the legacy `[S] ` prefix.
- **Metadata preservation**: GREEN. Existing `@alice`, `20 posts`, `1 post`, and `·` separators remain present.
- **Cluster-width invariant**: RED through the embedded `[S] ` absence guard; the row-isolated `TextWidth.display_width/1` comparison is in place and will become the alignment target after RichRow migration.

The full file command `rtk mix test test/foglet_bbs/tui/screens/thread_list_test.exs` exits non-zero with 24 tests, 5 failures, all in the new THREADS-01 block.

## Verification

- `rtk mix test test/foglet_bbs/tui/screens/thread_list_test.exs --only "render/1 — thread row state glyphs"`: RED as expected, 6 tests, 5 failures.
- `rtk mix test test/foglet_bbs/tui/screens/thread_list_test.exs --exclude "render/1 — thread row state glyphs"`: PASS, 18 tests, 0 failures.
- `rtk mix test test/foglet_bbs/tui/screens/thread_list_test.exs`: RED as expected, 24 tests, 5 failures.
- `rtk mix compile --warnings-as-errors`: PASS.
- Static acceptance greps: PASS for fake module count, alias count, describe count, glyph literals, `[S] ` refutes, locked fixture, `leading_cluster_for/2`, and `TextWidth.display_width(plain_cluster)`.

## Decisions Made

- Used the actual non-sticky fixture title `Older non-sticky` for the plain-row anchor instead of the plan example `Latest reply`.
- Added `@describetag :"render/1 — thread row state glyphs"` so the plan's exact `--only` and `--exclude` commands operate on the intended block.
- Kept production `ThreadList` untouched; this plan remains a RED test scaffold only.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Removed conflicting `flatten_text/1` import**
- **Found during:** Task 1 verification
- **Issue:** Importing `Foglet.TUI.WidgetHelpers.flatten_text/1` conflicted with the existing private `flatten_text/1` helper already defined in the test module.
- **Fix:** Removed the import and reused the existing helper, as allowed by the plan.
- **Files modified:** `test/foglet_bbs/tui/screens/thread_list_test.exs`
- **Verification:** Targeted THREADS-01 tests compile and run RED; existing tests excluding the block pass.
- **Committed in:** `7b42325`

**2. [Rule 3 - Blocking] Added an ExUnit describe tag for the required filter command**
- **Found during:** Task 1 verification
- **Issue:** The exact `--only "render/1 — thread row state glyphs"` command selected zero tests until a matching tag existed.
- **Fix:** Added `@describetag :"render/1 — thread row state glyphs"` inside the new describe block.
- **Files modified:** `test/foglet_bbs/tui/screens/thread_list_test.exs`
- **Verification:** The exact `--only` command now selects the six new tests and fails for the intended RED reasons.
- **Committed in:** `7b42325`

---

**Total deviations:** 2 auto-fixed (2 blocking).
**Impact on plan:** Both fixes keep the scaffold executable and targeted without widening scope or migrating production ThreadList.

## Issues Encountered

None beyond the auto-fixed scaffold issues above.

## User Setup Required

None - no external service configuration required.

## Known Stubs

None.

## Next Phase Readiness

Ready for Wave 2 ThreadList migration: this block is the GREEN target after `ThreadList` switches from the legacy `[S] ` prefix to RichRow state glyphs.

## Self-Check: PASSED

- Summary file exists: `.planning/phases/20-rich-rows-and-thread-flow/20-02-SUMMARY.md`
- Task commit exists: `7b42325`
- No tracked file deletions were introduced by the task commit.

---
*Phase: 20-rich-rows-and-thread-flow*
*Completed: 2026-04-25*
