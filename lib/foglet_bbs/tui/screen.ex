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

  New screens should implement only the canonical callbacks plus optional
  `subscriptions/2`.
  """

  @type message :: term()
  @type local_state :: term()
  @type effects :: [Foglet.TUI.Effect.t()]
  @type update_result :: {local_state(), effects()}

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

  @optional_callbacks init: 1,
                      update: 3,
                      render: 2,
                      subscriptions: 2
end
