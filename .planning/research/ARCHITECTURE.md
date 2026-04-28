# Architecture Research: v2.0 TUI Runtime Shell & Screen Update Loops

## Current Shape

`Foglet.TUI.App.update/2` normalizes incoming messages and then routes through many `do_update/2` clauses. Some clauses are generic runtime concerns, such as terminal resize, modal handling, heartbeat, session replacement, and command result re-dispatch. Many clauses are screen-specific, such as:

- `{:boards_loaded, boards}` resetting BoardList tree state.
- Board subscription results writing BoardList feedback.
- `{:threads_loaded, threads}` storing top-level `current_thread_list`.
- `{:posts_loaded, posts, opts}` warming PostReader render cache.
- `{:moderation_workspace_loaded, result}` writing Moderation state.
- `{:sysop_*_loaded, result}` writing Sysop tab slots.
- Account save results reaching into Account state.

Screens currently receive the whole App state and return `{:update, app_state, commands}`. That lets screens mutate route, top-level fields, and `screen_state` directly. It also forces App to know how to complete screen-local work.

## Target Shape

`Foglet.TUI.App` remains the only process-level shell:

- Normalize Raxol events into plain messages.
- Short-circuit size-gated input.
- Route modal input to generic modal handling.
- Route active-screen input/messages to the active screen.
- Store route and screen-state map.
- Interpret effects into App changes and Raxol commands.
- Own subscriptions, heartbeat, session replacement, terminal size, and task execution.

Screens own local reducers:

```elixir
@callback init(Foglet.TUI.Context.t()) ::
  {state(), [Foglet.TUI.Effect.t()]}

@callback update(term(), state(), Foglet.TUI.Context.t()) ::
  {state(), [Foglet.TUI.Effect.t()]}

@callback render(state(), Foglet.TUI.Context.t()) ::
  Raxol.renderable()
```

## App State Direction

```elixir
%Foglet.TUI.App{
  route: :board_list,
  current_user: user,
  session_context: session_context,
  session_pid: pid,
  terminal_size: {cols, rows},
  modal: modal,
  screens: %{
    board_list: %Foglet.TUI.Screens.BoardList.State{},
    thread_list: %Foglet.TUI.Screens.ThreadList.State{}
  }
}
```

Top-level App fields should be retained only when they are truly runtime/global. Board/thread/post lists are candidates to move into route params or screen-local states.

## Effect Direction

Likely effect values:

- `{:navigate, route}` or `{:navigate, route, params}`.
- `{:task, id, fun}` or `{:task, id, opts, fun}`.
- `{:modal, modal}` and `:dismiss_modal`.
- `{:publish, topic, event}`.
- `{:session, {:set_terminal_size, {cols, rows}}}`.
- `{:session, {:promote, user}}`.
- `{:session, :heartbeat}`.
- `{:quit, reason}`.
- `{:batch, effects}` if needed for composition.

## Migration Order

1. Add the new contract, context, effect model, and runtime helpers.
2. Migrate low-risk but representative screens first: Login and BoardList.
3. Migrate BBS navigation and composition as a connected flow.
4. Migrate operator workbenches after the task/result model is proven.
5. Simplify App only after all screens use the new boundary.

## Verification Strategy

- Unit-test effect values and App interpreter behavior.
- Unit-test each screen reducer's key and async-result handling.
- Keep existing render smoke tests for canonical terminal sizes.
- Add grep-style architectural tests sparingly for high-value invariants, such as no App clauses for `:boards_loaded` after migration.
- Run focused TUI screen tests after each phase and full precommit at milestone end.
