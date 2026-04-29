# Foglet TUI Screen Contract

This guide is for adding or migrating screens under the canonical
`Foglet.TUI.Screen` contract. `Foglet.TUI.App` owns the runtime shell:
session identity, the current route, terminal size, modal precedence, PubSub
subscription wiring, task execution, and effect interpretation. Screens own
screen-local state, key handling, async-result handling, and rendering from
already-loaded input.

New screens should implement `init/1`, `update/3`, and `render/2`. Screens that
need focused PubSub topics may also implement `subscriptions/2`.

## State Ownership

Use a first-class state struct for any screen with cursor position, loaded
rows, pending form data, submit status, route identity, render cache, or
transient feedback.

```elixir
defmodule Foglet.TUI.Screens.Example.State do
  @moduledoc false

  defstruct status: :idle,
            selected_index: 0,
            items: [],
            route_params: %{}

  def new(attrs \\ []), do: struct!(__MODULE__, attrs)
end
```

Stateless screens should explicitly return `:stateless` or `%{}` from `init/1`.
Do not store screen-local state in `%Foglet.TUI.App{}` fields and do not pass the
App struct into screen callbacks.

## `init/1`

`init/1` receives `Foglet.TUI.Context` and returns the screen-local state.
Use it to derive initial UI state from session, route params, terminal size, and
domain overrides.

```elixir
alias Foglet.TUI.Context

@impl Foglet.TUI.Screen
def init(%Context{} = context) do
  Example.State.new(
    route_params: context.route_params,
    status: :loading
  )
end
```

Do not perform durable domain writes in `init/1`. If the screen needs data, set
local loading state and request the work from `update/3` with a task effect.

## `update/3`

`update/3` is the screen reducer. It receives a normalized runtime message, the
local state, and `Foglet.TUI.Context`, then returns
`{new_local_state, effects}`.

Common messages:

- `{:key, %{key: :up}}`, `{:key, %{key: :char, char: "q"}}`, and other key
  events from Raxol.
- `:on_route_enter` when App navigates to or initially mounts the screen.
- `{:task_result, op, result}` after a task effect completes.
- Screen-owned PubSub messages such as `{:board_activity, board_id, event}`.
- Screen modal submit messages such as `{:modal_submit, kind, payload}`.

```elixir
alias Foglet.TUI.{Context, Effect}

@impl Foglet.TUI.Screen
def update(:on_route_enter, state, %Context{} = context) do
  {state, [load_items_effect(context)]}
end

def update({:key, %{key: :char, char: "q"}}, state, %Context{}) do
  {state, [Effect.navigate(:main_menu, %{})]}
end

def update(_message, state, %Context{}) do
  {state, []}
end
```

Keep authorization and durable state changes in the owning context modules. A
screen may request work; the context function inside the task remains the
authority.

## `render/2`

`render/2` receives only screen-local state and `Foglet.TUI.Context`. It should
be pure over already-loaded state. Route colors through `Foglet.TUI.Theme` and
shared widgets, and pass explicit chrome data such as `breadcrumb_parts`.

```elixir
alias Foglet.TUI.Context
alias Foglet.TUI.Widgets.Chrome.ScreenFrame

@impl Foglet.TUI.Screen
def render(%Example.State{} = state, %Context{} = context) do
  theme = Foglet.TUI.Theme.from_context(context)

  ScreenFrame.render(
    %{session_context: context.session_context, current_user: context.current_user},
    %{breadcrumb_parts: ["Foglet", "Example"]},
    render_body(state, theme),
    [{"Q", "Back"}]
  )
end
```

Render functions should not query the database, mutate state, subscribe to
topics, or start tasks.

## `Foglet.TUI.Context`

`Foglet.TUI.Context` is the narrow screen-facing runtime value. It contains:

- `current_user`
- `session_context`
- `session_pid`
- `terminal_size`
- `route`
- `route_params`
- `domain`

The constructor rejects unknown fields, so tests and fixtures should build the
same shape production screens receive:

```elixir
context =
  Foglet.TUI.Context.new(
    current_user: user,
    route: :thread_list,
    route_params: %{board_id: board.id},
    terminal_size: {80, 24},
    session_context: %{theme: Foglet.TUI.Theme.default()}
  )
```

Use `route_params` for route-owned identity such as `board_id`, `thread_id`, or
`load_intent`. Use `domain` for test/runtime dependency overrides, not for
durable user data.

## `Foglet.TUI.Effect`

`Foglet.TUI.Effect` is the only way screens ask App to do runtime work.

Supported requests:

- `Effect.navigate(screen, params)` changes the route and dispatches
  `:on_route_enter`.
- `Effect.task(op, screen_key, fun)` runs off-process work.
- `Effect.open_modal(modal)` and `Effect.dismiss_modal()` control App-owned
  modal state.
- `Effect.publish(topic, message)` broadcasts through PubSub.
- `Effect.session(message)` sends or dispatches session/runtime messages.
- `Effect.terminal_size(size)` requests a terminal resize update.
- `Effect.quit()` requests termination.

Return effects as a list from `update/3`:

```elixir
{state, [Effect.navigate(:post_reader, %{thread_id: thread.id})]}
```

## Task Effects And `task_result`

Use `Effect.task/3` for domain reads or mutations that should not run inside the
render or key event call stack. The task function is zero-arity and is executed
by App. App wraps the result and sends it back to the owning screen as
`{:task_result, op, result}`.

```elixir
defp load_items_effect(%Context{} = context) do
  items_mod = Map.get(context.domain, :items, Foglet.Items)

  Effect.task(:load_items, :example, fn ->
    items_mod.list_items(context.current_user)
  end)
end

@impl Foglet.TUI.Screen
def update({:task_result, :load_items, {:ok, items}}, state, %Context{}) do
  {%{state | status: :loaded, items: items}, []}
end

def update({:task_result, :load_items, {:error, reason}}, state, %Context{}) do
  {%{state | status: {:error, reason}}, []}
end
```

The task message shape delivered by App is
`{:screen_task_result, screen_key, op, result}` internally and
`{:task_result, op, result}` at the screen reducer boundary.

## Route Params

Route-owned screens should keep routed identity in local state and be able to
initialize from `context.route_params`.

```elixir
@impl Foglet.TUI.Screen
def init(%Context{route_params: params}) do
  Example.State.new(
    board_id: Map.get(params, :board_id),
    thread_id: Map.get(params, :thread_id),
    load_intent: Map.get(params, :load_intent)
  )
end
```

When navigating, include only the route identity and intent the destination
screen owns:

```elixir
Effect.navigate(:thread_list, %{board_id: board.id, select_thread_id: thread.id})
```

Do not pre-write the destination screen's loaded rows from the source screen.
The destination screen should apply its own route params and request its own
loads through `:on_route_enter`.

## Optional `subscriptions/2`

Screens that need focused PubSub topics implement `subscriptions/2`. App always
owns user-level topics; the active screen owns screen-specific topics.

```elixir
@impl Foglet.TUI.Screen
def subscriptions(%Example.State{thread_id: thread_id}, %Context{})
    when is_binary(thread_id) do
  [Foglet.PubSub.thread_topic(thread_id)]
end

def subscriptions(_state, _context), do: []
```

Return only topic strings. PubSub messages are routed back through `update/3`,
where the screen can choose to reload, patch local state, or ignore them.

## Modal Requests

Modal overlay ownership stays in App. Screens request modal changes with
`Foglet.TUI.Effect.open_modal/1` and `Foglet.TUI.Effect.dismiss_modal/0`.

For form modals, the screen opens a `Foglet.TUI.Modal` whose message is a
`Foglet.TUI.Widgets.Modal.Form`. On submit, App routes the payload back to the
screen as `{:modal_submit, kind, payload}`.

```elixir
def update({:key, %{key: :char, char: "n"}}, state, %Context{}) do
  {state, [Effect.open_modal(new_item_modal())]}
end

def update({:modal_submit, :new_item, payload}, state, %Context{} = context) do
  effect =
    Effect.task(:create_item, :example, fn ->
      Foglet.Items.create_item(context.current_user, payload)
    end)

  {state, [effect]}
end
```

Keep failed-submit recovery in the screen reducer: preserve the user's form
state or reopen the modal with `{:error, reason}` so the user can correct and
dismiss it.

## Render Fixtures And CLI Rendering

`Foglet.TUI.RenderFixtures` builds synthetic in-memory App states for
`Foglet.TUI.AsciiRenderer` and `rtk mix foglet.tui.render`. These fixtures are
for deterministic visual inspection, not behavior assertions.

Use the CLI when changing layout, chrome, or render-only code:

```bash
rtk mix foglet.tui.render main_menu
rtk mix foglet.tui.render board_list --width 132 --height 50
rtk mix foglet.tui.render login --width 64 --height 22
```

Use focused reducer tests for behavior. Use layout smoke tests when the contract
is visual positioning, width, or chrome behavior.

## Checklist

### New Screens

- [ ] Define a screen-local state struct, or explicitly return `:stateless` or
      `%{}` from `init/1`.
- [ ] Implement `init/1`, `update/3`, and `render/2`.
- [ ] Use `Foglet.TUI.Context` for session, route, terminal, and dependency
      override data.
- [ ] Emit `Foglet.TUI.Effect` values instead of mutating App or calling runtime
      services directly.
- [ ] Use `Effect.task/3` for domain reads/writes and handle
      `{:task_result, op, result}` in `update/3`.
- [ ] Keep authorization and durable mutations inside the owning context module.
- [ ] Pass explicit `breadcrumb_parts` to chrome.
- [ ] Implement `subscriptions/2` only if the focused screen needs PubSub
      topics.
- [ ] Use modal effects for modal requests and handle form submit payloads at
      the reducer boundary.
- [ ] Add reducer/effect tests for key handling, task results, route-entry
      behavior, and modal submit handling where applicable.
- [ ] Add or update render fixture support when `rtk mix foglet.tui.render`
      should inspect the screen.

### Migrated Screens

- [ ] Move App-shaped screen data into a screen-owned state struct.
- [ ] Replace direct `handle_key/2` use with `update({:key, event}, state,
      context)`.
- [ ] Replace broad `render/1` App-state rendering with `render/2`.
- [ ] Replace `init_screen_state/1` fixture setup with `init/1` or an explicit
      state constructor.
- [ ] Route task completions through `{:task_result, op, result}`.
- [ ] Move route-entry loads to `update(:on_route_enter, state, context)`.
- [ ] Declare focused PubSub topics with `subscriptions/2` instead of adding App
      branches.
- [ ] Preserve modal failure recovery and Escape dismissal behavior.
- [ ] Verify `rtk mix foglet.tui.render` for affected screens and supported
      sizes when layout changes.
- [ ] Keep tests at behavior boundaries: local state, emitted effects, task
      results, subscriptions, route params, and layout contracts.
