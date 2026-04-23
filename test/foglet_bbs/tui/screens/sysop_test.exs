defmodule Foglet.TUI.Screens.SysopTest do
  use ExUnit.Case, async: true

  alias Foglet.TUI.Screens.Sysop

  defp build_state(role \\ :sysop) do
    %Foglet.TUI.App{
      current_screen: :sysop,
      current_user: %Foglet.Accounts.User{id: "u1", handle: "alice", role: role},
      session_context: %{},
      terminal_size: {80, 24},
      screen_state: %{}
    }
    |> Map.from_struct()
  end

  setup do
    %{state: build_state(:sysop)}
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

  describe "init_screen_state/1" do
    test "returns struct with active_tab: 0 and Tabs wrapper" do
      ss = Sysop.init_screen_state()
      assert ss.active_tab == 0
      assert %Foglet.TUI.Widgets.Input.Tabs{} = ss.tabs
    end
  end

  describe "render/1" do
    setup %{state: state} do
      state = put_in(state, [:screen_state, :sysop], Sysop.init_screen_state())
      %{state: state}
    end

    test "does not crash with default screen state", %{state: state} do
      assert _ = Sysop.render(state)
    end

    test "shows all five tab labels in order: SITE, BOARDS, LIMITS, SYSTEM, USERS", %{
      state: state
    } do
      flat = Sysop.render(state) |> collect_text_values()
      expected_tabs = ["SITE", "BOARDS", "LIMITS", "SYSTEM", "USERS"]

      for tab <- expected_tabs do
        assert Enum.any?(flat, &String.contains?(&1, tab)),
               "Expected #{inspect(tab)} in flat text: #{inspect(flat)}"
      end

      # Assert order by finding index positions and checking they ascend
      tab_positions =
        Enum.map(expected_tabs, fn tab ->
          flat
          |> Enum.with_index()
          |> Enum.find_value(fn {text, idx} ->
            if String.contains?(text, tab), do: idx
          end)
        end)

      valid_positions = Enum.reject(tab_positions, &is_nil/1)

      assert valid_positions == Enum.sort(valid_positions),
             "Expected tab labels to appear in order SITE, BOARDS, LIMITS, SYSTEM, USERS. " <>
               "Got positions: #{inspect(Enum.zip(expected_tabs, tab_positions))}"
    end

    test "renders scaffold-only placeholder copy (no fake config writes)", %{state: state} do
      flat = Sysop.render(state) |> collect_text_values()
      # Forbidden substrings as action affordances: key-bar or button contexts
      forbidden = ["Save", "Apply", "Revert", "Set"]

      for word <- forbidden do
        refute Enum.any?(flat, &String.contains?(&1, word)),
               "Expected #{inspect(word)} not to appear as an action affordance in Sysop render output. " <>
                 "Found in: #{inspect(Enum.filter(flat, &String.contains?(&1, word)))}"
      end
    end
  end

  describe "handle_key/2" do
    setup %{state: state} do
      state = put_in(state, [:screen_state, :sysop], Sysop.init_screen_state())
      %{state: state}
    end

    test "advances through all five tabs with Right arrow (0→1→2→3→4, stays at 4)", %{
      state: state
    } do
      {state1, tab1} =
        case Sysop.handle_key(%{key: :right}, state) do
          {:update, s, _} -> {s, s.screen_state.sysop.active_tab}
        end

      {state2, tab2} =
        case Sysop.handle_key(%{key: :right}, state1) do
          {:update, s, _} -> {s, s.screen_state.sysop.active_tab}
        end

      {state3, tab3} =
        case Sysop.handle_key(%{key: :right}, state2) do
          {:update, s, _} -> {s, s.screen_state.sysop.active_tab}
        end

      {state4, tab4} =
        case Sysop.handle_key(%{key: :right}, state3) do
          {:update, s, _} -> {s, s.screen_state.sysop.active_tab}
        end

      {_state5, tab5} =
        case Sysop.handle_key(%{key: :right}, state4) do
          {:update, s, _} -> {s, s.screen_state.sysop.active_tab}
          :no_match -> {state4, state4.screen_state.sysop.active_tab}
        end

      assert tab1 == 1
      assert tab2 == 2
      assert tab3 == 3
      assert tab4 == 4
      # Stays at 4 (bounded)
      assert tab5 == 4
    end

    test "digit '5' jumps to USERS tab (index 4)", %{state: state} do
      {:update, new_state, _cmds} = Sysop.handle_key(%{key: :char, char: "5"}, state)
      assert new_state.screen_state.sysop.active_tab == 4
    end

    test "'Q' returns to :main_menu", %{state: state} do
      {:update, new_state, _cmds} = Sysop.handle_key(%{key: :char, char: "Q"}, state)
      assert new_state.current_screen == :main_menu
    end

    test "'q' returns to :main_menu", %{state: state} do
      {:update, new_state, _cmds} = Sysop.handle_key(%{key: :char, char: "q"}, state)
      assert new_state.current_screen == :main_menu
    end

    test "unknown key returns :no_match", %{state: state} do
      assert :no_match = Sysop.handle_key(%{key: :char, char: "z"}, state)
    end

    test "Sysop screen does NOT dispatch fake config-write commands", %{state: state} do
      forbidden_commands = [:save_config, :apply_config, :set_config]

      keys = [
        %{key: :right},
        %{key: :left},
        %{key: :home},
        %{key: :end},
        %{key: :char, char: "1"},
        %{key: :char, char: "2"},
        %{key: :char, char: "5"}
      ]

      for key <- keys do
        case Sysop.handle_key(key, state) do
          {:update, _new_state, cmds} ->
            for cmd <- cmds do
              if is_tuple(cmd) do
                refute elem(cmd, 0) in forbidden_commands,
                       "Unexpected command #{inspect(cmd)} from key #{inspect(key)}"
              end
            end

          :no_match ->
            :ok
        end
      end
    end
  end
end
