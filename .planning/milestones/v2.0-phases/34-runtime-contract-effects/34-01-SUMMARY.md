---
phase: 34-runtime-contract-effects
plan: "01"
subsystem: tui-runtime
tags: [tui, runtime-contract, screen-contract, context, effects, elixir]

requires:
  - phase: 34-runtime-contract-effects
    provides: [phase specification, context, and research for TUI runtime contracts]
provides:
  - Foglet.TUI.Screen init/update/render callback contract
  - Foglet.TUI.Context screen-facing runtime boundary
  - Foglet.TUI.Effect explicit effect constructors
affects: [phase-35-screen-migration, phase-36-board-thread-migration, phase-37-post-migration, phase-38-operator-migration, phase-39-app-shell]

tech-stack:
  added: []
  patterns: [screen-local reducer callbacks, narrow TUI context struct, explicit runtime effect values]

key-files:
  created:
    - lib/foglet_bbs/tui/context.ex
    - lib/foglet_bbs/tui/effect.ex
    - test/foglet_bbs/tui/screen_test.exs
    - test/foglet_bbs/tui/context_test.exs
    - test/foglet_bbs/tui/effect_test.exs
  modified:
    - lib/foglet_bbs/tui/screen.ex

key-decisions:
  - "New screen callbacks are present but optional during phases 34-38 so existing production screens with the legacy behaviour keep compiling until their migration plans."
  - "Foglet.TUI.Context rejects unknown fields instead of silently accepting App-owned screen storage."
  - "Foglet.TUI.Effect constructors return precise effect variants for Dialyzer-friendly contracts."

patterns-established:
  - "Screen reducers initialize and update screen-local state using Foglet.TUI.Context instead of broad App structs."
  - "Screen-facing runtime data is copied into a narrow context value with explicit defaults."
  - "Runtime work is represented as %Foglet.TUI.Effect{} values with typed constructors."

requirements-completed: [RUNTIME-01, RUNTIME-03, EFFECT-01]

duration: 8min
completed: 2026-04-28
---

# Phase 34 Plan 01: Runtime Contract Effects Summary

**Screen-local TUI runtime contracts with a narrow context boundary and explicit effect values for future App-shell migration.**

## Performance

- **Duration:** 8 min
- **Started:** 2026-04-28T18:09:09Z
- **Completed:** 2026-04-28T18:16:32Z
- **Tasks:** 3
- **Files modified:** 6

## Accomplishments

- Added `Foglet.TUI.Screen` target callbacks for `init/1`, `update/3`, and `render/2` over screen-local state plus `Foglet.TUI.Context`.
- Added `Foglet.TUI.Context` with explicit defaults and a guard against leaking App-owned screen storage fields.
- Added `Foglet.TUI.Effect` constructors for navigation, tasks, modal open/dismiss, publish, session, terminal size, and quit effects.
- Added focused tests proving the new contracts without migrating production screens.

## Task Commits

1. **Task 1: Add the new Screen behavior callbacks without forcing production migrations** - `b770d49` (feat)
2. **Task 2: Add Foglet.TUI.Context as the screen-facing runtime boundary** - `d681e1d` (feat)
3. **Task 3: Add Foglet.TUI.Effect constructors for generic runtime requests** - `da54e6b` (feat)

## Files Created/Modified

- `lib/foglet_bbs/tui/screen.ex` - Documents and types the new screen callback contract while keeping transitional legacy callbacks.
- `lib/foglet_bbs/tui/context.ex` - Defines the narrow screen-facing runtime context and default construction.
- `lib/foglet_bbs/tui/effect.ex` - Defines explicit runtime effect values and constructors.
- `test/foglet_bbs/tui/screen_test.exs` - Proves a sample stateful screen can init/update/render without `%Foglet.TUI.App{}`.
- `test/foglet_bbs/tui/context_test.exs` - Proves context defaults, accepted fields, domain defaults, and storage-field exclusion.
- `test/foglet_bbs/tui/effect_test.exs` - Proves every effect constructor shape and lazy task function behavior.

## Decisions Made

- Kept the new `Screen` callbacks optional during the migration window so existing `@behaviour Foglet.TUI.Screen` modules do not emit missing-callback warnings before phases 35-38 migrate them.
- Made `Context.new/1` reject unknown fields, which turns the “no App storage leakage” threat mitigation into an enforced boundary.
- Split `Effect` return types into precise variants so Dialyzer verifies the constructor contracts cleanly.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug] Tightened Effect constructor specs for Dialyzer**
- **Found during:** Task 3 precommit verification
- **Issue:** Broad constructor specs returning `t()` or a shared modal union were supertypes of the inferred success typings.
- **Fix:** Added precise effect variant types and exact constructor specs, including separate modal open/dismiss variants.
- **Files modified:** `lib/foglet_bbs/tui/effect.ex`
- **Verification:** `rtk mix test test/foglet_bbs/tui/effect_test.exs`, `rtk mix compile --warnings-as-errors`, `rtk mix precommit`
- **Committed in:** `da54e6b`

---

**Total deviations:** 1 auto-fixed (Rule 1)
**Impact on plan:** No scope change. The fix made the new effect contract stricter and more checkable.

## Issues Encountered

- `rtk mix precommit` initially failed in Dialyzer on effect constructor spec precision. The specs were narrowed and the Task 3 commit was amended.
- A test assertion attempted to match on `self()` directly in a pattern during Task 3. It was corrected before the task commit.

## Known Stubs

None.

## Threat Flags

None - the new context and effect boundaries are the planned threat-model surface for this plan, and no new network endpoints, auth paths, file access patterns, or schema trust boundaries were introduced.

## User Setup Required

None - no external service configuration required.

## Verification

- `rtk mix test test/foglet_bbs/tui/screen_test.exs` - passed
- `rtk mix test test/foglet_bbs/tui/context_test.exs` - passed
- `rtk mix test test/foglet_bbs/tui/effect_test.exs` - passed
- `rtk mix test test/foglet_bbs/tui/screen_test.exs test/foglet_bbs/tui/context_test.exs test/foglet_bbs/tui/effect_test.exs` - passed, 14 tests
- `rtk mix compile --warnings-as-errors` - passed
- `rtk mix precommit` - passed

## Next Phase Readiness

Plan 02 can build App runtime helpers and effect interpretation against stable `Screen`, `Context`, and `Effect` contracts. Existing production screens still use the transitional legacy callbacks until their migration phases.

## Self-Check: PASSED

- Summary file exists at `.planning/phases/34-runtime-contract-effects/34-01-SUMMARY.md`.
- Task commits found: `b770d49`, `d681e1d`, `da54e6b`.
- Key files exist: `lib/foglet_bbs/tui/screen.ex`, `lib/foglet_bbs/tui/context.ex`, `lib/foglet_bbs/tui/effect.ex`, and all three focused test files.

---
*Phase: 34-runtime-contract-effects*
*Completed: 2026-04-28*
