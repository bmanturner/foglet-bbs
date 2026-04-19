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
      {_new_state, cmds} = App.update({:key, %{key: :char, char: "Q"}}, state)
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
    test "returns empty list when session_pid is nil and no user" do
      {:ok, state} = App.init(%{})
      assert App.subscribe(state) == []
    end

    test "returns heartbeat subscription when session_pid is set" do
      {:ok, state} = App.init(%{session_context: %{session_pid: self()}})
      subs = App.subscribe(state)
      assert subs != []
    end

    test "returns PubSub custom subscription when current_user is set (Audit #12)" do
      user = %Foglet.Accounts.User{id: "u-pubsub", handle: "alice"}
      {:ok, state} = App.init(%{session_context: %{user: user, user_id: "u-pubsub"}})
      subs = App.subscribe(state)

      assert Enum.any?(subs, fn
               %Raxol.Core.Runtime.Subscription{type: :custom} -> true
               _ -> false
             end),
             "expected at least one :custom subscription for PubSub"
    end

    test "no PubSub subscription when not logged in" do
      {:ok, state} = App.init(%{})
      subs = App.subscribe(state)
      refute Enum.any?(subs, &match?(%Raxol.Core.Runtime.Subscription{type: :custom}, &1))
    end

    test "board_list screen adds 'boards' topic" do
      user = %Foglet.Accounts.User{id: "u1", handle: "alice"}
      {:ok, state} = App.init(%{session_context: %{user: user, user_id: "u1"}})
      state = %{state | current_screen: :board_list}
      subs = App.subscribe(state)

      pubsub_sub = Enum.find(subs, &match?(%Raxol.Core.Runtime.Subscription{type: :custom}, &1))
      assert pubsub_sub != nil
      assert "boards" in pubsub_sub.data.args.topics
    end

    test "thread_list screen adds board:<id> topic when current_board is set" do
      user = %Foglet.Accounts.User{id: "u1", handle: "alice"}
      board = %{id: "b-99", name: "General"}
      {:ok, state} = App.init(%{session_context: %{user: user, user_id: "u1"}})
      state = %{state | current_screen: :thread_list, current_board: board}
      subs = App.subscribe(state)

      pubsub_sub = Enum.find(subs, &match?(%Raxol.Core.Runtime.Subscription{type: :custom}, &1))
      assert pubsub_sub != nil
      assert "board:b-99" in pubsub_sub.data.args.topics
    end

    test "post_reader screen adds thread:<id> topic when current_thread is set" do
      user = %Foglet.Accounts.User{id: "u1", handle: "alice"}
      thread = %{id: "t-42", title: "Hello World"}
      {:ok, state} = App.init(%{session_context: %{user: user, user_id: "u1"}})
      state = %{state | current_screen: :post_reader, current_thread: thread}
      subs = App.subscribe(state)

      pubsub_sub = Enum.find(subs, &match?(%Raxol.Core.Runtime.Subscription{type: :custom}, &1))
      assert pubsub_sub != nil
      assert "thread:t-42" in pubsub_sub.data.args.topics
    end
  end

  describe "I/O command round-trip (Audit #11)" do
    setup do
      {:ok, base_state} = App.init(%{})

      state = %{
        base_state
        | current_user: %Foglet.Accounts.User{id: "u1", handle: "alice"}
      }

      %{state: state}
    end

    test "{:load_boards} returns a Command.task (not a no-op), {state, [%Command{}]}", %{
      state: state
    } do
      {new_state, cmds} = App.update({:load_boards}, state)
      # State unchanged — I/O happens in the task, not synchronously
      assert new_state == state
      assert [%Raxol.Core.Runtime.Command{type: :task}] = cmds
    end

    test "{:boards_loaded, boards} assigns board_list to state", %{state: state} do
      fake_boards = [%{id: "b1", name: "General", unread_count: 0}]
      {new_state, cmds} = App.update({:boards_loaded, fake_boards}, state)
      assert new_state.board_list == fake_boards
      assert cmds == []
    end

    test "{:load_threads, board_id} returns a Command.task", %{state: state} do
      {_new_state, cmds} = App.update({:load_threads, "b1"}, state)
      assert [%Raxol.Core.Runtime.Command{type: :task}] = cmds
    end

    test "{:threads_loaded, threads} assigns current_thread_list", %{state: state} do
      threads = [%{id: "t1", title: "Hello", sticky: false, last_post_at: DateTime.utc_now()}]
      {new_state, []} = App.update({:threads_loaded, threads}, state)
      assert new_state.current_thread_list == threads
    end

    test "{:load_posts, thread_id} returns a Command.task", %{state: state} do
      {_new_state, cmds} = App.update({:load_posts, "t1"}, state)
      assert [%Raxol.Core.Runtime.Command{type: :task}] = cmds
    end

    test "{:posts_loaded, posts} assigns posts", %{state: state} do
      posts = [%{id: "p1", body: "Hello", inserted_at: DateTime.utc_now()}]
      {new_state, []} = App.update({:posts_loaded, posts}, state)
      assert new_state.posts == posts
    end

    test "{:flush_read_pointers, ctx} returns a Command.task", %{state: state} do
      ctx = %{user_id: "u1", board_id: "b1", thread_id: "t1"}
      {_new_state, cmds} = App.update({:flush_read_pointers, ctx}, state)
      assert [%Raxol.Core.Runtime.Command{type: :task}] = cmds
    end

    test "{:read_pointers_flushed, thread_id} clears read_position entry", %{state: state} do
      state_with_rp = %{state | read_position: %{"t1" => %{last_read_post_id: "p5"}}}
      {new_state, []} = App.update({:read_pointers_flushed, "t1"}, state_with_rp)
      assert Map.get(new_state.read_position, "t1") == nil
    end
  end

  describe "PubSub message handlers (Audit #12)" do
    setup do
      user = %Foglet.Accounts.User{id: "u1", handle: "alice"}
      {:ok, state} = App.init(%{session_context: %{user: user, user_id: "u1"}})
      %{state: state, user: user}
    end

    test "{:board_activity, board_id, event} on :board_list screen triggers load", %{
      state: state
    } do
      state = %{state | current_screen: :board_list}
      {_new_state, cmds} = App.update({:board_activity, "b1", :new_post}, state)
      # Should issue a load_boards task
      assert Enum.any?(cmds, &match?(%Raxol.Core.Runtime.Command{type: :task}, &1))
    end

    test "{:board_activity, board_id, event} on non-board_list screen is a no-op", %{
      state: state
    } do
      state = %{state | current_screen: :main_menu}
      {_new_state, cmds} = App.update({:board_activity, "b1", :new_post}, state)
      assert cmds == []
    end

    test "{:thread_activity, thread_id, event} on :post_reader for current thread triggers load",
         %{state: state} do
      thread = %{id: "t-match", title: "T"}
      state = %{state | current_screen: :post_reader, current_thread: thread}
      {_new_state, cmds} = App.update({:thread_activity, "t-match", :new_post}, state)
      assert Enum.any?(cmds, &match?(%Raxol.Core.Runtime.Command{type: :task}, &1))
    end

    test "{:thread_activity} for a different thread is a no-op", %{state: state} do
      thread = %{id: "t-other", title: "T"}
      state = %{state | current_screen: :post_reader, current_thread: thread}
      {_new_state, cmds} = App.update({:thread_activity, "t-match", :new_post}, state)
      assert cmds == []
    end

    test "{:notification, user_id, kind, payload} shows a modal", %{state: state} do
      {new_state, []} = App.update({:notification, "u1", :dm, "hey!"}, state)
      assert new_state.modal != nil
      assert new_state.modal.type == :info
      assert new_state.modal.message =~ "message"
    end
  end

  describe "modal key dismissal (task #6)" do
    setup do
      {:ok, state} = App.init(%{})
      %{state: state}
    end

    test ":info modal + Enter dismisses modal", %{state: state} do
      state_with_modal = %{state | modal: %{type: :info, message: "Hello"}}
      {new_state, _cmds} = App.update({:key, %{key: :enter}}, state_with_modal)
      assert new_state.modal == nil
    end

    test ":info modal + Escape dismisses modal", %{state: state} do
      state_with_modal = %{state | modal: %{type: :info, message: "Hello"}}
      {new_state, _cmds} = App.update({:key, %{key: :escape}}, state_with_modal)
      assert new_state.modal == nil
    end

    test ":info modal + Space dismisses modal", %{state: state} do
      state_with_modal = %{state | modal: %{type: :info, message: "Hello"}}
      {new_state, _cmds} = App.update({:key, %{key: :char, char: " "}}, state_with_modal)
      assert new_state.modal == nil
    end

    test ":error modal + Escape dismisses modal", %{state: state} do
      state_with_modal = %{state | modal: %{type: :error, message: "Oops"}}
      {new_state, _cmds} = App.update({:key, %{key: :escape}}, state_with_modal)
      assert new_state.modal == nil
    end

    test ":warning modal + Enter dismisses modal", %{state: state} do
      state_with_modal = %{state | modal: %{type: :warning, message: "Careful"}}
      {new_state, _cmds} = App.update({:key, %{key: :enter}}, state_with_modal)
      assert new_state.modal == nil
    end

    test "unrecognised key on :info modal leaves state unchanged", %{state: state} do
      modal = %{type: :info, message: "Hello"}
      state_with_modal = %{state | modal: modal}
      {new_state, cmds} = App.update({:key, %{key: :char, char: "x"}}, state_with_modal)
      assert new_state.modal == modal
      assert cmds == []
    end

    test ":confirm modal + Y dispatches {:confirm_modal, :yes} and dismisses", %{state: state} do
      state_with_modal = %{state | modal: %{type: :confirm, message: "Delete?"}}
      {new_state, _cmds} = App.update({:key, %{key: :char, char: "y"}}, state_with_modal)
      assert new_state.modal == nil
    end

    test ":confirm modal + N dispatches {:confirm_modal, :no} and dismisses", %{state: state} do
      state_with_modal = %{state | modal: %{type: :confirm, message: "Delete?"}}
      {new_state, _cmds} = App.update({:key, %{key: :char, char: "n"}}, state_with_modal)
      assert new_state.modal == nil
    end

    test ":confirm modal + Y invokes on_confirm callback", %{state: state} do
      on_confirm = fn _s -> {:navigate, :board_list} end
      modal = %{type: :confirm, message: "Go?", on_confirm: on_confirm}
      state_with_modal = %{state | modal: modal}
      {new_state, _cmds} = App.update({:key, %{key: :char, char: "y"}}, state_with_modal)
      assert new_state.modal == nil
      assert new_state.current_screen == :board_list
    end

    test ":confirm modal + N invokes on_cancel callback", %{state: state} do
      on_cancel = fn _s -> {:navigate, :post_reader} end
      modal = %{type: :confirm, message: "Go?", on_cancel: on_cancel}
      state_with_modal = %{state | modal: modal}
      {new_state, _cmds} = App.update({:key, %{key: :char, char: "n"}}, state_with_modal)
      assert new_state.modal == nil
      assert new_state.current_screen == :post_reader
    end
  end

  describe "modal intercept guard (Gap 4)" do
    setup do
      {:ok, state} = App.init(%{})
      %{state: state}
    end

    test "Enter dismisses :error modal even when login screen is in :login_form sub-state with :password focused",
         %{state: state} do
      # This reproduces the suspended-account scenario (Gap 4):
      # Login screen's handle_form_key/2 matches Enter when sub is :login_form and
      # focused_field is :password — it would normally call submit_login/1 which
      # calls Accounts.authenticate_by_password/2. The modal intercept guard must
      # catch this BEFORE the screen module gets the key.
      login_ss = %{
        sub: :login_form,
        form: %{handle: "alice", password: "", error: nil},
        focused_field: :password
      }

      state_with_modal = %{
        state
        | modal: %{type: :error, message: "suspended"},
          current_screen: :login,
          screen_state: %{login: login_ss}
      }

      {new_state, _cmds} = App.update({:key, %{key: :enter}}, state_with_modal)
      assert new_state.modal == nil,
             "Expected modal to be dismissed, got: #{inspect(new_state.modal)}"
    end

    test "Escape dismisses :error modal when login screen is in :login_form sub-state",
         %{state: state} do
      login_ss = %{
        sub: :login_form,
        form: %{handle: "alice", password: "", error: nil},
        focused_field: :handle
      }

      state_with_modal = %{
        state
        | modal: %{type: :error, message: "suspended"},
          current_screen: :login,
          screen_state: %{login: login_ss}
      }

      {new_state, _cmds} = App.update({:key, %{key: :escape}}, state_with_modal)
      assert new_state.modal == nil
    end
  end

  describe "command_result dispatcher (Gap 5)" do
    setup do
      {:ok, base_state} = App.init(%{})

      state = %{
        base_state
        | current_user: %Foglet.Accounts.User{id: "u1", handle: "alice"}
      }

      %{state: state}
    end

    test "{:command_result, {:boards_loaded, boards}} assigns board_list", %{state: state} do
      boards = [%{id: "b1", name: "General", unread_count: 0}]
      {new_state, cmds} = App.update({:command_result, {:boards_loaded, boards}}, state)
      assert new_state.board_list == boards
      assert cmds == []
    end

    test "{:command_result, {:threads_loaded, threads}} assigns current_thread_list",
         %{state: state} do
      threads = [%{id: "t1", title: "Hello", sticky: false, last_post_at: DateTime.utc_now()}]
      {new_state, cmds} = App.update({:command_result, {:threads_loaded, threads}}, state)
      assert new_state.current_thread_list == threads
      assert cmds == []
    end

    test "{:command_result, {:posts_loaded, posts}} assigns posts", %{state: state} do
      posts = [%{id: "p1", body: "Hello", inserted_at: DateTime.utc_now()}]
      {new_state, cmds} = App.update({:command_result, {:posts_loaded, posts}}, state)
      assert new_state.posts == posts
      assert cmds == []
    end

    test "{:command_result, {:unknown_result}} hits catch-all safely — returns {state, []}",
         %{state: state} do
      assert {^state, []} = App.update({:command_result, {:unknown_result}}, state)
    end
  end
end
