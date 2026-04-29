---
phase: 34-runtime-contract-effects
plan: "03"
subsystem: tui-runtime
tags: [tui, runtime-contract, state-conventions, app-preservation, elixir]

requires:
  - phase: 34-runtime-contract-effects
    provides: [Foglet.TUI.Screen callbacks, Context boundary, Effect values, and App runtime helpers]
provides:
  - Screen stateful and stateless convention documentation
  - Architecture documentation for the Context/Effect/init-update-render foundation
  - Preservation checks for App init, modal precedence, SizeGate purity, and render smoke coverage
affects: [phase-35-screen-migration, phase-36-board-thread-migration, phase-37-post-migration, phase-38-operator-migration, phase-39-app-shell]

tech-stack:
  added: []
  patterns: [first-class screen state structs, explicit stateless screens, render-time SizeGate preservation]

key-files:
  created:
    - .planning/phases/34-runtime-contract-effects/34-03-SUMMARY.md
  modified:
    - lib/foglet_bbs/tui/screen.ex
    - docs/ARCHITECTURE.md
    - test/foglet_bbs/tui/screen_test.exs
    - test/foglet_bbs/tui/app_test.exs

key-decisions:
  - "Stateful screens must own first-class state structs with new/1 or document a local state type."
  - "Stateless screens must explicitly return :stateless or %{} from init/1 and avoid App-owned local storage."
  - "Phase 34 preserves existing App and smoke render behavior while deferring production migrations to phases 35-38 and final App cleanup to phase 39."

patterns-established:
  - "Screen convention tests use sample reducers and state shapes rather than brittle text-only assertions."
  - "Preservation tests assert App state invariants around modal precedence and render-time SizeGate behavior."

requirements-completed: [STATE-01, RUNTIME-01]

duration: 4min
completed: 2026-04-28
---

# Phase 34 Plan 03: Runtime Contract Preservation Summary

**State conventions and preservation checks that lock the TUI runtime foundation before production screen migrations.**

## Performance

- **Duration:** 4 min
- **Started:** 2026-04-28T18:36:23Z
- **Completed:** 2026-04-28T18:40:36Z
- **Tasks:** 3
- **Files modified:** 4

## Accomplishments

- Documented the stateful/stateless screen convention directly in `Foglet.TUI.Screen`.
- Updated the TUI/Raxol architecture section to name `Foglet.TUI.Context`, `Foglet.TUI.Effect`, and the `init/update/render` foundation without adding browser workflows.
- Added representative stateful and stateless sample screen tests.
- Added App preservation checks for modal precedence and SizeGate render-time purity while keeping the existing layout smoke suite green.
- Ran the exact targeted Phase 34 suite and compile gate.

## Task Commits

1. **Task 1: Document stateful and stateless screen conventions** - `f8da9d9` (docs)
2. **Task 2: Add preservation checks for current App behavior and smoke rendering** - `2bae5af` (test)
3. **Task 3: Run the Phase 34 targeted suite and compile gate** - `5ea81c8` (test, empty verification commit)

## Files Created/Modified

- `lib/foglet_bbs/tui/screen.ex` - Adds the state convention rules and migration boundary notes.
- `docs/ARCHITECTURE.md` - Documents the Context/Effect/init-update-render runtime foundation in the SSH-first TUI layer.
- `test/foglet_bbs/tui/screen_test.exs` - Adds `StatefulSample` and `StatelessSample` contract examples.
- `test/foglet_bbs/tui/app_test.exs` - Adds modal precedence and SizeGate state-preservation regression checks.

## Decisions Made

- Kept the new screen convention as documentation and representative tests, leaving production screen family migrations to phases 35-38.
- Used a pure validation commit for Task 3 because the task changed no files but needed an atomic task record.
- Treated existing App-test `ShellVisibility` sandbox warnings as non-blocking because the targeted suite passed.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

- `rtk mix test ... app_test.exs ... layout_smoke_test.exs` and the full targeted Phase 34 suite emit existing `ShellVisibility` Ecto sandbox warnings on some sysop/account render paths. The commands exit 0.
- `rtk mix compile --warnings-as-errors` prints vendored Raxol warnings before compiling `foglet_bbs`, but the command exits 0.

## Known Stubs

None.

## Threat Flags

None - this plan introduced no new network endpoints, auth paths, file access patterns, or schema trust boundaries.

## User Setup Required

None - no external service configuration required.

## Verification

- `rtk mix test test/foglet_bbs/tui/screen_test.exs` - passed, 3 tests.
- `rtk mix test test/foglet_bbs/tui/app_test.exs test/foglet_bbs/tui/layout_smoke_test.exs` - passed, 207 tests.
- `rtk mix test test/foglet_bbs/tui/screen_test.exs test/foglet_bbs/tui/context_test.exs test/foglet_bbs/tui/effect_test.exs test/foglet_bbs/tui/app_runtime_contract_test.exs test/foglet_bbs/tui/app_test.exs test/foglet_bbs/tui/command_test.exs test/foglet_bbs/tui/layout_smoke_test.exs` - passed, 234 tests.
- `rtk mix compile --warnings-as-errors` - passed.

## Next Phase Readiness

Phase 34 is ready for verification and transition. Later phases can migrate production screen families using the documented state convention and the Context/Effect/App runtime helper foundation from Plans 01-03.

## Self-Check: PASSED

- Summary file exists at `.planning/phases/34-runtime-contract-effects/34-03-SUMMARY.md`.
- Key files exist: `lib/foglet_bbs/tui/screen.ex`, `docs/ARCHITECTURE.md`, `test/foglet_bbs/tui/screen_test.exs`, and `test/foglet_bbs/tui/app_test.exs`.
- Task commits found: `f8da9d9`, `2bae5af`, `5ea81c8`.

---
*Phase: 34-runtime-contract-effects*
*Completed: 2026-04-28*
