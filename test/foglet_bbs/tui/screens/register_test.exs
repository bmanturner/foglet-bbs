defmodule Foglet.TUI.Screens.RegisterTest do
  use ExUnit.Case, async: true

  describe "Foglet.TUI.Screens.Register (SSH-04, D-01..D-07, D-23)" do
    @tag :pending
    test "wizard sequence for :open mode is handle → email → password → verify (D-23)" do
      flunk("Pending — Plan 03 implements Register wizard state machine")
    end

    @tag :pending
    test "wizard sequence for :invite_only mode is invite_code → handle → email → password → verify (D-23)" do
      flunk("Pending — Plan 03 implements invite_code step")
    end

    @tag :pending
    test "invalid invite_code aborts wizard before handle step (D-23)" do
      flunk("Pending — Plan 03 implements invite validation")
    end

    @tag :pending
    test ":sysop_approved mode calls Accounts.register_pending_user/1 (D-05)" do
      flunk("Pending — Plan 03 implements pending-path wizard")
    end

    @tag :pending
    test ":sysop_approved mode transitions to disconnect screen after submission (D-07)" do
      flunk("Pending — Plan 03 implements pending disconnect message")
    end

    @tag :pending
    test "DOES NOT collect SSH public keys during registration (D-24)" do
      flunk("Pending — Plan 03 implements register wizard (no SSH key step)")
    end

    @tag :pending
    test "handle_key validates handle format via Accounts boundary" do
      flunk("Pending — Plan 03 implements handle validation in wizard")
    end
  end
end
