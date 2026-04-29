defmodule Foglet.TUI.AppRuntimeContractTest do
  use ExUnit.Case, async: true

  alias Foglet.TUI.App
  alias Foglet.TUI.App.Routing
  alias Foglet.TUI.App.Subscriptions
  alias Foglet.TUI.Context

  defmodule SampleScreen do
    defmodule State do
      defstruct route_params: %{}, messages: [], results: []
    end

    def init(%Context{} = context) do
      %State{route_params: context.route_params}
    end

    def update({:task_result, op, result}, %State{} = state, %Context{} = context) do
      new_state = %{
        state
        | messages: [{op, context.route_params} | state.messages],
          results: [{op, result} | state.results]
      }

      {new_state, []}
    end

    def update({:key, key}, %State{} = state, %Context{} = context) do
      {%{state | messages: [{:key, key, context.route_params} | state.messages]}, []}
    end

    def update(:on_route_enter, %State{} = state, %Context{} = context) do
      {%{state | messages: [{:on_route_enter, context.route_params} | state.messages]}, []}
    end

    # Catch-all per Foglet.TUI.Screen contract — Phase 39 D-04 dispatches
    # :on_route_enter to every active screen via the generic route-entry path,
    # so test-fixture screens must tolerate unknown messages without crashing.
    def update(_message, %State{} = state, %Context{}) do
      {state, []}
    end

    def render(%State{} = state, %Context{} = context) do
      {:sample_render, state, context.route_params}
    end

    def subscriptions(%State{} = state, %Context{} = context) do
      state_topic = state.route_params[:topic]
      route_topic = context.route_params[:topic]

      [state_topic, route_topic]
      |> Enum.reject(&is_nil/1)
      |> Enum.map(&"sample:#{&1}")
      |> Enum.uniq()
    end
  end

  defmodule RenderOnlyScreen do
    def init(%Context{}), do: %{render_only: true}

    def render(local_state, %Context{}) do
      {:render_only, local_state}
    end
  end

  defp state(attrs) do
    attrs = Map.new(attrs)

    session_context =
      Map.get(attrs, :session_context, %{
        domain: %{screen_modules: %{sample_runtime: SampleScreen}}
      })

    struct!(
      App,
      Map.merge(
        %{
          current_screen: :main_menu,
          session_context: session_context,
          terminal_size: {100, 30},
          screen_state: %{
            main_menu: %{legacy: true},
            sample_runtime: %SampleScreen.State{route_params: %{existing: true}}
          }
        },
        attrs
      )
    )
  end

  describe "App effect integration" do
    test "legacy navigation clears route params from effect navigation" do
      with_params =
        state(
          current_screen: :sample_runtime,
          route_params: %{thread_id: "t1"},
          screen_state: %{sample_runtime: %SampleScreen.State{route_params: %{thread_id: "t1"}}}
        )

      {without_params, []} = App.update({:navigate, :main_menu}, with_params)

      assert without_params.current_screen == :main_menu
      assert without_params.route_params == %{}
      assert Routing.current_route(without_params) == :main_menu
    end

    test "new-contract screens handle keys and render without legacy callbacks" do
      state =
        state(
          current_screen: :sample_runtime,
          route_params: %{thread_id: "t1"},
          screen_state: %{
            sample_runtime: %SampleScreen.State{route_params: %{thread_id: "t1"}}
          }
        )

      {after_key, []} = App.update({:key, %{key: "j"}}, state)

      assert %SampleScreen.State{
               messages: [{:key, %{key: "j"}, %{thread_id: "t1"}}]
             } =
               Routing.screen_state_for(after_key, :sample_runtime)

      assert {:sample_render, %SampleScreen.State{}, %{thread_id: "t1"}} = App.view(after_key)
    end

    test "non-production override screens without update/3 no-op on keys" do
      state =
        state(
          current_screen: :render_only,
          session_context: %{domain: %{screen_modules: %{render_only: RenderOnlyScreen}}},
          screen_state: %{render_only: %{render_only: true}}
        )

      assert {^state, []} = App.update({:key, %{key: "j"}}, state)
      assert {:render_only, %{render_only: true}} = App.view(state)
    end
  end

  describe "App shell close-gate delegation" do
    test "initial route-enter hydration uses the active screen reducer" do
      state =
        state(
          current_screen: :sample_runtime,
          route_params: %{topic: "initial"},
          screen_state: %{sample_runtime: %SampleScreen.State{route_params: %{topic: "initial"}}}
        )

      {new_state, cmds} = App.update(:initial_route_enter, state)

      assert cmds == []

      assert %SampleScreen.State{messages: [{:on_route_enter, %{topic: "initial"}}]} =
               Routing.screen_state_for(new_state, :sample_runtime)
    end

    test "subscribe/1 delegates stable subscription construction" do
      user = %Foglet.Accounts.User{id: "u-sub", handle: "alice"}

      state =
        state(
          current_screen: :sample_runtime,
          current_user: user,
          route_params: %{topic: "route"},
          screen_state: %{
            sample_runtime: %SampleScreen.State{route_params: %{topic: "state"}}
          }
        )

      assert App.subscribe(state) == Subscriptions.subscribe(state)
    end
  end
end
