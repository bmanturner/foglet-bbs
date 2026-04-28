defmodule Foglet.TUI.AppRuntimeContractTest do
  use ExUnit.Case, async: true

  alias Foglet.TUI.App
  alias Foglet.TUI.Context
  alias Foglet.TUI.Effect
  alias Foglet.TUI.Modal

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

  describe "generic non-task effect interpretation" do
    test "navigate initializes only the target state and carries route params" do
      state = state()

      {new_state, cmds} =
        App.apply_effect(state, Effect.navigate(:sample_runtime, %{board_id: "b1"}))

      assert cmds == []
      assert new_state.current_screen == :sample_runtime
      assert new_state.modal == nil
      assert new_state.route_params == %{board_id: "b1"}
      assert context = App.build_context(new_state)
      assert context.route_params == %{board_id: "b1"}

      assert %SampleScreen.State{route_params: %{board_id: "b1"}} =
               App.screen_state_for(new_state, :sample_runtime)

      assert new_state.board_list == state.board_list
      assert new_state.posts == state.posts
      assert new_state.recent_oneliners == state.recent_oneliners
      assert new_state.screen_state.main_menu == state.screen_state.main_menu
    end

    test "modal, session, terminal, publish, and quit effects are generic" do
      user = %Foglet.Accounts.User{id: "u2", handle: "bob"}
      modal = %Modal{type: :info, message: "hello"}
      state = state()

      {with_modal, []} = App.apply_effect(state, Effect.open_modal(modal))
      assert with_modal.modal == modal

      {without_modal, []} = App.apply_effect(with_modal, Effect.dismiss_modal())
      assert without_modal.modal == nil

      {with_user, user_cmds} = App.apply_effect(without_modal, Effect.session({:set_user, user}))
      assert with_user.current_user == user
      assert with_user.current_screen == :main_menu
      assert [%Raxol.Core.Runtime.Command{type: :task}] = user_cmds

      {resized, []} = App.apply_effect(with_user, Effect.terminal_size({120, 40}))
      assert resized.terminal_size == {120, 40}

      assert {^resized, []} = App.apply_effect(resized, Effect.publish("topic", :message))

      assert {_same_state, [%Raxol.Core.Runtime.Command{type: :quit}]} =
               App.apply_effect(resized, Effect.quit())
    end
  end
end
