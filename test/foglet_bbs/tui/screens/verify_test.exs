defmodule Foglet.TUI.Screens.VerifyTest do
  use ExUnit.Case, async: true

  describe "Foglet.TUI.Screens.Verify (D-08..D-12)" do
    @tag :pending
    test "render/1 shows a prompt \"Enter 6-character code:\" (D-08, D-12)" do
      flunk("Pending — Plan 03 implements Verify screen")
    end

    @tag :pending
    test "handle_key/2 accumulates keypresses into a 6-char buffer" do
      flunk("Pending — Plan 03 implements code entry buffer")
    end

    @tag :pending
    test "on enter with 6-char code, calls Accounts.verify_email_code/2" do
      flunk("Pending — Plan 03 implements verify submission")
    end

    @tag :pending
    test "on success, transitions to :main_menu (D-12)" do
      flunk("Pending — Plan 03 implements success transition")
    end

    @tag :pending
    test "on :invalid_code, increments attempt counter and shows error modal (D-10)" do
      flunk("Pending — Plan 03 implements attempt counter (D-10)")
    end

    @tag :pending
    test "after 5 invalid attempts, enters cooldown state (D-10)" do
      flunk("Pending — Plan 03 implements cooldown (D-10)")
    end

    @tag :pending
    test "on :expired, shows message prompting user to request a new code" do
      flunk("Pending — Plan 03 implements expiry UX")
    end
  end
end
