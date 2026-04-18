defmodule Foglet.TUI.AppTest do
  use ExUnit.Case, async: true

  alias Foglet.TUI.App

  describe "init/1 (SSH-04, SSH-06)" do
    test "with empty context returns :login and guest" do
      {state, cmds} = App.init(%{})
      assert state.current_screen == :login
      assert state.current_user == nil
      assert state.terminal_size == {80, 24}
      assert cmds == []
    end

    test "with user in session_context returns :main_menu and authenticated user" do
      user = %Foglet.Accounts.User{id: "u1", handle: "alice"}
      {state, _} = App.init(%{session_context: %{user: user, user_id: "u1"}})
      assert state.current_screen == :main_menu
      assert state.current_user == user
    end

    test "uses terminal_size from context when provided" do
      {state, _} = App.init(%{terminal_size: {132, 50}})
      assert state.terminal_size == {132, 50}
    end
  end

  describe "update/2 (SSH-06, SSH-08)" do
    setup do
      {state, _} = App.init(%{})
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
      # 'Q' from :login screen should return a terminate command
      {_new_state, cmds} = App.update({:key, %{key: "Q"}}, state)
      assert [{:terminate, :user_quit}] = cmds
    end
  end

  describe "view/1 routing (SSH-07)" do
    setup do
      {state, _} = App.init(%{})
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
end
