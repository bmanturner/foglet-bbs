---
phase: 18-chrome-v2
plan: 02
subsystem: ui
tags: [tui, chrome-v2, raxol, command-bar, compatibility]

requires:
  - phase: 16-unicode-width-foundation
    provides: display-width measurement and truncation helpers
  - phase: 17-theme-and-mode-metadata
    provides: semantic command theme-slot mappings
provides:
  - Grouped Chrome.CommandBar rendering with priority truncation
  - Legacy flat key-list compatibility through Chrome.Normalizer
  - Chrome.KeyBar wrapper delegated to CommandBar
affects: [chrome-v2, screen-frame, keybar-migration]

tech-stack:
  added: []
  patterns:
    - Passive Chrome V2 command metadata renderer
    - Legacy key-list normalization into grouped command data

key-files:
  created:
    - lib/foglet_bbs/tui/widgets/chrome/command_bar.ex
    - lib/foglet_bbs/tui/widgets/chrome/normalizer.ex
    - test/foglet_bbs/tui/widgets/chrome/command_bar_test.exs
    - test/foglet_bbs/tui/widgets/chrome/normalizer_test.exs
  modified:
    - lib/foglet_bbs/tui/widgets/chrome/key_bar.ex
    - test/foglet_bbs/tui/widgets/chrome/key_bar_test.exs

key-decisions:
  - "Command hints remain passive display metadata; screen handlers and contexts still own behavior and authorization."
  - "Chrome.KeyBar is retained only as a compatibility wrapper over Normalizer.commands/1 and CommandBar.render/3."

patterns-established:
  - "Grouped commands sort by minimum command priority, then truncate lower-priority hints first under width pressure."
  - "Legacy key tuples normalize into stable groups: System, Navigate, Actions, Tabs, Field, Save, and Refresh."

requirements-completed: [CHROME-03, CHROME-05]

duration: 18min
completed: 2026-04-25
---

# Phase 18 Plan 02: Grouped Command Bar and Normalizer Summary

**Chrome V2 command hints now render through a grouped, width-budgeted CommandBar, with legacy flat key lists normalized into the same path.**

## Performance

- **Duration:** 18 min
- **Started:** 2026-04-25T16:58:00Z
- **Completed:** 2026-04-25T17:16:18Z
- **Tasks:** 2
- **Files modified:** 6

## Accomplishments

- Added `Foglet.TUI.Widgets.Chrome.CommandBar` for grouped command rendering, semantic theme-slot routing, display-width measurement, and priority-based truncation.
- Added `Foglet.TUI.Widgets.Chrome.Normalizer` so legacy `{key, description}` lists become grouped command data.
- Reduced `Chrome.KeyBar` to a compatibility wrapper that delegates to `Normalizer.commands/1` and `CommandBar.render/3`.

## Task Commits

Each task was committed atomically:

1. **Task 18-02-01 RED:** `31c1ddb` test(18-02): add failing command bar contract tests
2. **Task 18-02-01 GREEN:** `953cc21` feat(18-02): implement grouped command bar
3. **Task 18-02-02 RED:** `b94ba3f` test(18-02): add failing normalizer compatibility tests
4. **Task 18-02-02 GREEN:** `dfdc7df` feat(18-02): normalize legacy key hints into command groups
5. **Refactor:** `bf7ef7f` refactor(18-02): clean up command chrome implementation

## Files Created/Modified

- `lib/foglet_bbs/tui/widgets/chrome/command_bar.ex` - Grouped command renderer with normalization, theme-slot routing, and display-width truncation.
- `lib/foglet_bbs/tui/widgets/chrome/normalizer.ex` - Legacy flat key-list adapter for stable Chrome V2 command groups and priorities.
- `lib/foglet_bbs/tui/widgets/chrome/key_bar.ex` - Compatibility wrapper delegating to `CommandBar`.
- `test/foglet_bbs/tui/widgets/chrome/command_bar_test.exs` - Command grouping, priority order, truncation, and normalization coverage.
- `test/foglet_bbs/tui/widgets/chrome/normalizer_test.exs` - Legacy group classification and explicit command construction coverage.
- `test/foglet_bbs/tui/widgets/chrome/key_bar_test.exs` - Delegation and width-contract coverage for the retained wrapper.

## Decisions Made

- `CommandBar` accepts maps or structs, but normalizes internally to maps with string keys/labels and integer priorities.
- `Normalizer.commands/1` classifies existing hints conservatively: system and navigation stay priority `0`, tabs/field/save/refresh use `10`, ordinary actions use `30`, and verbose/help hints use `50`.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed Credo issues in new command chrome code**
- **Found during:** Final verification
- **Issue:** `rtk mix precommit` reported two `Enum.map/2 |> Enum.join/2` refactors and one complex normalizer classifier.
- **Fix:** Switched command text assembly to `Enum.map_join/3` and split classification into named predicates.
- **Files modified:** `lib/foglet_bbs/tui/widgets/chrome/command_bar.ex`, `lib/foglet_bbs/tui/widgets/chrome/normalizer.ex`
- **Verification:** Focused plan tests passed after the refactor.
- **Committed in:** `bf7ef7f`

---

**Total deviations:** 1 auto-fixed (Rule 1).
**Impact on plan:** No scope expansion; cleanup was required for project quality gates.

## Issues Encountered

`rtk mix precommit` progressed through compile, format, Credo, and Sobelow, then failed in Dialyzer because unrelated untracked release files in the worktree (`lib/foglet_bbs/release.ex`, `rel/`) are being compiled and emit unmatched-return warnings. Those files are outside plan 18-02 and were left untouched.

## Verification

- `rtk mix test test/foglet_bbs/tui/widgets/chrome/command_bar_test.exs` - PASS
- `rtk mix test test/foglet_bbs/tui/widgets/chrome/normalizer_test.exs test/foglet_bbs/tui/widgets/chrome/key_bar_test.exs` - PASS
- `rtk mix test test/foglet_bbs/tui/widgets/chrome/command_bar_test.exs test/foglet_bbs/tui/widgets/chrome/normalizer_test.exs test/foglet_bbs/tui/widgets/chrome/key_bar_test.exs` - PASS, 10 tests
- Acceptance rg checks for `CommandBar`, `Normalizer`, `CommandBar.render`, `Normalizer.commands`, and removed centered flat keybar path - PASS
- `rtk mix precommit` - PARTIAL: blocked by unrelated untracked release files described above

## Known Stubs

None.

## Threat Flags

None. The new modules are passive TUI render/normalization code and introduce no network endpoints, auth paths, file access, or schema changes.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

Plan 18-03 can integrate command groups into `ScreenFrame` without keeping the old flat `KeyBar` production path. Legacy callers can continue passing simple key tuples during staged migration because they now normalize into the grouped command contract.

## Self-Check: PASSED

- Created files exist: `command_bar.ex`, `normalizer.ex`, `command_bar_test.exs`, `normalizer_test.exs`.
- All 18-02 commits are present in git history.
- No tracked files were deleted by task commits.

---
*Phase: 18-chrome-v2*
*Completed: 2026-04-25*
