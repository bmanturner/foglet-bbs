defmodule Foglet.TUI.Screens.MainMenuTest do
  use ExUnit.Case, async: true

  describe "Foglet.TUI.Screens.MainMenu (SSH-07, SSH-08)" do
    @tag :pending
    test "render/1 shows menu options: Boards, Compose, Logout" do
      flunk("Pending — Plan 04 implements MainMenu")
    end

    @tag :pending
    test "handle_key/2 'B' returns {:navigate, :board_list} (SSH-08)" do
      flunk("Pending — Plan 04 implements navigation keys")
    end

    @tag :pending
    test "handle_key/2 'Q' returns {:terminate, :logout}" do
      flunk("Pending — Plan 04 implements quit")
    end

    @tag :pending
    test "key bar at bottom lists the single-key shortcuts (D-19)" do
      flunk("Pending — Plan 04 integrates KeyBar widget")
    end
  end
end
