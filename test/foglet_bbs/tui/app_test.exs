defmodule Foglet.TUI.AppTest do
  use ExUnit.Case, async: true

  alias Foglet.TUI.App

  describe "init/1 (SSH-04, SSH-06)" do
    test "with empty context returns :login and guest" do
      {:ok, state} = App.init(%{})
      assert state.current_screen == :login
      assert state.current_user == nil
      assert state.terminal_size == {80, 24}
    end

    test "with user in session_context returns :main_menu and authenticated user" do
      user = %Foglet.Accounts.User{id: "u1", handle: "alice"}
      {:ok, state} = App.init(%{session_context: %{user: user, user_id: "u1"}})
      assert state.current_screen == :main_menu
      assert state.current_user == user
    end

    test "uses terminal_size from context when provided" do
      {:ok, state} = App.init(%{terminal_size: {132, 50}})
      assert state.terminal_size == {132, 50}
    end

    test "stores session_pid from session_context" do
      # Use self() as a fake session pid
      {:ok, state} = App.init(%{session_context: %{session_pid: self()}})
      assert state.session_pid == self()
    end

    test "reads context from Lifecycle-style options map" do
      user = %Foglet.Accounts.User{id: "u2", handle: "bob"}

      nested_ctx = %{
        session_context: %{user: user, user_id: "u2", session_pid: nil},
        terminal_size: {120, 40}
      }

      # Lifecycle passes %{width:, height:, options: [context: %{...}]}
      lifecycle_context = %{width: 120, height: 40, options: [context: nested_ctx]}
      {:ok, state} = App.init(lifecycle_context)
      assert state.current_screen == :main_menu
      assert state.current_user == user
      assert state.terminal_size == {120, 40}
    end
  end

  describe "update/2 (SSH-06, SSH-08)" do
    setup do
      {:ok, state} = App.init(%{})
      %{state: state}
    end

    test "updates terminal_size on {:window_change, cols, rows} (SSH-06)", %{state: state} do
      {new_state, cmds} = App.update({:window_change, 120, 40}, state)
      assert new_state.terminal_size == {120, 40}
      assert cmds == []
    end

    test ":navigate changes current_screen", %{state: state} do
      {new_state, _} = App.update({:navigate, :board_list}, state)
      assert new_state.current_screen == :board_list
    end

    test ":navigate clears an active modal", %{state: state} do
      state_with_modal = %{state | modal: %{message: "old", type: :info}}
      {new_state, _} = App.update({:navigate, :main_menu}, state_with_modal)
      assert new_state.modal == nil
    end

    test ":set_user transitions to main_menu", %{state: state} do
      user = %Foglet.Accounts.User{id: "u2", handle: "bob"}
      {new_state, _} = App.update({:set_user, user}, state)
      assert new_state.current_user == user
      assert new_state.current_screen == :main_menu
    end

    test ":show_modal sets modal, :dismiss_modal clears it", %{state: state} do
      modal = %{message: "hi", type: :info}
      {with_modal, _} = App.update({:show_modal, modal}, state)
      assert with_modal.modal == modal

      {cleared, _} = App.update(:dismiss_modal, with_modal)
      assert cleared.modal == nil
    end

    test "returns {state, []} for unknown message", %{state: state} do
      assert {^state, []} = App.update({:totally_unknown, 42}, state)
    end

    test "all clauses return a 2-tuple with commands list (Pitfall 5)", %{state: state} do
      for msg <- [
            {:window_change, 100, 30},
            {:navigate, :main_menu},
            :dismiss_modal,
            {:totally_unknown, 42}
          ] do
        assert {_state, list} = App.update(msg, state)
        assert is_list(list)
      end
    end

    test "dispatches {:key, key_event} to current screen's handle_key/2", %{state: state} do
      # 'Q' from :login screen should return a quit command
      {_new_state, cmds} = App.update({:key, %{key: "Q"}}, state)
      assert [%Raxol.Core.Runtime.Command{type: :quit}] = cmds
    end

    test ":heartbeat_tick calls Session.heartbeat when session_pid is set", %{state: state} do
      # Use self() as a fake session_pid — heartbeat is a cast so it just sends
      # a GenServer cast message. We verify the handler doesn't crash.
      state_with_session = %{state | session_pid: self()}
      assert {^state_with_session, []} = App.update(:heartbeat_tick, state_with_session)
    end

    test ":heartbeat_tick is a no-op when session_pid is nil", %{state: state} do
      assert {^state, []} = App.update(:heartbeat_tick, state)
    end

    test "{:session_replaced, user_id} shows modal and issues quit command", %{state: state} do
      {new_state, cmds} = App.update({:session_replaced, "u1"}, state)
      assert new_state.modal != nil
      assert new_state.modal.type == :warning
      assert Enum.any?(cmds, &match?(%Raxol.Core.Runtime.Command{type: :quit}, &1))
    end

    test "{:promote_session, user} transitions to main_menu and sets current_user", %{
      state: state
    } do
      user = %Foglet.Accounts.User{id: "u3", handle: "carol", role: :user}
      state_with_session = %{state | session_pid: self()}
      {new_state, cmds} = App.update({:promote_session, user}, state_with_session)
      assert new_state.current_user == user
      assert new_state.current_screen == :main_menu
      assert cmds == []
    end

    test "{:promote_session, user} is safe when session_pid is nil", %{state: state} do
      user = %Foglet.Accounts.User{id: "u4", handle: "dave", role: :user}
      {new_state, cmds} = App.update({:promote_session, user}, state)
      assert new_state.current_user == user
      assert new_state.current_screen == :main_menu
      assert cmds == []
    end
  end

  describe "view/1 routing (SSH-07)" do
    setup do
      {:ok, state} = App.init(%{})
      %{state: state}
    end

    test "renders without crashing for every current_screen value", %{state: state} do
      for screen <- [
            :login,
            :register,
            :verify,
            :main_menu,
            :board_list,
            :thread_list,
            :post_reader,
            :post_composer
          ] do
        s = %{state | current_screen: screen}
        assert _ = App.view(s)
      end
    end

    test "renders with modal without crashing", %{state: state} do
      s = %{state | modal: %{type: :info, message: "Test"}}
      assert _ = App.view(s)
    end
  end

  describe "subscribe/1" do
    test "returns empty list when session_pid is nil" do
      {:ok, state} = App.init(%{})
      assert App.subscribe(state) == []
    end

    test "returns heartbeat subscription when session_pid is set" do
      {:ok, state} = App.init(%{session_context: %{session_pid: self()}})
      subs = App.subscribe(state)
      assert subs != []
    end
  end
end
