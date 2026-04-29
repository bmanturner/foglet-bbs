---
phase: 40-verification-documentation
plan: 05
subsystem: tui-documentation
tags: [tui, screen-contract, verification, raxol, precommit]

requires:
  - phase: 40-verification-documentation
    provides: "Plans 40-01 through 40-04 resolved blockers, bounded legacy runtime seams, completed breadcrumbs, and inventoried reducer coverage."
provides:
  - "TUI screen contract guide for Context/Effect/init/update/render screen work"
  - "Final Phase 40 render, full test, and precommit evidence"
  - "Completed Phase 40 carry-forward disposition register"
affects: [tui, widgets, screen-migration, verification-documentation]

tech-stack:
  added: []
  patterns:
    - "Screens own local state and emit Foglet.TUI.Effect values"
    - "App remains the runtime interpreter for tasks, modal state, navigation, PubSub, and rendering dispatch"

key-files:
  created:
    - lib/foglet_bbs/tui/SCREEN_CONTRACT.md
    - .planning/phases/40-verification-documentation/40-05-SUMMARY.md
  modified:
    - lib/foglet_bbs/tui/widgets/README.md
    - .planning/phases/40-verification-documentation/40-SUMMARY.md

key-decisions:
  - "The screen contract guide is TUI-adjacent and linked from the widget documentation surface."
  - "Render smoke evidence remains a lean representative close-gate proof rather than a broad terminal-size campaign."
  - "All Phase 39 carry-forward items now have Fixed or Excluded dispositions; no Blocking items remain."

patterns-established:
  - "Screen documentation should teach state ownership, Context, Effect, task results, route params, subscriptions, modal requests, and render fixtures together."
  - "Final verification evidence should record exact commands, exit codes, and deliberate-delta notes."

requirements-completed: [VERIFY-01, VERIFY-04, VERIFY-05]

duration: 6min
completed: 2026-04-29
---

# Phase 40 Plan 05: Screen Contract Documentation and Final Gates Summary

**TUI screen contract guide linked from widget docs, with final render, full test, precommit, and carry-forward evidence recorded.**

## Performance

- **Duration:** 6 min
- **Started:** 2026-04-29T15:46:38Z
- **Completed:** 2026-04-29T15:52:39Z
- **Tasks:** 3
- **Files modified:** 4

## Accomplishments

- Added `lib/foglet_bbs/tui/SCREEN_CONTRACT.md` with practical guidance for state ownership, `Foglet.TUI.Context`, `Foglet.TUI.Effect`, task results, route params, `subscriptions/2`, modal requests, render fixtures, and `rtk mix foglet.tui.render`.
- Linked the guide from `lib/foglet_bbs/tui/widgets/README.md`.
- Recorded render smoke, full `rtk mix test`, and `rtk mix precommit` evidence in the Phase 40 evidence summary.
- Finalized every Phase 39 carry-forward item as `Fixed` or `Excluded`; no `Blocking` item remains.

## Task Commits

1. **Task 1: Write and link screen contract guidance** - `4498e7b2` (`docs`)
2. **Task 2: Run render smoke evidence commands** - `ce1f8c20` (`docs`)
3. **Task 3: Run final gates and complete summary** - `4fa38ecd` (`docs`)

## Files Created/Modified

- `lib/foglet_bbs/tui/SCREEN_CONTRACT.md` - Developer guide for adding or migrating screens under the Context/Effect screen contract.
- `lib/foglet_bbs/tui/widgets/README.md` - Adds the screen contract guide to Further reading.
- `.planning/phases/40-verification-documentation/40-SUMMARY.md` - Records final Phase 40 evidence and carry-forward dispositions.
- `.planning/phases/40-verification-documentation/40-05-SUMMARY.md` - Plan-level completion summary.

## Verification

Commands run during Plan 40-05:

- `rtk rg -n "Foglet\\.TUI\\.Context|Foglet\\.TUI\\.Effect|init/1|update/3|render/2|subscriptions/2|modal|route params|task_result|rtk mix foglet\\.tui\\.render|## Checklist" lib/foglet_bbs/tui/SCREEN_CONTRACT.md` - exit 0.
- `rtk rg -n "SCREEN_CONTRACT|Screen Contract|screen contract" lib/foglet_bbs/tui/widgets/README.md` - exit 0.
- `rtk mix foglet.tui.render login --width 64 --height 22` - exit 0.
- `rtk mix foglet.tui.render main_menu --width 80 --height 24` - exit 0.
- `rtk mix foglet.tui.render board_list --width 132 --height 50` - exit 0.
- `rtk mix foglet.tui.render post_reader --width 80 --height 24` - exit 0.
- `rtk mix test test/foglet_bbs/tui/layout_smoke_test.exs` - exit 0, 84 tests, 0 failures.
- `rtk mix test` - exit 0, 1 property, 2160 tests, 0 failures.
- `rtk mix precommit` - exit 0; Credo found no issues, Sobelow completed, Dialyzer completed under configured ignores, and the task passed successfully.

## Decisions Made

- Kept the screen guide adjacent to `Foglet.TUI.*` modules and linked it from the widget documentation surface to satisfy D-10 without creating a new documentation hierarchy.
- Recorded dependency compile warnings and test-run warnings as non-blocking evidence context because the commands exited 0 and final precommit passed.
- Left the pre-existing unrelated worktree items (`AGENTS.md`, `.claude/worktrees/`, `LOGIN.md`) untouched.

## Deviations from Plan

None - plan executed exactly as written.

## Known Stubs

None found. The touched files were scanned for common placeholder/stub patterns before summary creation.

## Threat Flags

None. This plan added documentation and verification evidence only; it introduced no new network endpoint, auth path, file access pattern, schema change, or trust-boundary behavior.

## Issues Encountered

- Parallel render commands contended on the Mix build lock while the build warmed. They completed cleanly, and each render command exited 0.
- Initial render/test commands emitted existing dependency compile warnings from `raxol`; final `rtk mix precommit` passed.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

Phase 40 is closed from Plan 40-05's perspective: screen contract documentation exists, final verification evidence is recorded, and no human decision or checkpoint is needed.

## Self-Check: PASSED

- Found created files: `lib/foglet_bbs/tui/SCREEN_CONTRACT.md` and `.planning/phases/40-verification-documentation/40-05-SUMMARY.md`.
- Found updated evidence file: `.planning/phases/40-verification-documentation/40-SUMMARY.md`.
- Verified task commits exist: `4498e7b2`, `ce1f8c20`, and `4fa38ecd`.

---
*Phase: 40-verification-documentation*
*Completed: 2026-04-29*
