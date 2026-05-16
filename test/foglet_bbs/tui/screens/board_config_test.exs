defmodule Foglet.TUI.Screens.BoardConfigTest do
  use ExUnit.Case, async: true

  alias Foglet.Accounts.User
  alias Foglet.TUI.Context
  alias Foglet.TUI.Effect
  alias Foglet.TUI.Screens.BoardConfig
  alias Foglet.TUI.Screens.BoardConfig.State

  @actor %User{id: "u1", handle: "alice", role: :sysop, status: :active}

  defp context do
    Context.new(
      current_user: @actor,
      route: :thread_list,
      route_params: %{board_id: "b1"},
      terminal_size: {80, 24}
    )
  end

  describe "CONFIG keybar" do
    test "list mode advertises list actions" do
      [%{commands: commands}] = BoardConfig.keybar_groups(%State{mode: :list}, context())

      assert Enum.any?(commands, &(&1.key == "A" and &1.label == "Add feed"))
      assert Enum.any?(commands, &(&1.key == "T" and &1.label == "Edit selected TTL"))
      assert Enum.any?(commands, &(&1.key == "R" and &1.label == "Refresh"))
    end

    test "add mode advertises input actions, not list actions" do
      [%{commands: commands}] = BoardConfig.keybar_groups(%State{mode: :add}, context())

      refute Enum.any?(commands, &(&1.key in ["A", "T", "R"]))
      assert Enum.any?(commands, &(&1.key == "Enter" and &1.label == "Save/validate"))
      assert Enum.any?(commands, &(&1.key == "Backspace" and &1.label == "Delete"))
      assert Enum.any?(commands, &(&1.key == "Esc" and &1.label == "Cancel"))
    end

    test "ttl mode advertises TTL save input actions" do
      [%{commands: commands}] = BoardConfig.keybar_groups(%State{mode: :ttl}, context())

      refute Enum.any?(commands, &(&1.key in ["A", "T", "R"]))
      assert Enum.any?(commands, &(&1.key == "Enter" and &1.label == "Save"))
      assert Enum.any?(commands, &(&1.key == "Backspace" and &1.label == "Delete"))
    end
  end

  describe "TTL update" do
    test "enter in TTL mode targets the selected persisted feed" do
      feed = %{id: "feed-1", title: "Dispatch", cache_ttl_seconds: 3600}
      state = %State{mode: :ttl, feeds: [feed], ttl_input: "7200", selected_index: 0}

      {new_state,
       [
         %Effect{
           type: :task,
           payload: %{op: :update_feed_ttl, screen_key: screen_key}
         }
       ]} =
        BoardConfig.update({:key, %{key: :enter}}, state, context())

      assert screen_key == Effect.current_screen_key()
      assert new_state.message == "Saving TTL for selected feed…"
    end
  end
end
