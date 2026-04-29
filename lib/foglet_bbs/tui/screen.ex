defmodule Foglet.TUI.Screen do
  @moduledoc """
  Behaviour for Foglet TUI screens.

  The canonical screen runtime contract is:

  - `init/1` builds screen-local state from `Foglet.TUI.Context`.
  - `update/3` consumes normalized runtime messages, screen-local state, and
    context, then returns `{new_local_state, effects}`.
  - `render/2` renders from screen-local state plus context.
  - `subscriptions/2` is optional for focused-screen PubSub topics.

  ## State conventions

  - Stateful screens own a first-class state struct with `new/1` or document an explicit local state type.
  - Stateless screens explicitly return `:stateless` or `%{}` from `init/1` and do not store local state in App fields.
  - Screens do not receive `%Foglet.TUI.App{}` through `init/1`, `update/3`, or `render/2`.

  ## Bounded compatibility surface

  Production `Foglet.TUI.App` dispatch no longer calls the broad App-state
  callbacks below. They remain declared only so modules that still expose
  compatibility helpers can keep their `@impl` annotations while cleanup lands
  in the screen modules themselves:

  - `render/1` — bounded to compatibility helpers and older direct smoke tests;
    App rendering uses `render/2`.
  - `handle_key/2` — bounded to compatibility helpers and older direct tests;
    App key routing uses `update({:key, event}, local_state, context)`.
  - `init_screen_state/1` — bounded to compatibility constructors; render
    fixtures and migrated tests should prefer `init/1` or first-class
    `State.new/1`.

  New screens should implement only the canonical callbacks plus optional
  `subscriptions/2`.
  """

  @type message :: term()
  @type local_state :: term()
  @type effects :: [Foglet.TUI.Effect.t()]
  @type update_result :: {local_state(), effects()}

  @type key_event :: map()
  @type app_state :: map()
  @type command :: tuple() | Raxol.Core.Runtime.Command.t()
  @type handle_key_result :: {:update, app_state(), [command()]} | :no_match

  @callback init(Foglet.TUI.Context.t()) :: local_state()
  @callback update(message(), local_state(), Foglet.TUI.Context.t()) :: update_result()
  @callback render(local_state(), Foglet.TUI.Context.t()) :: any()

  @doc """
  Optional PubSub topic-interest declaration. Screens that wish to receive
  PubSub updates while focused declare the topics they want subscribed by
  returning a list of topic strings. Stateless screens and screens with no
  PubSub interest may omit this callback entirely.

  Per D-05 / SPEC R6, this is the App-shell-decoupled replacement for
  central App pattern-matching on the current screen — the App calls into
  this callback rather than encoding screen-specific topic logic itself.
  """
  @callback subscriptions(local_state(), Foglet.TUI.Context.t()) :: [String.t()]

  @doc """
  Bounded compatibility render callback that receives broad App state.
  Production App rendering uses `render/2`.
  """
  @callback render(state :: app_state()) :: any()

  @doc """
  Bounded compatibility key handler that receives broad App state.
  Production App key routing uses `update/3`.
  """
  @callback handle_key(key :: key_event(), state :: app_state()) :: handle_key_result()

  @doc """
  Bounded compatibility screen-state initializer. Prefer `init/1` or a
  first-class `State.new/1` constructor for new tests and fixtures.
  """
  @callback init_screen_state(opts :: keyword()) :: map()

  @optional_callbacks init: 1,
                      update: 3,
                      render: 2,
                      render: 1,
                      handle_key: 2,
                      init_screen_state: 1,
                      subscriptions: 2
end
