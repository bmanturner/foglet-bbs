---
phase: 18-chrome-v2
plan: 06
subsystem: tui
tags: [chrome-v2, account, moderation, operator-mode, raxol]

requires:
  - phase: 18-03
    provides: ScreenFrame Chrome V2 composition and compatibility normalization
provides:
  - Account screen caller explicitly declaring operator Chrome V2 mode
  - Moderation screen caller explicitly declaring operator Chrome V2 mode
  - Focused render assertions for Account and Moderation breadcrumbs and mode metadata
affects: [chrome-v2, account-screen, moderation-screen, operator-chrome]

tech-stack:
  added: []
  patterns:
    - Screen callers pass small Chrome V2 models into ScreenFrame while preserving existing content and command data
    - Presentation.mode_for!/1 remains display metadata only and does not affect authorization

key-files:
  created:
    - .planning/phases/18-chrome-v2/18-06-SUMMARY.md
  modified:
    - lib/foglet_bbs/tui/screens/account.ex
    - lib/foglet_bbs/tui/screens/moderation.ex
    - test/foglet_bbs/tui/screens/account_test.exs
    - test/foglet_bbs/tui/screens/moderation_test.exs

key-decisions:
  - "Account and Moderation now pass explicit Chrome V2 model maps into ScreenFrame instead of relying only on legacy title strings."
  - "Operator mode declaration stays display-only through Presentation.mode_for!/1; authorization remains in existing screen handlers and domain contexts."

patterns-established:
  - "Operator screen chrome migration can be a caller-local model helper plus existing ScreenFrame content/commands."

requirements-completed: [CHROME-01, CHROME-02, CHROME-03, CHROME-04]

duration: 4min
completed: 2026-04-25
---

# Phase 18 Plan 06: Account and Moderation Chrome Caller Summary

**Account and Moderation now declare operator-mode Chrome V2 at the shared ScreenFrame boundary without changing their workflows.**

## Performance

- **Duration:** 4 min
- **Started:** 2026-04-25T17:36:19Z
- **Completed:** 2026-04-25T17:40:46Z
- **Tasks:** 2
- **Files modified:** 4

## Accomplishments

- Account now passes an explicit `%{title: "Account", mode: Presentation.mode_for!(:account)}` Chrome V2 model into `ScreenFrame.render/4`.
- Moderation now passes an explicit `%{title: "Moderation", mode: Presentation.mode_for!(:moderation)}` Chrome V2 model through both authorized and defensive unavailable render paths.
- Focused tests assert `Foglet`, screen labels, and operator presentation mode for both screens while existing profile, preferences, SSH keys, invite, tab, and read-only moderation behavior remains covered.

## Task Commits

Each task was committed atomically:

1. **Task 18-06-01 GREEN: Account chrome caller migration** - `9a1cad6` (feat)
2. **Task 18-06-02 GREEN: Moderation chrome caller migration** - `7d55874` (feat)

**Plan metadata:** committed separately in this summary commit.

_Note: The RED render/mode assertions for Account and Moderation were already present in the incoming branch history before these GREEN commits, from interleaved parallel executor commits. The failing gates were re-run and failed for the intended missing caller-link reason before implementation._

## Files Created/Modified

- `lib/foglet_bbs/tui/screens/account.ex` - Adds an Account Chrome V2 model helper tied to `Presentation.mode_for!(:account)`.
- `lib/foglet_bbs/tui/screens/moderation.ex` - Adds a Moderation Chrome V2 model helper tied to `Presentation.mode_for!(:moderation)` and uses it in both render paths.
- `test/foglet_bbs/tui/screens/account_test.exs` - Contains Account render and presentation-mode assertions.
- `test/foglet_bbs/tui/screens/moderation_test.exs` - Contains Moderation render and presentation-mode assertions.

## Decisions Made

- Kept the migration at the screen call-site boundary; no screen behavior, key handling, authorization, forms, tabs, invite delegation, or moderation data flow changed.
- Did not introduce Phase 24/25 operator console primitives such as badges, key/value grids, inspectors, tables, or case-management workflow changes.

## Deviations from Plan

None - plan scope was executed as specified. The only process wrinkle was pre-existing RED test commits in the incoming parallel branch history; those tests were used as the TDD RED gates and the GREEN changes were committed under this plan.

## Issues Encountered

- The worktree contained unrelated modified and untracked files from other parallel work. They were left untouched and excluded from all 18-06 commits.
- Raxol dependency warnings still appear during test runs; they are pre-existing warnings outside this plan's changed files.

## Verification

- `rtk mix test test/foglet_bbs/tui/screens/account_test.exs test/foglet_bbs/tui/presentation_test.exs` - passed, 44 tests.
- `rtk mix test test/foglet_bbs/tui/screens/moderation_test.exs test/foglet_bbs/tui/presentation_test.exs` - passed, 37 tests.
- `rtk mix test test/foglet_bbs/tui/screens/account_test.exs test/foglet_bbs/tui/screens/moderation_test.exs test/foglet_bbs/tui/presentation_test.exs` - passed, 71 tests.
- Account acceptance greps passed: render/mode assertions are present and no `Badge`, `KvGrid`, `Inspector`, or `Table` references were added to `account.ex`.
- Moderation acceptance greps passed: render/mode assertions are present and no `case management`, `Inspector`, `KvGrid`, or `Badge` references were added to `moderation.ex`.

## Known Stubs

None. Existing honest unavailable copy in Moderation is intentional pre-existing workflow copy, not a new stub introduced by this plan.

## Threat Flags

None. Changes are confined to passive TUI chrome render metadata; no network endpoints, auth paths, file access, schema changes, or domain mutation surfaces were introduced.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

Sysop and later operator-console facelift work can follow the same explicit Chrome V2 caller pattern while keeping authorization and domain behavior separate from presentation mode.

## Self-Check: PASSED

- Created files exist: `.planning/phases/18-chrome-v2/18-06-SUMMARY.md`.
- Modified files exist: `lib/foglet_bbs/tui/screens/account.ex`, `lib/foglet_bbs/tui/screens/moderation.ex`, `test/foglet_bbs/tui/screens/account_test.exs`, `test/foglet_bbs/tui/screens/moderation_test.exs`.
- Commits exist: `9a1cad6`, `7d55874`.
- `STATE.md` and `ROADMAP.md` were not modified by this plan.

---
*Phase: 18-chrome-v2*
*Completed: 2026-04-25*
