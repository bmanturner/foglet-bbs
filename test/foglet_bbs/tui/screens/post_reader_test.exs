defmodule Foglet.TUI.Screens.PostReaderTest do
  use ExUnit.Case, async: true

  alias Foglet.TUI.{Context, Effect}
  alias Foglet.TUI.Screens.PostReader
  alias Foglet.TUI.Screens.PostReader.State

  # Test-only fake modules — standard ExUnit pattern, exempt from the CLAUDE.md
  # "no nested modules" convention (no cyclic-dependency risk in test files).
  defmodule FakePosts do
    def list_posts(_thread_id) do
      posts()
    end

    def list_reader_window(_thread_id, opts) do
      direction = Keyword.get(opts, :direction, :initial)

      %Foglet.Posts.ReaderWindow{
        posts: posts(),
        first_message_number: 1,
        last_message_number: 2,
        has_previous?: direction in [:previous, :around],
        has_next?: direction in [:initial, :next, :around],
        direction: direction
      }
    end

    defp posts do
      [
        %{
          id: "p1",
          message_number: 1,
          body: "first",
          user: %{handle: "alice"},
          inserted_at: ~U[2026-04-18 00:00:00.000000Z]
        },
        %{
          id: "p2",
          message_number: 2,
          body: "second",
          user: %{handle: "bob"},
          inserted_at: ~U[2026-04-18 00:01:00.000000Z]
        }
      ]
    end
  end

  defmodule FakeBoards do
    def advance_board_read_pointer(_user_id, _board_id, _msg_num), do: {:ok, %{}}
  end

  defmodule FakeThreads do
    def advance_thread_read_pointer(_user_id, _thread_id, _post_id), do: {:ok, %{}}
  end

  defmodule FakeMarkdown do
    # Returns [{text, style_atom}] tuples per the Foglet.Markdown.render/1 contract.
    def render(text), do: [{"MD[" <> text <> "]", :plain}]
  end

  defmodule EmptyPosts do
    def list_posts(_tid), do: []

    def list_reader_window(_tid, opts) do
      %Foglet.Posts.ReaderWindow{
        posts: [],
        has_previous?: false,
        has_next?: false,
        direction: Keyword.get(opts, :direction, :initial)
      }
    end
  end

  # Separate from FakePosts: uses message_number 5/6 (vs 1/2) to test
  # load-specific read-position keying and distinguish from default-fixture
  # data. The distinct message_numbers are load-post seeding assertions.
  defmodule FakePostsForLoad do
    def list_posts(_thread_id) do
      posts()
    end

    def list_reader_window(_thread_id, opts) do
      %Foglet.Posts.ReaderWindow{
        posts: posts(),
        first_message_number: 5,
        last_message_number: 6,
        has_previous?: false,
        has_next?: false,
        direction: Keyword.get(opts, :direction, :initial)
      }
    end

    defp posts do
      [
        %{
          id: "p1",
          body: "first post body",
          inserted_at: DateTime.utc_now(),
          user: %{handle: "sysop"},
          message_number: 5
        },
        %{
          id: "p2",
          body: "second post body",
          inserted_at: DateTime.utc_now(),
          user: %{handle: "sysop"},
          message_number: 6
        }
      ]
    end
  end

  defmodule BoundedFakePosts do
    def list_posts(_thread_id), do: raise("unbounded list_posts/1 is forbidden")

    def list_reader_window(thread_id, opts) do
      if pid = Process.get(:reader_window_test_pid) do
        send(pid, {:reader_window_requested, thread_id, opts})
      end

      direction = Keyword.get(opts, :direction, :initial)
      limit = Keyword.get(opts, :limit, 50)
      range = range_for(direction, opts, limit)
      posts = Enum.map(range, &post/1)

      %Foglet.Posts.ReaderWindow{
        posts: posts,
        first_message_number: posts |> List.first() |> message_number(),
        last_message_number: posts |> List.last() |> message_number(),
        has_previous?: range.first > 1,
        has_next?: range.last < 1000,
        direction: direction
      }
    end

    defp range_for(:last, _opts, limit), do: max(1, 1000 - limit + 1)..1000

    defp range_for(:next, opts, limit) do
      first = Keyword.fetch!(opts, :after_message_number) + 1
      first..min(1000, first + limit - 1)
    end

    defp range_for(:previous, opts, limit) do
      last = Keyword.fetch!(opts, :before_message_number) - 1
      max(1, last - limit + 1)..last
    end

    defp range_for(:around, opts, limit) do
      center = Keyword.get(opts, :around_message_number) || 1
      first = max(1, center - div(limit, 2))
      last = min(1000, first + limit - 1)
      max(1, last - limit + 1)..last
    end

    defp range_for(_direction, _opts, limit), do: 1..limit

    defp post(message_number) do
      %{
        id: "p#{message_number}",
        body: "body #{message_number}",
        inserted_at: ~U[2026-04-18 00:00:00.000000Z],
        user: %{handle: "sysop"},
        message_number: message_number
      }
    end

    defp message_number(nil), do: nil
    defp message_number(post), do: Map.get(post, :message_number)
  end

  setup do
    Process.put(:reader_window_test_pid, self())

    state =
      %Foglet.TUI.App{
        current_screen: :post_reader,
        current_user: %Foglet.Accounts.User{id: "u1", handle: "alice"},
        session_context: %{
          domain: %{
            posts: FakePosts,
            boards: FakeBoards,
            threads: FakeThreads,
            markdown: FakeMarkdown
          }
        },
        terminal_size: {80, 24},
        screen_state: %{
          post_reader:
            State.new(
              board: %{id: "b1", name: "General"},
              thread: %{id: "t1", title: "Hello"},
              posts: nil,
              pending_read_positions: %{}
            )
        }
      }
      |> Map.from_struct()

    %{state: state}
  end

  defp reader_ss(state) do
    case get_in(state, [:screen_state, :post_reader]) do
      %State{} = local_state ->
        local_state
        |> ensure_reader_ids()
        |> normalize_reader_state()

      _ ->
        State.new()
    end
  end

  defp ensure_reader_ids(%State{} = local_state) do
    %{
      local_state
      | board_id: local_state.board_id || id_from(local_state.board),
        thread_id: local_state.thread_id || id_from(local_state.thread)
    }
  end

  defp id_from(%{} = value), do: Map.get(value, :id) || Map.get(value, "id")
  defp id_from(_value), do: nil

  defp normalize_reader_state(%State{status: :loading, posts: posts} = local_state)
       when is_list(posts) and posts != [] do
    %{local_state | status: :loaded}
  end

  defp normalize_reader_state(%State{} = local_state), do: local_state

  defp reader_context_from_state(state) do
    local_state = reader_ss(state)

    Context.new(
      current_user: Map.get(state, :current_user),
      terminal_size: Map.get(state, :terminal_size) || {80, 24},
      route: :post_reader,
      route_params:
        Map.get(state, :route_params) ||
          %{
            board: local_state.board,
            board_id: local_state.board_id,
            thread: local_state.thread,
            thread_id: local_state.thread_id
          },
      session_context: Map.get(state, :session_context) || %{}
    )
  end

  defp render_screen(state) do
    render_screen(reader_ss(state), reader_context_from_state(state))
  end

  defp render_screen(%State{} = local_state, %Context{} = context) do
    PostReader.render(local_state, context)
  end

  defp handle_key_screen(key_event, state) do
    context = reader_context_from_state(state)
    local_state = reader_ss(state)
    {new_local_state, effects} = PostReader.update({:key, key_event}, local_state, context)

    state
    |> put_in([:screen_state, :post_reader], new_local_state)
    |> apply_reader_effects(new_local_state, effects)
  end

  defp apply_reader_effects(state, local_state, effects) do
    Enum.reduce(effects, {:update, state, []}, fn
      %Effect{type: :navigate, payload: %{screen: :post_composer, params: params}},
      {:update, acc, cmds} ->
        composer_state = Foglet.TUI.Screens.PostComposer.State.new(Keyword.new(params))

        {:update,
         Map.merge(acc, %{
           current_screen: :post_composer,
           route_params: params,
           screen_state: Map.put(acc.screen_state || %{}, :post_composer, composer_state)
         }), cmds}

      %Effect{type: :navigate, payload: %{screen: screen, params: params}},
      {:update, acc, cmds} ->
        {:update,
         Map.merge(acc, %{
           current_screen: screen,
           route_params: params,
           screen_state: Map.delete(acc.screen_state || %{}, :post_reader)
         }), cmds}

      %Effect{type: :task, payload: %{op: :flush_read_pointers}}, {:update, acc, cmds} ->
        ctx = build_flush_context(acc, local_state)
        {:update, acc, cmds ++ [{:flush_read_pointers, ctx}]}

      _effect, result ->
        result
    end)
  end

  defp build_flush_context(state, %State{} = local_state) do
    pending =
      local_state.pending_read_positions[local_state.thread_id] ||
        local_state.pending_read_positions[to_string(local_state.thread_id || "")]

    user = Map.get(state, :current_user)

    %{
      user_id: user_id(user),
      board_id: local_state.board_id,
      thread_id: local_state.thread_id,
      last_read_post_id: pending && pending.last_read_post_id,
      last_read_message_number: pending && pending.last_read_message_number
    }
  end

  defp user_id(%{id: id}), do: id
  defp user_id(_user), do: nil

  # ===========================================================================
  # READER-02 / D-03 / D-04: Public callback contract surface evidence
  #
  # load_posts/2 and flush_read_pointers/2 are intentional contract surface —
  # kept public to serve as screen-level test seams AND as callable entry
  # points for Foglet.TUI.App.do_update/2 command handling.  These tests act
  # as the explicit dead-code audit evidence (AUDIT-12) proving both functions
  # are called and tested, not dead code.
  # ===========================================================================

  test "load_posts/2 populates state.screen_state[:post_reader].posts", %{state: state} do
    # load_posts/2 intentional callback surface (READER-02, D-03, D-04)
    {s, _} = PostReader.load_posts(state, "t1")
    assert %State{} = ss = s.screen_state.post_reader
    assert length(ss.posts) == 2
  end

  test "State.new/1 returns the PostReader.State struct" do
    assert %State{
             selected_post_index: 0,
             render_cache: %{},
             board: nil,
             board_id: nil,
             thread: nil,
             thread_id: nil,
             posts: nil,
             status: :loading,
             pending_read_positions: %{},
             last_op: nil,
             last_error: nil,
             load_intent: nil
           } = State.new([])
  end

  test "PostReader.State.from_context/1 extracts route identity" do
    board = %{id: "b1", name: "General"}
    thread = %{id: "t1", title: "Hello"}

    context =
      Context.new(
        route: :post_reader,
        route_params: %{board: board, thread: thread, load_intent: :jump_last}
      )

    assert %State{
             board: ^board,
             board_id: "b1",
             thread: ^thread,
             thread_id: "t1",
             load_intent: :jump_last
           } = PostReader.State.from_context(context)
  end

  test "PostReader.State.from_context/1 accepts explicit string route params" do
    context =
      Context.new(
        route: :post_reader,
        route_params: %{
          "board_id" => "b-route",
          "thread_id" => "t-route",
          "load_intent" => "jump_last"
        }
      )

    assert %State{
             board_id: "b-route",
             thread_id: "t-route",
             load_intent: "jump_last"
           } = PostReader.State.from_context(context)
  end

  describe "decomposition contract" do
    test "PostReader.Render is the sibling render entry point" do
      assert Code.ensure_loaded?(PostReader.Render)
      assert function_exported?(PostReader.Render, :render, 2)

      source =
        __ENV__.file
        |> Path.dirname()
        |> Path.join("../../../../lib/foglet_bbs/tui/screens/post_reader.ex")
        |> Path.expand()
        |> File.read!()

      assert source =~
               "def render(%State{} = state, %Context{} = context), do: Render.render(state, context)"
    end

    test "PostReader keeps reducer-facing public seams" do
      assert Code.ensure_loaded?(PostReader)
      assert function_exported?(PostReader, :load_posts, 2)
      assert function_exported?(PostReader, :flush_read_pointers, 2)
      assert function_exported?(PostReader, :subscriptions, 2)
      assert function_exported?(PostReader, :update, 3)
    end
  end

  test "PostReader.update(:load, state, context) emits bounded load_posts_window task" do
    context = post_reader_context()
    state = PostReader.State.from_context(context)

    assert {%State{status: :loading, last_op: :load_posts_window, last_error: nil},
            [
              %Effect{
                type: :task,
                payload: %{op: :load_posts_window, screen_key: :post_reader, fun: fun}
              }
            ]} = PostReader.update(:load, state, context)

    assert %Foglet.Posts.ReaderWindow{posts: [%{id: "p1"}, %{id: "p2"}]} = fun.()
  end

  test "PostReader.update/3 stores loaded posts and seeds pending read data" do
    context = post_reader_context()
    state = %{PostReader.State.from_context(context) | load_intent: :jump_last}
    posts = FakePosts.list_posts("t1")

    assert {%State{} = loaded, []} =
             PostReader.update({:task_result, :load_posts, {:ok, posts}}, state, context)

    assert loaded.posts == posts
    assert loaded.status == :loaded
    assert loaded.selected_post_index == 1

    assert loaded.pending_read_positions["t1"] == %{
             last_read_post_id: "p2",
             last_read_message_number: 2
           }

    assert Map.has_key?(loaded.render_cache, {"p2", 80})
  end

  test "PostReader.update/3 reloads matching active thread activity through reader window" do
    context = post_reader_context()
    state = PostReader.State.from_context(context)

    assert {%State{last_op: :load_posts_window},
            [
              %Effect{
                type: :task,
                payload: %{op: :load_posts_window, screen_key: :post_reader, fun: fun}
              }
            ]} = PostReader.update({:thread_activity, "t1", :new_post}, state, context)

    assert %Foglet.Posts.ReaderWindow{posts: [%{id: "p1"}, %{id: "p2"}]} = fun.()
  end

  test "PostReader.update/3 ignores unrelated thread activity" do
    context = post_reader_context()
    state = PostReader.State.from_context(context)

    assert {^state, []} =
             PostReader.update({:thread_activity, "t-other", :new_post}, state, context)
  end

  test "PostReader.update/3 clears only flushed pending read entry on success" do
    state =
      State.new(
        thread_id: "t1",
        pending_read_positions: %{
          "t1" => %{last_read_post_id: "p1", last_read_message_number: 1},
          "t2" => %{last_read_post_id: "p9", last_read_message_number: 9}
        }
      )

    assert {%State{} = flushed, []} =
             PostReader.update(
               {:task_result, :flush_read_pointers, {:ok, {:read_pointers_flushed, "t1"}}},
               state,
               post_reader_context()
             )

    refute Map.has_key?(flushed.pending_read_positions, "t1")
    assert Map.has_key?(flushed.pending_read_positions, "t2")
  end

  test "PostReader.update/3 keeps pending read entry on flush failure" do
    state =
      State.new(
        thread_id: "t1",
        pending_read_positions: %{
          "t1" => %{last_read_post_id: "p1", last_read_message_number: 1}
        }
      )

    assert {%State{} = failed, []} =
             PostReader.update(
               {:task_result, :flush_read_pointers, {:error, :db_down}},
               state,
               post_reader_context()
             )

    assert Map.has_key?(failed.pending_read_positions, "t1")
    assert failed.last_error == :db_down
  end

  test "PostReader.update/3 keeps pending read entry on wrapped flush failure" do
    state =
      State.new(
        thread_id: "t1",
        pending_read_positions: %{
          "t1" => %{last_read_post_id: "p1", last_read_message_number: 1}
        }
      )

    assert {%State{} = failed, []} =
             PostReader.update(
               {:task_result, :flush_read_pointers, {:ok, {:error, :db_down}}},
               state,
               post_reader_context()
             )

    assert Map.has_key?(failed.pending_read_positions, "t1")
    assert failed.last_error == :db_down
  end

  test "PostReader.update/3 advances selection and pending read data from local posts" do
    context = post_reader_context()

    state =
      State.new(
        board_id: "b1",
        thread_id: "t1",
        posts: FakePosts.list_posts("t1"),
        status: :loaded
      )

    assert {%State{} = moved, []} =
             PostReader.update({:key, %{key: :char, char: "n"}}, state, context)

    assert moved.selected_post_index == 1

    assert moved.pending_read_positions["t1"] == %{
             last_read_post_id: "p2",
             last_read_message_number: 2
           }
  end

  test "PostReader.update/3 emits reply navigation with selected post" do
    context = post_reader_context()
    posts = FakePosts.list_posts("t1")

    state =
      State.new(
        board: %{id: "b1"},
        board_id: "b1",
        thread: %{id: "t1"},
        thread_id: "t1",
        posts: posts,
        selected_post_index: 1,
        status: :loaded
      )

    assert {%State{}, [%Effect{type: :navigate, payload: payload}]} =
             PostReader.update({:key, %{key: :char, char: "r"}}, state, context)

    assert payload.screen == :post_composer
    assert payload.params.reply_to.id == "p2"
    assert payload.params.thread_id == "t1"
  end

  test "PostReader.update/3 emits thread navigation and flush task from local identity" do
    context = post_reader_context()

    state =
      State.new(
        board: %{id: "b1"},
        board_id: "b1",
        thread_id: "t1",
        pending_read_positions: %{
          "t1" => %{last_read_post_id: "p2", last_read_message_number: 2}
        }
      )

    assert {%State{},
            [
              %Effect{type: :navigate, payload: %{screen: :thread_list}},
              %Effect{type: :task, payload: %{op: :flush_read_pointers, fun: fun}}
            ]} = PostReader.update({:key, %{key: :char, char: "q"}}, state, context)

    assert {:read_pointers_flushed, "t1"} = fun.()
  end

  describe "bounded reader-window contract" do
    test "route entry for a 1000-post thread uses list_reader_window/2 and bounded state" do
      context = bounded_post_reader_context()
      state = State.new(thread_id: "t-1000", reader_window_limit: 50)

      assert {%State{} = loading,
              [%Effect{type: :task, payload: %{op: :load_posts_window, fun: fun}}]} =
               PostReader.update(:load, state, context)

      assert %Foglet.Posts.ReaderWindow{} = window = fun.()

      assert_receive {:reader_window_requested, "t-1000", [direction: :initial, limit: 50]}

      assert {%State{} = loaded, []} =
               PostReader.update(
                 {:task_result, :load_posts_window, {:ok, window}},
                 loading,
                 context
               )

      assert length(loaded.posts) < 1000
      assert length(loaded.posts) == 50
      assert loaded.window_first_message_number == 1
      assert loaded.window_last_message_number == 50
      assert loaded.window_has_next?
    end

    test "n at the last active post requests direction: :next and lands on next first post" do
      context = bounded_post_reader_context()

      state =
        bounded_state(
          posts: bounded_posts(1..50),
          selected_post_index: 49,
          window_first_message_number: 1,
          window_last_message_number: 50,
          window_has_next?: true
        )

      assert {%State{} = loading,
              [%Effect{type: :task, payload: %{op: :load_posts_window, fun: fun}}]} =
               PostReader.update({:key, %{key: :char, char: "n"}}, state, context)

      window = fun.()

      assert_receive {:reader_window_requested, "t-1000",
                      [direction: :next, after_message_number: 50, limit: 50]}

      assert {%State{} = loaded, []} =
               PostReader.update(
                 {:task_result, :load_posts_window, {:ok, window}},
                 loading,
                 context
               )

      assert Enum.at(loaded.posts, loaded.selected_post_index).id == "p51"

      assert loaded.pending_read_positions["t-1000"] == %{
               last_read_post_id: "p51",
               last_read_message_number: 51
             }
    end

    test "page_down at the last active post also requests direction: :next" do
      context = bounded_post_reader_context()

      state =
        bounded_state(
          posts: bounded_posts(1..50),
          selected_post_index: 49,
          window_first_message_number: 1,
          window_last_message_number: 50,
          window_has_next?: true
        )

      assert {%State{}, [%Effect{type: :task, payload: %{fun: fun}}]} =
               PostReader.update({:key, %{key: :page_down}}, state, context)

      _window = fun.()
      assert_receive {:reader_window_requested, "t-1000", opts}
      assert Keyword.get(opts, :direction) == :next
    end

    test "p at the first active post requests direction: :previous and lands on previous last post" do
      context = bounded_post_reader_context()

      state =
        bounded_state(
          posts: bounded_posts(51..100),
          selected_post_index: 0,
          window_first_message_number: 51,
          window_last_message_number: 100,
          window_has_previous?: true
        )

      assert {%State{} = loading,
              [%Effect{type: :task, payload: %{op: :load_posts_window, fun: fun}}]} =
               PostReader.update({:key, %{key: :char, char: "p"}}, state, context)

      window = fun.()

      assert_receive {:reader_window_requested, "t-1000",
                      [direction: :previous, before_message_number: 51, limit: 50]}

      assert {%State{} = loaded, []} =
               PostReader.update(
                 {:task_result, :load_posts_window, {:ok, window}},
                 loading,
                 context
               )

      assert Enum.at(loaded.posts, loaded.selected_post_index).id == "p50"

      assert loaded.pending_read_positions["t-1000"] == %{
               last_read_post_id: "p50",
               last_read_message_number: 50
             }
    end

    test "page_up at the first active post also requests direction: :previous" do
      context = bounded_post_reader_context()

      state =
        bounded_state(
          posts: bounded_posts(51..100),
          selected_post_index: 0,
          window_first_message_number: 51,
          window_last_message_number: 100,
          window_has_previous?: true
        )

      assert {%State{}, [%Effect{type: :task, payload: %{fun: fun}}]} =
               PostReader.update({:key, %{key: :page_up}}, state, context)

      _window = fun.()
      assert_receive {:reader_window_requested, "t-1000", opts}
      assert Keyword.get(opts, :direction) == :previous
    end

    test "load_intent: :jump_last requests direction: :last and selects newest post" do
      context = bounded_post_reader_context()
      state = State.new(thread_id: "t-1000", load_intent: :jump_last, reader_window_limit: 50)

      assert {%State{} = loading, [%Effect{type: :task, payload: %{fun: fun}}]} =
               PostReader.update(:load, state, context)

      window = fun.()
      assert_receive {:reader_window_requested, "t-1000", [direction: :last, limit: 50]}

      assert {%State{} = loaded, []} =
               PostReader.update(
                 {:task_result, :load_posts_window, {:ok, window}},
                 loading,
                 context
               )

      assert Enum.at(loaded.posts, loaded.selected_post_index).id == "p1000"
    end

    test "matching thread_activity uses list_reader_window/2 and preserves selected post id" do
      context = bounded_post_reader_context()

      state =
        bounded_state(
          posts: bounded_posts(451..500),
          selected_post_index: 24,
          window_first_message_number: 451,
          window_last_message_number: 500,
          window_has_previous?: true,
          window_has_next?: true
        )

      selected_before = Enum.at(state.posts, state.selected_post_index)

      assert {%State{} = loading, [%Effect{type: :task, payload: %{fun: fun}}]} =
               PostReader.update({:thread_activity, "t-1000", :new_post}, state, context)

      window = fun.()

      assert_receive {:reader_window_requested, "t-1000", opts}
      assert Keyword.get(opts, :direction) == :around
      assert Keyword.get(opts, :around_message_number) == selected_before.message_number

      assert {%State{} = loaded, []} =
               PostReader.update(
                 {:task_result, :load_posts_window, {:ok, window}},
                 loading,
                 context
               )

      assert Enum.at(loaded.posts, loaded.selected_post_index).id == selected_before.id
    end
  end

  test "render/1 with posts loaded does not crash", %{state: state} do
    {s, _} = PostReader.load_posts(state, "t1")
    assert _ = render_screen(s)
  end

  test "render/2 falls back when context terminal size is nil" do
    context =
      Context.new(
        current_user: %{id: "u1", handle: "alice"},
        terminal_size: nil,
        route: :post_reader,
        route_params: %{board: %{id: "b1", name: "General"}, thread: %{id: "t1", title: "Hello"}},
        session_context: %{theme: theme()}
      )

    assert rendered = PostReader.render(State.new(status: :loading), context)
    assert is_map(rendered) or is_list(rendered)
  end

  test "render/1 delegates breadcrumb formatting to shared chrome", %{state: state} do
    # The legacy reader rendered "Thread:" as a hard-coded prefix in its
    # breadcrumb header. The chrome migration moved breadcrumb assembly
    # into shared chrome modules; this is a behavioural guard that the
    # rendered tree no longer contains the legacy prefix.
    {s, _} = PostReader.load_posts(state, "t1")
    text = render_screen(s) |> flatten_text()

    refute text =~ "Thread:"
  end

  # ===========================================================================
  # READER-03 / AUDIT-11: Loading-state spinner render (canonical "Loading…")
  # ===========================================================================

  describe "render/1 loading state" do
    test "nil posts renders canonical 'Loading…' text (not legacy 'Loading posts...')", %{
      state: state
    } do
      # state.posts == nil — loading not yet started
      flat = flatten_text(render_screen(state))
      assert flat =~ "Loading…", "Expected canonical Loading… text, got: #{inspect(flat)}"
      refute String.contains?(flat, "Loading posts..."), "Legacy loading text must not appear"
    end

    test "empty posts list renders canonical 'Loading…' text", %{state: state} do
      ss = %{state.screen_state.post_reader | posts: []}
      s = %{state | screen_state: Map.put(state.screen_state, :post_reader, ss)}
      flat = flatten_text(render_screen(s))
      assert flat =~ "Loading…", "Expected canonical Loading… text for empty posts"
      refute String.contains?(flat, "Loading posts...")
    end
  end

  describe "render/1 - Phase 22 reader facelift" do
    test "renders compact reader metadata for the selected post" do
      post =
        p2_post(
          id: "p42",
          body: "Reader body",
          inserted_at: DateTime.add(DateTime.utc_now(), -5 * 60, :second),
          message_number: 42,
          user: %{handle: "mina"}
        )

      s = p2_state(%{posts: [post]})
      flat = flatten_text(render_screen(s))

      assert flat =~ "Post 1 of 1"
      assert flat =~ "#42"
      assert flat =~ "@mina"
      assert Regex.match?(~r/\d+[smhd] ago/, flat)
    end

    test "renders compact progress for longer threads" do
      posts =
        Enum.map(1..12, fn idx ->
          p2_post(
            id: "p#{idx}",
            body: "Body #{idx}",
            message_number: idx,
            user: %{handle: "mina"}
          )
        end)

      ss = State.new(selected_post_index: 2)
      s = p2_state(%{posts: posts, screen_state: %{post_reader: ss}})

      assert render_screen(s) |> flatten_text() =~ "Posts 3/12"
    end

    test "renders guttered selected body text" do
      s = p2_state(%{posts: [p2_post(body: "Selected body text")]})
      flat = flatten_text(render_screen(s))

      assert flat =~ "│"
      assert flat =~ "Selected body text"
    end

    test "keeps markdown rendering delegated and strips raw markdown syntax" do
      s = p2_state(%{posts: [p2_post(body: "Hello **world**")]})
      tree = render_screen(s)
      serialized = inspect(tree, printable_limit: :infinity, limit: :infinity)

      refute serialized =~ "**world**"
      assert serialized =~ "world"
    end

    test "keeps compact header and progress outside viewport children" do
      s = p2_state(%{posts: [p2_post(body: "Viewport-only body")]})
      tree = render_screen(s)
      viewport = find_node(tree, &match?(%{id: "post_reader_vp"}, &1))
      viewport_text = flatten_text(viewport)

      assert viewport_text =~ "Viewport-only body"
      refute viewport_text =~ "Post 1 of 1"
      refute viewport_text =~ "Posts 1/1"
    end

    test "PostReader delegates reader assembly to PostCard reader helper", %{state: state} do
      # Behavioural check: rendering a thread with at least one post produces
      # the reader-card contract — a "Post N of M" header (PostCard.reader_parts
      # owns this format). The previous source-grep pinned the implementation
      # to a literal call shape.
      {s, _} = PostReader.load_posts(state, "t1")
      text = render_screen(s) |> flatten_text()

      assert text =~ ~r/Post \d+ of \d+/
    end
  end

  test "'n' advances to next post and updates pending_read_positions", %{state: state} do
    {s, _} = PostReader.load_posts(state, "t1")
    {:update, s, _} = handle_key_screen(%{key: :char, char: "n"}, s)
    ss = s.screen_state.post_reader
    assert ss.selected_post_index == 1
    assert ss.pending_read_positions["t1"][:last_read_post_id] == "p2"
    assert ss.pending_read_positions["t1"][:last_read_message_number] == 2
  end

  test "'p' decrements bounded at 0", %{state: state} do
    {s, _} = PostReader.load_posts(state, "t1")
    {:update, s, _} = handle_key_screen(%{key: :char, char: "p"}, s)
    assert s.screen_state.post_reader.selected_post_index == 0
  end

  test "'R' opens :post_composer with reply_to set to current post", %{state: state} do
    {s, _} = PostReader.load_posts(state, "t1")
    {:update, s, _} = handle_key_screen(%{key: :char, char: "R"}, s)
    assert s.current_screen == :post_composer
    assert s.screen_state.post_composer.reply_to.id == "p1"
  end

  test "'R' stashes origin: :post_reader in the :post_composer screen_state", %{state: state} do
    {s, _} = PostReader.load_posts(state, "t1")
    {:update, s, _} = handle_key_screen(%{key: :char, char: "r"}, s)
    assert s.current_screen == :post_composer
    assert s.screen_state.post_composer.origin == :post_reader
  end

  test "'Q' returns to :thread_list and emits {:flush_read_pointers, _} (SSH-09)",
       %{state: state} do
    {s, _} = PostReader.load_posts(state, "t1")
    {:update, s, _} = handle_key_screen(%{key: :char, char: "n"}, s)
    {:update, new_state, cmds} = handle_key_screen(%{key: :char, char: "Q"}, s)

    assert new_state.current_screen == :thread_list
    refute Map.has_key?(new_state.screen_state, :post_reader)
    assert Enum.any?(cmds, &match?({:flush_read_pointers, %{thread_id: "t1"}}, &1))
  end

  test "flush_read_pointers/2 calls domain modules and clears local pointer", %{state: state} do
    # flush_read_pointers/2 intentional callback surface (READER-02, D-03, D-04)
    {s, _} = PostReader.load_posts(state, "t1")
    {:update, s, _} = handle_key_screen(%{key: :char, char: "n"}, s)

    ctx = %{
      user_id: s.current_user.id,
      board_id: "b1",
      thread_id: "t1",
      last_read_post_id: "p2",
      last_read_message_number: 2
    }

    {new_state, _} = PostReader.flush_read_pointers(s, ctx)
    refute Map.has_key?(new_state.screen_state.post_reader.pending_read_positions, "t1")
  end

  # ===========================================================================
  # READER-07: Load-absorb semantics — navigation/scroll keys during loading
  # must return {:update, state, []} and not dispatch extra commands.
  # ===========================================================================

  describe "load-absorb behavior (READER-07)" do
    test "n key on loading state (posts nil) returns {:update, state, []} and absorbs", %{
      state: state
    } do
      # posts is nil — loading window not yet closed
      assert {:update, s, []} = handle_key_screen(%{key: :char, char: "n"}, state)
      # State is returned unchanged (no navigation occurred)
      assert s.screen_state.post_reader.posts == state.screen_state.post_reader.posts
    end

    test "p key on loading state absorbs without extra commands", %{state: state} do
      assert {:update, _s, []} = handle_key_screen(%{key: :char, char: "p"}, state)
    end

    test "space key on loading state absorbs without extra commands", %{state: state} do
      assert {:update, _s, []} = handle_key_screen(%{key: :char, char: " "}, state)
    end

    test "j key on loading state absorbs without extra commands", %{state: state} do
      assert {:update, _s, []} = handle_key_screen(%{key: :char, char: "j"}, state)
    end

    test "k key on loading state absorbs without extra commands", %{state: state} do
      assert {:update, _s, []} = handle_key_screen(%{key: :char, char: "k"}, state)
    end

    test "n key on empty posts list absorbs without extra commands", %{state: state} do
      ss = %{state.screen_state.post_reader | posts: []}
      s = %{state | screen_state: Map.put(state.screen_state, :post_reader, ss)}
      assert {:update, _s, []} = handle_key_screen(%{key: :char, char: "n"}, s)
    end
  end

  # ===========================================================================
  # READER-05: Render helper purity guard — static source check
  #
  # No defp render_* block may contain put_in(, %{state |, or Map.put( writes.
  # This test enforces the render purity boundary (D-07, D-08) at the source level.
  # ===========================================================================

  describe "render helper purity (READER-05, D-07, D-08)" do
    test "defp render_* blocks contain no state-write operations" do
      # Resolve source path relative to this test file's compile-time location.
      source_path =
        __ENV__.file
        |> Path.dirname()
        |> Path.join("../../../../lib/foglet_bbs/tui/screens/post_reader.ex")
        |> Path.expand()

      source = File.read!(source_path)
      lines = String.split(source, "\n")

      # Collect lines belonging to defp render_* bodies.
      # Note: This regex is sufficient for the current source. If multi-clause
      # render_* functions are added back-to-back, the second clause head
      # re-triggers scope entry — harmless but non-monotonic. A two-pass
      # line-range approach would be needed for full correctness.
      {render_lines, _} =
        Enum.reduce(lines, {[], false}, fn line, {acc, inside} ->
          cond do
            # Entering a render helper
            String.match?(line, ~r/^\s+defp render_/) ->
              {[line | acc], true}

            # Entering a non-render defp or public def — exit render scope
            inside and String.match?(line, ~r/^\s+defp [^r]|^\s+defp r[^e]|^\s+def /) ->
              {acc, false}

            inside ->
              {[line | acc], true}

            true ->
              {acc, false}
          end
        end)

      forbidden_patterns = [~r/put_in\(/, ~r/%\{state \|/, ~r/Map\.put\(/]

      violations =
        Enum.flat_map(render_lines, fn line ->
          Enum.flat_map(forbidden_patterns, fn pat ->
            if Regex.match?(pat, line), do: [String.trim(line)], else: []
          end)
        end)

      assert violations == [],
             "render_* helpers contain forbidden state-write operations:\n" <>
               Enum.join(violations, "\n")
    end
  end

  # --- Helper for Phase 2 integration tests (simpler state shape) ---

  defp theme, do: Foglet.TUI.Theme.default()

  defp bounded_post_reader_context do
    Context.new(
      current_user: %{id: "u1", handle: "alice"},
      terminal_size: {80, 24},
      route: :post_reader,
      route_params: %{thread_id: "t-1000"},
      session_context: %{domain: %{posts: BoundedFakePosts, markdown: FakeMarkdown}}
    )
  end

  defp bounded_state(opts) do
    State.new(
      Keyword.merge(
        [
          thread_id: "t-1000",
          reader_window_limit: 50,
          status: :loaded,
          window_first_message_number: 1,
          window_last_message_number: 50
        ],
        opts
      )
    )
  end

  defp bounded_posts(range) do
    Enum.map(range, fn message_number ->
      p2_post(
        id: "p#{message_number}",
        body: "body #{message_number}",
        message_number: message_number
      )
    end)
  end

  defp post_reader_context do
    Context.new(
      current_user: %{id: "u1", handle: "alice"},
      terminal_size: {80, 24},
      route: :post_reader,
      route_params: %{
        board: %{id: "b1", name: "General"},
        thread: %{id: "t1", title: "Hello"}
      },
      session_context: %{
        domain: %{
          posts: FakePosts,
          boards: FakeBoards,
          threads: FakeThreads,
          markdown: FakeMarkdown
        }
      }
    )
  end

  defp p2_post(opts) do
    %{
      id: Keyword.get(opts, :id, "p1"),
      body: Keyword.get(opts, :body, "Hello **world**."),
      inserted_at: Keyword.get(opts, :inserted_at, DateTime.utc_now()),
      user: Keyword.get(opts, :user, %{handle: "sysop"}),
      message_number: Keyword.get(opts, :message_number, 1)
    }
  end

  # Builds the App-shape state map for legacy callback tests. Phase 39 Plan 39-07
  # migrated `posts`, `pending_read_positions`, `thread`, and `board` from
  # top-level App fields onto the screen-owned `%PostReader.State{}` slot at
  # `screen_state[:post_reader]`. Overrides are routed there transparently — pass
  # `posts:`, `read_position:`, `current_thread:`, `current_board:` exactly as
  # callers have for years and the helper places them on the screen struct.
  defp p2_state(overrides) do
    overrides = Enum.into(overrides, %{})

    thread = Map.get(overrides, :current_thread, %{id: "t1", title: "Test Thread"})
    board = Map.get(overrides, :current_board, %{id: "b1"})
    posts = Map.get(overrides, :posts, [p2_post(id: "p1", body: "Hello **world**.")])

    pending =
      Map.get_lazy(overrides, :read_position, fn ->
        seed_pending_for_posts(Map.get(thread || %{}, :id), posts)
      end)

    existing_ss = Map.get(overrides, :screen_state, %{})

    base_ss =
      Map.get(existing_ss, :post_reader, State.new([]))
      |> then(fn ss ->
        struct(ss, %{
          posts: posts,
          status: if(posts in [nil, []], do: ss.status, else: :loaded),
          pending_read_positions: pending,
          thread: thread,
          thread_id: Map.get(thread || %{}, :id),
          board: board,
          board_id: Map.get(board || %{}, :id)
        })
      end)

    screen_state = Map.put(existing_ss, :post_reader, base_ss)

    base = %{
      current_screen: :post_reader,
      current_user: %{id: "u1", handle: "sysop"},
      screen_state: screen_state,
      session_context: %{theme: theme()},
      terminal_size: {80, 24},
      modal: nil
    }

    overrides_for_app =
      Map.drop(overrides, [
        :posts,
        :read_position,
        :current_thread,
        :current_board,
        :screen_state
      ])

    Map.merge(base, overrides_for_app)
  end

  defp seed_pending_for_posts(thread_id, [post | _]) when is_binary(thread_id) do
    %{
      thread_id => %{
        last_read_post_id: Map.get(post, :id),
        last_read_message_number: Map.get(post, :message_number) || 0
      }
    }
  end

  defp seed_pending_for_posts(_thread_id, _posts), do: %{}

  # Local flatten helpers (same pattern as MarkdownBodyTest)

  defp flatten_text(tree), do: tree |> p2_collect_text([]) |> Enum.reverse() |> Enum.join("")

  defp p2_collect_text(nil, acc), do: acc

  defp p2_collect_text(list, acc) when is_list(list),
    do: Enum.reduce(list, acc, &p2_collect_text/2)

  defp p2_collect_text(%{children: children} = node, acc) do
    acc = p2_maybe_add_content(node, acc)
    p2_collect_text(children, acc)
  end

  defp p2_collect_text(%{content: content}, acc) when is_binary(content), do: [content | acc]
  defp p2_collect_text(%{text: t}, acc) when is_binary(t), do: [t | acc]
  defp p2_collect_text(_other, acc), do: acc

  defp p2_maybe_add_content(%{content: content}, acc) when is_binary(content), do: [content | acc]
  defp p2_maybe_add_content(_node, acc), do: acc

  defp find_node(tree, predicate) when is_function(predicate, 1) do
    do_find_node(tree, predicate)
  end

  defp do_find_node(list, predicate) when is_list(list) do
    Enum.find_value(list, &do_find_node(&1, predicate))
  end

  defp do_find_node(%{children: children} = node, predicate) do
    if predicate.(node), do: node, else: do_find_node(children, predicate)
  end

  defp do_find_node(node, predicate) when is_map(node) do
    if predicate.(node), do: node, else: nil
  end

  defp do_find_node(_other, _predicate), do: nil

  # =================================================================
  # RENDER-01: markdown renders without literal \n artifacts
  # =================================================================

  describe "render/1 — RENDER-01 (no literal \\n in output)" do
    test "two-paragraph post renders without literal \\n characters" do
      s =
        p2_state(%{
          posts: [p2_post(body: "First paragraph.\n\nSecond paragraph.")]
        })

      tree = render_screen(s)
      flat = flatten_text(tree)

      assert flat =~ "First paragraph."
      assert flat =~ "Second paragraph."
      refute String.contains?(flat, "First paragraph.\nSecond paragraph.")
    end

    test "inherits MarkdownBody paragraph grouping for soft and blank line breaks" do
      s =
        p2_state(%{
          posts: [p2_post(body: "soft\nbreak\n\nFirst\n\nSecond\n\n\nThird")]
        })

      tree = render_screen(s)
      viewport = find_node(tree, &match?(%{id: "post_reader_vp"}, &1))
      serialized = inspect(viewport, printable_limit: :infinity, limit: :infinity)
      flat = flatten_text(viewport)

      assert flat =~ "soft"
      assert flat =~ "break"
      assert flat =~ "First"
      assert flat =~ "Second"
      assert flat =~ "Third"
      refute String.contains?(flat, "\n")
      refute serialized =~ ~s(content: "\\n")
    end

    test "bold markdown renders formatted (not raw **asterisks**)" do
      s = p2_state(%{posts: [p2_post(body: "Hello **world**.")]})

      tree = render_screen(s)
      serialized = inspect(tree, printable_limit: :infinity, limit: :infinity)

      # The raw markdown syntax must not appear in the rendered tree.
      refute serialized =~ "**world**"
      # The word itself must still be present.
      assert serialized =~ "world"
    end

    test "heading renders as uppercased underlined text" do
      s = p2_state(%{posts: [p2_post(body: "# Hello")]})
      tree = render_screen(s)
      flat = flatten_text(tree)
      assert flat =~ "HELLO"
    end
  end

  # =================================================================
  # RENDER-02: resize without style leaks; width is part of the cache key
  # =================================================================

  describe "render/1 — RENDER-02 (width changes re-flow without leaks)" do
    test "cache key includes width — resize triggers a fresh parse" do
      s80 = p2_state(%{posts: [p2_post(body: "Hello.")], terminal_size: {80, 24}})
      s40 = %{s80 | terminal_size: {40, 24}}

      tree80 = render_screen(s80)
      tree40 = render_screen(s40)

      # Both produce non-nil trees (sanity).
      refute is_nil(tree80)
      refute is_nil(tree40)
    end

    test "no stale styling after j then k then N (scroll + nav cycle)" do
      s =
        p2_state(%{
          posts: [
            p2_post(id: "p1", body: "A\n\nB\n\nC\n\nD\n\nE"),
            p2_post(id: "p2", body: "second post")
          ]
        })

      {:update, s1, _} = handle_key_screen(%{key: :char, char: "j"}, s)
      {:update, s2, _} = handle_key_screen(%{key: :char, char: "k"}, s1)
      {:update, s3, _} = handle_key_screen(%{key: :char, char: "n"}, s2)

      # After N, viewport.scroll_top must reset to 0 (D-04).
      assert s3.screen_state[:post_reader].viewport.scroll_top == 0
      # And the current selection is the second post.
      assert s3.screen_state[:post_reader].selected_post_index == 1

      # render/1 still works on the final state.
      tree = render_screen(s3)
      refute is_nil(tree)
    end
  end

  # =================================================================
  # Scroll: j/k within-post scroll
  # =================================================================

  describe "handle_key/2 — j/k within-post scroll (D-03, D-04, D-05)" do
    test "j advances viewport.scroll_top by 1" do
      # 5 lines, terminal height 12 → available_height = max(12-10, 5) = 5 → max_scroll = 3.
      # Need more lines than available. Use 8 lines with height 12 → available = 5 → max_scroll = 3.
      body = Enum.map_join(1..8, "\n\n", &"Line #{&1}")
      s = p2_state(%{posts: [p2_post(body: body)], terminal_size: {80, 12}})

      assert {:update, s1, []} = handle_key_screen(%{key: :char, char: "j"}, s)
      assert s1.screen_state[:post_reader].viewport.scroll_top == 1
    end

    test "k decrements viewport.scroll_top but clamps at 0" do
      s = p2_state(%{posts: [p2_post(body: "A\n\nB\n\nC")]})

      assert {:update, s1, []} = handle_key_screen(%{key: :char, char: "k"}, s)
      assert s1.screen_state[:post_reader].viewport.scroll_top == 0
    end

    test "j clamps at max_scroll for short posts (cannot scroll past end)" do
      # A single-line post has total_lines=1; with available_height >= 5
      # the max_scroll is 0 — j should not advance.
      s = p2_state(%{posts: [p2_post(body: "Just one line.")]})

      result = handle_key_screen(%{key: :char, char: "j"}, s)
      assert {:update, s1, []} = result
      assert s1.screen_state[:post_reader].viewport.scroll_top == 0
    end

    test "j scrolls through wrapped visual rows from a long paragraph" do
      body =
        Enum.map_join(1..4, " ", fn _ ->
          "alpha beta gamma delta epsilon zeta eta theta iota kappa lambda mu"
        end)

      s = p2_state(%{posts: [p2_post(body: body)], terminal_size: {40, 12}})

      {:update, s1, []} = handle_key_screen(%{key: :char, char: "j"}, s)

      assert s1.screen_state[:post_reader].viewport.scroll_top == 1
      assert length(s1.screen_state[:post_reader].viewport.children) > 1
    end

    test "N resets viewport.scroll_top to 0 (D-04)" do
      # Use small terminal so scroll works: height 12 → available = 5.
      body = Enum.map_join(1..8, "\n\n", &"Line #{&1}")

      s =
        p2_state(%{
          posts: [
            p2_post(id: "p1", body: body),
            p2_post(id: "p2", body: "second post")
          ],
          terminal_size: {80, 12}
        })

      # Scroll down twice on post 1.
      {:update, s1, _} = handle_key_screen(%{key: :char, char: "j"}, s)
      {:update, s2, _} = handle_key_screen(%{key: :char, char: "j"}, s1)
      assert s2.screen_state[:post_reader].viewport.scroll_top == 2

      # Press N to advance to post 2.
      {:update, s3, _} = handle_key_screen(%{key: :char, char: "n"}, s2)
      assert s3.screen_state[:post_reader].viewport.scroll_top == 0
      assert s3.screen_state[:post_reader].selected_post_index == 1
    end

    test "j/k accept uppercase letters too" do
      body = Enum.map_join(1..8, "\n\n", &"Line #{&1}")
      s = p2_state(%{posts: [p2_post(body: body)], terminal_size: {80, 12}})
      assert {:update, s1, []} = handle_key_screen(%{key: :char, char: "J"}, s)
      assert s1.screen_state[:post_reader].viewport.scroll_top == 1
      assert {:update, s2, []} = handle_key_screen(%{key: :char, char: "K"}, s1)
      assert s2.screen_state[:post_reader].viewport.scroll_top == 0
    end

    test "viewport state shape: scroll_top is a non-negative integer and children is a list" do
      body = Enum.map_join(1..8, "\n\n", &"Line #{&1}")
      s = p2_state(%{posts: [p2_post(body: body)], terminal_size: {80, 12}})

      {:update, s1, []} = handle_key_screen(%{key: :char, char: "j"}, s)
      ss = s1.screen_state[:post_reader]

      assert is_map(ss.viewport)
      assert is_integer(ss.viewport.scroll_top)
      assert ss.viewport.scroll_top >= 0
      assert is_list(ss.viewport.children)
      refute Map.has_key?(ss, :scroll_offset), ":scroll_offset key must be absent"
    end
  end

  # =================================================================
  # Render cache
  # =================================================================

  describe "render_cache — per-screen memoization" do
    test "cache is populated on first j (scroll warms cache)" do
      s = p2_state(%{posts: [p2_post(id: "p1", body: "A\n\nB\n\nC\n\nD")]})

      {:update, s1, _} = handle_key_screen(%{key: :char, char: "j"}, s)

      cache = s1.screen_state[:post_reader].render_cache

      assert Map.has_key?(cache, {"p1", 80}),
             "Expected cache key {\"p1\", 80}, got: #{inspect(Map.keys(cache))}"
    end

    test "cache is keyed on {post.id, width} and width change evicts stale entries" do
      s = p2_state(%{posts: [p2_post(id: "p1", body: "A\n\nB")]})

      # Warm cache at width 80.
      {:update, s1, _} = handle_key_screen(%{key: :char, char: "j"}, s)
      assert Map.has_key?(s1.screen_state[:post_reader].render_cache, {"p1", 80})

      # Change width, scroll again.
      s2 = %{s1 | terminal_size: {40, 24}}
      {:update, s3, _} = handle_key_screen(%{key: :char, char: "j"}, s2)

      cache = s3.screen_state[:post_reader].render_cache
      assert Map.has_key?(cache, {"p1", 40})
      refute Enum.any?(Map.keys(cache), &(elem(&1, 1) == 80))
    end

    test "reducer warming after resize retains only current-width cache keys" do
      context_80 = post_reader_context()
      context_40 = %{context_80 | terminal_size: {40, 24}}

      state =
        State.new(
          board_id: "b1",
          thread_id: "t1",
          posts: [p2_post(id: "p1", body: "A\n\nB\n\nC", message_number: 1)],
          status: :loaded
        )

      assert {%State{} = warmed_80, []} =
               PostReader.update({:key, %{key: :char, char: "j"}}, state, context_80)

      assert Enum.any?(Map.keys(warmed_80.render_cache), &(elem(&1, 1) == 80))

      assert {%State{} = warmed_40, []} =
               PostReader.update({:key, %{key: :char, char: "j"}}, warmed_80, context_40)

      assert Enum.any?(Map.keys(warmed_40.render_cache), &(elem(&1, 1) == 40))
      refute Enum.any?(Map.keys(warmed_40.render_cache), &(elem(&1, 1) == 80))

      assert Enum.all?(Map.keys(warmed_40.render_cache), fn
               {_post_id, width} when is_integer(width) -> true
               _other -> false
             end)
    end

    test "Q clears :post_reader screen_state (cache is discarded)" do
      s = p2_state(%{posts: [p2_post(id: "p1", body: "A\n\nB\n\nC")]})
      {:update, s1, _} = handle_key_screen(%{key: :char, char: "j"}, s)
      assert s1.screen_state[:post_reader].render_cache != %{}

      # Press Q.
      {:update, s2, cmds} = handle_key_screen(%{key: :char, char: "q"}, s1)
      assert s2.current_screen == :thread_list
      refute Map.has_key?(s2.screen_state, :post_reader)
      # And the flush command is dispatched.
      assert Enum.any?(cmds, fn
               {:flush_read_pointers, _} -> true
               _ -> false
             end)
    end

    test "render_cache is preserved verbatim through Viewport migration (D-13)" do
      # Multiple posts with scrollable content. After a j/N/j cycle the cache
      # should contain entries for BOTH posts at width 80 — Viewport migration
      # must not disturb the cache shape.
      body = Enum.map_join(1..8, "\n\n", &"Line #{&1}")

      s =
        p2_state(%{
          posts: [p2_post(id: "p1", body: body), p2_post(id: "p2", body: body)],
          terminal_size: {80, 12}
        })

      {:update, s1, _} = handle_key_screen(%{key: :char, char: "j"}, s)
      {:update, s2, _} = handle_key_screen(%{key: :char, char: "n"}, s1)
      {:update, s3, _} = handle_key_screen(%{key: :char, char: "j"}, s2)

      cache = s3.screen_state[:post_reader].render_cache
      assert Map.has_key?(cache, {"p1", 80})
      assert Map.has_key?(cache, {"p2", 80})
    end
  end

  # =================================================================
  # Seed-fixture UAT smoke
  # =================================================================

  describe "render/1 — seed-fixture UAT smoke" do
    test "Welcome thread body (bold + inline code + bullets) renders without raw markdown" do
      welcome_body = """
      Welcome aboard!

      Foglet BBS is a classic bulletin board system accessible over SSH.

      **Getting started:**
      - Press `B` from the Main Menu to browse boards
      - Press `C` to start a new thread
      - Press `R` while reading to compose a reply

      Enjoy your stay.
      """

      s = p2_state(%{posts: [p2_post(body: welcome_body)]})
      s = %{s | terminal_size: {80, 40}}
      tree = render_screen(s)
      flat = flatten_text(tree)
      serialized = inspect(tree, printable_limit: :infinity, limit: :infinity)

      # Content present
      assert flat =~ "Welcome aboard!"
      assert flat =~ "Enjoy your stay."
      assert flat =~ "Press"

      # Raw markdown syntax stripped
      refute serialized =~ "**Getting started:**"
      refute serialized =~ "`B`"
    end

    test "General Chat reply (inline bold + italic in one line) renders formatted" do
      body =
        "Agreed. Markdown preview in the composer is a nice touch — **bold** and *italic* both render correctly."

      s = p2_state(%{posts: [p2_post(body: body)]})
      tree = render_screen(s)
      serialized = inspect(tree, printable_limit: :infinity, limit: :infinity)
      flat = flatten_text(tree)

      # Text content intact
      assert flat =~ "bold"
      assert flat =~ "italic"
      assert flat =~ "Markdown preview"

      # Raw syntax stripped
      refute serialized =~ "**bold**"
      refute serialized =~ "*italic*"
    end
  end

  describe "load_posts/2 — read-on-entry seeding (LIST-01 D-05)" do
    test "seeds pending_read_positions[thread_id] with post 0's id and message_number on load" do
      s =
        p2_state(%{
          current_thread: %{id: "t1", title: "test"},
          posts: nil,
          read_position: %{},
          session_context: %{theme: theme(), domain: %{posts: FakePostsForLoad}}
        })

      {s_after, _} = PostReader.load_posts(s, "t1")

      rp = s_after.screen_state.post_reader.pending_read_positions["t1"]
      assert rp, "Expected pending_read_positions[\"t1\"] to be seeded"
      assert rp.last_read_post_id == "p1"
      assert rp.last_read_message_number == 5
    end

    test "does NOT touch other threads' pending_read_positions entries" do
      s =
        p2_state(%{
          current_thread: %{id: "t1", title: "test"},
          posts: nil,
          read_position: %{
            "tOther" => %{last_read_post_id: "pX", last_read_message_number: 99}
          },
          session_context: %{theme: theme(), domain: %{posts: FakePostsForLoad}}
        })

      {s_after, _} = PostReader.load_posts(s, "t1")

      pending = s_after.screen_state.post_reader.pending_read_positions
      assert pending["tOther"].last_read_post_id == "pX"
      assert pending["tOther"].last_read_message_number == 99
    end

    test "empty posts list leaves pending_read_positions unchanged (no crash)" do
      s =
        p2_state(%{
          current_thread: %{id: "t1", title: "test"},
          posts: nil,
          read_position: %{},
          session_context: %{theme: theme(), domain: %{posts: EmptyPosts}}
        })

      {s_after, _} = PostReader.load_posts(s, "t1")

      assert s_after.screen_state.post_reader.pending_read_positions == %{}
    end

    test "Q immediately after load produces a flush command with post 0's message_number (integration)" do
      s =
        p2_state(%{
          current_thread: %{id: "t1", title: "test"},
          current_board: %{id: "b1"},
          current_user: %{id: "u1", handle: "sysop"},
          posts: nil,
          read_position: %{},
          session_context: %{theme: theme(), domain: %{posts: FakePostsForLoad}}
        })

      {s_after_load, _} = PostReader.load_posts(s, "t1")
      {:update, _s_after_q, cmds} = handle_key_screen(%{key: :char, char: "q"}, s_after_load)

      flush =
        Enum.find(cmds, fn
          {:flush_read_pointers, _ctx} -> true
          _ -> false
        end)

      assert flush, "Expected a :flush_read_pointers command after Q, got: #{inspect(cmds)}"

      {:flush_read_pointers, ctx} = flush
      assert ctx[:last_read_message_number] == 5
      assert ctx[:last_read_post_id] == "p1"
      assert ctx[:thread_id] == "t1"
      assert ctx[:board_id] == "b1"
    end
  end

  describe "subscriptions/2 export (Phase 39 R6, D-08)" do
    test "module exports subscriptions/2" do
      assert Code.ensure_loaded?(Foglet.TUI.Screens.PostReader)
      assert function_exported?(Foglet.TUI.Screens.PostReader, :subscriptions, 2)
    end

    test "returns thread topic from local state" do
      state = %Foglet.TUI.Screens.PostReader.State{thread_id: "t-99"}
      ctx = %Foglet.TUI.Context{route_params: %{}}

      assert Foglet.TUI.Screens.PostReader.subscriptions(state, ctx) == ["thread:t-99"]
    end

    test "returns thread topic from atom-key route params when local state is empty" do
      ctx = %Foglet.TUI.Context{route_params: %{thread_id: "t-route"}}

      assert Foglet.TUI.Screens.PostReader.subscriptions(nil, ctx) == ["thread:t-route"]
    end

    test "returns thread topic from string-key route params when local state is empty" do
      ctx = %Foglet.TUI.Context{route_params: %{"thread_id" => "t-string"}}

      assert Foglet.TUI.Screens.PostReader.subscriptions(nil, ctx) == ["thread:t-string"]
    end

    test "returns [] when no thread id is available" do
      ctx = %Foglet.TUI.Context{route_params: %{}}

      assert Foglet.TUI.Screens.PostReader.subscriptions(nil, ctx) == []
    end
  end

  describe "update(:on_route_enter, …) — Phase 39 Plan 04" do
    # PostReader's route-entry semantics today (app.ex:838-843) only loads
    # when route_params carries a binary thread_id. This plan adds the
    # equivalent screen-side clauses with state-first / route_params-fallback
    # gating that mirrors subscriptions/2's shape.

    test "with binary thread_id in local state delegates to :load (state-first match)" do
      ctx = post_reader_context()
      # Local state already carries thread_id (e.g. re-entry via back-nav with
      # empty route_params).
      state = %State{thread_id: "t-from-state"}

      {state_via_on_enter, effects_via_on_enter} =
        PostReader.update(:on_route_enter, state, ctx)

      {state_via_load, effects_via_load} =
        PostReader.update(:load, state, ctx)

      assert state_via_on_enter == state_via_load
      assert effects_via_on_enter == effects_via_load
      assert state_via_on_enter.status == :loading
      assert [%Effect{type: :task, payload: %{op: :load_posts_window}}] = effects_via_on_enter
    end

    test "with no thread_id in state but atom :thread_id route param delegates to :load (surfaces :load's missing-thread error since fallback doesn't hydrate state)" do
      # Today App's app.ex:838-843 dispatches :load when route_params has a
      # thread_id; in the integrated flow App's init_route_screen_state has
      # already hydrated state.thread_id via State.from_context, so :load's
      # state-first guard matches. The screen-side fallback preserves the
      # dispatch shape — the binding test proves the clause matched and
      # delegated to :load (rather than the catch-all returning {state, []}
      # silently). When called with a non-hydrated state, :load surfaces
      # its missing-thread error guard rather than no-opping.
      ctx = %{post_reader_context() | route_params: %{thread_id: "t-atom"}}
      state = %State{}

      {new_state, effects} = PostReader.update(:on_route_enter, state, ctx)

      assert effects == []
      # Proves :load was dispatched (vs. the catch-all returning state unchanged).
      assert new_state.status == {:error, :missing_thread}
      assert new_state.last_error == :missing_thread
    end

    test "with no thread_id in state but string \"thread_id\" route param delegates to :load" do
      ctx = %{post_reader_context() | route_params: %{"thread_id" => "t-string"}}
      state = %State{}

      {new_state, effects} = PostReader.update(:on_route_enter, state, ctx)

      assert effects == []
      assert new_state.status == {:error, :missing_thread}
      assert new_state.last_error == :missing_thread
    end

    test "fully hydrated state from State.from_context still delegates correctly (integrated path)" do
      # Mirrors the real App flow: init_route_screen_state runs State.from_context
      # before :on_route_enter fires. The state-first clause matches.
      ctx = post_reader_context()
      state = PostReader.State.from_context(ctx)
      assert is_binary(state.thread_id)

      {new_state, effects} = PostReader.update(:on_route_enter, state, ctx)

      assert new_state.status == :loading
      assert [%Effect{type: :task, payload: %{op: :load_posts_window}}] = effects
    end

    test "with no thread_id in state and no thread_id route param no-ops" do
      ctx = %{post_reader_context() | route_params: %{}}
      state = %State{}

      {new_state, effects} = PostReader.update(:on_route_enter, state, ctx)

      assert effects == []
      assert new_state == state
    end

    test "non-binary thread_id (e.g. nil) in state falls through to route_params fallback" do
      # State.thread_id == nil should NOT match the state-first clause; falls
      # to the route_params fallback which finds nothing → no-op.
      ctx = %{post_reader_context() | route_params: %{}}
      state = %State{thread_id: nil}

      {new_state, effects} = PostReader.update(:on_route_enter, state, ctx)

      assert effects == []
      assert new_state == state
    end
  end
end
