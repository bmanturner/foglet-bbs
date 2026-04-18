defmodule Foglet.TUI.Screens.LoginTest do
  use ExUnit.Case, async: true

  describe "Foglet.TUI.Screens.Login (SSH-04)" do
    @tag :pending
    test "render/1 shows [L] Login, [R] Register, [Q] Quit when registration_mode != :disabled (D-22)" do
      flunk("Pending — Plan 03 implements Foglet.TUI.Screens.Login")
    end

    @tag :pending
    test "render/1 HIDES [R] Register when registration_mode is :disabled (D-06)" do
      flunk("Pending — Plan 03 implements registration gating in Login screen")
    end

    @tag :pending
    test "handle_key/2 'L' transitions to login-form sub-state" do
      flunk("Pending — Plan 03 implements Login.handle_key/2")
    end

    @tag :pending
    test "handle_key/2 'R' transitions to :register when registration enabled" do
      flunk("Pending — Plan 03 implements Login.handle_key/2 register path")
    end

    @tag :pending
    test "handle_key/2 'Q' returns a {:terminate, :user_quit} command" do
      flunk("Pending — Plan 03 implements quit handler")
    end
  end
end
