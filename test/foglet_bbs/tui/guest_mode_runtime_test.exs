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
  alias Foglet.TUI.Screens.Login
  alias Foglet.TUI.Screens.Login.State, as: LoginState
  alias Foglet.TUI.Screens.MainMenu
  alias Foglet.TUI.Screens.MainMenu.State, as: MainMenuState
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

  test "chat and board presence backends reject nil guest identity" do
    board = %Foglet.Boards.Board{id: "b1", chat_storage_mode: :ephemeral, chat_enabled: true}

    assert {:error, :guest_not_allowed} = BoardChat.post(board, nil, "hello")
    assert :ok = Foglet.Sessions.BoardScreen.track("b1", nil, :chat)
    assert Foglet.Sessions.BoardScreen.count("b1") == 0
  end
end
