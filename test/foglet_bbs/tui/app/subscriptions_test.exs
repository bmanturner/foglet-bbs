defmodule Foglet.TUI.App.SubscriptionsTest do
  use ExUnit.Case, async: true

  alias Foglet.TUI.App
  alias Foglet.TUI.App.Subscriptions
  alias Foglet.TUI.Context
  alias Raxol.Core.Runtime.Subscription

  defmodule SampleScreen do
    defmodule State do
      defstruct route_params: %{}
    end

    def subscriptions(%State{} = state, %Context{} = context) do
      [state.route_params[:topic], context.route_params[:topic]]
      |> Enum.reject(&is_nil/1)
      |> Enum.map(&"sample:#{&1}")
      |> Enum.uniq()
    end
  end

  defmodule NoSubscriptionsScreen do
    def render(local_state, %Context{}), do: {:no_subscription_render, local_state}
  end

  defmodule IntervalScreen do
    def subscriptions(%{topic: topic}, %Context{}) do
      %{topics: ["interval:#{topic}"], intervals: [{25, :interval_screen_tick}]}
    end
  end

  defp state(attrs \\ %{}) do
    attrs = Map.new(attrs)

    session_context =
      Map.get(attrs, :session_context, %{
        domain: %{
          screen_modules: %{
            sample: SampleScreen,
            interval: IntervalScreen,
            no_subscriptions: NoSubscriptionsScreen
          }
        }
      })

    struct!(
      App,
      Map.merge(
        %{
          current_screen: :sample,
          route_params: %{topic: "route"},
          session_context: session_context,
          terminal_size: {100, 30},
          screen_state: %{sample: %SampleScreen.State{route_params: %{topic: "state"}}}
        },
        attrs
      )
    )
  end

  defp interval_subscription(subscriptions, message) do
    Enum.find(subscriptions, fn
      %Subscription{type: :interval, data: %{message: ^message}} -> true
      _ -> false
    end)
  end

  defp custom_subscription(subscriptions, module) do
    Enum.find(subscriptions, fn
      %Subscription{type: :custom, data: %{module: ^module}} -> true
      _ -> false
    end)
  end

  test "unauthenticated state still subscribes to the central TUI clock topic" do
    assert Subscriptions.topics(
             state(
               current_screen: :no_subscriptions,
               route_params: %{},
               screen_state: %{}
             )
           ) == [Foglet.PubSub.tui_clock_topic()]
  end

  test "heartbeat_tick interval is present only when session_pid is a pid" do
    without_session = Subscriptions.subscribe(state(session_pid: nil))
    with_session = Subscriptions.subscribe(state(session_pid: self()))

    assert interval_subscription(without_session, :heartbeat_tick) == nil

    assert %Subscription{type: :interval, data: %{interval: 10_000}} =
             interval_subscription(with_session, :heartbeat_tick)
  end

  test "chrome clock uses PubSub instead of a per-session interval" do
    clock_topic = Foglet.PubSub.tui_clock_topic()
    subscriptions = Subscriptions.subscribe(state(session_pid: nil))

    assert interval_subscription(subscriptions, :main_menu_clock_tick) == nil

    assert %Subscription{
             type: :custom,
             data: %{args: %{topics: [^clock_topic, "sample:state", "sample:route"]}}
           } = custom_subscription(subscriptions, Foglet.TUI.PubSubForwarder)
  end

  test "screen-declared interval subscriptions are picked up generically" do
    clock_topic = Foglet.PubSub.tui_clock_topic()

    subscriptions =
      state(
        current_screen: :interval,
        route_params: %{},
        screen_state: %{interval: %{topic: "state"}}
      )
      |> Subscriptions.subscribe()

    assert %Subscription{type: :interval, data: %{interval: 25}} =
             interval_subscription(subscriptions, :interval_screen_tick)

    assert %Subscription{
             type: :custom,
             data: %{args: %{topics: [^clock_topic, "interval:state"]}}
           } = custom_subscription(subscriptions, Foglet.TUI.PubSubForwarder)
  end

  test "subscribe builds PubSubForwarder spec without starting a process for the caller" do
    before = :global.whereis_name({Foglet.TUI.PubSubForwarder, self()})

    subscriptions = Subscriptions.subscribe(state())

    assert custom_subscription(subscriptions, Foglet.TUI.PubSubForwarder)
    assert before == :undefined
    assert :global.whereis_name({Foglet.TUI.PubSubForwarder, self()}) == :undefined
  end

  test "PubSubForwarder subscription combines user, notification, and active screen topics" do
    user = %Foglet.Accounts.User{id: "u-subscriptions", handle: "alice"}
    clock_topic = Foglet.PubSub.tui_clock_topic()

    assert %Subscription{
             type: :custom,
             data: %{
               module: Foglet.TUI.PubSubForwarder,
               args: %{
                 topics: [
                   ^clock_topic,
                   "user:u-subscriptions",
                   "sample:state",
                   "sample:route",
                   "notifications:u-subscriptions"
                 ]
               }
             }
           } =
             state(current_user: user)
             |> Subscriptions.subscribe()
             |> custom_subscription(Foglet.TUI.PubSubForwarder)
  end

  test "InitialRouteEnterForwarder custom subscription is always present" do
    assert %Subscription{
             type: :custom,
             data: %{module: Foglet.TUI.InitialRouteEnterForwarder, args: %{}}
           } =
             state()
             |> Subscriptions.subscribe()
             |> custom_subscription(Foglet.TUI.InitialRouteEnterForwarder)
  end

  test "screen_declared_topics returns empty list when screen omits subscriptions callback" do
    assert Subscriptions.screen_declared_topics(
             state(
               current_screen: :no_subscriptions,
               route_params: %{},
               screen_state: %{no_subscriptions: %{loaded: true}}
             )
           ) == []
  end

  test "refresh_dynamic broadcasts only when effective topic lists change" do
    control_topic = Foglet.TUI.PubSubForwarder.control_topic(self())
    Phoenix.PubSub.subscribe(FogletBbs.PubSub, control_topic)

    user = %Foglet.Accounts.User{id: "u-refresh", handle: "alice"}
    old_state = state(current_user: nil)
    unchanged_state = state(current_user: nil)
    new_state = state(current_user: user)

    assert Subscriptions.refresh_dynamic(old_state, unchanged_state) == nil
    refute_receive {:pubsub_forwarder, {:refresh_topics, _topics}}

    assert :ok = Subscriptions.refresh_dynamic(old_state, new_state)

    clock_topic = Foglet.PubSub.tui_clock_topic()

    assert_receive {:pubsub_forwarder,
                    {:refresh_topics,
                     [
                       ^clock_topic,
                       "user:u-refresh",
                       "sample:state",
                       "sample:route",
                       "notifications:u-refresh"
                     ]}}
  end
end
