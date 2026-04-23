defmodule Foglet.TUI.Screens.ModerationTest do
  use ExUnit.Case, async: true

  import Foglet.TUI.RenderHelpers

  alias Foglet.TUI.Screens.Moderation

  defp build_state(role \\ :mod) do
    %Foglet.TUI.App{
      current_screen: :moderation,
      current_user: %Foglet.Accounts.User{id: "u1", handle: "alice", role: role},
      session_context: %{},
      terminal_size: {80, 24},
      screen_state: %{}
    }
    |> Map.from_struct()
  end

  setup do
    %{state: build_state(:mod)}
  end

  describe "init_screen_state/1" do
    test "returns struct with active_tab: 0 and Tabs wrapper" do
      ss = Moderation.init_screen_state()
      assert ss.active_tab == 0
      assert %Foglet.TUI.Widgets.Input.Tabs{} = ss.tabs
    end
  end

  describe "render/1" do
    setup %{state: state} do
      state = put_in(state, [:screen_state, :moderation], Moderation.init_screen_state())
      %{state: state}
    end

    test "does not crash with default screen state", %{state: state} do
      assert _ = Moderation.render(state)
    end

    test "shows all five tab labels: QUEUE, LOG, USERS, SANCTIONS, BOARDS (in that order)", %{
      state: state
    } do
      flat = Moderation.render(state) |> collect_text_values()
      expected_tabs = ["QUEUE", "LOG", "USERS", "SANCTIONS", "BOARDS"]

      for tab <- expected_tabs do
        assert Enum.any?(flat, &String.contains?(&1, tab)),
               "Expected #{inspect(tab)} in flat text: #{inspect(flat)}"
      end

      # Assert order by finding index positions of first occurrence and checking they ascend
      tab_positions =
        Enum.map(expected_tabs, fn tab ->
          flat
          |> Enum.with_index()
          |> Enum.find_value(fn {text, idx} ->
            if String.contains?(text, tab), do: idx
          end)
        end)

      # Filter out nils and check ascending
      valid_positions = Enum.reject(tab_positions, &is_nil/1)

      assert valid_positions == Enum.sort(valid_positions),
             "Expected tab labels to appear in order QUEUE, LOG, USERS, SANCTIONS, BOARDS. " <>
               "Got positions: #{inspect(Enum.zip(expected_tabs, tab_positions))}"
    end

    test "renders scaffold-only placeholder copy (no fake moderation actions)", %{state: state} do
      flat = Moderation.render(state) |> collect_text_values()
      # Forbidden substrings that would indicate fake operator actions in key-bar or buttons
      forbidden = ["Ban", "Unban", "Sanction", "Approve", "Remove", "Delete"]

      for word <- forbidden do
        refute Enum.any?(flat, &String.contains?(&1, word)),
               "Expected #{inspect(word)} not to appear in Moderation render output. " <>
                 "Found in: #{inspect(Enum.filter(flat, &String.contains?(&1, word)))}"
      end
    end
  end

  describe "handle_key/2" do
    setup %{state: state} do
      state = put_in(state, [:screen_state, :moderation], Moderation.init_screen_state())
      %{state: state}
    end

    test "Right arrow advances active_tab", %{state: state} do
      {:update, new_state, _cmds} = Moderation.handle_key(%{key: :right}, state)
      assert new_state.screen_state.moderation.active_tab == 1
    end

    test "digit '3' jumps to index 2 (USERS)", %{state: state} do
      {:update, new_state, _cmds} = Moderation.handle_key(%{key: :char, char: "3"}, state)
      assert new_state.screen_state.moderation.active_tab == 2
    end

    test "Home returns to tab 0", %{state: state} do
      # First advance to tab 2
      {:update, state2, _} = Moderation.handle_key(%{key: :right}, state)
      {:update, state3, _} = Moderation.handle_key(%{key: :right}, state2)
      assert state3.screen_state.moderation.active_tab == 2

      # Now Home should return to 0
      {:update, new_state, _cmds} = Moderation.handle_key(%{key: :home}, state3)
      assert new_state.screen_state.moderation.active_tab == 0
    end

    test "End jumps to last tab", %{state: state} do
      {:update, new_state, _cmds} = Moderation.handle_key(%{key: :end}, state)
      assert new_state.screen_state.moderation.active_tab == 4
    end

    test "'Q' returns to :main_menu", %{state: state} do
      {:update, new_state, _cmds} = Moderation.handle_key(%{key: :char, char: "Q"}, state)
      assert new_state.current_screen == :main_menu
    end

    test "'q' returns to :main_menu", %{state: state} do
      {:update, new_state, _cmds} = Moderation.handle_key(%{key: :char, char: "q"}, state)
      assert new_state.current_screen == :main_menu
    end

    test "unknown key returns :no_match", %{state: state} do
      assert :no_match = Moderation.handle_key(%{key: :char, char: "z"}, state)
    end

    test "Moderation screen does NOT dispatch fake moderation commands", %{state: state} do
      forbidden_commands = [:ban_user, :approve_queue_item, :remove_post, :issue_sanction]

      keys = [
        %{key: :right},
        %{key: :left},
        %{key: :home},
        %{key: :end},
        %{key: :char, char: "1"},
        %{key: :char, char: "2"},
        %{key: :char, char: "3"}
      ]

      for key <- keys do
        case Moderation.handle_key(key, state) do
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
