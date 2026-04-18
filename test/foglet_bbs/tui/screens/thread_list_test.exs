defmodule Foglet.TUI.Screens.ThreadListTest do
  use ExUnit.Case, async: true

  describe "Foglet.TUI.Screens.ThreadList (SSH-07, SSH-08)" do
    @tag :pending
    test "render/1 shows threads newest-activity-first with unread counts" do
      flunk("Pending — Plan 04 implements ThreadList (calls Foglet.Threads.list_threads/1)")
    end

    @tag :pending
    test "sticky threads appear at top" do
      flunk("Pending — Plan 04 implements sticky ordering")
    end

    @tag :pending
    test "enter opens selected thread (transition to :post_reader)" do
      flunk("Pending — Plan 04 implements thread selection")
    end
  end
end
