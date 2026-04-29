defmodule Foglet.TUI.AppStructTest do
  use ExUnit.Case, async: true

  alias Foglet.TUI.App

  describe "struct shape (Phase 39 R1, D-19)" do
    @tag :phase39_target
    test "%App{} contains exactly the eight runtime-shell fields" do
      keys = App.__struct__() |> Map.keys() |> Enum.sort()

      assert keys == [
               :__struct__,
               :current_screen,
               :current_user,
               :modal,
               :route_params,
               :screen_state,
               :session_context,
               :session_pid,
               :terminal_size
             ]
    end

    @tag :phase39_target
    test "%App{} contains none of the seven legacy fields" do
      keys = App.__struct__() |> Map.keys() |> MapSet.new()

      legacy = [
        :current_board,
        :current_thread,
        :current_thread_list,
        :posts,
        :read_position,
        :composer_draft,
        :board_list
      ]

      Enum.each(legacy, fn field ->
        refute MapSet.member?(keys, field),
               "expected legacy field #{inspect(field)} to be deleted"
      end)
    end
  end
end
