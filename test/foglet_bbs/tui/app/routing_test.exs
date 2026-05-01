defmodule Foglet.TUI.App.RoutingTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias Foglet.TUI.App
  alias Foglet.TUI.App.Routing
  alias Foglet.TUI.Context

  defmodule SampleScreen do
    defmodule State do
      defstruct route_params: %{}, messages: [], results: []
    end

    def init(%Context{} = context) do
      %State{route_params: context.route_params}
    end

    def update(:on_route_enter, %State{} = state, %Context{} = context) do
      {%{state | messages: state.messages ++ [{:on_route_enter, context.route_params}]}, []}
    end

    def update({:task_result, op, result}, %State{} = state, %Context{} = context) do
      new_state = %{
        state
        | messages: state.messages ++ [{op, context.route_params}],
          results: state.results ++ [{op, result}]
      }

      {new_state, []}
    end

    def update({:key, key}, %State{} = state, %Context{} = context) do
      {%{state | messages: state.messages ++ [{:key, key, context.route_params}]}, []}
    end

    def update(_message, %State{} = state, %Context{}) do
      {state, []}
    end

    def render(%State{} = state, %Context{} = context) do
      {:sample_render, state, context.route_params}
    end
  end

  defmodule RenderOnlyScreen do
    def init(%Context{}), do: %{render_only: true}
    def render(local_state, %Context{}), do: {:render_only, local_state}
  end

  defp state(attrs \\ %{}) do
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
          session_pid: self(),
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

  describe "route encoding and screen keys" do
    test "current_route/1 encodes empty params as an atom and non-empty params as a tuple" do
      assert Routing.current_route(state(route_params: %{})) == :main_menu

      routed =
        state(
          current_screen: :sample_runtime,
          route_params: %{board_id: "b1"}
        )

      assert Routing.current_route(routed) == {:sample_runtime, %{board_id: "b1"}}
    end

    test "screen_key/1 handles atom and tuple routes" do
      assert Routing.screen_key(:main_menu) == :main_menu
      assert Routing.screen_key({:sample_runtime, %{board_id: "b1"}}) == :sample_runtime
    end
  end

  describe "screen-local state" do
    test "current_screen_state/1, screen_state_for/2, and put_screen_state/3 only touch keyed state" do
      state = state()

      assert Routing.current_screen_state(state) == %{legacy: true}
      assert %SampleScreen.State{} = Routing.screen_state_for(state, :sample_runtime)

      new_local_state = %SampleScreen.State{route_params: %{board_id: "b2"}}
      new_state = Routing.put_screen_state(state, :sample_runtime, new_local_state)

      assert Routing.screen_state_for(new_state, :sample_runtime) == new_local_state
      assert Routing.screen_state_for(new_state, :main_menu) == %{legacy: true}
    end
  end

  describe "context construction" do
    test "build_context/1 preserves App runtime fields and defaults route params" do
      user = %Foglet.Accounts.User{id: "u1", handle: "alice"}
      state = state(current_user: user)

      context = Routing.build_context(state)

      assert %Context{} = context
      assert context.current_user == user
      assert context.session_context == state.session_context
      assert context.session_pid == self()
      assert context.terminal_size == {100, 30}
      assert context.route == :main_menu
      assert context.route_params == %{}
      assert context.domain == state.session_context.domain
    end

    test "build_context/2 preserves runtime fields with explicit route params" do
      state = state(route_params: %{ignored: true})

      context = Routing.build_context(state, %{board_id: "b1"})

      assert context.current_user == state.current_user
      assert context.session_context == state.session_context
      assert context.session_pid == self()
      assert context.terminal_size == {100, 30}
      assert context.route == :main_menu
      assert context.route_params == %{board_id: "b1"}
      assert context.domain == state.session_context.domain
    end
  end

  describe "route initialization and reducer dispatch" do
    test "navigation-style route initialization initializes only the target screen with params" do
      state =
        state()
        |> Map.put(:current_screen, :sample_runtime)
        |> Map.put(:route_params, %{board_id: "b1"})

      new_state = Routing.init_route_screen_state(state, :sample_runtime, %{board_id: "b1"})

      assert %SampleScreen.State{route_params: %{board_id: "b1"}, messages: []} =
               Routing.screen_state_for(new_state, :sample_runtime)

      assert Routing.screen_state_for(new_state, :main_menu) == %{legacy: true}
    end

    test "dispatch_route_entry/3 appends the route-entry message through the reducer" do
      state =
        state(
          current_screen: :sample_runtime,
          route_params: %{board_id: "b1"},
          screen_state: %{
            sample_runtime: %SampleScreen.State{route_params: %{board_id: "b1"}}
          }
        )

      {new_state, cmds} =
        Routing.dispatch_route_entry(state, :sample_runtime, %{board_id: "b1"})

      assert cmds == []

      assert %SampleScreen.State{
               messages: [{:on_route_enter, %{board_id: "b1"}}]
             } = Routing.screen_state_for(new_state, :sample_runtime)
    end

    test "built-in post_composer accepts route entry after reply navigation initialization" do
      params = %{
        origin: :post_reader,
        board: %{id: "b1", name: "General"},
        board_id: "b1",
        thread: %{id: "t1", title: "Hello", board_id: "b1"},
        thread_id: "t1",
        reply_to: %{id: "p1", body: "root post"}
      }

      state =
        state(
          current_screen: :post_composer,
          route_params: params,
          session_context: %{max_post_length: 1_000},
          current_user: %Foglet.Accounts.User{id: "u1", handle: "alice"},
          screen_state: %{}
        )
        |> Routing.init_route_screen_state(:post_composer, params)

      {new_state, cmds} = Routing.dispatch_route_entry(state, :post_composer, params)

      assert cmds == []

      assert %Foglet.TUI.Screens.PostComposer.State{thread_id: "t1", board_id: "b1"} =
               Routing.screen_state_for(new_state, :post_composer)
    end

    test "route_screen_update/3 no-ops when the override screen has no update/3" do
      state =
        state(
          current_screen: :render_only,
          session_context: %{domain: %{screen_modules: %{render_only: RenderOnlyScreen}}},
          screen_state: %{render_only: %{render_only: true}}
        )

      assert {^state, []} = Routing.route_screen_update(state, :render_only, {:key, %{key: "j"}})
    end
  end

  describe "screen module resolution" do
    test "screen_module_for/2 uses loadable domain screen module overrides" do
      assert Routing.screen_module_for(state(), :sample_runtime) == SampleScreen
    end

    test "invalid domain screen module override atoms fall back to the built-in resolver" do
      state =
        state(
          session_context: %{
            domain: %{screen_modules: %{main_menu: Foglet.TUI.App.RoutingTest.MissingScreen}}
          }
        )

      log =
        capture_log(fn ->
          assert Routing.screen_module_for(state, :main_menu) == Foglet.TUI.Screens.MainMenu
        end)

      assert String.contains?(log, "falling back to built-in resolver")
    end

    test "unknown screen atoms fall back to main menu instead of an inert screen" do
      state = state(current_screen: :future_screen, screen_state: %{})

      log =
        capture_log(fn ->
          assert Routing.screen_module_for(state, :future_screen) == Foglet.TUI.Screens.MainMenu
        end)

      assert String.contains?(log, "falling back to :main_menu")
    end
  end

  describe "rendering" do
    test "render_screen/1 uses render-only override screens" do
      state =
        state(
          current_screen: :render_only,
          session_context: %{domain: %{screen_modules: %{render_only: RenderOnlyScreen}}},
          screen_state: %{render_only: %{render_only: true}}
        )

      assert Routing.render_screen(state) == {:render_only, %{render_only: true}}
    end
  end
end
