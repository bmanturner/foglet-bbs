defmodule Foglet.TUI.AppTest do
  use ExUnit.Case, async: true

  alias Foglet.Config
  alias Foglet.TUI.App
  alias Foglet.TUI.App.Effects
  alias Foglet.TUI.Effect
  alias Foglet.TUI.Screens.BoardList.State, as: BoardListState
  alias Foglet.TUI.Screens.MainMenu.State, as: MainMenuState
  alias Foglet.TUI.Screens.NewThread.State, as: NewThreadState
  alias Foglet.TUI.Screens.PostComposer.State, as: PostComposerState
  alias Foglet.TUI.Screens.PostReader
  alias Foglet.TUI.Screens.PostReader.State, as: PostReaderState
  alias Foglet.TUI.Screens.Register.State, as: RegisterState
  alias Foglet.TUI.Screens.Sysop.State, as: SysopState
  alias Foglet.TUI.Screens.ThreadList.State, as: ThreadListState
  alias Foglet.TUI.Screens.Verify.State, as: VerifyState
  alias Foglet.TUI.SizeGate
  alias Foglet.TUI.Widgets.Input.TextInput
  alias Foglet.TUI.Widgets.Modal.Form

  defmodule FakeThreads do
    def list_threads("b1", _user_id) do
      [
        %{
          id: "t1",
          title: "Welcome",
          sticky: false,
          locked: false,
          post_count: 1,
          last_post_at: ~U[2026-04-28 18:00:00Z],
          created_by: %{handle: "alice"}
        }
      ]
    end

    def list_threads("b2", _user_id) do
      [
        %{
          id: "t2",
          title: "Second",
          sticky: false,
          locked: false,
          post_count: 1,
          last_post_at: ~U[2026-04-28 19:00:00Z],
          created_by: %{handle: "bob"}
        }
      ]
    end
  end

  defmodule FakePosts do
    alias Foglet.Posts.ReaderWindow

    # Phase 47 R1/R2: PostReader uses `list_reader_window/2` exclusively;
    # `list_posts/1` no longer exists in `Foglet.Posts`. The mock returns a
    # degenerate single-post window since the AppTest fixtures only carry one
    # post per thread.
    def list_reader_window("t1", _opts) do
      post = %{id: "p1", body: "Hello", message_number: 1, inserted_at: ~U[2026-04-28 18:00:00Z]}

      %ReaderWindow{
        posts: [post],
        first_message_number: post.message_number,
        last_message_number: post.message_number,
        has_previous?: false,
        has_next?: false,
        direction: :initial
      }
    end

    def list_reader_window("t2", _opts) do
      post = %{id: "p2", body: "Second", message_number: 2, inserted_at: ~U[2026-04-28 19:00:00Z]}

      %ReaderWindow{
        posts: [post],
        first_message_number: post.message_number,
        last_message_number: post.message_number,
        has_previous?: false,
        has_next?: false,
        direction: :initial
      }
    end
  end

  defmodule ModalSubmitTarget do
    def update({:modal_submit, kind, payload}, state, _context) do
      received = [{kind, payload} | Map.get(state || %{}, :received, [])]
      {Map.put(state || %{}, :received, received), []}
    end

    def update(_message, state, _context), do: {state || %{}, []}
  end

  defp fake_oneliners_context(extra) do
    Map.merge(%{domain: %{oneliners: Foglet.TUI.FakeOneliners}}, extra)
  end

  defp fake_moderation_context(extra) do
    Map.merge(
      %{domain: %{oneliners: Foglet.TUI.FakeOneliners, moderation: Foglet.TUI.FakeModeration}},
      extra
    )
  end

  defp interval_subscription(subscriptions, message) do
    Enum.find(subscriptions, fn
      %Raxol.Core.Runtime.Subscription{type: :interval, data: %{message: ^message}} -> true
      _ -> false
    end)
  end

  defp custom_subscription(subscriptions, module) do
    Enum.find(subscriptions, fn
      %Raxol.Core.Runtime.Subscription{type: :custom, data: %{module: ^module}} -> true
      _ -> false
    end)
  end

  defp text_contents(%{type: :text, content: content}), do: [content]

  defp text_contents(%{children: children}) when is_list(children) do
    Enum.flat_map(children, &text_contents/1)
  end

  defp text_contents(_element), do: []

  defp size_gate_text_contents(element) do
    case element do
      %{type: :flex, justify: :center, align: :center} -> text_contents(element)
      _other -> []
    end
  end

  defp size_gate_view?(element), do: size_gate_text_contents(element) != []

  # Seed the ETS config cache so render paths that call Config.get/2
  # (e.g. Login, Register, Verify screens) do not hit the DB.
  # Config.get/2 now only rescues Ecto.NoResultsError — other DB errors
  # propagate, so async tests without a DB checkout would fail without this.
  setup do
    Config.init_cache()
    :ets.insert(:foglet_config, {"registration_mode", "open"})
    :ets.insert(:foglet_config, {"delivery_mode", "no_email"})
    :ets.insert(:foglet_config, {"require_email_verification", false})
    :ets.insert(:foglet_config, {"email_verify_resend_cooldown_seconds", 60})
    :ets.insert(:foglet_config, {"invite_code_generators", "sysop_only"})
    # Sysop SITE form keys consumed by `Sysop.update(:load, ...)` on entry,
    # plus NewThread.init's optional config-driven limits. Seeding them here
    # keeps async unit tests off the Ecto sandbox.
    :ets.insert(:foglet_config, {"invite_generation_per_user_limit", 5})
    :ets.insert(:foglet_config, {"max_post_length", 8000})
    :ets.insert(:foglet_config, {"max_thread_title_length", 200})
    :ok
  end

  describe "init/1 (SSH-04, SSH-06)" do
    test "with empty context returns :login and guest" do
      {:ok, state} = App.init(%{})
      assert state.current_screen == :login
      assert state.current_user == nil
      assert state.terminal_size == {80, 24}
    end

    test "with user in session_context returns :main_menu and authenticated user" do
      Process.put(:fake_oneliners_owner, self())
      Process.put(:fake_oneliners_entries, [%{id: "ol1", body: "hello"}])
      user = %Foglet.Accounts.User{id: "u1", handle: "alice"}

      {:ok, state} =
        App.init(%{session_context: fake_oneliners_context(%{user: user, user_id: "u1"})})

      assert state.current_screen == :main_menu
      assert state.current_user == user

      assert %MainMenuState{recent_oneliners: []} = App.screen_state_for(state, :main_menu)

      # Phase 39 CR-01: init/1 itself doesn't fire :on_route_enter (Raxol's
      # init/1 contract returns {:ok, model} only — no commands). The actual
      # first-load dispatch happens via the InitialRouteEnterForwarder
      # subscription, which delivers :initial_route_enter to update/2 once
      # the Dispatcher starts. Simulate that here.
      refute_received {:list_recent_visible, 5}

      {state, cmds} = App.update(:initial_route_enter, state)

      # MainMenu's :on_route_enter clause ran, set oneliner_status to :loading,
      # and emitted the load task command.
      assert %MainMenuState{oneliner_status: :loading} =
               App.screen_state_for(state, :main_menu)

      assert [%Raxol.Core.Runtime.Command{type: :task, data: task}] = cmds

      assert {:screen_task_result, :main_menu, :load_oneliners, {:ok, [%{id: "ol1"}]}} =
               task.()

      assert_received {:list_recent_visible, 5}
    end

    test "pubkey-authenticated unconfirmed users route to verification when required" do
      :ets.insert(:foglet_config, {"require_email_verification", true})

      user = %Foglet.Accounts.User{
        id: "u1",
        handle: "alice",
        status: :active,
        confirmed_at: nil
      }

      {:ok, state} =
        App.init(%{
          session_context:
            fake_oneliners_context(%{
              user: user,
              user_id: "u1",
              pubkey_authenticated: true
            })
        })

      assert state.current_screen == :verify
      assert state.current_user == user
      assert App.screen_state_for(state, :main_menu) == nil
    end

    test "authenticated user can trigger bounded oneliner load command" do
      Process.put(:fake_oneliners_owner, self())
      Process.put(:fake_oneliners_entries, [%{id: "ol1", body: "hello"}])
      user = %Foglet.Accounts.User{id: "u1", handle: "alice"}

      {:ok, state} =
        App.init(%{
          session_context: fake_oneliners_context(%{user: user, user_id: "u1"})
        })

      assert state.current_screen == :main_menu
      {state, cmds} = App.update({:navigate, :main_menu}, %{state | current_screen: :board_list})
      assert state.current_screen == :main_menu
      assert [%Raxol.Core.Runtime.Command{type: :task, data: task}] = cmds

      assert {:screen_task_result, :main_menu, :load_oneliners, {:ok, [%{id: "ol1"}]}} =
               task.()

      assert_received {:list_recent_visible, 5}
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
        session_context: fake_oneliners_context(%{user: user, user_id: "u2", session_pid: nil}),
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

    test "updates terminal_size on %Raxol.Core.Events.Event{type: :resize, ...} (SSH-06)", %{
      state: state
    } do
      resize_event = %Raxol.Core.Events.Event{
        type: :resize,
        data: %{width: 120, height: 40}
      }

      {new_state, cmds} = App.update(resize_event, state)
      assert new_state.terminal_size == {120, 40}
      assert cmds == []
    end

    test ":navigate changes current_screen", %{state: state} do
      {new_state, _} = App.update({:navigate, :board_list}, state)
      assert new_state.current_screen == :board_list
    end

    test ":navigate to main_menu queues oneliner load for authenticated user", %{state: state} do
      user = %Foglet.Accounts.User{id: "u1", handle: "alice"}

      state = %{
        state
        | current_user: user,
          session_context: %{domain: %{oneliners: Foglet.TUI.FakeOneliners}}
      }

      {new_state, cmds} = App.update({:navigate, :main_menu}, state)

      assert new_state.current_screen == :main_menu
      assert [%Raxol.Core.Runtime.Command{type: :task}] = cmds
    end

    test ":navigate clears an active modal", %{state: state} do
      state_with_modal = %{state | modal: %Foglet.TUI.Modal{message: "old", type: :info}}
      {new_state, _} = App.update({:navigate, :main_menu}, state_with_modal)
      assert new_state.modal == nil
    end

    test ":set_user transitions to main_menu", %{state: state} do
      user = %Foglet.Accounts.User{id: "u2", handle: "bob"}
      {new_state, _} = App.update({:set_user, user}, state)
      assert new_state.current_user == user
      assert new_state.current_screen == :main_menu
    end

    test ":set_user queues oneliner load command", %{state: state} do
      user = %Foglet.Accounts.User{id: "u2", handle: "bob"}

      state = %{
        state
        | session_context: %{domain: %{oneliners: Foglet.TUI.FakeOneliners}}
      }

      {_new_state, cmds} = App.update({:set_user, user}, state)
      assert [%Raxol.Core.Runtime.Command{type: :task}] = cmds
    end

    test ":show_modal sets modal, :dismiss_modal clears it", %{state: state} do
      modal = %Foglet.TUI.Modal{message: "hi", type: :info}
      {with_modal, _} = App.update({:show_modal, modal}, state)
      assert with_modal.modal == modal

      {cleared, _} = App.update(:dismiss_modal, with_modal)
      assert cleared.modal == nil
    end

    test "form modal submit effect routes through App to target screen update", %{state: state} do
      form =
        Form.init(
          title: "Test Submit",
          fields: [%{name: :topic, type: :text, label: "Topic"}],
          on_submit: fn payload -> Effect.modal_submit(:target_key, :test_submit, payload) end,
          on_cancel: fn -> :ok end
        )

      state =
        %{
          state
          | session_context: %{
              domain: %{screen_modules: %{target_key: ModalSubmitTarget}}
            },
            screen_state: %{target_key: %{received: []}},
            modal: %Foglet.TUI.Modal{type: :form, message: form}
        }

      {new_state, cmds} = App.update({:key, %{key: :enter}}, state)

      assert cmds == []

      assert App.screen_state_for(new_state, :target_key).received == [
               {:test_submit, %{topic: ""}}
             ]
    end

    test "form modal submit effect with missing target becomes visible error", %{state: state} do
      form =
        Form.init(
          title: "Test Submit",
          fields: [%{name: :topic, type: :text, label: "Topic"}],
          on_submit: fn payload -> Effect.modal_submit(:missing_target, :test_submit, payload) end,
          on_cancel: fn -> :ok end
        )

      state = %{state | modal: %Foglet.TUI.Modal{type: :form, message: form}}

      {new_state, cmds} = App.update({:key, %{key: :enter}}, state)

      assert cmds == []

      assert %Foglet.TUI.Modal{type: :error, message: "Unable to submit form."} =
               new_state.modal
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
      {_new_state, cmds} = App.update({:key, %{key: :char, char: "L"}}, state)
      assert cmds == []
    end

    test "modal precedence prevents screen key handling", %{state: state} do
      modal = %Foglet.TUI.Modal{message: "pause", type: :info}
      state = %{state | modal: modal, screen_state: %{}}

      {new_state, cmds} = App.update({:key, %{key: :char, char: "L"}}, state)

      assert new_state.current_screen == :login
      assert new_state.screen_state == %{}
      assert new_state.modal == modal
      assert cmds == []
    end

    test "Ctrl+C on login exits through a quit command", %{state: state} do
      {_new_state, cmds} = App.update({:key, %{key: :char, char: "c", ctrl: true}}, state)
      assert [%Raxol.Core.Runtime.Command{type: :quit}] = cmds
    end

    test "{:screen_task_result, :login, :login, result} routes through Login local state", %{
      state: state
    } do
      login_ss = %{
        sub: :login_form,
        focused_field: :password,
        handle_input: TextInput.init(value: "ghost"),
        password_input: TextInput.init(value: "nope", mask_char: "*"),
        error: nil,
        submitting?: true
      }

      state = %{state | screen_state: %{login: login_ss}}

      {new_state, cmds} =
        App.update(
          {:screen_task_result, :login, :login, {:ok, {:error, :invalid_credentials}}},
          state
        )

      assert cmds == []
      assert new_state.screen_state.login.error == "That handle and password don't match."
      assert new_state.screen_state.login.submitting? == false
    end

    test "{:screen_task_result, :register, :register, result} routes through Register local state",
         %{state: state} do
      state = %{
        state
        | current_screen: :register,
          screen_state: %{register: RegisterState.default()}
      }

      {new_state, cmds} =
        App.update(
          {:screen_task_result, :register, :register, {:ok, {:error, :unavailable}}},
          state
        )

      assert cmds == []
      assert new_state.current_screen == :register
      assert new_state.screen_state.register == RegisterState.default()
      assert new_state.modal.type == :error
    end

    test "{:screen_task_result, :verify, :verify_submit, result} routes through Verify local state",
         %{state: state} do
      verify_ss = VerifyState.default() |> Map.merge(%{buffer: "WRONG1"})

      state = %{
        state
        | current_screen: :verify,
          current_user: %Foglet.Accounts.User{id: "u5", handle: "eve"},
          screen_state: %{verify: verify_ss}
      }

      {new_state, cmds} =
        App.update(
          {:screen_task_result, :verify, :verify_submit, {:ok, {:error, :invalid_code}}},
          state
        )

      assert cmds == []
      assert new_state.current_screen == :verify
      assert new_state.screen_state.verify.attempts == 1
      assert new_state.screen_state.verify.buffer == ""
      assert new_state.modal.type == :error
    end

    test "{:command_result, {:screen_task_result, :board_list, :load_boards, result}} routes through BoardList local state only",
         %{state: state} do
      directory = [
        %{
          category: %{id: "c1", name: "General"},
          boards: [
            %{
              board: %{id: "b1", name: "General", slug: "general"},
              subscribed?: true,
              required_subscription?: false,
              unread_count: 0,
              last_post_at: nil
            }
          ]
        }
      ]

      state = %{
        state
        | current_screen: :board_list,
          screen_state: %{board_list: BoardListState.new(feedback: "keep")}
      }

      {new_state, cmds} =
        App.update(
          {:command_result, {:screen_task_result, :board_list, :load_boards, {:ok, directory}}},
          state
        )

      assert cmds == []

      assert %BoardListState{
               directory: ^directory,
               status: :loaded,
               feedback: "keep",
               board_tree: %Foglet.TUI.Widgets.List.BoardTree{}
             } = App.screen_state_for(new_state, :board_list)
    end

    test "{:command_result, {:screen_task_result, :thread_list, :load_threads, result}} routes through ThreadList local state only",
         %{state: state} do
      threads = [
        %{
          id: "t1",
          title: "Hello",
          sticky: false,
          locked: false,
          post_count: 1,
          last_post_at: ~U[2026-04-28 18:00:00Z],
          created_by: %{handle: "alice"}
        }
      ]

      local_state = ThreadListState.new(board: %{id: "b1"}, board_id: "b1")

      state = %{
        state
        | current_screen: :thread_list,
          screen_state: %{thread_list: local_state}
      }

      {new_state, cmds} =
        App.update(
          {:command_result, {:screen_task_result, :thread_list, :load_threads, {:ok, threads}}},
          state
        )

      assert cmds == []

      assert %ThreadListState{threads: ^threads, status: :loaded, selected_index: 0} =
               App.screen_state_for(new_state, :thread_list)
    end

    test "{:screen_task_result, :post_composer, :submit_reply, result} routes through PostComposer local state",
         %{state: state} do
      local_state =
        PostComposerState.new(
          board: %{id: "b1"},
          board_id: "b1",
          thread: %{id: "t1"},
          thread_id: "t1",
          submission_status: :submitting,
          value: "hi"
        )

      state = %{
        state
        | current_screen: :post_composer,
          route_params: %{board_id: "b1", thread_id: "t1"},
          screen_state: %{post_composer: local_state},
          session_context: %{domain: %{posts: FakePosts}}
      }

      {new_state, cmds} =
        App.update(
          {:screen_task_result, :post_composer, :submit_reply, {:ok, {:ok, %{id: "p2"}}}},
          state
        )

      assert new_state.current_screen == :post_reader
      assert new_state.route_params.board_id == "b1"
      assert new_state.route_params.thread_id == "t1"
      assert new_state.route_params.load_intent == :jump_last

      assert %PostComposerState{submission_status: :submitted} =
               App.screen_state_for(new_state, :post_composer)

      assert %PostReader.State{thread_id: "t1", load_intent: :jump_last} =
               App.screen_state_for(new_state, :post_reader)

      assert [%Raxol.Core.Runtime.Command{type: :task, data: task}] = cmds

      assert {:screen_task_result, :post_reader, :load_posts_window,
              {:ok, %Foglet.Posts.ReaderWindow{posts: [%{id: "p1"}]}}} = task.()
    end

    test "{:screen_task_result, :new_thread, :create_thread, result} routes through NewThread local state",
         %{state: state} do
      board = %{id: "b1", name: "General", slug: "general"}
      thread = %{id: "t-new", title: "Created"}

      local_state =
        NewThreadState.new(
          step: :compose,
          board: board,
          submission_status: :submitting,
          title_value: "Created",
          body_value: "body"
        )

      state = %{
        state
        | current_screen: :new_thread,
          route_params: %{origin: :thread_list, board: board, board_id: "b1"},
          screen_state: %{new_thread: local_state},
          session_context: %{domain: %{threads: FakeThreads}}
      }

      {new_state, cmds} =
        App.update(
          {:screen_task_result, :new_thread, :create_thread,
           {:ok, {:ok, %{thread: thread, post: %{id: "p-new"}}}}},
          state
        )

      assert new_state.current_screen == :thread_list
      assert new_state.route_params.board == board
      assert new_state.route_params.board_id == "b1"
      assert new_state.route_params.select_thread_id == "t-new"

      assert %NewThreadState{submission_status: :submitted, submit_result: %{thread: ^thread}} =
               App.screen_state_for(new_state, :new_thread)

      assert %ThreadListState{
               board: ^board,
               board_id: "b1",
               select_thread_id: "t-new",
               status: :loading
             } = App.screen_state_for(new_state, :thread_list)

      assert [%Raxol.Core.Runtime.Command{type: :task, data: task}] = cmds

      assert {:screen_task_result, :thread_list, :load_threads, {:ok, [%{id: "t1"}]}} =
               task.()
    end

    test "navigating to thread_list initializes local state and queues its load task", %{
      state: state
    } do
      user = %Foglet.Accounts.User{id: "u1", handle: "alice"}
      board = %{id: "b1", name: "General", slug: "general"}

      state = %{
        state
        | current_user: user,
          session_context: %{domain: %{threads: FakeThreads}}
      }

      {new_state, cmds} =
        Effects.apply_effect(
          state,
          Effect.navigate(:thread_list, %{board: board, board_id: "b1"})
        )

      assert new_state.current_screen == :thread_list
      assert new_state.route_params == %{board: board, board_id: "b1"}

      assert %ThreadListState{board: ^board, board_id: "b1", status: :loading} =
               App.screen_state_for(new_state, :thread_list)

      assert [%Raxol.Core.Runtime.Command{type: :task, data: task}] = cmds

      assert {:screen_task_result, :thread_list, :load_threads, {:ok, [%{id: "t1"}]}} =
               task.()
    end

    test "navigating to post_reader initializes local state and queues generic post loading", %{
      state: state
    } do
      board = %{id: "b1", name: "General", slug: "general"}
      thread = %{id: "t1", title: "Welcome"}

      state = %{state | session_context: %{domain: %{posts: FakePosts}}}

      {new_state, cmds} =
        Effects.apply_effect(
          state,
          Effect.navigate(:post_reader, %{
            board: board,
            board_id: "b1",
            thread: thread,
            thread_id: "t1"
          })
        )

      assert new_state.current_screen == :post_reader

      assert %PostReader.State{thread_id: "t1", status: :loading} =
               App.screen_state_for(new_state, :post_reader)

      assert [%Raxol.Core.Runtime.Command{type: :task, data: task}] = cmds

      assert {:screen_task_result, :post_reader, :load_posts_window,
              {:ok, %Foglet.Posts.ReaderWindow{posts: [%{id: "p1"}]}}} = task.()
    end

    test "navigating post_reader from one thread to another refreshes route-owned local state", %{
      state: state
    } do
      board = %{id: "b1", name: "General", slug: "general"}
      thread_a = %{id: "t1", title: "Welcome"}
      thread_b = %{id: "t2", title: "Second"}

      state = %{state | session_context: %{domain: %{posts: FakePosts}}}

      {state_a, [_cmd_a]} =
        Effects.apply_effect(
          state,
          Effect.navigate(:post_reader, %{
            board: board,
            board_id: "b1",
            thread: thread_a,
            thread_id: "t1"
          })
        )

      assert %PostReader.State{thread_id: "t1"} = App.screen_state_for(state_a, :post_reader)

      {state_b, cmds} =
        Effects.apply_effect(
          state_a,
          Effect.navigate(:post_reader, %{
            board: board,
            board_id: "b1",
            thread: thread_b,
            thread_id: "t2"
          })
        )

      assert %PostReader.State{thread_id: "t2"} = App.screen_state_for(state_b, :post_reader)
      assert [%Raxol.Core.Runtime.Command{type: :task, data: task}] = cmds

      assert {:screen_task_result, :post_reader, :load_posts_window,
              {:ok, %Foglet.Posts.ReaderWindow{posts: [%{id: "p2"}]}}} = task.()
    end

    test "navigating thread_list to another board refreshes route-owned local state", %{
      state: state
    } do
      user = %Foglet.Accounts.User{id: "u1", handle: "alice"}
      board_a = %{id: "b1", name: "General", slug: "general"}
      board_b = %{id: "b2", name: "Second", slug: "second"}

      state = %{
        state
        | current_user: user,
          session_context: %{domain: %{threads: FakeThreads}}
      }

      {state_a, [_cmd_a]} =
        Effects.apply_effect(
          state,
          Effect.navigate(:thread_list, %{board: board_a, board_id: "b1"})
        )

      assert %ThreadListState{board_id: "b1"} = App.screen_state_for(state_a, :thread_list)

      {state_b, cmds} =
        Effects.apply_effect(
          state_a,
          Effect.navigate(:thread_list, %{
            board: board_b,
            board_id: "b2",
            select_thread_id: "t2"
          })
        )

      assert %ThreadListState{board_id: "b2", select_thread_id: "t2"} =
               App.screen_state_for(state_b, :thread_list)

      assert [%Raxol.Core.Runtime.Command{type: :task, data: task}] = cmds

      assert {:screen_task_result, :thread_list, :load_threads, {:ok, [%{id: "t2"}]}} =
               task.()
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

    test ":main_menu_clock_tick is a no-op rerender trigger preserving loaded state", %{
      state: state
    } do
      state = %{
        state
        | current_screen: :main_menu,
          screen_state: %{main_menu: %{ignored: true}, board_list: %{selected_index: 2}},
          modal: %Foglet.TUI.Modal{message: "keep me", type: :info}
      }

      {new_state, cmds} = App.update(:main_menu_clock_tick, state)

      assert new_state.current_screen == state.current_screen
      assert new_state.screen_state == state.screen_state
      assert new_state.modal == state.modal
      assert cmds == []
    end

    test "{:session_replaced, user_id} shows modal that quits on dismiss", %{state: state} do
      {new_state, cmds} = App.update({:session_replaced, "u1"}, state)
      assert new_state.modal != nil
      assert new_state.modal.type == :warning
      # No immediate quit — the user must dismiss the modal first.
      assert cmds == []

      # Both dismiss callbacks return Command.quit() so the session ends
      # whether the user confirms or cancels.
      assert is_function(new_state.modal.on_confirm, 1)
      assert is_function(new_state.modal.on_cancel, 1)

      {_, [confirm_cmd]} = new_state.modal.on_confirm.(new_state)
      {_, [cancel_cmd]} = new_state.modal.on_cancel.(new_state)
      assert match?(%Raxol.Core.Runtime.Command{type: :quit}, confirm_cmd)
      assert match?(%Raxol.Core.Runtime.Command{type: :quit}, cancel_cmd)
    end

    test "{:promote_session, user} transitions to main_menu and sets current_user", %{
      state: state
    } do
      user = %Foglet.Accounts.User{id: "u3", handle: "carol", role: :user}
      state_with_session = %{state | session_pid: self()}
      {new_state, cmds} = App.update({:promote_session, user}, state_with_session)
      assert new_state.current_user == user
      assert new_state.current_screen == :main_menu
      assert [%Raxol.Core.Runtime.Command{type: :task}] = cmds
    end

    test "{:promote_session, user} is safe when session_pid is nil", %{state: state} do
      user = %Foglet.Accounts.User{id: "u4", handle: "dave", role: :user}
      {new_state, cmds} = App.update({:promote_session, user}, state)
      assert new_state.current_user == user
      assert new_state.current_screen == :main_menu
      assert [%Raxol.Core.Runtime.Command{type: :task}] = cmds
    end
  end

  describe "oneliner lifecycle (Phase 7)" do
    setup do
      Process.put(:fake_oneliners_owner, self())

      user = %Foglet.Accounts.User{id: "u1", handle: "alice", role: :user}

      {:ok, state} =
        App.init(%{
          session_context: %{
            user: user,
            user_id: user.id,
            domain: %{oneliners: Foglet.TUI.FakeOneliners}
          }
        })

      %{state: state, user: user}
    end

    test "{:screen_task_result, :main_menu, :load_oneliners, result} stores MainMenu local rows",
         %{state: state} do
      entries = [%{id: "ol1", body: "first"}]

      {new_state, cmds} =
        App.update({:screen_task_result, :main_menu, :load_oneliners, {:ok, entries}}, state)

      assert %MainMenuState{recent_oneliners: ^entries} =
               App.screen_state_for(new_state, :main_menu)

      assert cmds == []
    end

    test "pressing O opens focused Post Oneliner form through MainMenu effect", %{state: state} do
      {new_state, cmds} = App.update({:key, %{key: :char, char: "O"}}, state)

      assert cmds == []
      assert %Foglet.TUI.Modal{type: :form, message: %Form{} = form} = new_state.modal
      assert form.title == "Post Oneliner"
      assert [%{name: :body, type: :text, max_length: 120}] = form.fields
      assert form.focus_index == 0
      assert App.view(new_state)
    end

    test "composer cancel clears modal and stays on main menu", %{state: state} do
      {with_modal, []} = App.update({:key, %{key: :char, char: "O"}}, state)

      {new_state, cmds} = App.update({:key, %{key: :escape}}, with_modal)

      assert new_state.modal == nil
      assert new_state.current_screen == :main_menu
      assert cmds == []
      refute_received {:create_entry, _user, _attrs}
    end

    test "valid submit creates oneliner with current_user, closes modal, and refreshes", %{
      state: state,
      user: user
    } do
      Process.put(:fake_oneliners_create_result, {:ok, %{id: "ol2", body: "ship it", user: user}})

      {submitting, submit_cmds} =
        App.update(
          {:screen_task_result, :main_menu, :submit_oneliner,
           {:ok, {:ok, %{id: "ol2", body: "ship it"}}}},
          state
        )

      assert submitting.current_screen == :main_menu
      assert submitting.modal == nil

      assert %MainMenuState{oneliner_status: :loading} =
               App.screen_state_for(submitting, :main_menu)

      assert [%Raxol.Core.Runtime.Command{type: :task, data: refresh_task}] = submit_cmds
      assert {:screen_task_result, :main_menu, :load_oneliners, {:ok, _entries}} = refresh_task.()
    end

    test "same_user_latest_visible keeps composer focused with visible base error", %{
      state: state
    } do
      {new_state, cmds} =
        App.update(
          {:screen_task_result, :main_menu, :submit_oneliner,
           {:ok, {:error, :same_user_latest_visible}}},
          state
        )

      assert cmds == []

      assert %MainMenuState{
               oneliner_errors: %{base: "Let someone else post before posting again."}
             } =
               App.screen_state_for(new_state, :main_menu)

      assert %Foglet.TUI.Modal{type: :form, message: %Form{} = form} = new_state.modal
      assert form.errors.base == "Let someone else post before posting again."
      assert App.view(new_state)
    end
  end

  describe "moderation workspace and hide modal lifecycle (Phase 8)" do
    setup do
      Process.put(:fake_oneliners_owner, self())
      Process.put(:fake_moderation_owner, self())

      user = %Foglet.Accounts.User{id: "mod1", handle: "mod-alice", role: :mod}

      {:ok, state} =
        App.init(%{
          session_context:
            fake_moderation_context(%{
              user: user,
              user_id: user.id
            })
        })

      state =
        App.put_screen_state(state, :main_menu, %MainMenuState{
          recent_oneliners: [
            %{id: "ol1", body: "abuse", user: %{handle: "bad"}},
            %{id: "ol2", body: "hello", user: %{handle: "good"}}
          ],
          selected_oneliner_index: 0
        })

      %{state: state, user: user}
    end

    test "pressing M as a moderator queues moderation screen task", %{state: state, user: user} do
      {new_state, cmds} = App.update({:key, %{key: :char, char: "M"}}, state)

      assert new_state.current_screen == :moderation
      assert [%Raxol.Core.Runtime.Command{type: :task, data: task}] = cmds

      assert {:screen_task_result, :moderation, :load_moderation_workspace,
              {:ok, {:ok, snapshot}}} =
               task.()

      assert snapshot.scopes == [:site]
      assert_received {:workspace_snapshot, ^user}
    end

    test "{:navigate, :moderation} queues moderation screen task", %{state: state, user: user} do
      {new_state, cmds} = App.update({:navigate, :moderation}, state)

      assert new_state.current_screen == :moderation
      assert [%Raxol.Core.Runtime.Command{type: :task, data: task}] = cmds

      assert {:screen_task_result, :moderation, :load_moderation_workspace,
              {:ok, {:ok, _snapshot}}} =
               task.()

      assert_received {:workspace_snapshot, ^user}
    end

    test "moderation screen task result stores scoped screen state", %{
      state: state
    } do
      snapshot = %{
        scopes: [:site],
        queue: [%{id: "r1"}],
        log: [%{id: "a1", reason: "spam"}],
        users: [%{handle: "alice", role: :user, status: :active}],
        boards: [%{name: "General", slug: "general", category_name: "Main", scope: :site}]
      }

      {new_state, cmds} =
        App.update(
          {:screen_task_result, :moderation, :load_moderation_workspace, {:ok, {:ok, snapshot}}},
          state
        )

      assert cmds == []
      assert new_state.screen_state.moderation.scopes == [:site]
      assert new_state.screen_state.moderation.queue == snapshot.queue
      assert new_state.screen_state.moderation.mod_log == snapshot.log
      assert new_state.screen_state.moderation.users == snapshot.users
      assert new_state.screen_state.moderation.boards == snapshot.boards
      refute new_state.screen_state.moderation.loading?
      assert new_state.screen_state.moderation.error == nil
    end

    test "{:open_hide_oneliner_modal, entry_id} opens focused required reason form", %{
      state: state
    } do
      {new_state, cmds} = App.update({:key, %{key: :char, char: "H"}}, state)

      assert cmds == []

      assert %MainMenuState{pending_hide_oneliner_id: "ol1"} =
               App.screen_state_for(new_state, :main_menu)

      assert %Foglet.TUI.Modal{type: :form, title: "Hide Oneliner", message: %Form{} = form} =
               new_state.modal

      assert form.title == "Hide Oneliner"

      assert [%{name: :reason, type: :text, label: "Reason", placeholder: "Required"}] =
               form.fields

      assert form.focus_index == 0
      assert App.view(new_state)
    end

    test "hide task validation error keeps modal focused in MainMenu local state", %{
      state: state
    } do
      {with_modal, []} = App.update({:key, %{key: :char, char: "H"}}, state)

      {new_state, cmds} =
        App.update(
          {:screen_task_result, :main_menu, :submit_hide_oneliner,
           {:ok, {:error, %Ecto.Changeset{}}}},
          with_modal
        )

      assert cmds == []
      assert %Foglet.TUI.Modal{type: :form, message: %Form{} = form} = new_state.modal
      assert form.errors == %{}

      assert %MainMenuState{pending_hide_oneliner_id: "ol1"} =
               App.screen_state_for(new_state, :main_menu)

      refute_received {:hide_entry, _actor, _target, _reason}
    end

    test "hide success routes through MainMenu local state", %{state: state, user: _user} do
      Process.put(:fake_oneliners_hide_result, {:ok, %{id: "ol1", hidden?: true}})
      {with_modal, []} = App.update({:key, %{key: :char, char: "H"}}, state)

      {submitting, cmds} =
        App.update(
          {:screen_task_result, :main_menu, :submit_hide_oneliner, {:ok, {:ok, %{id: "ol1"}}}},
          with_modal
        )

      assert submitting.modal == nil
      assert cmds == []

      assert %MainMenuState{pending_hide_oneliner_id: nil} =
               App.screen_state_for(submitting, :main_menu)
    end

    test "{:oneliner_hidden, {:ok, hidden}} clears modal and removes row immediately", %{
      state: state
    } do
      {with_modal, []} = App.update({:key, %{key: :char, char: "H"}}, state)

      {new_state, cmds} =
        App.update(
          {:screen_task_result, :main_menu, :submit_hide_oneliner, {:ok, {:ok, %{id: "ol1"}}}},
          with_modal
        )

      assert cmds == []
      assert new_state.modal == nil

      assert %MainMenuState{pending_hide_oneliner_id: nil, recent_oneliners: rows} =
               App.screen_state_for(new_state, :main_menu)

      refute Enum.any?(rows, &(&1.id == "ol1"))
      assert Enum.any?(rows, &(&1.id == "ol2"))
    end

    test "{:oneliner_hidden, {:error, :forbidden}} keeps modal error and visible row", %{
      state: state
    } do
      {with_modal, []} = App.update({:key, %{key: :char, char: "H"}}, state)

      {new_state, cmds} =
        App.update(
          {:screen_task_result, :main_menu, :submit_hide_oneliner, {:ok, {:error, :forbidden}}},
          with_modal
        )

      assert cmds == []
      assert %Foglet.TUI.Modal{type: :form, message: %Form{} = form} = new_state.modal
      assert form.errors.base == "You are not allowed to hide this oneliner."

      assert %MainMenuState{pending_hide_oneliner_id: "ol1", recent_oneliners: rows} =
               App.screen_state_for(new_state, :main_menu)

      assert Enum.any?(rows, &(&1.id == "ol1"))
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
            :post_composer,
            :new_thread
          ] do
        s =
          case screen do
            :thread_list ->
              %{
                state
                | current_screen: :thread_list,
                  screen_state: %{
                    thread_list:
                      ThreadListState.new(
                        board: %{id: "b1", name: "General"},
                        board_id: "b1",
                        threads: [],
                        status: :empty
                      )
                  }
              }

            other ->
              %{state | current_screen: other}
          end

        assert _ = App.view(s)
      end
    end

    test "renders with modal without crashing", %{state: state} do
      s = %{state | modal: %Foglet.TUI.Modal{type: :info, message: "Test"}}
      assert _ = App.view(s)
    end
  end

  describe "view/1 size gate (FRAME-03, Phase 5)" do
    test "renders SizeGate output when cols < 64" do
      {:ok, state} = App.init(%{terminal_size: {40, 30}})
      element = App.view(state)

      assert SizeGate.too_small?(state)

      assert size_gate_text_contents(element) == [
               "Terminal too small.",
               "Foglet BBS requires at least 64×22.",
               "Your terminal is currently: 40×30.",
               "Please resize."
             ]
    end

    test "renders SizeGate output when rows < 22" do
      {:ok, state} = App.init(%{terminal_size: {100, 10}})
      element = App.view(state)

      assert SizeGate.too_small?(state)

      assert size_gate_text_contents(element) == [
               "Terminal too small.",
               "Foglet BBS requires at least 64×22.",
               "Your terminal is currently: 100×10.",
               "Please resize."
             ]
    end

    test "renders normal screen at exactly 64×22 (strict inequality per D-13)" do
      {:ok, state} = App.init(%{terminal_size: {64, 22}})
      element = App.view(state)

      refute SizeGate.too_small?(state)
      refute size_gate_view?(element)
    end

    test "renders normal screen at 80×24 (common default)" do
      {:ok, state} = App.init(%{terminal_size: {80, 24}})
      element = App.view(state)

      refute SizeGate.too_small?(state)
      refute size_gate_view?(element)
    end

    test "renders SizeGate after receiving a resize event that drops below minimum" do
      {:ok, state} = App.init(%{terminal_size: {100, 30}})

      resize_event = %Raxol.Core.Events.Event{
        type: :resize,
        data: %{width: 40, height: 10}
      }

      {new_state, _cmds} = App.update(resize_event, state)
      element = App.view(new_state)

      assert SizeGate.too_small?(new_state)

      assert size_gate_text_contents(element) == [
               "Terminal too small.",
               "Foglet BBS requires at least 64×22.",
               "Your terminal is currently: 40×10.",
               "Please resize."
             ]
    end

    test "gate takes precedence over modal (D-04 ordering)" do
      {:ok, state} = App.init(%{terminal_size: {40, 10}})

      {with_modal, _} =
        App.update({:show_modal, %Foglet.TUI.Modal{type: :info, message: "a modal"}}, state)

      element = App.view(with_modal)

      assert SizeGate.too_small?(with_modal)
      assert size_gate_view?(element)
      assert with_modal.modal.message == "a modal"
    end

    test "gate is purely render-time — state is not modified by view/1 call" do
      {:ok, state} = App.init(%{terminal_size: {40, 10}})

      state_with_screen = %{
        state
        | current_screen: :board_list,
          screen_state: %{
            board_list: %{selected_index: 3},
            post_composer: PostComposerState.new(value: "draft-in-progress")
          },
          modal: %Foglet.TUI.Modal{type: :info, message: "preserve me"}
      }

      _ = App.view(state_with_screen)

      # view/1 is pure — state should be completely unchanged
      assert state_with_screen.current_screen == :board_list
      assert state_with_screen.screen_state.board_list.selected_index == 3
      assert state_with_screen.modal.message == "preserve me"

      assert state_with_screen.screen_state.post_composer.input_state.value ==
               "draft-in-progress"
    end
  end

  describe "update/2 {:window_change} same-size guard (D-09, Pitfall 4)" do
    setup do
      {:ok, state} = App.init(%{terminal_size: {100, 30}})
      %{state: state}
    end

    test "short-circuits when {cols, rows} matches state.terminal_size", %{state: state} do
      {new_state, cmds} = App.update({:window_change, 100, 30}, state)
      # Identity — state must not be mutated at all (D-09)
      assert new_state == state
      assert cmds == []
    end

    test "processes normally when size differs", %{state: state} do
      {new_state, cmds} = App.update({:window_change, 120, 40}, state)
      assert new_state.terminal_size == {120, 40}
      assert cmds == []
    end

    test "processes normally when only cols change", %{state: state} do
      {new_state, _} = App.update({:window_change, 120, 30}, state)
      assert new_state.terminal_size == {120, 30}
    end

    test "processes normally when only rows change", %{state: state} do
      {new_state, _} = App.update({:window_change, 100, 40}, state)
      assert new_state.terminal_size == {100, 40}
    end

    test "short-circuits even when state.session_pid is set (no Session cast)", %{state: state} do
      # When state.terminal_size already matches, we must NOT send a cast to Session.
      # Using self() as a stand-in session_pid — if a cast were sent, self()'s
      # mailbox would accumulate it.
      state_with_pid = %{state | session_pid: self()}
      {_new_state, cmds} = App.update({:window_change, 100, 30}, state_with_pid)
      assert cmds == []
      # No cast message should be in our mailbox from Session.set_terminal_size
      refute_receive {:"$gen_cast", _}, 10
    end
  end

  describe "update/2 {:key} swallow when gated (FRAME-03, D-11)" do
    test "swallows {:key, _} when SizeGate.too_small?(state)" do
      {:ok, state} = App.init(%{terminal_size: {40, 10}})
      {new_state, cmds} = App.update({:key, %{key: :char, char: "q"}}, state)
      assert new_state == state
      assert cmds == []
    end

    test "swallows enter when gated" do
      {:ok, state} = App.init(%{terminal_size: {40, 10}})
      {new_state, cmds} = App.update({:key, %{key: :enter}}, state)
      assert new_state == state
      assert cmds == []
    end

    test "swallows escape when gated" do
      {:ok, state} = App.init(%{terminal_size: {40, 10}})
      {new_state, cmds} = App.update({:key, %{key: :escape}}, state)
      assert new_state == state
      assert cmds == []
    end

    test "does NOT dispatch to screen's handle_key when gated" do
      {:ok, state} = App.init(%{terminal_size: {40, 10}})
      # When gated, keys must be swallowed before they reach screen handlers.
      {_new_state, cmds} = App.update({:key, %{key: :char, char: "Q"}}, state)
      assert cmds == []
    end

    test "still dispatches {:key, _} normally above threshold" do
      {:ok, state} = App.init(%{terminal_size: {80, 24}})
      {new_state, cmds} = App.update({:key, %{key: :char, char: "L"}}, state)
      assert get_in(new_state.screen_state, [:login, :sub]) == :login_form
      assert cmds == []
    end

    test "{:window_change, _, _} reaches the normal handler even when gated" do
      {:ok, state} = App.init(%{terminal_size: {40, 10}})
      # Resize OUT of the gate — this non-key message must still process
      # so the user can un-gate by resizing up
      {new_state, _cmds} = App.update({:window_change, 100, 30}, state)
      assert new_state.terminal_size == {100, 30}
    end

    test ":heartbeat_tick reaches the normal handler even when gated" do
      {:ok, state} = App.init(%{terminal_size: {40, 10}})
      # Non-key messages flow through normally — heartbeat is a no-op with
      # no session_pid but must not crash or be swallowed
      {new_state, cmds} = App.update(:heartbeat_tick, state)
      assert new_state == state
      assert cmds == []
    end

    test "gate precedence: gate beats modal" do
      {:ok, state} = App.init(%{terminal_size: {40, 10}})

      {with_modal, _} =
        App.update({:show_modal, %Foglet.TUI.Modal{type: :info, message: "x"}}, state)

      # Even with a modal open, the key is swallowed by the gate (gate is first in cond)
      {new_state, cmds} = App.update({:key, %{key: :enter}}, with_modal)
      # Modal would normally dismiss on :enter; gate prevents that
      assert new_state.modal != nil
      assert cmds == []
    end
  end

  describe "composer draft preservation across resize gate cycles (Pitfall 4)" do
    test "post_composer input_state.value survives resize-down → key-press → resize-up cycle" do
      {:ok, state} = App.init(%{terminal_size: {100, 30}})

      # Simulate a post_composer session with an in-flight draft
      state_with_composer = %{
        state
        | current_screen: :post_composer,
          screen_state: %{
            post_composer: PostComposerState.new(value: "draft-in-progress")
          }
      }

      # Step 1: resize DOWN below threshold — gate engages
      {gated, _cmds} = App.update({:window_change, 40, 10}, state_with_composer)
      assert Foglet.TUI.SizeGate.too_small?(gated)
      # Composer state is preserved through the resize (update/2 didn't touch it)
      assert gated.screen_state.post_composer.input_state.value == "draft-in-progress"
      assert gated.current_screen == :post_composer

      # Step 2: user hammers keys while gated — ALL must be swallowed
      {after_q, _} = App.update({:key, %{key: :char, char: "q"}}, gated)
      {after_enter, _} = App.update({:key, %{key: :enter}}, after_q)
      {after_esc, _} = App.update({:key, %{key: :escape}}, after_enter)
      # Draft still intact
      assert after_esc.screen_state.post_composer.input_state.value == "draft-in-progress"
      assert after_esc.current_screen == :post_composer

      # Step 3: resize BACK above threshold — gate releases
      {released, _} = App.update({:window_change, 100, 30}, after_esc)
      refute Foglet.TUI.SizeGate.too_small?(released)
      # Draft survives the full cycle end-to-end
      assert released.screen_state.post_composer.input_state.value == "draft-in-progress"
      assert released.current_screen == :post_composer
    end

    test "new_thread body_input_state.value survives the same cycle" do
      {:ok, state} = App.init(%{terminal_size: {100, 30}})

      state_with_new_thread = %{
        state
        | current_screen: :new_thread,
          screen_state: %{
            new_thread:
              NewThreadState.new(
                step: :compose,
                title_input_state: TextInput.init(value: "My new thread"),
                body_value: "line1\nline2\nline3",
                focused: :body
              )
          }
      }

      # Resize down → key presses → resize up
      {gated, _} = App.update({:window_change, 50, 15}, state_with_new_thread)
      {after_keys, _} = App.update({:key, %{key: :char, char: "X"}}, gated)
      {released, _} = App.update({:window_change, 100, 30}, after_keys)

      # Multi-line content preserved verbatim
      assert released.screen_state.new_thread.body_input_state.value == "line1\nline2\nline3"

      assert released.screen_state.new_thread.title_input_state.raxol_state.value ==
               "My new thread"

      assert released.current_screen == :new_thread
    end

    test "rapid resize bursts at the same sub-threshold size do not mutate state" do
      {:ok, state} = App.init(%{terminal_size: {100, 30}})

      state_with_composer = %{
        state
        | current_screen: :post_composer,
          screen_state: %{
            post_composer: PostComposerState.new(value: "important-draft")
          }
      }

      # One resize to sub-threshold
      {gated_once, _} = App.update({:window_change, 40, 10}, state_with_composer)

      # Burst of same-size events (simulates tmux drag) — D-09 same-size guard
      # Each one must short-circuit to identity
      final =
        Enum.reduce(1..20, gated_once, fn _, acc ->
          {new_state, _cmds} = App.update({:window_change, 40, 10}, acc)
          new_state
        end)

      # Draft preserved, state structurally identical to gated_once
      assert final == gated_once
      assert final.screen_state.post_composer.input_state.value == "important-draft"
    end

    test "pending_read_positions survives resize gate cycle" do
      {:ok, state} = App.init(%{terminal_size: {100, 30}})

      pending = %{"thread-1" => %{last_post_id: "post-42", scroll: 15}}

      state_reading = %{
        state
        | current_screen: :post_reader,
          screen_state: %{
            post_reader:
              PostReaderState.new(
                selected_post_index: 5,
                thread: %{id: "thread-1"},
                pending_read_positions: pending
              )
          }
      }

      {gated, _} = App.update({:window_change, 50, 15}, state_reading)
      {after_keys, _} = App.update({:key, %{key: :char, char: "j"}}, gated)
      {released, _} = App.update({:window_change, 100, 30}, after_keys)

      assert released.screen_state.post_reader.pending_read_positions == pending
      assert %PostReader.State{} = released.screen_state.post_reader
      assert released.screen_state.post_reader.selected_post_index == 5
      assert released.current_screen == :post_reader
    end
  end

  describe "subscribe/1" do
    test "starts stable runtime subscriptions when session_pid is nil and no user" do
      {:ok, state} = App.init(%{})
      subs = App.subscribe(state)

      # Even an unauthenticated session needs the one-shot
      # :initial_route_enter forwarder so the :login screen's
      # :on_route_enter clause runs (Phase 39 CR-01).
      assert %Raxol.Core.Runtime.Subscription{
               type: :custom,
               data: %{module: Foglet.TUI.InitialRouteEnterForwarder}
             } = custom_subscription(subs, Foglet.TUI.InitialRouteEnterForwarder)

      assert %Raxol.Core.Runtime.Subscription{
               type: :custom,
               data: %{module: Foglet.TUI.PubSubForwarder, args: %{topics: []}}
             } = custom_subscription(subs, Foglet.TUI.PubSubForwarder)

      assert %Raxol.Core.Runtime.Subscription{type: :interval} =
               interval_subscription(subs, :main_menu_clock_tick)
    end

    test "returns heartbeat subscription when session_pid is set" do
      {:ok, state} = App.init(%{session_context: %{session_pid: self()}})
      subs = App.subscribe(state)
      assert subs != []
    end

    test "main_menu screen adds chrome clock interval subscription" do
      user = %Foglet.Accounts.User{id: "u-clock", handle: "alice"}

      {:ok, state} =
        App.init(%{
          session_context:
            fake_oneliners_context(%{user: user, user_id: "u-clock", session_pid: nil})
        })

      state = %{state | current_screen: :main_menu}
      subs = App.subscribe(state)

      assert %Raxol.Core.Runtime.Subscription{type: :interval, data: data} =
               interval_subscription(subs, :main_menu_clock_tick)

      assert is_integer(data.interval)
      assert data.interval <= 60_000
    end

    test "non-main-menu screens also add chrome clock interval subscription" do
      user = %Foglet.Accounts.User{id: "u-clock", handle: "alice"}

      {:ok, state} =
        App.init(%{
          session_context:
            fake_oneliners_context(%{user: user, user_id: "u-clock", session_pid: nil})
        })

      state = %{state | current_screen: :board_list}
      subs = App.subscribe(state)

      assert %Raxol.Core.Runtime.Subscription{type: :interval, data: data} =
               interval_subscription(subs, :main_menu_clock_tick)

      assert is_integer(data.interval)
      assert data.interval <= 60_000
    end

    test "returns PubSub custom subscription when current_user is set (Audit #12)" do
      user = %Foglet.Accounts.User{id: "u-pubsub", handle: "alice"}

      {:ok, state} =
        App.init(%{
          session_context: fake_oneliners_context(%{user: user, user_id: "u-pubsub"})
        })

      subs = App.subscribe(state)

      assert custom_subscription(subs, Foglet.TUI.PubSubForwarder),
             "expected a stable :custom subscription for PubSub"
    end

    test "PubSub forwarder starts with no topics when not logged in" do
      {:ok, state} = App.init(%{})
      subs = App.subscribe(state)

      assert %Raxol.Core.Runtime.Subscription{
               type: :custom,
               data: %{module: Foglet.TUI.PubSubForwarder, args: %{topics: []}}
             } = custom_subscription(subs, Foglet.TUI.PubSubForwarder)
    end

    test "login refreshes the stable PubSub forwarder with user topics" do
      {:ok, state} = App.init(%{})
      user = %Foglet.Accounts.User{id: "u-dynamic", handle: "alice"}
      control_topic = Foglet.TUI.PubSubForwarder.control_topic(self())

      Phoenix.PubSub.subscribe(FogletBbs.PubSub, control_topic)

      {_new_state, _cmds} = App.update({:set_user, user}, state)

      assert_receive {:pubsub_forwarder, {:refresh_topics, ["user:u-dynamic"]}}
    end

    test "board_list screen adds 'boards' topic" do
      user = %Foglet.Accounts.User{id: "u1", handle: "alice"}

      {:ok, state} =
        App.init(%{session_context: fake_oneliners_context(%{user: user, user_id: "u1"})})

      state = %{state | current_screen: :board_list}
      subs = App.subscribe(state)

      pubsub_sub = Enum.find(subs, &match?(%Raxol.Core.Runtime.Subscription{type: :custom}, &1))
      assert pubsub_sub != nil
      assert "boards" in pubsub_sub.data.args.topics
    end

    test "thread_list screen adds board:<id> topic from route params" do
      user = %Foglet.Accounts.User{id: "u1", handle: "alice"}

      {:ok, state} =
        App.init(%{session_context: fake_oneliners_context(%{user: user, user_id: "u1"})})

      state = %{state | current_screen: :thread_list, route_params: %{board_id: "b-99"}}
      subs = App.subscribe(state)

      pubsub_sub = Enum.find(subs, &match?(%Raxol.Core.Runtime.Subscription{type: :custom}, &1))
      assert pubsub_sub != nil
      assert "board:b-99" in pubsub_sub.data.args.topics
    end

    test "thread_list screen adds board:<id> topic from ThreadList local state" do
      user = %Foglet.Accounts.User{id: "u1", handle: "alice"}

      {:ok, state} =
        App.init(%{session_context: fake_oneliners_context(%{user: user, user_id: "u1"})})

      state = %{
        state
        | current_screen: :thread_list,
          route_params: %{},
          screen_state: %{thread_list: ThreadListState.new(board_id: "b-77")}
      }

      subs = App.subscribe(state)

      pubsub_sub = Enum.find(subs, &match?(%Raxol.Core.Runtime.Subscription{type: :custom}, &1))
      assert pubsub_sub != nil
      assert "board:b-77" in pubsub_sub.data.args.topics
    end

    test "post_reader screen adds thread:<id> topic from route params" do
      user = %Foglet.Accounts.User{id: "u1", handle: "alice"}

      {:ok, state} =
        App.init(%{session_context: fake_oneliners_context(%{user: user, user_id: "u1"})})

      state = %{state | current_screen: :post_reader, route_params: %{thread_id: "t-route"}}
      subs = App.subscribe(state)

      pubsub_sub = Enum.find(subs, &match?(%Raxol.Core.Runtime.Subscription{type: :custom}, &1))
      assert pubsub_sub != nil
      assert "thread:t-route" in pubsub_sub.data.args.topics
    end

    test "post_reader screen adds thread:<id> topic from local state" do
      user = %Foglet.Accounts.User{id: "u1", handle: "alice"}

      {:ok, state} =
        App.init(%{session_context: fake_oneliners_context(%{user: user, user_id: "u1"})})

      state = %{
        state
        | current_screen: :post_reader,
          route_params: %{},
          screen_state: %{post_reader: PostReaderState.new(thread_id: "t-state")}
      }

      subs = App.subscribe(state)

      pubsub_sub = Enum.find(subs, &match?(%Raxol.Core.Runtime.Subscription{type: :custom}, &1))
      assert pubsub_sub != nil
      assert "thread:t-state" in pubsub_sub.data.args.topics
    end

    test "main_menu (stateless authenticated screen) produces only user topic (Phase 39 D-18)" do
      user = %Foglet.Accounts.User{id: "u1", handle: "alice"}

      {:ok, state} =
        App.init(%{session_context: fake_oneliners_context(%{user: user, user_id: "u1"})})

      state = %{state | current_screen: :main_menu, current_user: user}
      subs = App.subscribe(state)

      pubsub_sub = Enum.find(subs, &match?(%Raxol.Core.Runtime.Subscription{type: :custom}, &1))
      assert pubsub_sub != nil
      assert pubsub_sub.data.args.topics == ["user:u1"]
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

    test "{:boards_loaded, boards} does not mutate cached BoardList local state", %{state: state} do
      fake_boards = [%{id: "b1", name: "General", unread_count: 0}]
      board_tree = %{selected_id: {:board, "b1"}}

      state = %{
        state
        | screen_state: %{
            board_list: %Foglet.TUI.Screens.BoardList.State{
              board_tree: board_tree,
              feedback: "Subscribed"
            }
          }
      }

      {new_state, cmds} = App.update({:boards_loaded, fake_boards}, state)

      assert new_state.screen_state.board_list.board_tree == board_tree
      assert new_state.screen_state.board_list.feedback == "Subscribed"
      assert cmds == []
    end

    test "{:load_posts, thread_id} is ignored by App local-flow cleanup", %{state: state} do
      {_new_state, cmds} = App.update({:load_posts, "t1"}, state)
      assert cmds == []
    end

    test "{:posts_loaded, posts} does not assign post_reader local state", %{state: state} do
      posts = [%{id: "p1", body: "Hello", inserted_at: DateTime.utc_now()}]

      {new_state, []} = App.update({:posts_loaded, posts}, state)

      assert App.screen_state_for(new_state, :post_reader) == nil
    end

    test "{:posts_loaded, posts, jump_last: true} leaves PostReader.State untouched", %{
      state: state
    } do
      posts = [
        %{id: "p1", body: "Hello", inserted_at: DateTime.utc_now()},
        %{id: "p2", body: "Second", inserted_at: DateTime.utc_now()}
      ]

      state_with_reader = %{
        state
        | screen_state: %{post_reader: PostReaderState.new(selected_post_index: 0)}
      }

      {new_state, []} = App.update({:posts_loaded, posts, jump_last: true}, state_with_reader)

      assert App.screen_state_for(new_state, :post_reader) ==
               App.screen_state_for(state_with_reader, :post_reader)
    end

    test "{:flush_read_pointers, ctx} is ignored by App local-flow cleanup", %{state: state} do
      ctx = %{user_id: "u1", board_id: "b1", thread_id: "t1"}
      {_new_state, cmds} = App.update({:flush_read_pointers, ctx}, state)
      assert cmds == []
    end

    test "{:read_pointers_flushed, thread_id} does not clear PostReader pending entry", %{
      state: state
    } do
      post_reader_state =
        PostReaderState.new(
          thread_id: "t1",
          pending_read_positions: %{
            "t1" => %{last_read_post_id: "p5", last_read_message_number: 5}
          }
        )

      state_with_rp = %{state | screen_state: %{post_reader: post_reader_state}}

      {new_state, []} = App.update({:read_pointers_flushed, "t1"}, state_with_rp)

      assert Map.has_key?(new_state.screen_state.post_reader.pending_read_positions, "t1")
    end
  end

  describe "PubSub message handlers (Audit #12)" do
    setup do
      user = %Foglet.Accounts.User{id: "u1", handle: "alice"}

      {:ok, state} =
        App.init(%{session_context: fake_oneliners_context(%{user: user, user_id: "u1"})})

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

    test "{:thread_activity, thread_id, event} on active :post_reader routes through local state",
         %{state: state} do
      state = %{
        state
        | current_screen: :post_reader,
          route_params: %{thread_id: "t1"},
          screen_state: %{post_reader: PostReaderState.new(thread_id: "t1")},
          session_context: %{domain: %{posts: FakePosts}}
      }

      {new_state, cmds} = App.update({:thread_activity, "t1", :new_post}, state)

      assert %PostReader.State{last_op: :load_posts_window} =
               App.screen_state_for(new_state, :post_reader)

      assert [%Raxol.Core.Runtime.Command{type: :task, data: task}] = cmds

      assert {:screen_task_result, :post_reader, :load_posts_window,
              {:ok, %Foglet.Posts.ReaderWindow{posts: [%{id: "p1"}]}}} = task.()
    end

    test "{:thread_activity} for a different thread is a no-op", %{state: state} do
      local_state = PostReaderState.new(thread_id: "t-other")

      state = %{
        state
        | current_screen: :post_reader,
          route_params: %{thread_id: "t-other"},
          screen_state: %{post_reader: local_state}
      }

      {new_state, cmds} = App.update({:thread_activity, "t-match", :new_post}, state)

      assert App.screen_state_for(new_state, :post_reader) == local_state
      assert cmds == []
    end

    test "{:notification, user_id, kind, payload} shows a modal", %{state: state} do
      {new_state, []} = App.update({:notification, "u1", :dm, %{body: "hey!"}}, state)
      assert new_state.modal != nil
      assert new_state.modal.type == :info
      assert new_state.modal.message == "New message: hey!"
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
        | modal: %Foglet.TUI.Modal{type: :error, message: "suspended"},
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
        | modal: %Foglet.TUI.Modal{type: :error, message: "suspended"},
          current_screen: :login,
          screen_state: %{login: login_ss}
      }

      {new_state, _cmds} = App.update({:key, %{key: :escape}}, state_with_modal)
      assert new_state.modal == nil
    end
  end

  describe "Phase 0 screen routing" do
    setup do
      user = %Foglet.Accounts.User{id: "u1", handle: "alice", role: :user}

      {:ok, state} =
        App.init(%{session_context: fake_oneliners_context(%{user: user, user_id: "u1"})})

      %{state: state}
    end

    test "screen_module_for/1 maps :account — navigating and calling view/1 does not crash", %{
      state: state
    } do
      {new_state, _cmds} = App.update({:navigate, :account}, state)
      assert new_state.current_screen == :account
      assert _ = App.view(new_state)
    end

    test "screen_module_for/1 maps :moderation — navigating and calling view/1 does not crash",
         %{state: state} do
      {new_state, _cmds} = App.update({:navigate, :moderation}, state)
      assert new_state.current_screen == :moderation
      assert _ = App.view(new_state)
    end

    test "screen_module_for/1 maps :sysop — navigating and calling view/1 does not crash", %{
      state: state
    } do
      {new_state, _cmds} = App.update({:navigate, :sysop}, state)
      assert new_state.current_screen == :sysop
      assert _ = App.view(new_state)
    end

    test "navigating to :account does not land on :login (routing succeeds)", %{state: state} do
      {new_state, _cmds} = App.update({:navigate, :account}, state)
      refute new_state.current_screen == :login
    end

    test "init/1 does NOT route authenticated users into :account/:moderation/:sysop by default",
         %{state: state} do
      # After init with user, stays at :main_menu — not directly at new shells
      assert state.current_screen == :main_menu
      refute state.current_screen in [:account, :moderation, :sysop]
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

    test "{:command_result, {:boards_loaded, boards}} is a no-op at App level", %{
      state: state
    } do
      boards = [%{id: "b1", name: "General", unread_count: 0}]
      {_new_state, cmds} = App.update({:command_result, {:boards_loaded, boards}}, state)
      assert cmds == []
    end

    test "{:command_result, {:threads_loaded, threads}} is a no-op at App level",
         %{state: state} do
      threads = [%{id: "t1", title: "Hello", sticky: false, last_post_at: DateTime.utc_now()}]
      {_new_state, cmds} = App.update({:command_result, {:threads_loaded, threads}}, state)
      assert cmds == []
    end

    test "{:command_result, {:posts_loaded, posts}} does not mutate Phase 37 state", %{
      state: state
    } do
      posts = [%{id: "p1", body: "Hello", inserted_at: DateTime.utc_now()}]

      {new_state, cmds} = App.update({:command_result, {:posts_loaded, posts}}, state)

      assert App.screen_state_for(new_state, :post_reader) == nil
      assert cmds == []
    end

    test "{:command_result, {:unknown_result}} hits catch-all safely — returns {state, []}",
         %{state: state} do
      assert {^state, []} = App.update({:command_result, {:unknown_result}}, state)
    end
  end

  describe "update/2 — {:read_pointers_flushed, thread_id} second-phase refresh (LIST-02 D-06)" do
    setup do
      {:ok, base_state} = App.init(%{})

      state =
        %{
          base_state
          | current_user: %Foglet.Accounts.User{id: "u1", handle: "alice"},
            session_context: %{
              domain: %{
                boards: %{
                  list_subscribed_boards: fn _user ->
                    [%{id: "b1", name: "General", slug: "general", unread_count: 3}]
                  end
                }
              }
            }
        }

      %{state: state}
    end

    test "legacy flush result leaves PostReader pending entry untouched", %{state: state} do
      state = %{
        state
        | current_screen: :thread_list,
          screen_state: %{
            post_reader:
              PostReaderState.new(
                thread_id: "t1",
                pending_read_positions: %{
                  "t1" => %{last_read_post_id: "p1", last_read_message_number: 5}
                }
              )
          }
      }

      {new_state, _cmds} = App.update({:read_pointers_flushed, "t1"}, state)
      assert Map.has_key?(new_state.screen_state.post_reader.pending_read_positions, "t1")
    end

    test "nil thread_id leaves PostReader pending entries unchanged", %{state: state} do
      pending = %{"t1" => %{last_read_post_id: "p1", last_read_message_number: 5}}

      state = %{
        state
        | current_screen: :thread_list,
          screen_state: %{
            post_reader: PostReaderState.new(thread_id: "t1", pending_read_positions: pending)
          }
      }

      {new_state, _cmds} = App.update({:read_pointers_flushed, nil}, state)
      assert new_state.screen_state.post_reader.pending_read_positions == pending
    end

    test "on :board_list — legacy flush result is ignored", %{state: state} do
      state = %{state | current_screen: :board_list}
      {_new_state, cmds} = App.update({:read_pointers_flushed, "t1"}, state)

      assert cmds == []
    end

    test "on :thread_list — does NOT dispatch {:load_boards}", %{state: state} do
      state = %{state | current_screen: :thread_list}
      {_new_state, cmds} = App.update({:read_pointers_flushed, "t1"}, state)

      refute Enum.any?(cmds, fn
               %Raxol.Core.Runtime.Command{} -> true
               _ -> false
             end),
             "Expected no {:load_boards} refresh on :thread_list screen"
    end

    test "on :post_reader — does NOT dispatch {:load_boards}", %{state: state} do
      state = %{state | current_screen: :post_reader}
      {_new_state, cmds} = App.update({:read_pointers_flushed, "t1"}, state)

      refute Enum.any?(cmds, fn
               %Raxol.Core.Runtime.Command{} -> true
               _ -> false
             end)
    end
  end

  describe "App-routed sysop screen tasks (Phase 38)" do
    @describetag :sysop_load_triad

    defp fake_sysop_context(extra) do
      Map.merge(
        %{
          domain: %{
            oneliners: Foglet.TUI.FakeOneliners,
            moderation: Foglet.TUI.FakeModeration,
            accounts: Foglet.TUI.FakeAccounts
          }
        },
        extra
      )
    end

    setup do
      Process.put(:fake_oneliners_owner, self())
      Process.put(:fake_oneliners_entries, [])
      Process.put(:fake_accounts_owner, self())

      sysop = %Foglet.Accounts.User{
        id: "sysop1",
        handle: "alice",
        role: :sysop,
        status: :active
      }

      {:ok, state} =
        App.init(%{
          session_context:
            fake_sysop_context(%{
              user: sysop,
              user_id: sysop.id
            })
        })

      %{state: state, user: sysop}
    end

    test "{:navigate, :sysop} on USERS-active state queues sysop screen task", %{
      state: state,
      user: user
    } do
      ss =
        SysopState.new(
          current_user: user,
          session_context: state.session_context,
          active: 4
        )

      state = put_in(state, [Access.key(:screen_state), :sysop], ss)

      {new_state, cmds} = App.update({:navigate, :sysop}, state)

      assert new_state.screen_state.sysop.users_view == :loading
      assert [%Raxol.Core.Runtime.Command{type: :task, data: task}] = cmds

      # Closure capture (Pitfall 8): user is bound at dispatch time.
      assert {:screen_task_result, :sysop, :sysop_load_users,
              {:ok, {:ok, %Foglet.TUI.Screens.Sysop.UsersView{}}}} = task.()

      assert_received {:list_user_status_admin_targets, ^user}
    end

    test "sysop task success sets slot to {:loaded, sub}", %{state: state} do
      sub = %Foglet.TUI.Screens.Sysop.UsersView{current_user: state.current_user}

      {new_state, cmds} =
        App.update({:screen_task_result, :sysop, :sysop_load_users, {:ok, {:ok, sub}}}, state)

      assert cmds == []
      assert new_state.screen_state.sysop.users_view == {:loaded, sub}
    end

    test "sysop task forbidden result sets slot to {:error, :forbidden}",
         %{state: state} do
      {new_state, cmds} =
        App.update(
          {:screen_task_result, :sysop, :sysop_load_users, {:ok, {:error, :forbidden}}},
          state
        )

      assert cmds == []
      assert new_state.screen_state.sysop.users_view == {:error, :forbidden}
    end

    test "sysop task timeout result sets slot to {:error, :timeout}",
         %{state: state} do
      {new_state, cmds} =
        App.update(
          {:screen_task_result, :sysop, :sysop_load_users, {:ok, {:error, :timeout}}},
          state
        )

      assert cmds == []
      assert new_state.screen_state.sysop.users_view == {:error, :timeout}
    end

    test "{:navigate, :sysop} on SITE-active state emits no command (D-03 sync)", %{
      state: state,
      user: user
    } do
      ss =
        SysopState.new(
          current_user: user,
          session_context: state.session_context,
          active: 0
        )

      state = put_in(state, [Access.key(:screen_state), :sysop], ss)

      {new_state, cmds} = App.update({:navigate, :sysop}, state)

      assert new_state.current_screen == :sysop
      assert cmds == []
      # D-03: SITE is synchronous — no Effect.task is emitted. The form is
      # seeded inline by `Sysop.update(:load, ...)` from the Config cache.
      assert %Foglet.TUI.Screens.Sysop.SiteForm.State{current_user: ^user} =
               new_state.screen_state.sysop.site_form
    end

    test "{:navigate, :sysop} is idempotent — re-entering a {:loaded, _} tab emits no command",
         %{state: state, user: user} do
      ss =
        SysopState.new(
          current_user: user,
          session_context: state.session_context,
          active: 4
        )

      ss = %{ss | users_view: {:loaded, %Foglet.TUI.Screens.Sysop.UsersView{}}}
      state = put_in(state, [Access.key(:screen_state), :sysop], ss)

      {new_state, cmds} = App.update({:navigate, :sysop}, state)

      assert cmds == []

      assert new_state.screen_state.sysop.users_view ==
               {:loaded, %Foglet.TUI.Screens.Sysop.UsersView{}}

      refute_received {:list_user_status_admin_targets, _}
    end

    test "all four lifecycle slots round-trip through screen task results", %{
      state: state
    } do
      slots = [
        {:boards_view, %Foglet.TUI.Screens.Sysop.BoardsView{}, :sysop_load_boards},
        {:limits_form, %Foglet.TUI.Screens.Sysop.LimitsForm{}, :sysop_load_limits},
        {:system_snapshot, %Foglet.TUI.Screens.Sysop.SystemSnapshot{}, :sysop_load_system},
        {:users_view, %Foglet.TUI.Screens.Sysop.UsersView{}, :sysop_load_users}
      ]

      for {slot, sub, op} <- slots do
        {after_loaded, []} =
          App.update({:screen_task_result, :sysop, op, {:ok, {:ok, sub}}}, state)

        assert Map.get(after_loaded.screen_state.sysop, slot) == {:loaded, sub}

        reason = if slot in [:users_view, :limits_form], do: :forbidden, else: :timeout

        {after_error, []} =
          App.update({:screen_task_result, :sysop, op, {:ok, {:error, reason}}}, after_loaded)

        slot_value = Map.get(after_error.screen_state.sysop, slot)
        assert match?({:error, _}, slot_value), "Expected {:error, _} got #{inspect(slot_value)}"
      end
    end
  end
end
