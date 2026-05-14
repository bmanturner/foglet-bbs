defmodule Foglet.TUI.TerminalAlertTest do
  use ExUnit.Case, async: true

  alias Foglet.TUI.TerminalAlert

  describe "mode normalization" do
    test "defaults missing preferences to terminal_bell" do
      assert TerminalAlert.mode_from_user(%{preferences: %{}}) == :terminal_bell
      assert TerminalAlert.mode_from_user(%{preferences: nil}) == :terminal_bell
      assert TerminalAlert.mode_from_user(nil) == :terminal_bell
    end

    test "accepts only supported modes and falls back safely" do
      assert TerminalAlert.mode_from_user(%{preferences: %{"notification_alert" => "off"}}) ==
               :off

      assert TerminalAlert.mode_from_user(%{
               preferences: %{"notification_alert" => "terminal_bell"}
             }) == :terminal_bell

      assert TerminalAlert.mode_from_user(%{
               preferences: %{"notification_alert" => "desktop_osc_best_effort"}
             }) == :desktop_osc_best_effort

      assert TerminalAlert.mode_from_user(%{preferences: %{"notification_alert" => "\e]evil\a"}}) ==
               :terminal_bell
    end
  end

  describe "safe terminal payloads" do
    test "off emits nothing" do
      assert TerminalAlert.sequence(:off) == nil
    end

    test "terminal_bell emits BEL only" do
      assert TerminalAlert.sequence(:terminal_bell) == <<7>>
    end

    test "OSC mode emits only generic text and never notification content" do
      seq = TerminalAlert.sequence(:desktop_osc_best_effort, %{body: "secret \e]52 clipboard"})

      assert seq == "\e]9;Foglet: new notification\a"
      refute seq =~ "secret"
      refute seq =~ "clipboard"
    end
  end

  describe "storm guard" do
    test "allows first alert and suppresses repeats within the quiet window" do
      state = %{}
      assert {:emit, state} = TerminalAlert.check_rate_limit(state, 1_000)
      assert {:suppress, ^state} = TerminalAlert.check_rate_limit(state, 1_500)
      assert {:emit, _state} = TerminalAlert.check_rate_limit(state, 3_100)
    end
  end
end
