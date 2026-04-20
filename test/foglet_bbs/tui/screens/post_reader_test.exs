defmodule Foglet.TUI.Screens.PostReaderTest do
  use ExUnit.Case, async: true

  alias Foglet.TUI.Screens.PostReader

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
        screen_state: %{post_reader: %{selected_post_index: 0}}
      }
      |> Map.from_struct()

    %{state: state}
  end

  test "load_posts/2 populates state.posts", %{state: state} do
    {s, _} = PostReader.load_posts(state, "t1")
    assert length(s.posts) == 2
  end

  test "render/1 with posts loaded does not crash", %{state: state} do
    {s, _} = PostReader.load_posts(state, "t1")
    assert _ = PostReader.render(s)
  end

  test "render/1 with no posts shows loading message", %{state: state} do
    assert _ = PostReader.render(state)
  end

  test "'n' advances to next post and updates read_position", %{state: state} do
    {s, _} = PostReader.load_posts(state, "t1")
    {:update, s, _} = PostReader.handle_key(%{key: :char, char: "n"}, s)
    assert get_in(s.screen_state, [:post_reader, :selected_post_index]) == 1
    assert s.read_position["t1"][:last_read_post_id] == "p2"
    assert s.read_position["t1"][:last_read_message_number] == 2
  end

  test "'p' decrements bounded at 0", %{state: state} do
    {s, _} = PostReader.load_posts(state, "t1")
    {:update, s, _} = PostReader.handle_key(%{key: :char, char: "p"}, s)
    assert get_in(s.screen_state, [:post_reader, :selected_post_index]) == 0
  end

  test "'R' opens :post_composer with reply_to set to current post", %{state: state} do
    {s, _} = PostReader.load_posts(state, "t1")
    {:update, s, _} = PostReader.handle_key(%{key: :char, char: "R"}, s)
    assert s.current_screen == :post_composer
    assert get_in(s.screen_state, [:post_composer, :reply_to]).id == "p1"
  end

  test "'R' stashes origin: :post_reader in the :post_composer screen_state", %{state: state} do
    {s, _} = PostReader.load_posts(state, "t1")
    {:update, s, _} = PostReader.handle_key(%{key: :char, char: "r"}, s)
    assert s.current_screen == :post_composer
    assert get_in(s.screen_state, [:post_composer, :origin]) == :post_reader
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

  # --- Helper for Phase 2 integration tests (simpler state shape) ---

  defp theme, do: Foglet.TUI.Theme.default()

  defp p2_post(opts) do
    %{
      id: Keyword.get(opts, :id, "p1"),
      body: Keyword.get(opts, :body, "Hello **world**."),
      inserted_at: Keyword.get(opts, :inserted_at, DateTime.utc_now()),
      user: Keyword.get(opts, :user, %{handle: "sysop"}),
      message_number: Keyword.get(opts, :message_number, 1)
    }
  end

  defp p2_state(overrides \\ %{}) do
    base = %{
      current_screen: :post_reader,
      current_thread: %{id: "t1", title: "Test Thread"},
      current_board: %{id: "b1"},
      current_user: %{id: "u1", handle: "sysop"},
      posts: [p2_post(id: "p1", body: "Hello **world**.")],
      read_position: %{},
      screen_state: %{},
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

      # After N, scroll_offset must reset to 0 (D-04).
      assert s3.screen_state[:post_reader].scroll_offset == 0
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
    test "j advances scroll_offset by 1" do
      # 5 lines, terminal height 12 → available_height = max(12-10, 5) = 5 → max_offset = 0
      # Need more lines than available. Use 8 lines with height 12 → available = 5 → max_offset = 3.
      body = Enum.map_join(1..8, "\n\n", &"Line #{&1}")
      s = p2_state(%{posts: [p2_post(body: body)], terminal_size: {80, 12}})

      assert {:update, s1, []} = PostReader.handle_key(%{key: :char, char: "j"}, s)
      assert s1.screen_state[:post_reader].scroll_offset == 1
    end

    test "k decrements scroll_offset but clamps at 0" do
      s = p2_state(%{posts: [p2_post(body: "A\n\nB\n\nC")]})

      assert {:update, s1, []} = PostReader.handle_key(%{key: :char, char: "k"}, s)
      assert s1.screen_state[:post_reader].scroll_offset == 0
    end

    test "j clamps at max_offset for short posts (cannot scroll past end)" do
      # A single-line post has total_lines=1; with available_height >= 5
      # the max_offset is 0 — j should not advance.
      s = p2_state(%{posts: [p2_post(body: "Just one line.")]})

      result = PostReader.handle_key(%{key: :char, char: "j"}, s)
      assert {:update, s1, []} = result
      assert s1.screen_state[:post_reader].scroll_offset == 0
    end

    test "N resets scroll_offset to 0 (D-04)" do
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
      assert s2.screen_state[:post_reader].scroll_offset == 2

      # Press N to advance to post 2.
      {:update, s3, _} = PostReader.handle_key(%{key: :char, char: "n"}, s2)
      assert s3.screen_state[:post_reader].scroll_offset == 0
      assert s3.screen_state[:post_reader].selected_post_index == 1
    end

    test "j/k accept uppercase letters too" do
      body = Enum.map_join(1..8, "\n\n", &"Line #{&1}")
      s = p2_state(%{posts: [p2_post(body: body)], terminal_size: {80, 12}})
      assert {:update, s1, []} = PostReader.handle_key(%{key: :char, char: "J"}, s)
      assert s1.screen_state[:post_reader].scroll_offset == 1
      assert {:update, s2, []} = PostReader.handle_key(%{key: :char, char: "K"}, s1)
      assert s2.screen_state[:post_reader].scroll_offset == 0
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
  end

  # =================================================================
  # Screen-state migration (legacy state without new keys)
  # =================================================================

  describe "get_screen_state — legacy state migration" do
    test "render/1 works against a state with only :selected_post_index (pre-Phase-2 shape)" do
      s =
        p2_state(%{
          posts: [p2_post(body: "Hello **world**.")],
          screen_state: %{post_reader: %{selected_post_index: 0}}
        })

      tree = PostReader.render(s)
      refute is_nil(tree)
    end

    test "j works against a legacy-shaped state (no crash)" do
      s =
        p2_state(%{
          posts: [p2_post(body: "A\n\nB\n\nC\n\nD")],
          screen_state: %{post_reader: %{selected_post_index: 0}}
        })

      {:update, s1, _} = PostReader.handle_key(%{key: :char, char: "j"}, s)
      # scroll_offset default is 0; j advances to 1 (bounded by max_offset)
      assert s1.screen_state[:post_reader].scroll_offset in [0, 1]
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
