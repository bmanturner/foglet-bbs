defmodule Foglet.TUI.Screens.MainMenuTest do
  use ExUnit.Case, async: true

  alias Foglet.TUI.Screens.MainMenu

  defp build_state(role) do
    %Foglet.TUI.App{
      current_screen: :main_menu,
      current_user: %Foglet.Accounts.User{id: "u1", handle: "alice", role: role},
      session_context: %{},
      terminal_size: {80, 24}
    }
    |> Map.from_struct()
  end

  setup do
    %{state: build_state(:user)}
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
    assert s.screen_state.new_thread.step == :board
    assert s.screen_state.new_thread.origin == :main_menu

    {:update, s2, cmds2} = MainMenu.handle_key(%{key: :char, char: "c"}, state)
    assert s2.current_screen == :new_thread
    assert {:load_boards_for_new_thread} in cmds2
    assert s2.screen_state.new_thread.step == :board
    assert s2.screen_state.new_thread.origin == :main_menu
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

  describe "Phase 0 shell entry points" do
    test "authenticated user with role :user sees Account menu entry" do
      state = build_state(:user)
      flat = MainMenu.render(state) |> collect_text_values()
      assert Enum.any?(flat, &String.contains?(&1, "Account"))
      assert Enum.any?(flat, &String.contains?(&1, "[A]"))
    end

    test "role :user does NOT see Moderation menu entry" do
      state = build_state(:user)
      flat = MainMenu.render(state) |> collect_text_values()
      refute Enum.any?(flat, &String.contains?(&1, "Moderation"))
    end

    test "role :user does NOT see Sysop menu entry" do
      state = build_state(:user)
      flat = MainMenu.render(state) |> collect_text_values()
      refute Enum.any?(flat, &String.contains?(&1, "Sysop"))
    end

    test "role :mod sees Account AND Moderation entries but NOT Sysop" do
      state = build_state(:mod)
      flat = MainMenu.render(state) |> collect_text_values()
      assert Enum.any?(flat, &String.contains?(&1, "Account"))
      assert Enum.any?(flat, &String.contains?(&1, "Moderation"))
      refute Enum.any?(flat, &String.contains?(&1, "Sysop"))
    end

    test "role :sysop sees Account AND Moderation AND Sysop entries" do
      state = build_state(:sysop)
      flat = MainMenu.render(state) |> collect_text_values()
      assert Enum.any?(flat, &String.contains?(&1, "Account"))
      assert Enum.any?(flat, &String.contains?(&1, "Moderation"))
      assert Enum.any?(flat, &String.contains?(&1, "Sysop"))
    end

    test "'A'/'a' navigates to :account and seeds screen_state" do
      state = build_state(:user)
      {:update, s, _cmds} = MainMenu.handle_key(%{key: :char, char: "A"}, state)
      assert s.current_screen == :account
      assert s.screen_state[:account] != nil

      {:update, s2, _cmds2} = MainMenu.handle_key(%{key: :char, char: "a"}, state)
      assert s2.current_screen == :account
      assert s2.screen_state[:account] != nil
    end

    test "'M'/'m' navigates to :moderation for role :mod" do
      state = build_state(:mod)
      {:update, s, _cmds} = MainMenu.handle_key(%{key: :char, char: "M"}, state)
      assert s.current_screen == :moderation

      {:update, s2, _cmds2} = MainMenu.handle_key(%{key: :char, char: "m"}, state)
      assert s2.current_screen == :moderation
    end

    test "'M'/'m' returns :no_match for role :user (key bound guarded per D-02)" do
      state = build_state(:user)
      assert :no_match = MainMenu.handle_key(%{key: :char, char: "M"}, state)
      assert :no_match = MainMenu.handle_key(%{key: :char, char: "m"}, state)
    end

    test "'S'/'s' navigates to :sysop for role :sysop" do
      state = build_state(:sysop)
      {:update, s, _cmds} = MainMenu.handle_key(%{key: :char, char: "S"}, state)
      assert s.current_screen == :sysop

      {:update, s2, _cmds2} = MainMenu.handle_key(%{key: :char, char: "s"}, state)
      assert s2.current_screen == :sysop
    end

    test "'S'/'s' returns :no_match for role :mod" do
      state = build_state(:mod)
      assert :no_match = MainMenu.handle_key(%{key: :char, char: "S"}, state)
      assert :no_match = MainMenu.handle_key(%{key: :char, char: "s"}, state)
    end

    test "'S'/'s' returns :no_match for role :user" do
      state = build_state(:user)
      assert :no_match = MainMenu.handle_key(%{key: :char, char: "S"}, state)
      assert :no_match = MainMenu.handle_key(%{key: :char, char: "s"}, state)
    end
  end
end
