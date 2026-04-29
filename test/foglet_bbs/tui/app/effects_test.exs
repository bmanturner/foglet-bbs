defmodule Foglet.TUI.App.EffectsTest do
  use ExUnit.Case, async: true

  alias Foglet.TUI.App
  alias Foglet.TUI.App.Effects
  alias Foglet.TUI.App.Routing
  alias Foglet.TUI.Context
  alias Foglet.TUI.Effect
  alias Foglet.TUI.Modal
  alias Raxol.Core.Runtime.Command

  defmodule SampleScreen do
    defmodule State do
      defstruct route_params: %{}, messages: [], submits: []
    end

    def init(%Context{} = context), do: %State{route_params: context.route_params}

    def update(:on_route_enter, %State{} = state, %Context{} = context) do
      {%{state | messages: [{:on_route_enter, context.route_params} | state.messages]}, []}
    end

    def update({:modal_submit, kind, payload}, %State{} = state, %Context{}) do
      {%{state | submits: [{kind, payload} | state.submits]}, []}
    end

    def update(_message, %State{} = state, %Context{}), do: {state, []}
  end

  defp state(attrs \\ %{}) do
    attrs = Map.new(attrs)

    session_context =
      Map.get(attrs, :session_context, %{
        domain: %{screen_modules: %{sample: SampleScreen, target: SampleScreen}}
      })

    struct!(
      App,
      Map.merge(
        %{
          current_screen: :main_menu,
          session_context: session_context,
          terminal_size: {100, 30},
          screen_state: %{
            main_menu: %{kept: true},
            sample: %SampleScreen.State{route_params: %{existing: true}},
            target: %SampleScreen.State{}
          }
        },
        attrs
      )
    )
  end

  test "navigate initializes target state, clears modal, carries route params, and dispatches route entry" do
    modal = %Modal{type: :info, message: "open"}

    {new_state, cmds} =
      state(modal: modal)
      |> Effects.apply_effect(Effect.navigate(:sample, %{board_id: "b1"}))

    assert cmds == []
    assert new_state.current_screen == :sample
    assert new_state.route_params == %{board_id: "b1"}
    assert new_state.modal == nil
    assert new_state.screen_state.main_menu == %{kept: true}

    assert %SampleScreen.State{
             route_params: %{board_id: "b1"},
             messages: [{:on_route_enter, %{board_id: "b1"}}]
           } = Routing.screen_state_for(new_state, :sample)
  end

  test "modal open and dismiss update modal state" do
    modal = %Modal{type: :info, message: "hello"}

    {with_modal, []} = Effects.apply_effect(state(), Effect.open_modal(modal))
    assert with_modal.modal == modal

    {without_modal, []} = Effects.apply_effect(with_modal, Effect.dismiss_modal())
    assert without_modal.modal == nil
  end

  test "modal_submit reaches target reducer and missing targets produce generic error modal" do
    payload = %{field: "value"}

    {submitted, []} =
      Effects.apply_effect(state(), Effect.modal_submit(:target, :save_profile, payload))

    assert %SampleScreen.State{submits: [save_profile: ^payload]} =
             Routing.screen_state_for(submitted, :target)

    {failed, []} = Effects.apply_effect(state(), Effect.modal_submit(:missing, :save, payload))

    assert %Modal{
             type: :error,
             title: "Form Error",
             message: "Unable to submit form."
           } = failed.modal
  end

  test "session set_current_user updates only current_user and generic session payload sends to pid" do
    user = %Foglet.Accounts.User{id: "u-effects", handle: "alice"}
    original = state(session_pid: self(), current_screen: :sample, route_params: %{id: "1"})

    {updated, []} = Effects.apply_effect(original, Effect.session({:set_current_user, user}))

    assert updated.current_user == user
    assert updated.current_screen == original.current_screen
    assert updated.route_params == original.route_params
    assert updated.screen_state == original.screen_state

    assert {^updated, []} =
             Effects.apply_effect(updated, Effect.session({:heartbeat, self()}))

    assert_receive {:heartbeat, pid} when pid == self()
  end

  test "terminal size effect updates terminal_size through window-change handling" do
    {resized, []} = Effects.apply_effect(state(), Effect.terminal_size({120, 40}))

    assert resized.terminal_size == {120, 40}
  end

  test "publish effect broadcasts PubSub message" do
    topic = "test:effects:#{System.unique_integer([:positive])}"
    Phoenix.PubSub.subscribe(FogletBbs.PubSub, topic)

    assert {same_state, []} = Effects.apply_effect(state(), Effect.publish(topic, :message))
    assert same_state.current_screen == :main_menu
    assert_receive :message
  end

  test "quit effect returns a quit runtime command" do
    assert {_state, [%Command{type: :quit}]} = Effects.apply_effect(state(), Effect.quit())
  end

  test "task effect success and failure preserve screen_task_result wrapper" do
    {same_state, [%Command{type: :task, data: success_task}]} =
      Effects.apply_effect(state(), Effect.task(:load, :sample, fn -> {:loaded, 1} end))

    assert same_state.current_screen == :main_menu

    assert {:screen_task_result, :sample, :load, {:ok, {:loaded, 1}}} =
             success_task.()

    {_state, [%Command{type: :task, data: failure_task}]} =
      Effects.apply_effect(state(), Effect.task(:load, :sample, fn -> raise "boom" end))

    assert {:screen_task_result, :sample, :load, {:error, reason}} = failure_task.()
    assert String.contains?(reason, "boom")
  end
end
