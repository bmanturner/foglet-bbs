---
phase: 08-moderation-workspace-population-and-scope-aware-operations
plan: 03
subsystem: tui
tags: [elixir, phoenix, raxol, tui, moderation, oneliners, bodyguard]

requires:
  - phase: 08-01
    provides: actor-aware oneliner hide authorization and domain mutation
provides:
  - Main-menu oneliner rows selectable through app-owned selected_oneliner_index
  - Advisory moderator/sysop Hide oneliner affordance gated by Bodyguard.permit?/4
  - Reserved Enter behavior for future profile navigation
affects: [main-menu, moderation, oneliners, tui-app-integration]

tech-stack:
  added: []
  patterns:
    - Stateless TUI screen reads and writes selection through app state
    - Advisory UI authorization mirrors domain policy without performing mutation

key-files:
  created:
    - .planning/phases/08-moderation-workspace-population-and-scope-aware-operations/08-03-SUMMARY.md
  modified:
    - lib/foglet_bbs/tui/screens/main_menu.ex
    - test/foglet_bbs/tui/screens/main_menu_test.exs

key-decisions:
  - "MainMenu remains stateless; selected_oneliner_index is read from and written back to app state."
  - "Hide oneliner UI is advisory only and emits {:open_hide_oneliner_modal, id}; authoritative mutation remains outside MainMenu."
  - "Enter on selected oneliners intentionally returns :no_match for future profile navigation."

patterns-established:
  - "Bounded oneliner selection clamps within the five-row visible strip."
  - "Selected oneliners render with a concrete '> ' row marker while unselected rows preserve two-space alignment."

requirements-completed: [MODR-05]

duration: 7min
completed: 2026-04-24T13:09:28Z
---

# Phase 08 Plan 03: Main Menu Oneliner Selection Summary

**Bounded main-menu oneliner selection with Bodyguard-gated moderator hide affordance and reserved Enter behavior**

## Performance

- **Duration:** 7 min
- **Started:** 2026-04-24T13:02:00Z
- **Completed:** 2026-04-24T13:09:28Z
- **Tasks:** 2
- **Files modified:** 3

## Accomplishments

- Added focused tests for oneliner selection, selected-row rendering, hidden operator affordance for regular users, mod/sysop hide dispatch, and no profile navigation on Enter.
- Implemented app-owned `selected_oneliner_index` handling in `MainMenu` without adding screen-local state or `init_screen_state/1`.
- Added advisory `[H] Hide oneliner` key-bar visibility and `{:open_hide_oneliner_modal, id}` dispatch only for selected entries with ids and permitted operators.

## Task Commits

1. **Task 1: Add MainMenu tests for selected oneliners and operator affordance** - `83c46b5` (test)
2. **Task 2: Implement selectable oneliner rows and hide command dispatch** - `5de5d1d` (feat)

## Files Created/Modified

- `lib/foglet_bbs/tui/screens/main_menu.ex` - Adds bounded selection, selected-row markers, `H` hide dispatch, and advisory Bodyguard rendering check.
- `test/foglet_bbs/tui/screens/main_menu_test.exs` - Covers selection movement, role-based hide affordance, hide command output, and reserved Enter behavior.
- `.planning/phases/08-moderation-workspace-population-and-scope-aware-operations/08-03-SUMMARY.md` - Execution summary.

## Decisions Made

- Used `Map.put/3` for `selected_oneliner_index` updates so `MainMenu` can work with map-shaped app state and avoid introducing screen-local state.
- Defaulted the selected row to index `0` when recent oneliners exist, keeping the strip focusable without adding a separate initialization path.
- Kept hide commands narrow: only the selected target id crosses from `MainMenu` to `App`.

## Deviations from Plan

None - plan executed as written.

## Issues Encountered

- `mix precommit` did not pass because Credo reported an unrelated readability issue in already-dirty `lib/foglet_bbs/moderation.ex`: alias ordering for `Foglet.Authorization`. That file is outside Plan 08-03 and was not modified here.
- Focused verification passed: `mix test test/foglet_bbs/tui/screens/main_menu_test.exs`.

## Known Stubs

None.

## Threat Flags

None.

## TDD Gate Compliance

- RED commit present: `83c46b5`
- GREEN commit present after RED: `5de5d1d`
- Refactor commit: not needed

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

Plan 08-04 can consume `{:open_hide_oneliner_modal, selected_id}` from `MainMenu` and keep the authoritative hide-reason modal and domain mutation in `Foglet.TUI.App`.

## Self-Check: PASSED

- Found `lib/foglet_bbs/tui/screens/main_menu.ex`.
- Found `test/foglet_bbs/tui/screens/main_menu_test.exs`.
- Found `.planning/phases/08-moderation-workspace-population-and-scope-aware-operations/08-03-SUMMARY.md`.
- Found task commits `83c46b5` and `5de5d1d`.

---
*Phase: 08-moderation-workspace-population-and-scope-aware-operations*
*Completed: 2026-04-24*
