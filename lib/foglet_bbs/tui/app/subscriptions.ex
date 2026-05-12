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

    screen_intervals = screen_declared_intervals(state)
    pubsub = [Subscription.custom(PubSubForwarder, %{topics: topics(state)})]
    initial_route = [Subscription.custom(InitialRouteEnterForwarder, %{})]

    heartbeat ++ screen_intervals ++ pubsub ++ initial_route
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

    notification_topics =
      if state.current_user do
        [PubSub.notifications_topic(state.current_user.id)]
      else
        []
      end

    clock_topics = [PubSub.tui_clock_topic()]

    (clock_topics ++ user_topics ++ screen_declared_topics(state) ++ notification_topics)
    |> Enum.uniq()
  end

  @doc "Returns topics from the active screen's optional `subscriptions/2` callback."
  @spec screen_declared_topics(App.t()) :: [String.t()]
  def screen_declared_topics(%App{} = state) do
    state
    |> screen_declared_subscription_shape()
    |> Map.fetch!(:topics)
  end

  @doc "Returns interval subscriptions from the active screen's optional `subscriptions/2` callback."
  @spec screen_declared_intervals(App.t()) :: [Subscription.t()]
  def screen_declared_intervals(%App{} = state) do
    state
    |> screen_declared_subscription_shape()
    |> Map.fetch!(:intervals)
    |> Enum.map(fn {interval, message} -> subscribe_interval(interval, message) end)
  end

  defp screen_declared_subscription_shape(%App{} = state) do
    key = Routing.screen_key(Routing.current_route(state))
    module = Routing.screen_module_for(state, key)

    if Code.ensure_loaded?(module) and function_exported?(module, :subscriptions, 2) do
      module.subscriptions(Routing.screen_state_for(state, key), Routing.build_context(state))
      |> normalize_screen_subscriptions()
    else
      %{topics: [], intervals: []}
    end
  end

  @doc "Refreshes the dispatcher-owned PubSub forwarder when effective topics change."
  @spec refresh_dynamic(App.t(), App.t()) :: :ok | term()
  def refresh_dynamic(%App{} = old_state, %App{} = new_state) do
    old_topics = topics(old_state)
    new_topics = topics(new_state)

    if old_topics != new_topics do
      PubSubForwarder.ensure_refreshed(new_topics)
    end
  end

  defp subscribe_interval(interval, message) do
    Subscription.interval(interval, message)
  end

  defp normalize_screen_subscriptions(topics) when is_list(topics) do
    if Keyword.keyword?(topics) do
      topics
      |> Map.new()
      |> normalize_screen_subscriptions()
    else
      %{topics: topics, intervals: []}
    end
  end

  defp normalize_screen_subscriptions(%{} = subscriptions) do
    %{
      topics: Map.get(subscriptions, :topics, []),
      intervals: subscriptions |> Map.get(:intervals, []) |> Enum.map(&normalize_interval/1)
    }
  end

  defp normalize_interval({interval, message}) when is_integer(interval) and interval > 0,
    do: {interval, message}

  defp normalize_interval(%{interval: interval, message: message})
       when is_integer(interval) and interval > 0,
       do: {interval, message}

  defp normalize_interval(%{interval_ms: interval, message: message})
       when is_integer(interval) and interval > 0,
       do: {interval, message}

  defp normalize_interval(invalid) do
    raise ArgumentError, "invalid screen interval subscription: #{inspect(invalid)}"
  end
end
