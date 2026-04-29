---
phase: 42-app-runtime-helper-extraction
plan: 42-04
subsystem: tui
tags: [elixir, raxol, tui, subscriptions, app-runtime, pubsub]

requires:
  - phase: 42-01
    provides: Foglet.TUI.App.Routing helper for screen keys, state, context, and screen module resolution
  - phase: 42-03
    provides: Foglet.TUI.App.Effects helper and App-shell delegation pattern
provides:
  - Foglet.TUI.App.Subscriptions helper for stable runtime subscriptions and dynamic PubSub topic refresh
  - App-shell delegation of subscribe/1 and topic refresh paths out of Foglet.TUI.App
  - Focused subscription helper contract tests for subscription structs and refresh effects
affects: [phase-42, tui-runtime, app-shell, pubsub-forwarding]

tech-stack:
  added: []
  patterns:
    - App runtime helpers operate on %Foglet.TUI.App{} while App remains the Raxol callback boundary
    - Subscription ownership lives in App.Subscriptions; App only decides when Raxol callbacks and update transitions call it

key-files:
  created:
    - lib/foglet_bbs/tui/app/subscriptions.ex
    - test/foglet_bbs/tui/app/subscriptions_test.exs
  modified:
    - lib/foglet_bbs/tui/app.ex
    - test/foglet_bbs/tui/app_runtime_contract_test.exs

key-decisions:
  - "Subscriptions owns heartbeat gating, chrome clock interval wiring, PubSubForwarder wiring, InitialRouteEnterForwarder wiring, user topics, screen-declared topics, and dynamic refresh diffing."
  - "Foglet.TUI.App retains only the Raxol callback integration points for subscribe/1 and post-update refresh timing."

patterns-established:
  - "App.Subscriptions helper: narrow runtime helper for subscription construction, topic derivation, and PubSubForwarder.refresh/1 gating."
  - "Helper-level tests: subscription contract assertions live beside the helper while App runtime tests retain delegation coverage."

requirements-completed: [TUI-04]

duration: 8min
completed: 2026-04-29
---

# Phase 42 Plan 04: App Subscriptions Helper Extraction Summary

**Stable TUI runtime subscriptions, screen-declared PubSub topics, and dynamic topic refresh diffing now live in `Foglet.TUI.App.Subscriptions`.**

## Performance

- **Duration:** 8 min
- **Started:** 2026-04-29T22:08:00Z
- **Completed:** 2026-04-29T22:15:27Z
- **Tasks:** 3
- **Files modified:** 4

## Accomplishments

- Created `Foglet.TUI.App.Subscriptions` with the planned public API: `subscribe/1`, `topics/1`, `screen_declared_topics/1`, and `refresh_dynamic/2`.
- Updated `Foglet.TUI.App` so `subscribe/1` delegates stable subscription construction and `update/2` delegates dynamic PubSub refresh gating.
- Added focused helper tests for heartbeat gating, chrome clock intervals, custom forwarders, screen-declared topics, and `PubSubForwarder.refresh/1` only-when-topic-lists-change behavior.

## Task Commits

Each task was committed atomically:

1. **Task 42-04-01: Create subscription helper** - `9034f869` (feat)
2. **Task 42-04-02: Delegate App subscription paths** - `9ab60312` (refactor)
3. **Task 42-04-03: Add subscription helper tests** - `b23b2135` (test)

## Files Created/Modified

- `lib/foglet_bbs/tui/app/subscriptions.ex` - New App-shell helper for runtime subscription construction, topic derivation, screen callback delegation, and dynamic refresh diffing.
- `lib/foglet_bbs/tui/app.ex` - Delegates subscription-owned behavior to `App.Subscriptions` while keeping Raxol callbacks and update timing.
- `test/foglet_bbs/tui/app/subscriptions_test.exs` - Focused helper contract tests for subscription structs and refresh broadcast behavior.
- `test/foglet_bbs/tui/app_runtime_contract_test.exs` - Replaced broad subscription contract assertions with App-level delegation coverage.

## Decisions Made

- Kept `InitialRouteEnterForwarder` in the stable subscription list so directly mounted authenticated sessions still receive the first `:on_route_enter` pass after dispatcher startup.
- Used the existing `PubSubForwarder.control_topic/1` broadcast path to prove `refresh_dynamic/2` only emits refresh control messages when effective topic lists change.

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

- Vendored `raxol` warnings continue to print during compile/test/precommit, matching prior Phase 42 summaries. Commands exited successfully.

## Verification

- `rtk rg -n "defmodule Foglet\\.TUI\\.App\\.Subscriptions" lib/foglet_bbs/tui/app/subscriptions.ex` - passed.
- `rtk rg -n "def (subscribe|topics|screen_declared_topics|refresh_dynamic)\\(" lib/foglet_bbs/tui/app/subscriptions.ex` - passed.
- `rtk rg -n "PubSubForwarder|InitialRouteEnterForwarder|subscribe_interval\\(10_000, :heartbeat_tick\\)|subscribe_interval\\(60_000, :main_menu_clock_tick\\)|refresh\\(" lib/foglet_bbs/tui/app/subscriptions.ex` - passed.
- `rtk rg -n "Subscriptions\\.(subscribe|refresh_dynamic)" lib/foglet_bbs/tui/app.ex` - passed.
- `rtk rg -n "defp (build_pubsub_topics|refresh_dynamic_subscriptions|screen_declared_topics)\\(" lib/foglet_bbs/tui/app.ex` - passed with no matches.
- `rtk rg -n "defmodule Foglet\\.TUI\\.App\\.SubscriptionsTest" test/foglet_bbs/tui/app/subscriptions_test.exs` - passed.
- `rtk rg -n "heartbeat_tick|main_menu_clock_tick|PubSubForwarder|InitialRouteEnterForwarder|screen_declared_topics|refresh_dynamic" test/foglet_bbs/tui/app/subscriptions_test.exs` - passed.
- `rtk mix test test/foglet_bbs/tui/app/subscriptions_test.exs test/foglet_bbs/tui/app_runtime_contract_test.exs` - passed, 12 tests, 0 failures.
- `rtk mix compile --warnings-as-errors` - passed.
- `rtk mix precommit` - passed.

## User Setup Required

None - no external service configuration required.

## Known Stubs

None. Stub scan found only legitimate nil/empty-list assertions and guard checks in tests/runtime code.

## Threat Flags

None. This plan moved existing subscription and PubSub refresh behavior into a helper without adding endpoints, auth paths, file access patterns, schema changes, or new trust-boundary persistence behavior.

## Next Phase Readiness

Routing, modal, effect, and subscription behavior now have narrow App runtime helpers. The remaining Phase 42 work can focus on final App consolidation while preserving `Foglet.TUI.App` as the Raxol callback integration point.

## Self-Check: PASSED

- Verified created files exist: `lib/foglet_bbs/tui/app/subscriptions.ex`, `test/foglet_bbs/tui/app/subscriptions_test.exs`, `.planning/phases/42-app-runtime-helper-extraction/42-04-SUMMARY.md`.
- Verified commits exist in git history: `9034f869`, `9ab60312`, `b23b2135`.

---
*Phase: 42-app-runtime-helper-extraction*
*Completed: 2026-04-29*
