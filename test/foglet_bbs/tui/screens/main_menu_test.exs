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

  defp collect_text_values(node, acc \\ [])

  defp collect_text_values(node, acc) when is_map(node) do
    acc =
      case Map.get(node, :type) do
        :text ->
          content = Map.get(node, :content)

          if is_binary(content) do
            [content | acc]
          else
            acc
          end

        _ ->
          acc
      end

    node
    |> Map.get(:children, [])
    |> collect_text_values(acc)
  end

  defp collect_text_values(nodes, acc) when is_list(nodes) do
    Enum.reduce(nodes, acc, fn node, text_acc -> collect_text_values(node, text_acc) end)
  end

  test "render/1 does not crash", %{state: state} do
    assert _ = MainMenu.render(state)
  end

  test "MainMenu has no public init_screen_state/1" do
    refute function_exported?(MainMenu, :init_screen_state, 1)
  end

  test "render includes main menu owned text rows", %{state: state} do
    texts = MainMenu.render(state) |> collect_text_values()

    assert "Welcome back, alice." in texts
    assert "  [B] Browse Boards" in texts
    assert "  [C] Compose New Thread" in texts
    assert "  [Q] Logout" in texts
  end

  test "'B'/'b' navigates to :board_list with {:load_boards} command", %{state: state} do
    {:update, s, cmds} = MainMenu.handle_key(%{key: :char, char: "B"}, state)
    assert s.current_screen == :board_list
    assert {:load_boards} in cmds

    {:update, s2, cmds2} = MainMenu.handle_key(%{key: :char, char: "b"}, state)
    assert s2.current_screen == :board_list
    assert {:load_boards} in cmds2
  end

  test "'C'/'c' navigates to :new_thread and seeds compose screen state", %{state: state} do
    {:update, s, cmds} = MainMenu.handle_key(%{key: :char, char: "C"}, state)
    assert s.current_screen == :new_thread
    assert {:load_boards_for_new_thread} in cmds
    assert get_in(s, [:screen_state, :new_thread, :step]) == :board
    assert get_in(s, [:screen_state, :new_thread, :origin]) == :main_menu

    {:update, s2, cmds2} = MainMenu.handle_key(%{key: :char, char: "c"}, state)
    assert s2.current_screen == :new_thread
    assert {:load_boards_for_new_thread} in cmds2
    assert get_in(s2, [:screen_state, :new_thread, :step]) == :board
    assert get_in(s2, [:screen_state, :new_thread, :origin]) == :main_menu
  end

  test "'Q'/'q' emits {:terminate, :logout} command", %{state: state} do
    {:update, _, cmds} = MainMenu.handle_key(%{key: :char, char: "Q"}, state)
    assert {:terminate, :logout} in cmds

    {:update, _, cmds2} = MainMenu.handle_key(%{key: :char, char: "q"}, state)
    assert {:terminate, :logout} in cmds2
  end

  test "unknown key returns :no_match", %{state: state} do
    assert :no_match = MainMenu.handle_key(%{key: :char, char: "z"}, state)
  end
end
