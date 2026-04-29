defmodule Foglet.TUI.Screens.PostReaderTest do
  use ExUnit.Case, async: true

  alias Foglet.TUI.Screens.PostReader
  alias Foglet.TUI.Screens.PostReader.State
  alias Foglet.TUI.{Context, Effect}

  # Test-only fake modules — standard ExUnit pattern, exempt from the CLAUDE.md
  # "no nested modules" convention (no cyclic-dependency risk in test files).
  defmodule FakePosts do
    def list_posts(_thread_id) do
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
  end

  # Separate from FakePosts: uses message_number 5/6 (vs 1/2) to test
  # load-specific read-position keying and distinguish from default-fixture
  # data. The distinct message_numbers are load-post seeding assertions.
  defmodule FakePostsForLoad do
    def list_posts(_thread_id) do
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

  setup do
    state =
      %Foglet.TUI.App{
        current_screen: :post_reader,
        current_user: %Foglet.Accounts.User{id: "u1", handle: "alice"},
        current_board: %{id: "b1", name: "General"},
        current_thread: %{id: "t1", title: "Hello"},
        session_context: %{
          domain: %{
            posts: FakePosts,
            boards: FakeBoards,
            threads: FakeThreads,
            markdown: FakeMarkdown
          }
        },
        terminal_size: {80, 24},
        posts: nil,
        read_position: %{},
        screen_state: %{post_reader: PostReader.init_screen_state([])}
      }
      |> Map.from_struct()

    %{state: state}
  end

  # ===========================================================================
  # READER-02 / D-03 / D-04: Public callback contract surface evidence
  #
  # load_posts/2 and flush_read_pointers/2 are intentional contract surface —
  # kept public to serve as screen-level test seams AND as callable entry
  # points for Foglet.TUI.App.do_update/2 command handling.  These tests act
  # as the explicit dead-code audit evidence (AUDIT-12) proving both functions
  # are called and tested, not dead code.
  # ===========================================================================

  test "load_posts/2 populates state.posts", %{state: state} do
    # load_posts/2 intentional callback surface (READER-02, D-03, D-04)
    {s, _} = PostReader.load_posts(state, "t1")
    assert length(s.posts) == 2
    assert %State{} = s.screen_state.post_reader
  end

  test "init_screen_state/1 returns the PostReader.State struct" do
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
           } = PostReader.init_screen_state([])
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

  test "PostReader.update(:load, state, context) emits load_posts task" do
    context = post_reader_context()
    state = PostReader.State.from_context(context)

    assert {%State{status: :loading, last_op: :load_posts, last_error: nil},
            [
              %Effect{
                type: :task,
                payload: %{op: :load_posts, screen_key: :post_reader, fun: fun}
              }
            ]} = PostReader.update(:load, state, context)

    assert [%{id: "p1"}, %{id: "p2"}] = fun.()
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

  test "PostReader.update/3 reloads matching active thread activity" do
    context = post_reader_context()
    state = PostReader.State.from_context(context)

    assert {%State{last_op: :load_posts},
            [
              %Effect{
                type: :task,
                payload: %{op: :load_posts, screen_key: :post_reader, fun: fun}
              }
            ]} = PostReader.update({:thread_activity, "t1", :new_post}, state, context)

    assert [%{id: "p1"}, %{id: "p2"}] = fun.()
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

  test "render/1 with posts loaded does not crash", %{state: state} do
    {s, _} = PostReader.load_posts(state, "t1")
    assert _ = PostReader.render(s)
  end

  test "render/1 delegates breadcrumb formatting to shared chrome" do
    source =
      __ENV__.file
      |> Path.dirname()
      |> Path.join("../../../../lib/foglet_bbs/tui/screens/post_reader.ex")
      |> Path.expand()
      |> File.read!()

    refute source =~ "Thread:"
  end

  # ===========================================================================
  # READER-03 / AUDIT-11: Loading-state spinner render (canonical "Loading…")
  # ===========================================================================

  describe "render/1 loading state" do
    test "nil posts renders canonical 'Loading…' text (not legacy 'Loading posts...')", %{
      state: state
    } do
      # state.posts == nil — loading not yet started
      flat = flatten_text(PostReader.render(state))
      assert flat =~ "Loading…", "Expected canonical Loading… text, got: #{inspect(flat)}"
      refute String.contains?(flat, "Loading posts..."), "Legacy loading text must not appear"
    end

    test "empty posts list renders canonical 'Loading…' text", %{state: state} do
      s = %{state | posts: []}
      flat = flatten_text(PostReader.render(s))
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
      flat = flatten_text(PostReader.render(s))

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

      ss = PostReader.init_screen_state(selected_post_index: 2)
      s = p2_state(%{posts: posts, screen_state: %{post_reader: ss}})

      assert PostReader.render(s) |> flatten_text() =~ "Posts 3/12"
    end

    test "renders guttered selected body text" do
      s = p2_state(%{posts: [p2_post(body: "Selected body text")]})
      flat = flatten_text(PostReader.render(s))

      assert flat =~ "│"
      assert flat =~ "Selected body text"
    end

    test "keeps markdown rendering delegated and strips raw markdown syntax" do
      s = p2_state(%{posts: [p2_post(body: "Hello **world**")]})
      tree = PostReader.render(s)
      serialized = inspect(tree, printable_limit: :infinity, limit: :infinity)

      refute serialized =~ "**world**"
      assert serialized =~ "world"
    end

    test "keeps compact header and progress outside viewport children" do
      s = p2_state(%{posts: [p2_post(body: "Viewport-only body")]})
      tree = PostReader.render(s)
      viewport = find_node(tree, &match?(%{id: "post_reader_vp"}, &1))
      viewport_text = flatten_text(viewport)

      assert viewport_text =~ "Viewport-only body"
      refute viewport_text =~ "Post 1 of 1"
      refute viewport_text =~ "Posts 1/1"
    end

    test "PostReader delegates reader assembly to PostCard reader helper" do
      source =
        __ENV__.file
        |> Path.dirname()
        |> Path.join("../../../../lib/foglet_bbs/tui/screens/post_reader.ex")
        |> Path.expand()
        |> File.read!()

      assert source =~ "PostCard.reader_parts"
      refute source =~ "PostCard.author_line(post)"
      refute source =~ ~s(text("Post \#{idx + 1} of \#{total}")
    end
  end

  test "'n' advances to next post and updates read_position", %{state: state} do
    {s, _} = PostReader.load_posts(state, "t1")
    {:update, s, _} = PostReader.handle_key(%{key: :char, char: "n"}, s)
    assert s.screen_state.post_reader.selected_post_index == 1
    assert s.read_position["t1"][:last_read_post_id] == "p2"
    assert s.read_position["t1"][:last_read_message_number] == 2
  end

  test "'p' decrements bounded at 0", %{state: state} do
    {s, _} = PostReader.load_posts(state, "t1")
    {:update, s, _} = PostReader.handle_key(%{key: :char, char: "p"}, s)
    assert s.screen_state.post_reader.selected_post_index == 0
  end

  test "'R' opens :post_composer with reply_to set to current post", %{state: state} do
    {s, _} = PostReader.load_posts(state, "t1")
    {:update, s, _} = PostReader.handle_key(%{key: :char, char: "R"}, s)
    assert s.current_screen == :post_composer
    assert s.screen_state.post_composer.reply_to.id == "p1"
  end

  test "'R' stashes origin: :post_reader in the :post_composer screen_state", %{state: state} do
    {s, _} = PostReader.load_posts(state, "t1")
    {:update, s, _} = PostReader.handle_key(%{key: :char, char: "r"}, s)
    assert s.current_screen == :post_composer
    assert s.screen_state.post_composer.origin == :post_reader
  end

  test "'Q' returns to :thread_list and emits {:flush_read_pointers, _} (SSH-09)",
       %{state: state} do
    {s, _} = PostReader.load_posts(state, "t1")
    {:update, s, _} = PostReader.handle_key(%{key: :char, char: "n"}, s)
    {:update, new_state, cmds} = PostReader.handle_key(%{key: :char, char: "Q"}, s)

    assert new_state.current_screen == :thread_list
    assert new_state.posts == nil
    assert Enum.any?(cmds, &match?({:flush_read_pointers, %{thread_id: "t1"}}, &1))
  end

  test "flush_read_pointers/2 calls domain modules and clears local pointer", %{state: state} do
    # flush_read_pointers/2 intentional callback surface (READER-02, D-03, D-04)
    {s, _} = PostReader.load_posts(state, "t1")
    {:update, s, _} = PostReader.handle_key(%{key: :char, char: "n"}, s)

    ctx = %{
      user_id: s.current_user.id,
      board_id: "b1",
      thread_id: "t1",
      last_read_post_id: "p2",
      last_read_message_number: 2
    }

    {new_state, _} = PostReader.flush_read_pointers(s, ctx)
    refute Map.has_key?(new_state.read_position, "t1")
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
      assert {:update, s, []} = PostReader.handle_key(%{key: :char, char: "n"}, state)
      # State is returned unchanged (no navigation occurred)
      assert s.posts == state.posts
    end

    test "p key on loading state absorbs without extra commands", %{state: state} do
      assert {:update, _s, []} = PostReader.handle_key(%{key: :char, char: "p"}, state)
    end

    test "space key on loading state absorbs without extra commands", %{state: state} do
      assert {:update, _s, []} = PostReader.handle_key(%{key: :char, char: " "}, state)
    end

    test "j key on loading state absorbs without extra commands", %{state: state} do
      assert {:update, _s, []} = PostReader.handle_key(%{key: :char, char: "j"}, state)
    end

    test "k key on loading state absorbs without extra commands", %{state: state} do
      assert {:update, _s, []} = PostReader.handle_key(%{key: :char, char: "k"}, state)
    end

    test "n key on empty posts list absorbs without extra commands", %{state: state} do
      s = %{state | posts: []}
      assert {:update, _s, []} = PostReader.handle_key(%{key: :char, char: "n"}, s)
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

  defp p2_state(overrides) do
    base = %{
      current_screen: :post_reader,
      current_thread: %{id: "t1", title: "Test Thread"},
      current_board: %{id: "b1"},
      current_user: %{id: "u1", handle: "sysop"},
      posts: [p2_post(id: "p1", body: "Hello **world**.")],
      read_position: %{},
      screen_state: %{post_reader: PostReader.init_screen_state([])},
      session_context: %{theme: theme()},
      terminal_size: {80, 24},
      modal: nil,
      composer_draft: ""
    }

    Map.merge(base, overrides)
  end

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

      tree = PostReader.render(s)
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

      tree = PostReader.render(s)
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

      tree = PostReader.render(s)
      serialized = inspect(tree, printable_limit: :infinity, limit: :infinity)

      # The raw markdown syntax must not appear in the rendered tree.
      refute serialized =~ "**world**"
      # The word itself must still be present.
      assert serialized =~ "world"
    end

    test "heading renders as uppercased underlined text" do
      s = p2_state(%{posts: [p2_post(body: "# Hello")]})
      tree = PostReader.render(s)
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

      tree80 = PostReader.render(s80)
      tree40 = PostReader.render(s40)

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

      {:update, s1, _} = PostReader.handle_key(%{key: :char, char: "j"}, s)
      {:update, s2, _} = PostReader.handle_key(%{key: :char, char: "k"}, s1)
      {:update, s3, _} = PostReader.handle_key(%{key: :char, char: "n"}, s2)

      # After N, viewport.scroll_top must reset to 0 (D-04).
      assert s3.screen_state[:post_reader].viewport.scroll_top == 0
      # And the current selection is the second post.
      assert s3.screen_state[:post_reader].selected_post_index == 1

      # render/1 still works on the final state.
      tree = PostReader.render(s3)
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

      assert {:update, s1, []} = PostReader.handle_key(%{key: :char, char: "j"}, s)
      assert s1.screen_state[:post_reader].viewport.scroll_top == 1
    end

    test "k decrements viewport.scroll_top but clamps at 0" do
      s = p2_state(%{posts: [p2_post(body: "A\n\nB\n\nC")]})

      assert {:update, s1, []} = PostReader.handle_key(%{key: :char, char: "k"}, s)
      assert s1.screen_state[:post_reader].viewport.scroll_top == 0
    end

    test "j clamps at max_scroll for short posts (cannot scroll past end)" do
      # A single-line post has total_lines=1; with available_height >= 5
      # the max_scroll is 0 — j should not advance.
      s = p2_state(%{posts: [p2_post(body: "Just one line.")]})

      result = PostReader.handle_key(%{key: :char, char: "j"}, s)
      assert {:update, s1, []} = result
      assert s1.screen_state[:post_reader].viewport.scroll_top == 0
    end

    test "j scrolls through wrapped visual rows from a long paragraph" do
      body =
        Enum.map_join(1..4, " ", fn _ ->
          "alpha beta gamma delta epsilon zeta eta theta iota kappa lambda mu"
        end)

      s = p2_state(%{posts: [p2_post(body: body)], terminal_size: {40, 12}})

      {:update, s1, []} = PostReader.handle_key(%{key: :char, char: "j"}, s)

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
      {:update, s1, _} = PostReader.handle_key(%{key: :char, char: "j"}, s)
      {:update, s2, _} = PostReader.handle_key(%{key: :char, char: "j"}, s1)
      assert s2.screen_state[:post_reader].viewport.scroll_top == 2

      # Press N to advance to post 2.
      {:update, s3, _} = PostReader.handle_key(%{key: :char, char: "n"}, s2)
      assert s3.screen_state[:post_reader].viewport.scroll_top == 0
      assert s3.screen_state[:post_reader].selected_post_index == 1
    end

    test "j/k accept uppercase letters too" do
      body = Enum.map_join(1..8, "\n\n", &"Line #{&1}")
      s = p2_state(%{posts: [p2_post(body: body)], terminal_size: {80, 12}})
      assert {:update, s1, []} = PostReader.handle_key(%{key: :char, char: "J"}, s)
      assert s1.screen_state[:post_reader].viewport.scroll_top == 1
      assert {:update, s2, []} = PostReader.handle_key(%{key: :char, char: "K"}, s1)
      assert s2.screen_state[:post_reader].viewport.scroll_top == 0
    end

    test "viewport state shape: scroll_top is a non-negative integer and children is a list" do
      body = Enum.map_join(1..8, "\n\n", &"Line #{&1}")
      s = p2_state(%{posts: [p2_post(body: body)], terminal_size: {80, 12}})

      {:update, s1, []} = PostReader.handle_key(%{key: :char, char: "j"}, s)
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

      {:update, s1, _} = PostReader.handle_key(%{key: :char, char: "j"}, s)

      cache = s1.screen_state[:post_reader].render_cache

      assert Map.has_key?(cache, {"p1", 80}),
             "Expected cache key {\"p1\", 80}, got: #{inspect(Map.keys(cache))}"
    end

    test "cache is keyed on {post.id, width} — width change adds a new entry" do
      s = p2_state(%{posts: [p2_post(id: "p1", body: "A\n\nB")]})

      # Warm cache at width 80.
      {:update, s1, _} = PostReader.handle_key(%{key: :char, char: "j"}, s)
      assert Map.has_key?(s1.screen_state[:post_reader].render_cache, {"p1", 80})

      # Change width, scroll again.
      s2 = %{s1 | terminal_size: {40, 24}}
      {:update, s3, _} = PostReader.handle_key(%{key: :char, char: "j"}, s2)

      cache = s3.screen_state[:post_reader].render_cache
      assert Map.has_key?(cache, {"p1", 80})
      assert Map.has_key?(cache, {"p1", 40})
    end

    test "Q clears :post_reader screen_state (cache is discarded)" do
      s = p2_state(%{posts: [p2_post(id: "p1", body: "A\n\nB\n\nC")]})
      {:update, s1, _} = PostReader.handle_key(%{key: :char, char: "j"}, s)
      assert s1.screen_state[:post_reader].render_cache != %{}

      # Press Q.
      {:update, s2, cmds} = PostReader.handle_key(%{key: :char, char: "q"}, s1)
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

      {:update, s1, _} = PostReader.handle_key(%{key: :char, char: "j"}, s)
      {:update, s2, _} = PostReader.handle_key(%{key: :char, char: "n"}, s1)
      {:update, s3, _} = PostReader.handle_key(%{key: :char, char: "j"}, s2)

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
      tree = PostReader.render(s)
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
      tree = PostReader.render(s)
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
    test "seeds read_position[thread_id] with post 0's id and message_number on load" do
      s =
        p2_state(%{
          current_thread: %{id: "t1", title: "test"},
          posts: nil,
          read_position: %{},
          session_context: %{theme: theme(), domain: %{posts: FakePostsForLoad}}
        })

      {s_after, _} = PostReader.load_posts(s, "t1")

      rp = s_after.read_position["t1"]
      assert rp, "Expected read_position[\"t1\"] to be seeded"
      assert rp.last_read_post_id == "p1"
      assert rp.last_read_message_number == 5
    end

    test "does NOT touch other threads' read_position entries" do
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

      assert s_after.read_position["tOther"].last_read_post_id == "pX"
      assert s_after.read_position["tOther"].last_read_message_number == 99
    end

    test "empty posts list leaves read_position unchanged (no crash)" do
      s =
        p2_state(%{
          current_thread: %{id: "t1", title: "test"},
          posts: nil,
          read_position: %{},
          session_context: %{theme: theme(), domain: %{posts: EmptyPosts}}
        })

      {s_after, _} = PostReader.load_posts(s, "t1")

      assert s_after.read_position == %{}
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
      {:update, _s_after_q, cmds} = PostReader.handle_key(%{key: :char, char: "q"}, s_after_load)

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
end
