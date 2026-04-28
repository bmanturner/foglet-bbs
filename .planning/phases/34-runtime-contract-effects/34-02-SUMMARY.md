---
phase: 34-runtime-contract-effects
plan: "02"
subsystem: tui-runtime
tags: [tui, runtime-contract, app-shell, effects, screen-state, elixir]

requires:
  - phase: 34-runtime-contract-effects
    provides: [Foglet.TUI.Screen callbacks, Foglet.TUI.Context, and Foglet.TUI.Effect values]
provides:
  - App route, screen-state, and context helper APIs
  - Generic App effect interpretation for navigation and runtime shell effects
  - Task-effect routing through Foglet.TUI.Command.task/2 into screen update/3
affects: [phase-35-screen-migration, phase-36-board-thread-migration, phase-37-post-migration, phase-38-operator-migration, phase-39-app-shell]

tech-stack:
  added: []
  patterns: [route-param-aware App context construction, screen-keyed local state storage, task result reducer routing]

key-files:
  created:
    - test/foglet_bbs/tui/app_runtime_contract_test.exs
  modified:
    - lib/foglet_bbs/tui/app.ex

key-decisions:
  - "Route params are stored separately on App state during the transition so legacy current_screen atom routing remains compatible."
  - "Test-only sample screens are registered through session_context.domain.screen_modules to prove generic routing without production-screen-specific clauses."
  - "Task effect failures are wrapped directly by the effect interpreter before reaching Foglet.TUI.Command.task/2's outer safety wrapper."

patterns-established:
  - "App helpers expose current route, screen key, screen-local state access, context construction, and effect interpretation as public runtime APIs."
  - "Navigation effects initialize only the target screen-state key and preserve legacy App fields until later migration phases."
  - "Screen task results use {:screen_task_result, screen_key, op, result} and re-enter the requesting screen's update/3 callback."

requirements-completed: [RUNTIME-02, EFFECT-02, EFFECT-03, EFFECT-04]

duration: 12min
completed: 2026-04-28
---

# Phase 34 Plan 02: App Runtime Contract Effects Summary

**Generic App runtime helpers and effect routing for navigation params, screen-local state, and reducer-owned task results.**

## Performance

- **Duration:** 12 min
- **Started:** 2026-04-28T18:20:45Z
- **Completed:** 2026-04-28T18:32:14Z
- **Tasks:** 3
- **Files modified:** 2

## Accomplishments

- Added App helper functions for current route lookup, screen-key derivation, screen-state reads/writes, and `Foglet.TUI.Context` construction.
- Added generic `apply_effect/2` and `apply_effects/2` handling for navigation, modal, session, terminal, publish, quit, and task effects.
- Added focused App runtime contract tests using a sample screen to prove route params, target state initialization, legacy field preservation, and task success/failure routing through `update/3`.

## Task Commits

1. **Task 1: Add App route and screen-state helpers** - `044285d` (feat)
2. **Task 2: Interpret navigation and non-task effects generically** - `a087c2c` (feat)
3. **Task 3: Route task effect success and failure back through screen update/3** - `ca5faeb` (feat)

## Files Created/Modified

- `lib/foglet_bbs/tui/app.ex` - Adds route/context/state helpers, generic effect interpretation, navigation initialization, and screen task result routing.
- `test/foglet_bbs/tui/app_runtime_contract_test.exs` - Proves helper behavior and generic effect routing with a test-only screen reducer.

## Decisions Made

- Stored transition route params on `%Foglet.TUI.App{}` as `route_params` while keeping `current_screen` as an atom for legacy screen compatibility.
- Registered sample screen modules through `session_context.domain.screen_modules` in tests so App does not need production-screen-specific effect clauses.
- Wrapped task effect exceptions inside the interpreter so both success and failure use the same `{:screen_task_result, screen_key, op, result}` reducer path, while still running inside `Foglet.TUI.Command.task/2`.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

- While splitting the implementation into atomic commits, an early test helper accepted only maps; it was corrected to normalize keyword attrs before the Task 1 commit.
- `rtk mix test test/foglet_bbs/tui/app_test.exs` emits existing `ShellVisibility` sandbox warnings during sysop/account render paths, but the suite passes.

## Known Stubs

None.

## Threat Flags

None - the new effect interpreter and task-result route are the planned threat-model surfaces for this plan, and no new network endpoints, auth paths, file access patterns, or schema trust boundaries were introduced.

## User Setup Required

None - no external service configuration required.

## Verification

- `rtk mix test test/foglet_bbs/tui/app_runtime_contract_test.exs` - passed, 2 tests after Task 1.
- `rtk mix test test/foglet_bbs/tui/app_runtime_contract_test.exs test/foglet_bbs/tui/app_test.exs` - passed, 126 tests after Task 2.
- `rtk mix test test/foglet_bbs/tui/app_runtime_contract_test.exs test/foglet_bbs/tui/command_test.exs` - passed, 11 tests after Task 3.
- `rtk mix test test/foglet_bbs/tui/app_runtime_contract_test.exs test/foglet_bbs/tui/app_test.exs test/foglet_bbs/tui/command_test.exs` - passed, 133 tests.
- `rtk mix compile --warnings-as-errors` - passed.

## Next Phase Readiness

Plan 03 can document the state convention and run preservation checks against concrete App runtime helpers. Later screen migration phases can request navigation and task effects without expanding App with production-screen-specific effect clauses.

## Self-Check: PASSED

- Summary file exists at `.planning/phases/34-runtime-contract-effects/34-02-SUMMARY.md`.
- Task commits found: `044285d`, `a087c2c`, `ca5faeb`.
- Key files exist: `lib/foglet_bbs/tui/app.ex` and `test/foglet_bbs/tui/app_runtime_contract_test.exs`.

---
*Phase: 34-runtime-contract-effects*
*Completed: 2026-04-28*
