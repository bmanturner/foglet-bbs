defmodule Foglet.TUI.App.Subscriptions do
  @moduledoc """
  App-shell subscription helper for stable runtime subscriptions and dynamic topics.

  This module owns subscription construction and PubSub topic diffing for
  `%Foglet.TUI.App{}` state while leaving `Foglet.TUI.App` as the Raxol
  callback integration point.
  """

  alias Foglet.PubSub
  alias Foglet.TUI.App
  alias Foglet.TUI.App.Routing
  alias Foglet.TUI.InitialRouteEnterForwarder
  alias Foglet.TUI.PubSubForwarder
  alias Raxol.Core.Runtime.Subscription

  @doc "Builds the stable Raxol subscriptions for the current App state."
  @spec subscribe(App.t()) :: [Subscription.t()]
  def subscribe(%App{} = state) do
    heartbeat =
      if is_pid(state.session_pid) do
        [subscribe_interval(10_000, :heartbeat_tick)]
      else
        []
      end

    clock = [subscribe_interval(60_000, :main_menu_clock_tick)]
    pubsub = [Subscription.custom(PubSubForwarder, %{topics: topics(state)})]
    initial_route = [Subscription.custom(InitialRouteEnterForwarder, %{})]

    heartbeat ++ clock ++ pubsub ++ initial_route
  end

  @doc "Returns App-owned user topics plus topics declared by the active screen."
  @spec topics(App.t()) :: [String.t()]
  def topics(%App{} = state) do
    user_topics =
      if state.current_user do
        [PubSub.user_topic(state.current_user.id)]
      else
        []
      end

    user_topics ++ screen_declared_topics(state)
  end

  @doc "Returns topics from the active screen's optional `subscriptions/2` callback."
  @spec screen_declared_topics(App.t()) :: [String.t()]
  def screen_declared_topics(%App{} = state) do
    key = Routing.screen_key(Routing.current_route(state))
    module = Routing.screen_module_for(state, key)

    if Code.ensure_loaded?(module) and function_exported?(module, :subscriptions, 2) do
      module.subscriptions(Routing.screen_state_for(state, key), Routing.build_context(state))
    else
      []
    end
  end

  @doc "Refreshes the dispatcher-owned PubSub forwarder when effective topics change."
  @spec refresh_dynamic(App.t(), App.t()) :: :ok | term()
  def refresh_dynamic(%App{} = old_state, %App{} = new_state) do
    old_topics = topics(old_state)
    new_topics = topics(new_state)

    if old_topics != new_topics do
      PubSubForwarder.refresh(new_topics)
    end
  end

  defp subscribe_interval(interval, message) do
    Subscription.interval(interval, message)
  end
end
