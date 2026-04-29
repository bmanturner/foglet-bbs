# Phase 41: Pattern Map

## Scope Signals

Phase 41 touches two existing TUI runtime boundaries:

- Screen contract cleanup: `Foglet.TUI.Screen`, production modules under `lib/foglet_bbs/tui/screens`, TUI tests, render fixtures, layout smoke helpers, and `SCREEN_CONTRACT.md`.
- Modal submit routing: `Foglet.TUI.Effect`, `Foglet.TUI.App.apply_effect/2`, `Foglet.TUI.App.route_screen_update/3`, `Foglet.TUI.Widgets.Modal.Form`, and consumers currently using submit stashes.

## Closest Existing Patterns

### Effects

Use `Foglet.TUI.Effect` constructor functions and `%Effect{type, payload}` values as the public API. Existing examples:

- `Effect.task(op, screen_key, fun)` stores a typed payload that App interprets and routes back to screen reducers as `{:task_result, op, result}`.
- `Effect.open_modal(modal)` and `Effect.dismiss_modal()` keep modal ownership in App while screens request modal operations explicitly.

The modal-submit effect should mirror this style with a constructor like:

```elixir
Effect.modal_submit(screen_key, kind, payload)
```

and an App interpreter that routes to:

```elixir
route_screen_update(state, screen_key, {:modal_submit, kind, payload})
```

### App Routing

`Foglet.TUI.App.route_screen_update/3` is the existing reducer boundary. It loads the target screen module, reads local state with `screen_state_for/2`, builds a `Foglet.TUI.Context`, calls `module.update(message, local_state, context)`, stores the new local state, and applies returned effects.

Modal-submit routing should reuse this function rather than introducing a screen-specific path.

### Modal Form

`Foglet.TUI.Widgets.Modal.Form.handle_event/2` is already the submit boundary. The current Enter-on-last-field clause collects typed payloads, calls `on_submit`, sets `submit_state: :submitting`, and returns `:submitted`. The phase should preserve form state-machine behavior while making submit output explicit.

### State Construction

Several screens already have first-class state constructors:

- `Foglet.TUI.Screens.Account.State.new/1`
- `Foglet.TUI.Screens.Sysop.State.new/1`
- `Foglet.TUI.Screens.Moderation.State.new/1`
- `Foglet.TUI.Screens.PostReader.State.new/1`
- `Foglet.TUI.Screens.BoardList.State.new/1`
- `Foglet.TUI.Screens.ThreadList.State.new/1`

Tests that need direct state setup should call these constructors or canonical `screen.init(context)` instead of screen-level `init_screen_state/1`.

## Current Legacy/Hidden Handoffs

Known production submit handoff paths:

- `Foglet.TUI.App` uses `{Foglet.TUI.App, :pending_screen_modal_submit}`.
- `Foglet.TUI.Widgets.Modal.Form.SubmitStash` stores payloads in the process dictionary.
- `Foglet.TUI.Screens.Account.ProfileForm` and `PrefsForm` pop `SubmitStash`.
- `Foglet.TUI.Screens.Sysop.SiteForm` pops `SubmitStash`.
- `Foglet.TUI.Screens.Sysop.BoardsView` uses `{BoardsView, :pending_submit}`.

Known production screen compatibility helpers include screen modules under `lib/foglet_bbs/tui/screens` exposing public `render/1`, `handle_key/2`, or `init_screen_state/1`. Non-screen helper modules may keep their own `render/2` or `handle_key` APIs when they are not implementing old `Foglet.TUI.Screen` callbacks.

## Planning Risks

- Removing the behavior callbacks before migrating `@impl true` annotations can create compile failures. Plans should order compatibility-helper migration before final behavior removal or keep the compile step in the same plan.
- `Modal.Form` submit-state locking is user-visible. The explicit effect path must not accidentally leave forms stuck in `:submitting` after synchronous visible failures.
- Project tests use unrelated `Process.put/get` fakes. Acceptance checks must distinguish those from modal-submit payload handoffs.
