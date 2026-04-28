defmodule Foglet.TUI.AppRuntimeContractTest do
  use ExUnit.Case, async: true

  alias Foglet.TUI.App
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
          terminal_size: {100, 30},
          screen_state: %{
            main_menu: %{legacy: true},
            sample_runtime: %SampleScreen.State{route_params: %{existing: true}}
          },
          board_list: [%{id: "b1"}],
          posts: [%{id: "p1"}],
          recent_oneliners: [%{id: "ol1"}]
        },
        attrs
      )
    )
  end

  describe "route and screen-state helpers" do
    test "read and write screen-local state without mutating legacy fields" do
      state = state()

      assert App.current_route(state) == :main_menu
      assert App.screen_key(:sample_runtime) == :sample_runtime
      assert App.screen_key({:sample_runtime, %{board_id: "b1"}}) == :sample_runtime
      assert App.current_screen_state(state) == %{legacy: true}
      assert %SampleScreen.State{} = App.screen_state_for(state, :sample_runtime)

      new_local_state = %SampleScreen.State{route_params: %{board_id: "b2"}}
      new_state = App.put_screen_state(state, :sample_runtime, new_local_state)

      assert App.screen_state_for(new_state, :sample_runtime) == new_local_state
      assert new_state.board_list == state.board_list
      assert new_state.posts == state.posts
      assert new_state.recent_oneliners == state.recent_oneliners
      assert new_state.screen_state.main_menu == state.screen_state.main_menu
    end

    test "build_context/1 exposes runtime fields and defaults route params" do
      user = %Foglet.Accounts.User{id: "u1", handle: "alice"}
      state = state(current_user: user, session_pid: self())

      context = App.build_context(state)

      assert %Context{} = context
      assert context.current_user == user
      assert context.session_context == state.session_context
      assert context.session_pid == self()
      assert context.terminal_size == {100, 30}
      assert context.route == :main_menu
      assert context.route_params == %{}
      assert context.domain == state.session_context.domain
    end
  end
end
