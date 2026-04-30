defmodule Foglet.TUI.App.ScreenStatesTest do
  use ExUnit.Case, async: true

  alias Foglet.TUI.App
  alias Foglet.TUI.App.ScreenStates

  defp state(attrs \\ %{}) do
    attrs = Map.new(attrs)

    struct!(
      App,
      Map.merge(
        %{
          current_screen: :main_menu,
          screen_state: %{main_menu: %{seeded: true}, board_list: %{cursor: 3}},
          terminal_size: {100, 30}
        },
        attrs
      )
    )
  end

  describe "get/2" do
    test "returns the screen state for a known key" do
      assert ScreenStates.get(state(), :main_menu) == %{seeded: true}
      assert ScreenStates.get(state(), :board_list) == %{cursor: 3}
    end

    test "returns nil for an unknown key" do
      assert ScreenStates.get(state(), :unknown) == nil
    end

    test "is nil-safe when state.screen_state is nil" do
      assert ScreenStates.get(state(screen_state: nil), :main_menu) == nil
    end
  end

  describe "put/3" do
    test "writes the value and returns the updated %App{}" do
      new_state = ScreenStates.put(state(), :main_menu, %{seeded: false})
      assert new_state.screen_state.main_menu == %{seeded: false}
    end

    test "is nil-safe when state.screen_state is nil" do
      new_state = ScreenStates.put(state(screen_state: nil), :main_menu, %{x: 1})
      assert new_state.screen_state == %{main_menu: %{x: 1}}
    end
  end

  describe "update/4" do
    test "applies the update fn to the existing state" do
      new_state =
        ScreenStates.update(state(), :board_list, %{cursor: 0}, fn s ->
          %{s | cursor: s.cursor + 1}
        end)

      assert new_state.screen_state.board_list == %{cursor: 4}
    end

    test "uses the default initial value when key is absent" do
      new_state =
        ScreenStates.update(state(), :missing, %{cursor: 7}, fn s ->
          %{s | cursor: s.cursor + 1}
        end)

      assert new_state.screen_state.missing == %{cursor: 7}
    end
  end

  describe "delete/2" do
    test "removes the key and returns the updated %App{}" do
      new_state = ScreenStates.delete(state(), :main_menu)
      refute Map.has_key?(new_state.screen_state, :main_menu)
      assert Map.has_key?(new_state.screen_state, :board_list)
    end

    test "is nil-safe when state.screen_state is nil" do
      new_state = ScreenStates.delete(state(screen_state: nil), :main_menu)
      assert new_state.screen_state == %{}
    end
  end
end
