# Foglet TUI Screen Contract

Foglet TUI screens implement `Foglet.TUI.Screen`. `Foglet.TUI.App` owns the
runtime shell: session identity, route state, terminal size, modal overlay
state, task execution, PubSub wiring, and effect interpretation. Screens own
their screen-local state, reducer logic, focused subscriptions, and pure
rendering from already-loaded state.

The public callbacks are:

- `init/1`
- `update/3`
- `render/2`
- optional `subscriptions/2`

## State

Use a first-class state struct for screens with cursor position, loaded rows,
form drafts, selected indexes, submit status, route identity, render caches, or
transient feedback.

```elixir
defmodule Foglet.TUI.Screens.Example.State do
  defstruct status: :idle, selected_index: 0, items: []

  def new(opts \\ []), do: struct!(__MODULE__, opts)
end
```

Stateless screens should return `:stateless` or `%{}` from `init/1`. Screen
callbacks receive screen-local state plus `Foglet.TUI.Context`; they do not
receive `%Foglet.TUI.App{}`.

## `init/1`

`init/1` receives `Foglet.TUI.Context` and returns screen-local state. Use it to
derive initial UI state from session data, route params, terminal size, and
domain overrides.

```elixir
@impl Foglet.TUI.Screen
def init(%Foglet.TUI.Context{} = context) do
  Example.State.new(
    board_id: Map.get(context.route_params, :board_id),
    status: :loading
  )
end
```

Do not perform durable domain writes in `init/1`. If the screen needs data,
request it from `update/3` with a task effect.

## `update/3`

`update/3` is the screen reducer. It receives a runtime message, local state,
and `Foglet.TUI.Context`, then returns `{new_local_state, effects}`.

Common messages include:

- `{:key, event}` for keyboard input.
- `:on_route_enter` when App enters or mounts the route.
- `{:task_result, op, result}` after App completes a task effect.
- Screen-owned PubSub messages.
- `{:modal_submit, kind, payload}` for App-routed form submit payloads.

```elixir
alias Foglet.TUI.Effect

@impl Foglet.TUI.Screen
def update(:on_route_enter, state, context) do
  {state, [load_items_effect(context)]}
end

def update({:key, %{key: :char, char: "q"}}, state, _context) do
  {state, [Effect.navigate(:main_menu, %{})]}
end

def update(_message, state, _context), do: {state, []}
```

Keep authorization and durable state changes in the owning `Foglet.*` context.
A screen can request work; the context function inside the task remains the
authority.

## `render/2`

`render/2` receives screen-local state and `Foglet.TUI.Context`. It should be
pure over already-loaded state. Route colors through `Foglet.TUI.Theme`, use
shared widgets, and pass explicit chrome data such as breadcrumb parts.

```elixir
@impl Foglet.TUI.Screen
def render(%Example.State{} = state, %Foglet.TUI.Context{} = context) do
  theme = Foglet.TUI.Theme.from_context(context)

  Foglet.TUI.Widgets.Chrome.ScreenFrame.render(
    %{session_context: context.session_context, current_user: context.current_user},
    %{breadcrumb_parts: ["Foglet", "Example"]},
    render_body(state, theme),
    [{"Q", "Back"}]
  )
end
```

Render code must not query the database, mutate state, subscribe to topics, or
start tasks.

## `subscriptions/2`

Screens that need focused PubSub topics implement `subscriptions/2`. App owns
user-level topics; the active screen owns screen-specific topics.

```elixir
@impl Foglet.TUI.Screen
def subscriptions(%Example.State{thread_id: thread_id}, _context)
    when is_binary(thread_id) do
  [Foglet.PubSub.thread_topic(thread_id)]
end

def subscriptions(_state, _context), do: []
```

Return only topic strings. PubSub messages route back through `update/3`.

## Context

`Foglet.TUI.Context` is the narrow screen-facing runtime value. It carries:

- `current_user`
- `session_context`
- `session_pid`
- `terminal_size`
- `route`
- `route_params`
- `domain`

Tests should build the same shape production screens receive:

```elixir
Foglet.TUI.Context.new(
  current_user: user,
  route: :thread_list,
  route_params: %{board_id: board.id},
  terminal_size: {80, 24},
  session_context: %{theme: Foglet.TUI.Theme.default()}
)
```

Use `route_params` for route-owned identity such as `board_id`, `thread_id`, or
`load_intent`. Use `domain` for test/runtime dependency overrides.

## Effects

`Foglet.TUI.Effect` is how screens ask App to perform runtime work.

- `Effect.navigate(screen, params)` changes route and dispatches
  `:on_route_enter`.
- `Effect.task(op, screen_key, fun)` runs work through App and returns a
  `{:task_result, op, result}` message.
- `Effect.open_modal(modal)` and `Effect.dismiss_modal()` control App-owned
  modal state.
- `Effect.modal_submit(screen_key, kind, payload)` routes a form submit payload
  to a screen reducer.
- `Effect.publish(topic, message)` broadcasts through PubSub.
- `Effect.session(message)` sends or dispatches session/runtime messages.
- `Effect.terminal_size(size)` requests a terminal size update.
- `Effect.quit()` requests runtime termination.

## Modal Forms

Screens open form modals with `Effect.open_modal/1`. App owns the overlay and
routes submit payloads back to the target screen as
`{:modal_submit, kind, payload}`.

```elixir
def update({:key, %{key: :char, char: "n"}}, state, _context) do
  {state, [Effect.open_modal(new_item_modal())]}
end

def update({:modal_submit, :new_item, payload}, state, context) do
  effect =
    Effect.task(:create_item, :example, fn ->
      Foglet.Items.create_item(context.current_user, payload)
    end)

  {state, [effect]}
end
```

Keep failed-submit recovery in the screen reducer by preserving or rebuilding
the form state with an error.

## Tests And Fixtures

Direct screen tests should call `Screen.init(context)` for canonical setup or
explicit state constructors such as `Example.State.new/1` for state-only unit
tests. Drive input through `Screen.update({:key, event}, state, context)` and
render through `Screen.render(state, context)`.

`Foglet.TUI.RenderFixtures` builds synthetic in-memory App states for
`Foglet.TUI.AsciiRenderer` and `rtk mix foglet.tui.render`. These fixtures are
for visual inspection, not behavior assertions.

## Large Screen Decomposition

Large screens with substantial reducer and render helper code should use a
top-level reducer-facing screen module, sibling `state.ex`, and sibling `render.ex`.
The top-level module remains the `Foglet.TUI.Screen` implementation and keeps
`init/1`, `update/3`, optional `subscriptions/2`, effect creation, task result
handling, modal submit handling, and public non-render test seams.

Sibling render modules own frame, content, and keybar assembly plus detailed
body, tab, form, panel, or helper rendering. Render modules consume
already-loaded screen state plus `Foglet.TUI.Context` or a derived render model.
They should route styling through `Foglet.TUI.Theme` and existing widgets.

Render modules must not query the database, mutate screen state, subscribe to
topics, start tasks, or perform durable domain writes. Domain work remains in
the owning `Foglet.*` context and is requested by the reducer-facing screen
through effects.

Current Phase 43 examples are PostReader, Sysop, Login, MainMenu, NewThread, and Account.

## Checklist

- [ ] Define screen-local state or return an explicit stateless value.
- [ ] Implement `init/1`, `update/3`, and `render/2`.
- [ ] Implement `subscriptions/2` only for focused PubSub topics.
- [ ] Use `Foglet.TUI.Context` for session, route, terminal, and dependency
      override data.
- [ ] Emit `Foglet.TUI.Effect` values for runtime work.
- [ ] Use `Effect.task/3` for domain reads/writes and handle
      `{:task_result, op, result}` in `update/3`.
- [ ] Keep authorization and durable mutations inside the owning context.
- [ ] Pass explicit chrome and breadcrumb data.
- [ ] Handle form submit payloads at the reducer boundary.
- [ ] Add reducer/effect tests for key handling, task results, route entry,
      subscriptions, and modal submit handling where applicable.
- [ ] Add or update render fixture support when CLI rendering should inspect
      the screen.
