defmodule Foglet.TUI.AppTest do
  use ExUnit.Case, async: true

  describe "Foglet.TUI.App.init/2 (SSH-04, SSH-06)" do
    @tag :pending
    test "initializes with current_screen: :login when session_context has no user_id (SSH-04)" do
      flunk("Pending — Plan 03 implements Foglet.TUI.App.init/2")
    end

    @tag :pending
    test "initializes with current_screen: :main_menu when session_context has an authenticated user" do
      flunk("Pending — Plan 03 implements Foglet.TUI.App.init/2 authenticated path")
    end

    @tag :pending
    test "initializes terminal_size from session_context" do
      flunk("Pending — Plan 03 implements Foglet.TUI.App.init/2 terminal_size")
    end
  end

  describe "Foglet.TUI.App.update/2 (SSH-06, SSH-08)" do
    @tag :pending
    test "updates terminal_size on {:window_change, cols, rows} message (SSH-06)" do
      flunk("Pending — Plan 03 implements :window_change handler")
    end

    @tag :pending
    test "navigates to :board_list on 'B' key from main menu (SSH-08)" do
      flunk("Pending — Plan 04 implements main menu key routing")
    end

    @tag :pending
    test "navigates to :post_composer on 'R' key from post reader" do
      flunk("Pending — Plan 04 implements post reader key routing")
    end

    @tag :pending
    test "dispatches unhandled keys to current screen's handle_key/2" do
      flunk("Pending — Plan 03 implements screen-scoped key dispatch")
    end

    @tag :pending
    test "returns {state, []} from every update/2 clause (Pitfall 5)" do
      flunk("Pending — Plan 03 implements update/2 arity contract")
    end
  end

  describe "Foglet.TUI.App.view/1 routing (SSH-07)" do
    @tag :pending
    test "renders login screen module when current_screen == :login" do
      flunk("Pending — Plan 03 implements view/1 dispatch")
    end

    @tag :pending
    test "renders register screen when current_screen == :register" do
      flunk("Pending — Plan 03 implements view/1 dispatch")
    end

    @tag :pending
    test "renders verify screen when current_screen == :verify" do
      flunk("Pending — Plan 03 implements view/1 dispatch")
    end

    @tag :pending
    test "renders main_menu when current_screen == :main_menu" do
      flunk("Pending — Plan 04 implements main_menu screen")
    end

    @tag :pending
    test "renders board_list when current_screen == :board_list" do
      flunk("Pending — Plan 04 implements board_list screen")
    end

    @tag :pending
    test "renders thread_list when current_screen == :thread_list" do
      flunk("Pending — Plan 04 implements thread_list screen")
    end

    @tag :pending
    test "renders post_reader when current_screen == :post_reader" do
      flunk("Pending — Plan 04 implements post_reader screen")
    end

    @tag :pending
    test "renders post_composer when current_screen == :post_composer" do
      flunk("Pending — Plan 04 implements post_composer screen")
    end
  end

  describe "read pointer flush on screen transition (SSH-09)" do
    @tag :pending
    test "flushes board_read_pointer to DB when leaving :post_reader" do
      flunk("Pending — Plan 04 implements read-pointer flush")
    end

    @tag :pending
    test "flushes thread_read_pointer to DB when leaving :post_reader" do
      flunk("Pending — Plan 04 implements thread-read-pointer flush")
    end
  end
end
