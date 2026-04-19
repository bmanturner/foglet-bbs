defmodule Foglet.TUI.Screens.MainMenuTest do
  use ExUnit.Case, async: true

  alias Foglet.TUI.Screens.MainMenu

  setup do
    state =
      %Foglet.TUI.App{
        current_screen: :main_menu,
        current_user: %Foglet.Accounts.User{id: "u1", handle: "alice", role: :user},
        session_context: %{},
        terminal_size: {80, 24}
      }
      |> Map.from_struct()

    %{state: state}
  end

  test "render/1 does not crash", %{state: state} do
    assert _ = MainMenu.render(state)
  end

  test "'B'/'b' navigates to :board_list with {:load_boards} command", %{state: state} do
    {:update, s, cmds} = MainMenu.handle_key(%{key: "B"}, state)
    assert s.current_screen == :board_list
    assert {:load_boards} in cmds

    {:update, s2, cmds2} = MainMenu.handle_key(%{key: "b"}, state)
    assert s2.current_screen == :board_list
    assert {:load_boards} in cmds2
  end

  test "'C' navigates to :new_thread wizard and dispatches {:load_boards_for_new_thread}",
       %{state: state} do
    {:update, s, cmds} = MainMenu.handle_key(%{key: "C"}, state)
    assert s.current_screen == :new_thread
    assert {:load_boards_for_new_thread} in cmds
    # Wizard screen_state initialised at the board step
    assert get_in(s, [:screen_state, :new_thread, :step]) == :board

    # lowercase 'c' same behaviour
    {:update, s2, cmds2} = MainMenu.handle_key(%{key: "c"}, state)
    assert s2.current_screen == :new_thread
    assert {:load_boards_for_new_thread} in cmds2
  end

  test "'Q' emits {:terminate, :logout} command", %{state: state} do
    {:update, _, cmds} = MainMenu.handle_key(%{key: "Q"}, state)
    assert {:terminate, :logout} in cmds
  end

  test "unknown key returns :no_match", %{state: state} do
    assert :no_match = MainMenu.handle_key(%{key: "z"}, state)
  end
end
