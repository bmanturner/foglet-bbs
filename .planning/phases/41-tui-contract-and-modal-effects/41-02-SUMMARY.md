---
phase: 41-tui-contract-and-modal-effects
plan: 41-02
subsystem: tui
tags: [elixir, raxol, tui, screen-contract, testing]

requires:
  - phase: 41-tui-contract-and-modal-effects
    provides: production screens expose only canonical screen callbacks (41-01)
  - phase: 41-tui-contract-and-modal-effects
    provides: modal form submit effects route through App to screen reducers (41-03)
provides:
  - canonical TUI tests and smoke helpers using Screen.init/update/render or State constructors
  - layout smoke and render fixture paths free of screen-level init helper dependency
  - post-cleanup SCREEN_CONTRACT.md documentation
affects: [tui-screen-contract, layout-smoke-tests, screen-tests, render-fixtures]

tech-stack:
  added: []
  patterns:
    - direct screen tests build Foglet.TUI.Context and call Screen.update/render
    - smoke helpers render local state through canonical render/2
    - state-only tests use sibling State.new/1 constructors

key-files:
  created:
    - .planning/phases/41-tui-contract-and-modal-effects/41-02-SUMMARY.md
  modified:
    - lib/foglet_bbs/tui/screens/post_composer.ex
    - lib/foglet_bbs/tui/SCREEN_CONTRACT.md
    - test/foglet_bbs/tui/layout_smoke_test.exs
    - test/support/foglet/tui/layout_smoke/account_helper.ex
    - test/support/foglet/tui/layout_smoke/moderation_helper.ex
    - test/support/foglet/tui/layout_smoke/sysop_helper.ex
    - test/foglet_bbs/tui/app_test.exs
    - test/foglet_bbs/tui/screens/login_test.exs
    - test/foglet_bbs/tui/screens/post_composer_test.exs
    - test/foglet_bbs/tui/screens/account_test.exs
    - test/foglet_bbs/tui/screens/sysop_test.exs
    - test/foglet_bbs/tui/screens/moderation_test.exs
    - test/foglet_bbs/tui/screens/main_menu_test.exs

key-decisions:
  - "Kept direct screen tests at reducer/render boundaries by adding test-local helpers that build Context and call update/3 or render/2."
  - "Used sibling State.new/1 constructors for state-only setup instead of restoring screen-level setup helpers."
  - "Updated modal-related screen tests to align with the explicit App modal-submit failure behavior from plan 41-03."

patterns-established:
  - "Test fixtures should use Screen.init(context), Screen.update(message, state, context), Screen.render(state, context), or explicit State.new/1."
  - "Layout smoke helper modules should convert App-shaped fixture maps into local state plus Context before rendering."

requirements-completed: [TUI-02]

duration: 2h
completed: 2026-04-29
---

# Phase 41 Plan 41-02: Canonical TUI Test Contract Summary

**TUI tests, smoke helpers, and screen contract docs now exercise the canonical init/update/render path without screen-level setup helpers.**

## Performance

- **Duration:** 2h
- **Started:** 2026-04-29T17:30:00Z
- **Completed:** 2026-04-29T19:30:33Z
- **Tasks:** 4
- **Files modified:** 14

## Accomplishments

- Migrated layout smoke setup and render helpers to local screen state plus `Foglet.TUI.Context`.
- Migrated App and screen tests from `init_screen_state/1` to sibling `State.new/1`, `Screen.init/1`, `Screen.update/3`, and `Screen.render/2`.
- Removed the legacy callback vocabulary from `SCREEN_CONTRACT.md` and documented the canonical screen callbacks only.
- Verified the TUI test surface has no remaining `init_screen_state` references.

## Task Commits

Each task was committed atomically:

1. **Task 41-02-01: Layout smoke and render fixture setup** - `283ac8fb` (test)
2. **Task 41-02-02: App test state setup** - `3d946926` (test)
3. **Task 41-02-03: Screen-specific tests** - `b8c12b8b` (test)
4. **Task 41-02-04: Screen contract docs** - `ec8c921c` (docs)

**Plan metadata:** pending final docs commit.

## Files Created/Modified

- `.planning/phases/41-tui-contract-and-modal-effects/41-02-SUMMARY.md` - Execution summary and verification record.
- `lib/foglet_bbs/tui/screens/post_composer.ex` - Fixed canonical edit render input focus handling.
- `lib/foglet_bbs/tui/SCREEN_CONTRACT.md` - Documents only `init/1`, `update/3`, `render/2`, and optional `subscriptions/2`.
- `test/foglet_bbs/tui/layout_smoke_test.exs` - Layout smoke setup uses canonical screen state/render paths.
- `test/support/foglet/tui/layout_smoke/account_helper.ex` - Account smoke helper renders through canonical context.
- `test/support/foglet/tui/layout_smoke/moderation_helper.ex` - Moderation smoke helper renders through canonical context.
- `test/support/foglet/tui/layout_smoke/sysop_helper.ex` - Sysop smoke helper renders through canonical context.
- `test/foglet_bbs/tui/app_test.exs` - App tests use explicit state constructors for state setup.
- `test/foglet_bbs/tui/screens/login_test.exs` - Login tests use canonical initialization.
- `test/foglet_bbs/tui/screens/post_composer_test.exs` - Post composer tests use explicit state construction.
- `test/foglet_bbs/tui/screens/account_test.exs` - Account tests use canonical update/render helpers and 41-03 modal submit behavior.
- `test/foglet_bbs/tui/screens/sysop_test.exs` - Sysop tests use canonical update/render helpers.
- `test/foglet_bbs/tui/screens/moderation_test.exs` - Moderation tests use canonical update/render helpers.
- `test/foglet_bbs/tui/screens/main_menu_test.exs` - Removed legacy callback residue.

## Decisions Made

- Kept direct screen tests close to the screen contract by building `Foglet.TUI.Context` explicitly and calling `update/3` or `render/2`.
- Preserved state-focused test setup with sibling `State.new/1` constructors instead of adding compatibility helpers back to screen modules.
- Matched Account modal tests to the 41-03 effect pipeline, where invalid modal submissions produce visible modal errors before task result recovery paths.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Fixed canonical PostComposer render focus handling**
- **Found during:** Task 41-02-01 (Layout smoke and render fixture setup)
- **Issue:** `PostComposer.render/2` passed an App-shaped frame map into `render_input/4`, which read `state.mode` and failed once smoke tests used the canonical render path.
- **Fix:** Changed `render_input/4` to receive an explicit focus boolean and passed `true` from edit-body rendering.
- **Files modified:** `lib/foglet_bbs/tui/screens/post_composer.ex`
- **Verification:** `rtk mix test test/foglet_bbs/tui/layout_smoke_test.exs`; `rtk mix precommit`
- **Committed in:** `283ac8fb`

**2. [Rule 3 - Blocking] Migrated support helper and MainMenu legacy residue outside the nominal task file list**
- **Found during:** Tasks 41-02-01 and 41-02-03
- **Issue:** Macro-expanded layout smoke helper modules and a MainMenu negative assertion still referenced the removed legacy screen helper name and blocked final grep/test verification.
- **Fix:** Added canonical support helper render paths and removed the obsolete MainMenu assertion.
- **Files modified:** `test/support/foglet/tui/layout_smoke/account_helper.ex`, `test/support/foglet/tui/layout_smoke/moderation_helper.ex`, `test/support/foglet/tui/layout_smoke/sysop_helper.ex`, `test/foglet_bbs/tui/screens/main_menu_test.exs`
- **Verification:** `rtk rg -n "init_screen_state" test/foglet_bbs/tui lib/foglet_bbs/tui/SCREEN_CONTRACT.md`; focused TUI test suites
- **Committed in:** `283ac8fb`, `b8c12b8b`

**3. [Rule 3 - Blocking] Aligned screen tests with 41-03 modal submit effect behavior**
- **Found during:** Task 41-02-03 (Screen-specific tests)
- **Issue:** Account screen tests still expected the older modal submit process behavior after 41-03 routed modal submissions through App effects and visible invalid-submit modal errors.
- **Fix:** Updated the affected tests to assert the App/effect-visible behavior while preserving form error recovery assertions after task results.
- **Files modified:** `test/foglet_bbs/tui/screens/account_test.exs`
- **Verification:** Focused screen test suite; `rtk mix precommit`
- **Committed in:** `b8c12b8b`

---

**Total deviations:** 3 auto-fixed (1 Rule 1, 2 Rule 3)
**Impact on plan:** All fixes were required for the canonical screen contract migration to run through real render/update paths. No product-surface scope was added.

## Issues Encountered

None beyond the auto-fixed issues above.

## Known Stubs

None introduced. The stub scan found existing test placeholders and intentional empty/nil state assertions only; no new unimplemented UI behavior was added.

## Threat Flags

None. This plan changed TUI tests, smoke helpers, one screen render bug, and contract documentation only; it added no new network endpoints, auth paths, file access paths, schema changes, or trust-boundary behavior.

## User Setup Required

None - no external service configuration required.

## Verification

- `rtk mix test test/foglet_bbs/tui/layout_smoke_test.exs`
- `rtk mix test test/foglet_bbs/tui/app_test.exs`
- `rtk mix test test/foglet_bbs/tui/screens/login_test.exs test/foglet_bbs/tui/screens/post_composer_test.exs test/foglet_bbs/tui/screens/account_test.exs test/foglet_bbs/tui/screens/sysop_test.exs test/foglet_bbs/tui/screens/moderation_test.exs test/foglet_bbs/tui/screens/main_menu_test.exs`
- `rtk rg -n "init_screen_state" test/foglet_bbs/tui lib/foglet_bbs/tui/SCREEN_CONTRACT.md`
- `rtk rg -n "init_screen_state|render/1|handle_key/2|compatibility" lib/foglet_bbs/tui/SCREEN_CONTRACT.md`
- `rtk rg -n "init/1|update/3|render/2|subscriptions/2" lib/foglet_bbs/tui/SCREEN_CONTRACT.md`
- `rtk mix precommit`

## Next Phase Readiness

The TUI test suite and screen contract documentation no longer depend on screen-level compatibility helpers. Future App/runtime extraction work can assume tests target canonical screen lifecycle boundaries.

## Self-Check: PASSED

- Summary file exists at `.planning/phases/41-tui-contract-and-modal-effects/41-02-SUMMARY.md`.
- Task commits found: `283ac8fb`, `3d946926`, `b8c12b8b`, `ec8c921c`.
- No STATE.md or ROADMAP.md updates were made by this executor.

---
*Phase: 41-tui-contract-and-modal-effects*
*Completed: 2026-04-29*
