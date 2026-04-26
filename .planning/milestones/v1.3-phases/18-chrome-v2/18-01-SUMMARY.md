---
phase: 18-chrome-v2
plan: 01
subsystem: tui
tags: [chrome-v2, breadcrumbs, status-bar, presentation-mode, text-width]

requires:
  - phase: 16-unicode-width-foundation
    provides: TextWidth display-width truncation helpers
  - phase: 17-theme-and-mode-metadata
    provides: Presentation.mode_for!/1 screen metadata
provides:
  - Shared `Foglet.TUI.Widgets.Chrome.BreadcrumbBar` path, format, and render contract
  - Mode-aware `Foglet.TUI.Widgets.Chrome.StatusBar.status_atoms/1`
  - Focused TDD coverage for breadcrumb and status atom behavior
affects: [chrome-v2, screen-frame, tui-facelift, operator-console]

tech-stack:
  added: []
  patterns:
    - Central breadcrumb path derivation rooted at `Foglet`
    - Mode-aware status atom lists selected by `Presentation.mode_for!/1`
    - Honest optional status omission for unavailable unread/activity/scope/system fields

key-files:
  created:
    - lib/foglet_bbs/tui/widgets/chrome/breadcrumb_bar.ex
    - test/foglet_bbs/tui/widgets/chrome/breadcrumb_test.exs
  modified:
    - lib/foglet_bbs/tui/widgets/chrome/status_bar.ex
    - test/foglet_bbs/tui/widgets/chrome/status_bar_test.exs

key-decisions:
  - "Breadcrumbs are display-only chrome derived centrally from existing TUI state."
  - "Status atoms use Phase 17 presentation mode metadata and do not infer mode from theme, role, or authorization."
  - "Guest status remains `guest`; optional unread/activity/scope/system atoms render only when concrete state fields exist."

patterns-established:
  - "Chrome breadcrumb formatting delegates width clipping to `Foglet.TUI.TextWidth.truncate/2`."
  - "StatusBar.render/2 remains legacy-compatible while render/3 accepts breadcrumb parts or a small chrome model."

requirements-completed: [CHROME-01, CHROME-02]

duration: 10min
completed: 2026-04-25
---

# Phase 18 Plan 01: Chrome V2 Primitives Summary

**Foglet-rooted breadcrumb formatting and mode-aware status atoms for shared TUI chrome**

## Performance

- **Duration:** 10 min
- **Started:** 2026-04-25T17:11:39Z
- **Completed:** 2026-04-25T17:21:49Z
- **Tasks:** 2
- **Files modified:** 4

## Accomplishments

- Added `Chrome.BreadcrumbBar` with `parts_for/1`, `format/2`, and `render/3`.
- Added Unicode and ASCII breadcrumb formatting with display-width truncation through `TextWidth`.
- Extended `Chrome.StatusBar` with public `status_atoms/1` selected by `Presentation.mode_for!/1`.
- Preserved legacy `StatusBar.render(state, title)` behavior while adding `render/3` support for breadcrumb parts.

## Task Commits

1. **Task 18-01-01 RED: Breadcrumb formatter contract tests** - `0e38d20` (test)
2. **Task 18-01-01 GREEN: Breadcrumb chrome primitive** - `1b676c0` (feat)
3. **Task 18-01-02 RED: Status atom contract tests** - `d02e5ad` (test)
4. **Task 18-01-02 GREEN: Mode-aware status atoms** - `bf6f83c` (feat)

## Files Created/Modified

- `lib/foglet_bbs/tui/widgets/chrome/breadcrumb_bar.ex` - Shared breadcrumb path derivation, formatting, truncation, and themed render.
- `test/foglet_bbs/tui/widgets/chrome/breadcrumb_test.exs` - Contract tests for named screen paths, fallbacks, separators, truncation, and render.
- `lib/foglet_bbs/tui/widgets/chrome/status_bar.ex` - Mode-aware status atom builder and breadcrumb-capable render arity.
- `test/foglet_bbs/tui/widgets/chrome/status_bar_test.exs` - Status atom tests for BBS, operator, guest, unknown mode, and render compatibility.

## Decisions Made

- Unknown or incomplete breadcrumb state returns a non-empty path rooted at `Foglet`.
- Operator active-tab labels are included only when safely present; missing tab state is omitted rather than guessed.
- Guest status emits only `guest`, even if optional status fields are present, because clocks and status atoms are authenticated-session chrome.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

- `rtk mix test` intermittently hit Mix PubSub socket sandbox restrictions; rerunning the focused commands with approved execution completed successfully.
- `rtk mix precommit` failed on pre-existing Dialyzer warnings in `lib/foglet_bbs/release.ex` unmatched returns. The local `StatusBar.render/2` spec warning found during the first precommit run was fixed before committing the final status implementation.

## Verification

- `rtk mix test test/foglet_bbs/tui/widgets/chrome/breadcrumb_test.exs` - passed, 6 tests.
- `rtk mix test test/foglet_bbs/tui/widgets/chrome/status_bar_test.exs` - passed, 13 tests.
- `rtk mix test test/foglet_bbs/tui/widgets/chrome/breadcrumb_test.exs test/foglet_bbs/tui/widgets/chrome/status_bar_test.exs` - passed, 19 tests.
- Task acceptance `rtk rg` checks for breadcrumb exports, separators, screen ids, `Presentation.mode_for!`, `status_atoms`, and absence of placeholder strings all passed.
- `rtk mix precommit` - failed only on out-of-scope pre-existing Dialyzer warnings in `lib/foglet_bbs/release.ex`.

## Known Stubs

None.

## Threat Flags

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

Chrome V2 callers can now consume central breadcrumb paths and honest mode-aware status atoms before `ScreenFrame` and screen migrations wire the full top chrome.

## Self-Check: PASSED

- Created files exist: `lib/foglet_bbs/tui/widgets/chrome/breadcrumb_bar.ex`, `test/foglet_bbs/tui/widgets/chrome/breadcrumb_test.exs`, `.planning/phases/18-chrome-v2/18-01-SUMMARY.md`.
- Modified files exist: `lib/foglet_bbs/tui/widgets/chrome/status_bar.ex`, `test/foglet_bbs/tui/widgets/chrome/status_bar_test.exs`.
- Commits exist: `0e38d20`, `1b676c0`, `d02e5ad`, `bf6f83c`.
- No `STATE.md` or `ROADMAP.md` changes were made by this plan.

---
*Phase: 18-chrome-v2*
*Completed: 2026-04-25*
