---
phase: 18-chrome-v2
plan: 03
subsystem: tui
tags: [chrome-v2, screen-frame, layout, raxol, command-bar]

requires:
  - phase: 18-01
    provides: BreadcrumbBar and mode-aware StatusBar status atoms
  - phase: 18-02
    provides: grouped CommandBar and Normalizer compatibility path
provides:
  - Chrome V2 composition through ScreenFrame.render/4
  - Positioned layout size-contract coverage for 64x22, 80x24, and 132x50
  - Nil-safe breadcrumb fallback for screens without loaded board/thread context
affects: [chrome-v2, screen-frame, tui-layout, screen-migration]

tech-stack:
  added: []
  patterns:
    - ScreenFrame remains the single screen-facing chrome boundary
    - Legacy title/key tuple callers normalize into Chrome V2 breadcrumb/status/command data
    - Positioned layout tests assert x/y bounds and vertical ordering

key-files:
  created:
    - test/foglet_bbs/tui/widgets/chrome/screen_frame_test.exs
  modified:
    - lib/foglet_bbs/tui/widgets/chrome/screen_frame.ex
    - lib/foglet_bbs/tui/widgets/chrome/breadcrumb_bar.ex
    - test/foglet_bbs/tui/layout_smoke_test.exs

key-decisions:
  - "ScreenFrame derives breadcrumb parts centrally from state for legacy title callers."
  - "Command groups are rendered through CommandBar inside the outer frame; KeyBar is no longer a ScreenFrame production dependency."
  - "Layout smoke coverage inspects positioned text from Raxol.UI.Layout.Engine.apply_layout/2 at the required terminal sizes."

patterns-established:
  - "ScreenFrame builds a small Chrome V2 model from legacy callers before rendering."
  - "Chrome size-contract tests assert terminal-width bounds with TextWidth.display_width/1."

requirements-completed: [CHROME-01, CHROME-02, CHROME-03, CHROME-04]

duration: 6min
completed: 2026-04-25
---

# Phase 18 Plan 03: ScreenFrame Chrome V2 Integration Summary

**ScreenFrame now composes breadcrumb/status chrome, caller content, and grouped command chrome inside one bordered TUI frame.**

## Performance

- **Duration:** 6 min
- **Started:** 2026-04-25T17:24:38Z
- **Completed:** 2026-04-25T17:30:06Z
- **Tasks:** 2
- **Files modified:** 4

## Accomplishments

- Replaced the old `ScreenFrame` production `KeyBar` dependency with `BreadcrumbBar`, `StatusBar`, `Normalizer`, and `CommandBar`.
- Preserved the existing `render(state, title_or_chrome, content, commands)` call path while normalizing legacy title/key tuple callers into Chrome V2 data.
- Added positioned Chrome V2 layout coverage at 64x22, 80x24, and 132x50 that checks text bounds and top/content/command y-ordering.

## Task Commits

Each task was committed atomically:

1. **Task 18-03-01 RED: ScreenFrame Chrome V2 contract** - `f0bc1e7` (test)
2. **Task 18-03-01 GREEN: ScreenFrame Chrome V2 composition** - `3eb38ce` (feat)
3. **Task 18-03-02 RED: Chrome V2 layout size contracts** - `ff272af` (test)
4. **Task 18-03-02 GREEN: Layout contract stabilization** - `745073c` (fix)

## Files Created/Modified

- `lib/foglet_bbs/tui/widgets/chrome/screen_frame.ex` - Composes Chrome V2 breadcrumb/status and grouped command bar through the shared frame boundary.
- `lib/foglet_bbs/tui/widgets/chrome/breadcrumb_bar.ex` - Handles nil board/thread context with honest fallback labels.
- `test/foglet_bbs/tui/widgets/chrome/screen_frame_test.exs` - Verifies Chrome V2 composition and content ordering through `ScreenFrame.render/4`.
- `test/foglet_bbs/tui/layout_smoke_test.exs` - Adds positioned Chrome V2 size-contract coverage and updates the delegated KeyBar smoke expectation.

## Decisions Made

- Legacy title strings are ignored for breadcrumb text once `ScreenFrame` can derive a richer path from state.
- Legacy flat command tuples continue to work only through `Normalizer.commands/1` feeding `CommandBar.render/3`.
- The size-contract test uses direct `ScreenFrame.render/4` output to isolate shared chrome layout from later screen facelift work.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed nil board/thread breadcrumb crashes**
- **Found during:** Task 18-03-02 layout smoke verification
- **Issue:** Screens such as `NewThread` and `PostComposer` can render before `current_board` is loaded; `BreadcrumbBar.parts_for/1` crashed by calling `Map.get/3` on nil.
- **Fix:** Added a small nil-safe map fallback before reading board and thread labels.
- **Files modified:** `lib/foglet_bbs/tui/widgets/chrome/breadcrumb_bar.ex`
- **Verification:** `rtk mix test test/foglet_bbs/tui/layout_smoke_test.exs` passed.
- **Committed in:** `745073c`

**2. [Rule 3 - Blocking] Updated smoke expectation for delegated KeyBar output**
- **Found during:** Task 18-03-02 layout smoke verification
- **Issue:** Existing Phase 16 smoke coverage expected bracketed legacy `KeyBar` text, but Phase 18 Plan 02 changed `KeyBar` into a compatibility wrapper over grouped command output.
- **Fix:** Updated the smoke assertion to require the unbracketed key and group label emitted by the grouped command path.
- **Files modified:** `test/foglet_bbs/tui/layout_smoke_test.exs`
- **Verification:** `rtk mix test test/foglet_bbs/tui/layout_smoke_test.exs` passed.
- **Committed in:** `745073c`

---

**Total deviations:** 2 auto-fixed (1 Rule 1 bug, 1 Rule 3 blocker).
**Impact on plan:** Both fixes were required to keep Chrome V2 compatible with existing screen render paths and verification coverage. No domain behavior or screen navigation changed.

## Issues Encountered

- `rtk mix test test/foglet_bbs/tui/layout_smoke_test.exs` initially surfaced the nil breadcrumb crash and stale KeyBar smoke expectation above.
- Raxol dependency warnings are still emitted during test runs; they are pre-existing warnings outside this plan's changed files.

## Verification

- `rtk mix test test/foglet_bbs/tui/widgets/chrome/screen_frame_test.exs` - passed, 2 tests.
- `rtk mix test test/foglet_bbs/tui/layout_smoke_test.exs` - passed, 21 tests.
- `rtk mix test test/foglet_bbs/tui/widgets/chrome/screen_frame_test.exs test/foglet_bbs/tui/layout_smoke_test.exs` - passed, 23 tests.
- Acceptance `rtk rg` checks for Chrome V2 primitives, absence of `KeyBar` in `ScreenFrame`, and required layout markers all passed.

## Known Stubs

None.

## Threat Flags

None. Changes are confined to passive TUI render composition and test coverage; no network endpoints, auth paths, file access, or schema changes were introduced.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

Named screens can continue using the existing `ScreenFrame.render/4` call path while later Phase 18 plans migrate callers and Login chrome behavior deliberately.

## Self-Check: PASSED

- Created files exist: `test/foglet_bbs/tui/widgets/chrome/screen_frame_test.exs`, `.planning/phases/18-chrome-v2/18-03-SUMMARY.md`.
- Modified files exist: `lib/foglet_bbs/tui/widgets/chrome/screen_frame.ex`, `lib/foglet_bbs/tui/widgets/chrome/breadcrumb_bar.ex`, `test/foglet_bbs/tui/layout_smoke_test.exs`.
- Commits exist: `f0bc1e7`, `3eb38ce`, `ff272af`, `745073c`.
- No `STATE.md` or `ROADMAP.md` changes were made by this plan.

---
*Phase: 18-chrome-v2*
*Completed: 2026-04-25*
