# Stack Research: v2.0 TUI Runtime Shell & Screen Update Loops

## Question

What stack additions or changes are needed to move Foglet from an App-centralized TUI update model to screen-owned mini update loops?

## Findings

No new external dependency is needed.

The existing stack already has the primitives required:

- `Raxol.Core.Runtime.Application` provides `init/1`, `update/2`, `view/1`, and `subscribe/1`.
- `Raxol.Core.Runtime.Command` already supports off-process task commands returned from `update/2`.
- `Foglet.TUI.Command.task/2` wraps task work with the current task-result conventions.
- Widgets already model stateful local reducers with `init/1`, `handle_event/2`, and `render/2`.
- Screen modules already implement a lighter `Foglet.TUI.Screen` behavior with `render/1`, `handle_key/2`, and optional `init_screen_state/1`.

## Needed Internal Modules

- `Foglet.TUI.Context` - immutable data passed into screens: user, session context, session pid, terminal size, route params, theme access, and domain overrides.
- `Foglet.TUI.Effect` - explicit effect values for `App` to interpret.
- Revised `Foglet.TUI.Screen` behavior - `init/1`, `update/3`, `render/2`.
- Optional `Foglet.TUI.ScreenRuntime` helper - registry/runtime logic for route-to-module lookup and state initialization.

## What Not To Add

- No GenServer per screen. The App/Raxol process remains the runtime owner.
- No browser client, LiveView surface, or JavaScript state model.
- No new persistence layer for TUI state. Screen state remains ephemeral and reconstructable.
- No dependency on a state-machine library unless later phases prove a real need.

## Integration Points

- `lib/foglet_bbs/tui/app.ex` - central runtime shell and effect interpreter.
- `lib/foglet_bbs/tui/screen.ex` - behavior contract.
- `lib/foglet_bbs/tui/screens/*` - screen migrations.
- `lib/foglet_bbs/tui/render_fixtures.ex` and `test/foglet_bbs/tui/layout_smoke_test.exs` - render fixture updates.
- `test/foglet_bbs/tui/app_test.exs` and screen tests - reducer/effect coverage.
