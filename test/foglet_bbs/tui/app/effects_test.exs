defmodule Foglet.TUI.App.EffectsTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

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

  test "guest direct navigation with stale members-only content params is denied before route state initializes" do
    guest_state =
      state(
        current_user: nil,
        session_context: %{guest: true, user: nil, user_id: nil},
        current_screen: :board_list,
        route_params: %{},
        screen_state: %{board_list: %{loaded: true}}
      )

    private_board = %{
      id: "private-board",
      name: "Members Hidden Board",
      readable_by: :members,
      chat_enabled: true
    }

    cases = [
      {:board, :thread_list, %{board: private_board, board_id: private_board.id}},
      {:thread, :post_reader,
       %{thread: %{id: "private-thread", title: "Hidden Thread", board: private_board}}},
      {:post, :post_reader,
       %{post: %{id: "private-post", body: "Hidden Post", board: private_board}}},
      {:chat, :thread_list,
       %{board: Map.put(private_board, :chat_enabled, true), board_id: private_board.id}}
    ]

    for {_surface, screen, params} <- cases do
      {new_state, cmds} = Effects.apply_effect(guest_state, Effect.navigate(screen, params))

      assert cmds == []
      assert new_state.current_screen == :board_list
      assert new_state.route_params == %{}
      assert new_state.screen_state == guest_state.screen_state

      assert %Modal{type: :error, message: "That board is for registered users. Log in first."} =
               new_state.modal

      state_dump = inspect(new_state)
      refute state_dump =~ "Members Hidden Board"
      refute state_dump =~ "Hidden Thread"
      refute state_dump =~ "Hidden Post"
    end
  end

  test "authenticated navigation may carry members-only board params for domain-authorized routes" do
    user = %Foglet.Accounts.User{id: "u-member", handle: "member", role: :user}

    {new_state, cmds} =
      state(current_user: user, session_context: %{user: user, user_id: user.id})
      |> Effects.apply_effect(
        Effect.navigate(:thread_list, %{
          board: %{id: "b-private", name: "Members Board", readable_by: :members},
          board_id: "b-private"
        })
      )

    assert match?([%Raxol.Core.Runtime.Command{type: :task}], cmds)
    assert new_state.current_screen == :thread_list
    assert new_state.route_params.board.name == "Members Board"
    assert new_state.modal == nil
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

  test "session promote_session navigates to main_menu and sets current_user" do
    user = %Foglet.Accounts.User{id: "u-promote", handle: "alice", role: :user}

    session_context = %{
      domain: %{screen_modules: %{main_menu: SampleScreen, sample: SampleScreen}}
    }

    original =
      state(
        session_pid: self(),
        current_screen: :sample,
        session_context: session_context,
        screen_state: %{sample: %SampleScreen.State{}}
      )

    {promoted, _cmds} =
      Effects.apply_effect(original, Effect.session({:promote_session, user}))

    assert promoted.current_user == user
    assert promoted.current_screen == :main_menu
    assert promoted.session_context.user == user
    assert promoted.session_context.user_id == user.id
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

    secret = "sysop@example.test token=super-secret"

    {_state, [%Command{type: :task, data: failure_task}]} =
      Effects.apply_effect(state(), Effect.task(:load, :sample, fn -> raise secret end))

    log =
      capture_log(fn ->
        assert {:screen_task_result, :sample, :load, {:error, {:task_failed, :exception}}} =
                 failure_task.()
      end)

    assert log =~ "tui_screen_task_failed"
    assert log =~ "screen=sample"
    assert log =~ "operation=load"
    assert log =~ "failure_kind=exception"
    assert log =~ "reason_class=Elixir.RuntimeError"
    refute log =~ secret
    refute log =~ "sysop@example.test"
    refute log =~ "super-secret"
  end

  test "task thrown tuple payloads are logged with low-cardinality reason class only" do
    secret = "raw-secret-token@example.test"

    {_state, [%Command{type: :task, data: failure_task}]} =
      Effects.apply_effect(
        state(),
        Effect.task(:probe, :sample, fn -> throw({secret, :details}) end)
      )

    log =
      capture_log(fn ->
        assert {:screen_task_result, :sample, :probe, {:error, {:task_failed, :throw}}} =
                 failure_task.()
      end)

    assert log =~ "tui_screen_task_failed"
    assert log =~ "screen=sample"
    assert log =~ "operation=probe"
    assert log =~ "failure_kind=throw"
    assert log =~ "reason_class=tuple"
    refute log =~ secret
    refute log =~ "raw-secret-token"
    refute log =~ "example.test"
    refute log =~ "details"
  end
end
