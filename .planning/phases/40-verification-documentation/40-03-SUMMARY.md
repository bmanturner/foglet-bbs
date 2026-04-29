---
phase: 40-verification-documentation
plan: 03
subsystem: tui
tags: [tui, raxol, breadcrumbs, tests, verification]
requires:
  - phase: 40-01
    provides: "Phase 40 deferred blocker cleanup and evidence register foundation"
  - phase: 40-02
    provides: "Screen dispatch/rendering through the new production contract"
provides:
  - "Explicit breadcrumb_parts for remaining production screens"
  - "Active breadcrumb smoke coverage for auth, home, board, account, and moderation screens"
  - "Targeted IN-03 migrated-TUI test hygiene disposition"
affects: [phase-40, tui-screen-contract, breadcrumb-chrome, migrated-tui-tests]
tech-stack:
  added: []
  patterns:
    - "Screens pass explicit breadcrumb_parts maps to ScreenFrame.render/4"
    - "Breadcrumb tests assert actual chrome behavior where chrome text is the contract"
    - "Migrated TUI tests prefer reducer state where available and document visual-contract checks"
key-files:
  created:
    - .planning/phases/40-verification-documentation/40-03-SUMMARY.md
  modified:
    - lib/foglet_bbs/tui/screens/login.ex
    - lib/foglet_bbs/tui/screens/register.ex
    - lib/foglet_bbs/tui/screens/verify.ex
    - lib/foglet_bbs/tui/screens/main_menu.ex
    - lib/foglet_bbs/tui/screens/board_list.ex
    - lib/foglet_bbs/tui/screens/account.ex
    - lib/foglet_bbs/tui/screens/moderation.ex
    - test/foglet_bbs/tui/widgets/chrome/breadcrumb_migration_test.exs
    - test/foglet_bbs/tui/layout_smoke_test.exs
    - test/foglet_bbs/tui/screens/post_composer_test.exs
    - .planning/phases/40-verification-documentation/40-SUMMARY.md
key-decisions:
  - "Remaining production screens now own simple explicit breadcrumb_parts rather than relying on ScreenFrame fallback."
  - "Login reset-token breadcrumb coverage now asserts the explicit Login chrome row and token non-leak behavior instead of resurrecting removed sub-path inference."
  - "IN-03 cleanup stayed targeted: one weak PostComposer render assertion moved to reducer state, while chrome/layout assertions remain documented visual contracts."
patterns-established:
  - "Use exact screen-owned breadcrumb_parts for migrated production screens."
  - "Treat breadcrumb/chrome strings as acceptable text assertions only when they are the behavior contract."
requirements-completed: [VERIFY-01, VERIFY-02]
duration: 7 min
completed: 2026-04-29
---

# Phase 40 Plan 03: Breadcrumb Ownership and Test Hygiene Summary

**Remaining production TUI screens now emit explicit breadcrumbs, pending Login breadcrumb smoke is active, and targeted IN-03 hygiene is documented without broad test churn.**

## Performance

- **Duration:** 7 min
- **Started:** 2026-04-29T15:26:47Z
- **Completed:** 2026-04-29T15:34:06Z
- **Tasks:** 3
- **Files modified:** 11

## Accomplishments

- Added explicit `breadcrumb_parts` for Login, Register, Verify, MainMenu, BoardList, Account, and Moderation.
- Activated pending Login breadcrumb smoke checks and expanded breadcrumb migration tests to cover the remaining production screens.
- Replaced one weak migrated-TUI render assertion with reducer-owned PostComposer state checks and recorded the remaining visual-contract/deferred IN-03 disposition in `40-SUMMARY.md`.

## Task Commits

1. **Task 1: Add explicit breadcrumbs for remaining screens** - `b5ff611` (feat)
2. **Task 2: Activate pending breadcrumb smoke tests and keep render proof lightweight** - `c11f8eb` (test)
3. **Task 3: Clean targeted migrated-TUI weak checks** - `eaec5d4` (test)

## Files Created/Modified

- `lib/foglet_bbs/tui/screens/login.ex` - emits `["Foglet", "Login"]`.
- `lib/foglet_bbs/tui/screens/register.ex` - emits `["Foglet", "Register"]`.
- `lib/foglet_bbs/tui/screens/verify.ex` - emits `["Foglet", "Verify"]`.
- `lib/foglet_bbs/tui/screens/main_menu.ex` - emits `["Foglet", "Home"]`.
- `lib/foglet_bbs/tui/screens/board_list.ex` - emits `["Foglet", "Boards"]`.
- `lib/foglet_bbs/tui/screens/account.ex` - emits `["Foglet", "Account"]`.
- `lib/foglet_bbs/tui/screens/moderation.ex` - emits `["Foglet", "Moderation"]`.
- `test/foglet_bbs/tui/widgets/chrome/breadcrumb_migration_test.exs` - covers explicit breadcrumb emission across the remaining screens.
- `test/foglet_bbs/tui/layout_smoke_test.exs` - removes `:phase39_login_breadcrumb_pending` and asserts active Login chrome behavior.
- `test/foglet_bbs/tui/screens/post_composer_test.exs` - replaces a preview-mode text assertion with local reducer state checks.
- `.planning/phases/40-verification-documentation/40-SUMMARY.md` - records IN-03 targeted hygiene, visual contracts, and deferred broad cleanup.

## Verification

- `rtk rg -n "breadcrumb_parts" lib/foglet_bbs/tui/screens/login.ex lib/foglet_bbs/tui/screens/register.ex lib/foglet_bbs/tui/screens/verify.ex lib/foglet_bbs/tui/screens/main_menu.ex lib/foglet_bbs/tui/screens/board_list.ex lib/foglet_bbs/tui/screens/account.ex lib/foglet_bbs/tui/screens/moderation.ex` - passed.
- `rtk mix test test/foglet_bbs/tui/widgets/chrome/breadcrumb_migration_test.exs` - passed, 15 tests.
- `rtk rg -n "phase39_login_breadcrumb_pending" test/foglet_bbs/tui/layout_smoke_test.exs` - exited 1 as expected.
- `rtk mix test test/foglet_bbs/tui/widgets/chrome/breadcrumb_migration_test.exs test/foglet_bbs/tui/layout_smoke_test.exs` - passed, 99 tests.
- `rtk mix test test/foglet_bbs/tui/screens/post_composer_test.exs test/foglet_bbs/tui/screens/post_reader_test.exs test/foglet_bbs/tui/screens/sysop_test.exs test/foglet_bbs/tui/widgets/chrome/screen_frame_test.exs` - passed, 233 tests.
- `rtk rg -n "IN-03|weak assertion|visual contract|deferred" .planning/phases/40-verification-documentation/40-SUMMARY.md` - passed.
- `rtk mix precommit` - passed.

## Decisions Made

- Used the plan's exact simple breadcrumbs for all remaining screens; no screen retained the `["Foglet"]` fallback.
- Kept Login reset-token breadcrumb behavior intentionally simple (`["Foglet", "Login"]`) and tested token non-leak at the chrome row rather than reintroducing removed state-derived breadcrumb inference.
- Treated ScreenFrame, breadcrumb migration, PostReader compact render, and Sysop command-surface text checks as visual contract coverage because the rendered terminal text is the user-facing contract.

## Deviations from Plan

None - plan executed exactly as written.

## Known Stubs

None introduced. Stub-pattern scan hits were existing test placeholders, intentionally empty test input values, or existing "not available"/"placeholder" copy outside this plan's new behavior.

## Threat Flags

None. This plan did not add network endpoints, auth paths, file access patterns, persistence changes, or new trust-boundary behavior.

## Issues Encountered

- Existing dependency warnings from `raxol` appeared during test and precommit runs; they predate this plan and did not fail verification.
- Existing PostReader render-cache warnings and a Sysop test offline board-server rollback log appeared in affected suites; the suites still passed and these logs were not introduced by this plan.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

Ready for Plan 40-04. Breadcrumb ownership is complete for the plan's remaining screens, pending Login breadcrumb tags are gone, and targeted IN-03 hygiene is documented without expanding into a whole-suite rewrite.

## Self-Check: PASSED

- Found `.planning/phases/40-verification-documentation/40-03-SUMMARY.md`.
- Verified task commits exist: `b5ff611`, `c11f8eb`, `eaec5d4`.

---
*Phase: 40-verification-documentation*
*Completed: 2026-04-29*
