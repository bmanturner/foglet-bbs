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

  test "'C' navigates to :post_composer with empty draft and no current_thread", %{state: state} do
    {:update, s, _} = MainMenu.handle_key(%{key: "C"}, state)
    assert s.current_screen == :post_composer
    assert s.composer_draft == ""
    assert s.current_thread == nil
  end

  test "'Q' emits {:terminate, :logout} command", %{state: state} do
    {:update, _, cmds} = MainMenu.handle_key(%{key: "Q"}, state)
    assert {:terminate, :logout} in cmds
  end

  test "unknown key returns :no_match", %{state: state} do
    assert :no_match = MainMenu.handle_key(%{key: "z"}, state)
  end
end
