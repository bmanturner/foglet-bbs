defmodule Foglet.TUI.GuestModeRuntimeTest do
  use ExUnit.Case, async: true

  alias Foglet.BoardChat
  alias Foglet.Config
  alias Foglet.Doors.Manifest
  alias Foglet.TUI.App
  alias Foglet.TUI.App.Effects
  alias Foglet.TUI.Context
  alias Foglet.TUI.Effect
  alias Foglet.TUI.Guest
  alias Foglet.TUI.Screens.ChatRoom
  alias Foglet.TUI.Screens.ChatRoom.State, as: ChatRoomState
  alias Foglet.TUI.Screens.Login
  alias Foglet.TUI.Screens.Login.State, as: LoginState
  alias Foglet.TUI.Screens.MainMenu
  alias Foglet.TUI.Screens.MainMenu.State, as: MainMenuState
  alias Foglet.TUI.Screens.PostReader
  alias Foglet.TUI.Screens.PostReader.State, as: PostReaderState
  alias Foglet.TUI.Screens.ThreadList
  alias Foglet.TUI.Screens.ThreadList.State, as: ThreadListState
  alias Foglet.TUI.SessionContext

  setup do
    Config.init_cache()
    :ets.insert(:foglet_config, {"registration_mode", "open"})
    :ets.insert(:foglet_config, {"guest_mode_enabled", true})
    :ets.insert(:foglet_config, {"max_post_length", 8000})
    :ok
  end

  test "login G enters explicit guest state only when guest mode is enabled" do
    local_state = LoginState.default()
    context = Context.new(session_context: %{guest_mode_enabled: true})

    {_local_state, effects} = Login.update({:key, %{key: :char, char: "G"}}, local_state, context)

    assert [%Effect{type: :session, payload: :enter_guest}] = effects

    context = Context.new(session_context: %{guest_mode_enabled: false})

    assert {^local_state, []} =
             Login.update({:key, %{key: :char, char: "G"}}, local_state, context)
  end

  test "App routes explicit guests to main menu without an authenticated user" do
    {:ok, state} =
      App.init(%{
        session_context: %SessionContext{guest: true, guest_mode_enabled: true, user: nil}
      })

    assert state.current_screen == :main_menu
    assert state.current_user == nil
    assert Guest.guest?(state)
  end

  test "Main Menu hides write/account actions and denies compose and doors for guests" do
    context = Context.new(session_context: %{guest: true, guest_mode_enabled: true})
    local_state = MainMenuState.new(context)

    refute Enum.any?(MainMenu.visible_destinations(nil), fn {key, _label} -> key == "A" end)

    refute Enum.any?(
             MainMenu.visible_actions(%{current_user: nil, recent_oneliners: []}),
             fn group ->
               Enum.any?(group.commands, &(&1.key == "O"))
             end
           )

    {_, compose_effects} = MainMenu.update({:key, %{key: :char, char: "C"}}, local_state, context)
    assert [%Effect{type: :modal, payload: {:open, compose_modal}}] = compose_effects
    assert compose_modal.type == :error

    {_, door_effects} = MainMenu.update({:key, %{key: :char, char: "D"}}, local_state, context)
    assert [%Effect{type: :modal, payload: {:open, door_modal}}] = door_effects
    assert door_modal.type == :error
  end

  test "App runtime denies direct guest routes and door launch effects" do
    state = %App{
      session_context: %{guest: true, guest_mode_enabled: true},
      current_screen: :main_menu
    }

    {state, []} = Effects.apply_effect(state, Effect.navigate(:new_thread))
    assert state.current_screen == :main_menu
    assert state.modal.type == :error

    manifest = %Manifest{id: "demo", slug: "demo", display_name: "Demo", runtime: :native_elixir}
    state = %{state | modal: nil}

    {state, []} = Effects.apply_effect(state, Effect.launch_door(manifest))
    assert state.modal.type == :error
  end

  test "thread and post reader compose shortcuts deny guests with modal effects" do
    context = Context.new(session_context: %{guest: true, guest_mode_enabled: true})

    thread_state =
      ThreadListState.new(
        board: %{id: "b1", name: "General", archived: false},
        board_id: "b1",
        threads: [%{id: "t1", title: "Welcome"}],
        status: :loaded
      )

    {^thread_state, thread_effects} =
      ThreadList.update({:key, %{key: :char, char: "C"}}, thread_state, context)

    assert [%Effect{type: :modal, payload: {:open, thread_modal}}] = thread_effects
    assert thread_modal.type == :error

    post_state =
      PostReaderState.new(
        board: %{id: "b1", name: "General", archived: false},
        board_id: "b1",
        thread: %{id: "t1", title: "Welcome", locked: false},
        thread_id: "t1",
        posts: [%{id: "p1", body: "hi"}],
        status: :loaded
      )

    {^post_state, post_effects} =
      PostReader.update({:key, %{key: :char, char: "R"}}, post_state, context)

    assert [%Effect{type: :modal, payload: {:open, post_modal}}] = post_effects
    assert post_modal.type == :error
  end

  test "chat and board presence backends reject nil guest identity" do
    board = %Foglet.Boards.Board{id: "b1", chat_storage_mode: :ephemeral, chat_enabled: true}

    assert {:error, :guest_not_allowed} = BoardChat.post(board, nil, "hello")
    assert :ok = Foglet.Sessions.BoardScreen.track("b1", nil, :chat)
    assert Foglet.Sessions.BoardScreen.count("b1") == 0
  end

  test "chat tab keeps guest transcript read-only without composer send affordances" do
    context =
      Context.new(
        current_user: nil,
        session_context: %{guest: true, guest_mode_enabled: true},
        terminal_size: {120, 40}
      )

    state = %ChatRoomState{board: %{id: "b1", chat_storage_mode: :ephemeral}, board_id: "b1"}

    refute Enum.any?(ChatRoom.keybar_groups(state, context), fn group ->
             Enum.any?(group.commands, &(&1.key == "Enter" and &1.label == "Send"))
           end)

    assert {^state, []} = ChatRoom.update({:key, %{key: :char, char: "h"}}, state, context)

    {^state, effects} = ChatRoom.update({:key, %{key: :enter}}, state, context)
    assert [%Effect{type: :modal, payload: {:open, modal}}] = effects
    assert modal.type == :error
  end
end
