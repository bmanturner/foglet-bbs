---
phase: 18-chrome-v2
plan: 07
subsystem: tui
tags: [chrome-v2, sysop, keybar, command-bar, operator-mode]

requires:
  - phase: 18-03
    provides: ScreenFrame Chrome V2 composition and CommandBar integration
provides:
  - Sysop caller with explicit Chrome V2 breadcrumb and grouped command data
  - Static proof that KeyBar is compatibility-only and production chrome uses CommandBar
  - CHROME-05 closure coverage for the legacy footer path
affects: [chrome-v2, sysop-screen, command-bar, keybar-compatibility]

tech-stack:
  added: []
  patterns:
    - Screens can pass explicit breadcrumb parts when fallback state inference is too coarse
    - Static tests guard legacy adapters from becoming production render paths again

key-files:
  created:
    - .planning/phases/18-chrome-v2/18-07-SUMMARY.md
  modified:
    - lib/foglet_bbs/tui/screens/sysop.ex
    - test/foglet_bbs/tui/screens/sysop_test.exs
    - test/foglet_bbs/tui/widgets/chrome/normalizer_test.exs

key-decisions:
  - "Sysop now supplies explicit breadcrumb parts from its real tab labels instead of relying on the generic fallback tab list."
  - "Sysop command hints are grouped data at the caller, while KeyBar remains only a delegation adapter."

patterns-established:
  - "Operator screens with existing tab state can build Chrome V2 breadcrumb data from their screen state without changing handlers."
  - "Chrome compatibility guarantees are enforced with source-level tests under the chrome widget test suite."

requirements-completed: [CHROME-01, CHROME-02, CHROME-03, CHROME-04, CHROME-05]

duration: 5min
completed: 2026-04-25
---

# Phase 18 Plan 07: Sysop Chrome and KeyBar Compatibility Summary

**Sysop now renders explicit operator Chrome V2 data, and tests prove the old KeyBar footer is compatibility-only.**

## Performance

- **Duration:** 5 min
- **Started:** 2026-04-25T17:36:34Z
- **Completed:** 2026-04-25T17:41:00Z
- **Tasks:** 2
- **Files modified:** 4

## Accomplishments

- Added a Sysop render contract proving `Presentation.mode_for!(:sysop) == :operator` and that active Sysop tab breadcrumbs are rooted at `Foglet`.
- Updated Sysop to pass explicit Chrome V2 breadcrumb parts and grouped command data to `ScreenFrame.render/4`.
- Added static chrome tests proving `ScreenFrame` uses `CommandBar` and `Normalizer`, screen modules do not call `KeyBar.render`, and `KeyBar` only delegates to `CommandBar.render/3`.

## Task Commits

Each task was committed atomically:

1. **Task 18-07-01 RED: Sysop operator chrome contract** - `0210247` (test)
2. **Task 18-07-01 GREEN: Sysop Chrome V2 caller migration** - `8c6f1b3` (feat)
3. **Task 18-07-02: KeyBar compatibility proof** - `619cb38` (test)

## Files Created/Modified

- `lib/foglet_bbs/tui/screens/sysop.ex` - Passes explicit Sysop breadcrumb data and grouped command groups into `ScreenFrame`.
- `test/foglet_bbs/tui/screens/sysop_test.exs` - Covers operator presentation mode and active Sysop breadcrumb rendering.
- `test/foglet_bbs/tui/widgets/chrome/normalizer_test.exs` - Adds static compatibility tests for the KeyBar-to-CommandBar path.
- `.planning/phases/18-chrome-v2/18-07-SUMMARY.md` - Captures execution results for this plan.

## Decisions Made

- Kept Sysop behavior, tab handling, invite loading, guarded authorization posture, and submodule delegation unchanged.
- Used explicit command groups in Sysop rather than legacy `{key, label}` tuples so the caller is no longer depending on the old flat key-list shape.
- Left `KeyBar` in place because it is already a compatibility adapter over `CommandBar.render/3`.

## Deviations from Plan

None - plan executed within the requested scope.

## Issues Encountered

- Task 18-07-02's new static tests passed immediately because the KeyBar compatibility behavior had already been implemented by prior Phase 18 work. The plan goal for that task was executable proof, so it was completed as a test-only commit.
- Raxol dependency warnings still appear during test runs. They are pre-existing warnings outside this plan's changed files.
- The worktree had unrelated dirty files before and during execution. They were not staged or committed by this plan.

## TDD Gate Compliance

- Task 18-07-01 followed RED then GREEN with separate commits.
- Task 18-07-02 did not produce a failing RED commit because the behavior under test already existed. The resulting commit is a static proof test, not an implementation change.

## Verification

- `rtk mix test test/foglet_bbs/tui/screens/sysop_test.exs test/foglet_bbs/tui/presentation_test.exs` - passed, 55 tests.
- `rtk mix test test/foglet_bbs/tui/widgets/chrome/normalizer_test.exs` - passed, 7 tests.
- `rtk mix test test/foglet_bbs/tui/screens/sysop_test.exs test/foglet_bbs/tui/widgets/chrome/normalizer_test.exs` - passed, 52 tests.
- Acceptance `rtk rg` checks for Sysop chrome evidence, absence of later operator-console primitives, absence of production `KeyBar.render` calls, `ScreenFrame` `CommandBar`/`Normalizer` usage, and normalizer static proof markers all passed.

## Known Stubs

None introduced. Existing Sysop lazy-load placeholder copy remains part of the pre-existing screen behavior and does not block this plan's chrome goal.

## Threat Flags

None. Changes are confined to passive TUI chrome render data and source-level tests; no network endpoints, auth paths, file access paths beyond tests reading local source files, or schema changes were introduced.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

Phase 18 caller migration coverage is complete for Sysop and CHROME-05 has executable static proof. Later operator-console facelift work can proceed without relying on a separate legacy footer path.

## Self-Check: PASSED

- Created summary exists: `.planning/phases/18-chrome-v2/18-07-SUMMARY.md`.
- Modified files exist: `lib/foglet_bbs/tui/screens/sysop.ex`, `test/foglet_bbs/tui/screens/sysop_test.exs`, `test/foglet_bbs/tui/widgets/chrome/normalizer_test.exs`.
- Commits exist: `0210247`, `8c6f1b3`, `619cb38`.
- No `STATE.md`, `ROADMAP.md`, or `REQUIREMENTS.md` changes were made by this plan.

---
*Phase: 18-chrome-v2*
*Completed: 2026-04-25*
