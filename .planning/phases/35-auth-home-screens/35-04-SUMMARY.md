---
phase: 35-auth-home-screens
plan: "04"
subsystem: tui
tags: [elixir, raxol, tui, auth, main-menu, screen-contract, app-shell]

requires:
  - phase: 34-runtime-contract-effects
    provides: [Foglet.TUI.Context, Foglet.TUI.Effect, generic App screen task routing]
  - phase: 35-auth-home-screens
    plan: "01"
    provides: [Login screen reducer ownership]
  - phase: 35-auth-home-screens
    plan: "02"
    provides: [Register and Verify screen reducer ownership]
  - phase: 35-auth-home-screens
    plan: "03"
    provides: [MainMenu state struct and oneliner reducer ownership]
provides:
  - App local-flow cleanup for Phase 35 auth/home screen-specific clauses
  - Generic modal submit routing into screen reducers
  - Target screen ownership documentation
  - Integrated auth/home validation and precommit coverage
affects: [phase-35-auth-home-screens, phase-36-board-thread-directory-flow, phase-39-app-shell-cleanup, tui-runtime]

tech-stack:
  added: []
  patterns:
    - App routes MainMenu entry loads through MainMenu.update/3 instead of App do_update clauses
    - Modal form submit callbacks stash generic {screen_key, kind, payload} targets for App to route
    - Render smoke tests drive migrated screens through App.view/1 and App.update/2

key-files:
  created:
    - .planning/phases/35-auth-home-screens/35-04-SUMMARY.md
  modified:
    - lib/foglet_bbs/tui/app.ex
    - lib/foglet_bbs/tui/render_fixtures.ex
    - lib/foglet_bbs/tui/screens/login.ex
    - lib/foglet_bbs/tui/screens/register.ex
    - lib/foglet_bbs/tui/screens/verify.ex
    - lib/foglet_bbs/tui/screens/main_menu.ex
    - lib/foglet_bbs/tui/screens/main_menu/state.ex
    - test/foglet_bbs/tui/app_test.exs
    - test/foglet_bbs/tui/layout_smoke_test.exs

key-decisions:
  - "App no longer carries Phase 35 production local-flow do_update clauses for Login, Register, Verify, or MainMenu/oneliners."
  - "MainMenu initial and navigation loads enter through MainMenu.update/3 using the generic screen reducer/effect path."
  - "Modal form submit routing remains App runtime plumbing but carries only a generic screen key, submit kind, and payload."
  - "Phase 35 render smoke coverage now exercises migrated screens through App.view/1 and App.update/2."

patterns-established:
  - "Screen-owned modal submit handling: forms set a generic pending submit target; App routes {:modal_submit, kind, payload} to the screen reducer."
  - "Migrated screen smoke tests should render via App.view/1 instead of legacy render/1 callbacks."

requirements-completed: [SCREEN-01, SCREEN-02]

duration: 15min
completed: 2026-04-28
---

# Phase 35 Plan 04: Auth Home Integration Cleanup Summary

**Auth/home screens now own their local flows end to end while App routes effects, modal submits, and task results generically.**

## Performance

- **Duration:** 15 min
- **Started:** 2026-04-28T20:16:44Z
- **Completed:** 2026-04-28T20:31:06Z
- **Tasks:** 3
- **Files modified:** 9

## Accomplishments

- Removed App-owned Phase 35 local-flow clauses for auth/home events and oneliner results.
- Routed authenticated MainMenu entry loads through `MainMenu.update/3` and `Effect.task/3`.
- Removed App top-level oneliner fields so recent rows, selection, and pending hide target live in `MainMenu.State`.
- Updated screen/module docs to describe reducer-owned state and App as runtime/effect interpreter.
- Updated auth/home smoke tests to use migrated `App.view/1` and `App.update/2` boundaries.

## Task Commits

1. **Task 1: Remove Phase 35 local-flow clauses from App or reduce them to generic runtime plumbing** - `ffbf581` (feat)
2. **Task 2: Update target screen docs and state docs for the new ownership boundary** - `ee1cb61` (docs)
3. **Task 3: Run integrated auth/home preservation checks and compile gate** - `df16f31` (fix)

## Files Created/Modified

- `lib/foglet_bbs/tui/app.ex` - Removed Phase 35 App local-flow handlers and top-level MainMenu oneliner state; kept generic effect, modal, and task routing.
- `lib/foglet_bbs/tui/render_fixtures.ex` - Seeds MainMenu render fixtures through `screen_state[:main_menu]`.
- `lib/foglet_bbs/tui/screens/login.ex` - Documents Login-owned reducer boundary.
- `lib/foglet_bbs/tui/screens/register.ex` - Documents Register-owned reducer boundary.
- `lib/foglet_bbs/tui/screens/verify.ex` - Documents Verify-owned reducer boundary.
- `lib/foglet_bbs/tui/screens/main_menu.ex` - Adds reducer load entry and documents MainMenu ownership.
- `lib/foglet_bbs/tui/screens/main_menu/state.ex` - Documents MainMenu state fields.
- `test/foglet_bbs/tui/app_test.exs` - Updates App assertions around generic MainMenu load routing.
- `test/foglet_bbs/tui/layout_smoke_test.exs` - Moves migrated screen smoke checks to App render/update paths.

## Decisions Made

- MainMenu load refresh is a screen reducer message (`:load_oneliners`) rather than a production-specific App `do_update/2` clause.
- App keeps only generic form modal submit plumbing: the submit callback records `{screen_key, kind, payload}`, and App routes `{:modal_submit, kind, payload}` to the target reducer.
- Render fixtures and smoke tests should seed/read migrated state through `screen_state` to avoid reintroducing App-owned fields.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] Updated render fixtures after removing App oneliner fields**
- **Found during:** Task 1 (Remove Phase 35 local-flow clauses)
- **Issue:** `Foglet.TUI.RenderFixtures` still built `%App{recent_oneliners: ...}` after those fields were removed from App.
- **Fix:** Seeded MainMenu fixture rows through `App.put_screen_state/3` and `MainMenu.State.from_entries/2`.
- **Files modified:** `lib/foglet_bbs/tui/render_fixtures.ex`
- **Verification:** `rtk mix test test/foglet_bbs/tui/app_test.exs`; full targeted validation.
- **Committed in:** `ffbf581`

**2. [Rule 3 - Blocking] Migrated smoke tests away from removed callbacks**
- **Found during:** Task 3 (Run integrated auth/home preservation checks)
- **Issue:** `layout_smoke_test.exs` still called removed `render/1` and `handle_key/2` callbacks on Login, Register, Verify, and MainMenu.
- **Fix:** Added smoke helpers that render migrated screens via `App.view/1` and drive Login reset flows via `App.update/2`.
- **Files modified:** `test/foglet_bbs/tui/layout_smoke_test.exs`
- **Verification:** `rtk mix test test/foglet_bbs/tui/layout_smoke_test.exs`; full targeted validation.
- **Committed in:** `df16f31`

**3. [Rule 1 - Bug] Removed impossible route_params fallback**
- **Found during:** Task 3 (`rtk mix precommit`)
- **Issue:** Dialyzer flagged `state.route_params || %{}` as a guard failure because `route_params` is typed as a map.
- **Fix:** Passed `state.route_params` directly to route screen initialization.
- **Files modified:** `lib/foglet_bbs/tui/app.ex`
- **Verification:** `rtk mix precommit`
- **Committed in:** `df16f31`

---

**Total deviations:** 3 auto-fixed (1 bug, 2 blocking)
**Impact on plan:** All fixes were required to complete the App cleanup and keep migrated screens covered. No product behavior scope was added.

## Issues Encountered

- A parallel staging attempt briefly created a stale Git index lock. It cleared before further staging and no files were lost or reverted.
- Existing App tests still emit sandbox ownership warnings from unrelated Sysop/ShellVisibility config reads, but all targeted tests and precommit pass.
- Vendored `raxol` still prints dependency warnings during compile/precommit, but exits 0.

## Known Stubs

None. Stub scan matches were UI placeholder strings, ordinary "User session is not available" error copy, and test assertions; none are goal-blocking stubs.

## Threat Flags

None. This plan did not add new network endpoints, auth paths, file access patterns, schemas, or trust boundaries beyond the declared App runtime -> screen reducer and modal-submit routing surface.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

Phase 35 is ready to close. Phase 36 can migrate BoardList/ThreadList using the same pattern: screen-owned load/result reducers with App limited to runtime effect interpretation.

## Verification

- `rtk mix test test/foglet_bbs/tui/app_test.exs` - passed
- `rtk mix compile --warnings-as-errors` - passed
- `rtk mix test test/foglet_bbs/tui/screens/login_test.exs test/foglet_bbs/tui/screens/register_test.exs test/foglet_bbs/tui/screens/verify_test.exs test/foglet_bbs/tui/screens/main_menu_test.exs test/foglet_bbs/tui/app_test.exs test/foglet_bbs/tui/layout_smoke_test.exs && rtk mix compile --warnings-as-errors` - passed
- `rtk rg -n "defp do_update\\(\\{:(register_wizard|verify_event|login_result|load_oneliners|oneliners_loaded|open_oneliner_composer|submit_oneliner|oneliner_created|open_hide_oneliner_modal|submit_hide_oneliner|oneliner_hidden)" lib/foglet_bbs/tui/app.ex` - no matches
- `rtk mix precommit` - passed

## Self-Check: PASSED

- `FOUND_SUMMARY` for `.planning/phases/35-auth-home-screens/35-04-SUMMARY.md`
- Found task commit `ffbf581`
- Found task commit `ee1cb61`
- Found task commit `df16f31`
- Stub scan found no goal-blocking implementation stubs in modified files.

---
*Phase: 35-auth-home-screens*
*Completed: 2026-04-28*
