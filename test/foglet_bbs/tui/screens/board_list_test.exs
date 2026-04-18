defmodule Foglet.TUI.Screens.BoardListTest do
  use ExUnit.Case, async: true

  describe "Foglet.TUI.Screens.BoardList (SSH-07, SSH-08)" do
    @tag :pending
    test "render/1 lists subscribed boards with unread counts" do
      flunk("Pending — Plan 04 implements BoardList (calls Foglet.Boards.unread_counts/1)")
    end

    @tag :pending
    test "arrow keys move selection up/down" do
      flunk("Pending — Plan 04 implements selection state")
    end

    @tag :pending
    test "enter opens selected board (transition to :thread_list)" do
      flunk("Pending — Plan 04 implements board selection")
    end

    @tag :pending
    test "renders empty-state message when no boards subscribed" do
      flunk("Pending — Plan 04 implements empty state")
    end
  end
end
