---
phase: 17-theme-and-mode-metadata
plan: 01
subsystem: tui
tags: [presentation-mode, tui, exunit, theme-independence]

requires: []
provides:
  - Central `Foglet.TUI.Presentation` screen-to-mode metadata contract
  - Focused ExUnit coverage for all current TUI screen ids
  - Theme-independence checks proving modes are not derived from user theme state
affects: [chrome-v2, tui-facelift, operator-console]

tech-stack:
  added: []
  patterns:
    - Screen presentation mode is resolved through a pure TUI metadata module keyed only by screen id.
    - Unknown screen ids raise instead of defaulting to a valid presentation mode.

key-files:
  created:
    - lib/foglet_bbs/tui/presentation.ex
    - test/foglet_bbs/tui/presentation_test.exs
  modified: []

key-decisions:
  - "Presentation mode is display metadata only, not authorization."
  - "Mode lookup accepts only a screen id and ignores theme/session/palette state."
  - "All current Foglet.TUI.App screen ids are explicitly mapped to :bbs or :operator."

patterns-established:
  - "Central presentation metadata contract: future chrome/layout code should call `Foglet.TUI.Presentation.mode_for!/1`."
  - "Theme independence tests use `Theme.ids()` as irrelevant alternate inputs without adding a stateful lookup API."

requirements-completed: [MODE-01]

duration: 13min
completed: 2026-04-25
---

# Phase 17 Plan 01: Presentation Mode Metadata Summary

**Screen-id-only TUI presentation mode contract with explicit BBS/operator mappings and theme-independence tests**

## Performance

- **Duration:** 13 min
- **Started:** 2026-04-25T14:05:42Z
- **Completed:** 2026-04-25T14:18:12Z
- **Tasks:** 2
- **Files modified:** 2

## Accomplishments

- Added `Foglet.TUI.Presentation` with `modes/0`, `screen_modes/0`, `screen_ids/0`, and `mode_for!/1`.
- Mapped all 12 current `Foglet.TUI.App.screen/0` ids to exactly `:bbs` or `:operator`.
- Added tests proving unknown ids raise and theme ids do not affect mode resolution.

## Task Commits

1. **Task 17-01-01 RED: Add failing presentation mode contract tests** - `bf55519` (test)
2. **Task 17-01-01 GREEN: Add central screen-mode contract** - `5968137` (feat)
3. **Task 17-01-02: Prove mode is independent from theme state** - `32efada` (test)

## Files Created/Modified

- `lib/foglet_bbs/tui/presentation.ex` - Pure presentation metadata API for screen ids, supported modes, and unknown-id rejection.
- `test/foglet_bbs/tui/presentation_test.exs` - Focused MODE-01 and THEME-02 tests for mode coverage, unknown ids, and theme independence.

## Decisions Made

- Followed the plan's exact BBS and operator screen sets.
- Kept presentation mode separate from authorization and from theme state.
- Did not change screen modules, rendering, chrome, widgets, or layout behavior.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

- The initial focused test run was blocked because dependencies were not fetched in this worktree. Resolved with `rtk mix deps.get`.
- `rtk mix format lib/foglet_bbs/tui/presentation.ex test/foglet_bbs/tui/presentation_test.exs` initially failed on `_build` ownership, then passed after the dev build was available.
- `rtk mix precommit` failed on pre-existing Credo findings outside this plan:
  - `test/foglet_bbs/tui/widgets/modal_test.exs:4` alias ordering.
  - `test/foglet_bbs/tui/widgets/list/list_row_test.exs:4` alias ordering.
  - `lib/foglet_bbs/tui/widgets/list/list_row.ex:32` alias ordering.
  - `lib/foglet_bbs/tui/text_width.ex:112` cond refactoring suggestion.

## Verification

- `rtk mix test test/foglet_bbs/tui/presentation_test.exs` - passed, 7 tests.
- `rtk mix test test/foglet_bbs/tui/theme_test.exs test/foglet_bbs/tui/presentation_test.exs` - passed, 13 tests.
- `rtk mix format lib/foglet_bbs/tui/presentation.ex test/foglet_bbs/tui/presentation_test.exs` - passed.
- `rtk mix precommit` - failed on out-of-scope pre-existing Credo findings listed above.

## Known Stubs

None.

## Threat Flags

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

Future chrome/layout work can call `Foglet.TUI.Presentation.mode_for!/1` to choose BBS or operator presentation rhythm without inspecting theme, session, or screen module state.

## Self-Check: PASSED

- Created files exist: `lib/foglet_bbs/tui/presentation.ex`, `test/foglet_bbs/tui/presentation_test.exs`, `.planning/phases/17-theme-and-mode-metadata/17-01-SUMMARY.md`.
- Commits exist: `bf55519`, `5968137`, `32efada`.
- No `STATE.md` or `ROADMAP.md` changes were made.

---
*Phase: 17-theme-and-mode-metadata*
*Completed: 2026-04-25*
