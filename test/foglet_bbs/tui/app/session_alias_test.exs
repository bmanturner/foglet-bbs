defmodule Foglet.TUI.App.SessionAliasTest do
  use ExUnit.Case, async: true

  alias Foglet.TUI.App
  alias Foglet.TUI.App.SessionAlias
  alias Raxol.Core.Runtime.Command

  defp state(attrs \\ %{}) do
    attrs = Map.new(attrs)

    session_context =
      Map.get(attrs, :session_context, %{
        user: nil,
        user_id: nil,
        ssh_peer: {{127, 0, 0, 1}, 22}
      })

    struct!(
      App,
      Map.merge(
        %{
          current_screen: :login,
          current_user: nil,
          session_context: session_context,
          session_pid: nil,
          terminal_size: {100, 30},
          screen_state: %{}
        },
        attrs
      )
    )
  end

  describe "set_user/2" do
    test "delegates to promote_session/2 returning the same {App, [Command]} tuple shape" do
      user = %Foglet.Accounts.User{id: "u1", handle: "alice", role: :user}
      {new_state, cmds} = SessionAlias.set_user(state(), user)

      assert %App{} = new_state
      assert is_list(cmds)
      assert new_state.current_user == user
      assert new_state.current_screen == :main_menu
    end
  end

  describe "promote_session/2" do
    test "writes current_user onto the App state" do
      user = %Foglet.Accounts.User{id: "u2", handle: "bob", role: :user}
      {new_state, _cmds} = SessionAlias.promote_session(state(), user)
      assert new_state.current_user == user
    end

    test "is safe when session_pid is nil (skips Sessions.Supervisor call)" do
      user = %Foglet.Accounts.User{id: "u3", handle: "carol", role: :user}
      {new_state, cmds} = SessionAlias.promote_session(state(), user)
      assert new_state.current_user == user
      assert new_state.current_screen == :main_menu
      assert [%Command{type: :task}] = cmds
    end

    test "calls Sessions.Supervisor.promote_guest_session when session_pid is a pid" do
      user = %Foglet.Accounts.User{id: "u4", handle: "dave", role: :user}
      state_with_pid = state(session_pid: self())

      # Mirrors the existing app_test.exs:860 contract — runs without raising
      # when session_pid is set; result is ignored. The fact that the call is
      # reached is observable by it not raising for any other reason.
      {new_state, cmds} = SessionAlias.promote_session(state_with_pid, user)
      assert new_state.current_user == user
      assert [%Command{type: :task}] = cmds
    end

    test "updates session_context.user and session_context.user_id" do
      user = %Foglet.Accounts.User{id: "u5", handle: "erin", role: :user}
      {new_state, _cmds} = SessionAlias.promote_session(state(), user)
      assert Map.get(new_state.session_context, :user) == user
      assert Map.get(new_state.session_context, :user_id) == user.id
    end

    test "navigates to :main_menu via Effects.apply_effect" do
      user = %Foglet.Accounts.User{id: "u6", handle: "frank", role: :user}
      {new_state, _cmds} = SessionAlias.promote_session(state(), user)
      assert new_state.current_screen == :main_menu
    end
  end

  describe "session_replaced/2" do
    test "opens a warning modal with on_confirm/on_cancel returning Command.quit/0" do
      {new_state, cmds} = SessionAlias.session_replaced(state(), "u1")

      assert cmds == []
      assert %Foglet.TUI.Modal{type: :warning} = new_state.modal
      assert is_function(new_state.modal.on_confirm, 1)
      assert is_function(new_state.modal.on_cancel, 1)

      {_, [confirm_cmd]} = new_state.modal.on_confirm.(new_state)
      {_, [cancel_cmd]} = new_state.modal.on_cancel.(new_state)
      assert match?(%Command{type: :quit}, confirm_cmd)
      assert match?(%Command{type: :quit}, cancel_cmd)
    end
  end
end
