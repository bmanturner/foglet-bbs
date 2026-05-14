defmodule Foglet.TUI.App.TerminalNotificationAlertTest do
  use ExUnit.Case, async: true

  alias Foglet.TUI.App
  alias Foglet.TUI.App.Effects
  alias Foglet.TUI.App.RuntimeMessages
  alias Foglet.TUI.Effect

  test "new notification for current user emits configured terminal alert effect" do
    state = %App{
      current_user: %{id: "u1", preferences: %{"notification_alert" => "terminal_bell"}},
      session_context: %{}
    }

    {state, effects} =
      RuntimeMessages.handle({:notification, "u1", :dm, %{body: "secret"}}, state)

    assert [%Effect{type: :terminal, payload: {:alert, :terminal_bell}}] = effects
    assert state.modal.message == "New message: secret"
  end

  test "new notification for another user does not emit an alert" do
    state = %App{
      current_user: %{id: "u1", preferences: %{"notification_alert" => "terminal_bell"}},
      session_context: %{}
    }

    {_state, effects} =
      RuntimeMessages.handle({:notification, "u2", :dm, %{body: "secret"}}, state)

    assert effects == []
  end

  test "off preference preserves inbox modal but emits no terminal alert" do
    state = %App{current_user: %{id: "u1", preferences: %{"notification_alert" => "off"}}}

    {state, effects} =
      RuntimeMessages.handle({:notification, "u1", :mention, %{thread_title: "hello"}}, state)

    assert effects == []
    assert state.modal.message == "You were mentioned in: hello"
  end

  test "coalesces repeated notification alerts in one session" do
    state = %App{current_user: %{id: "u1", preferences: %{}}}

    {state, first_effects} = RuntimeMessages.handle({:notification, "u1", :system, %{}}, state)
    {_state, second_effects} = RuntimeMessages.handle({:notification, "u1", :system, %{}}, state)

    assert [%Effect{type: :terminal}] = first_effects
    assert second_effects == []
  end

  test "terminal alert effect sends safe sequence only to this session handler" do
    state = %App{session_context: %{door_handler_pid: self()}}

    assert {%App{}, []} = Effects.apply_effect(state, Effect.terminal_alert(:terminal_bell))
    assert_receive {:foglet_terminal_alert, <<7>>}
  end
end
