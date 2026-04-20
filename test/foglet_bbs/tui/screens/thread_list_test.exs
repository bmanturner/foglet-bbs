defmodule Foglet.TUI.Screens.ThreadListTest do
  use ExUnit.Case, async: true

  alias Foglet.TUI.Screens.ThreadList

  defmodule FakeThreads do
    def list_threads(_board_id) do
      now = DateTime.utc_now()

      [
        %{
          id: "t1",
          title: "Old but sticky",
          sticky: true,
          last_post_at: DateTime.add(now, -10_000, :second),
          unread_count: 0,
          post_count: 20,
          created_by: %{handle: "alice"}
        },
        %{
          id: "t2",
          title: "Recent non-sticky",
          sticky: false,
          last_post_at: DateTime.add(now, -10, :second),
          unread_count: 5,
          post_count: 3,
          created_by: %{handle: "bob"}
        },
        %{
          id: "t3",
          title: "Older non-sticky",
          sticky: false,
          last_post_at: DateTime.add(now, -1_000, :second),
          unread_count: 0,
          post_count: 1,
          created_by: %{handle: "carol"}
        }
      ]
    end

    def list_threads(board_id, nil), do: list_threads(board_id)

    def list_threads(board_id, _user_id) do
      list_threads(board_id)
      |> Enum.map(&Map.put(&1, :has_unread, false))
    end
  end

  setup do
    state =
      %Foglet.TUI.App{
        current_screen: :thread_list,
        current_user: %Foglet.Accounts.User{id: "u1", handle: "alice"},
        current_board: %{id: "b1", name: "General", slug: "general"},
        session_context: %{domain: %{threads: FakeThreads}},
        terminal_size: {80, 24},
        current_thread_list: nil,
        screen_state: %{thread_list: %{selected_index: 0}}
      }
      |> Map.from_struct()

    %{state: state}
  end

  test "load_threads/2 populates current_thread_list", %{state: state} do
    {s, _} = ThreadList.load_threads(state, "b1")
    assert length(s.current_thread_list) == 3
  end

  test "sticky thread appears first — enter at index 0 selects sticky thread", %{state: state} do
    {s, _} = ThreadList.load_threads(state, "b1")
    {:update, s, cmds} = ThreadList.handle_key(%{key: :enter}, s)
    assert s.current_thread.sticky == true
    assert {:load_posts, "t1"} in cmds
  end

  test "non-sticky threads sort newest-first (t2 before t3)", %{state: state} do
    {s, _} = ThreadList.load_threads(state, "b1")
    {:update, s, _} = ThreadList.handle_key(%{key: :char, char: "j"}, s)
    {:update, s, _} = ThreadList.handle_key(%{key: :enter}, s)
    assert s.current_thread.id == "t2"
  end

  test "'C' opens :post_composer with current_thread == nil (new thread)", %{state: state} do
    {:update, s, _} = ThreadList.handle_key(%{key: :char, char: "C"}, state)
    assert s.current_screen == :post_composer
    assert s.current_thread == nil
  end

  test "'Q' returns to :board_list and dispatches {:load_boards} (LIST-02)", %{state: state} do
    {:update, s, cmds} = ThreadList.handle_key(%{key: :char, char: "Q"}, state)
    assert s.current_screen == :board_list
    assert {:load_boards} in cmds
  end

  test "render/1 does not crash with loaded threads", %{state: state} do
    {s, _} = ThreadList.load_threads(state, "b1")
    assert _ = ThreadList.render(s)
  end

  describe "render/1 — thread row metadata (LIST-03)" do
    defp flatten_text(tree), do: tree |> collect_text([]) |> Enum.reverse() |> Enum.join("")

    defp collect_text(nil, acc), do: acc
    defp collect_text(list, acc) when is_list(list), do: Enum.reduce(list, acc, &collect_text/2)

    defp collect_text(%{children: children} = node, acc) do
      acc = maybe_add_content(node, acc)
      collect_text(children, acc)
    end

    defp collect_text(%{content: content}, acc) when is_binary(content), do: [content | acc]
    defp collect_text(%{text: t}, acc) when is_binary(t), do: [t | acc]
    defp collect_text(_other, acc), do: acc

    defp maybe_add_content(%{content: content}, acc) when is_binary(content), do: [content | acc]
    defp maybe_add_content(_node, acc), do: acc

    test "thread rows include creator handle", %{state: state} do
      {s, _} = ThreadList.load_threads(state, "b1")
      flat = flatten_text(ThreadList.render(s))
      assert flat =~ "@alice"
      assert flat =~ "@bob"
      assert flat =~ "@carol"
    end

    test "thread rows include post count with pluralization", %{state: state} do
      {s, _} = ThreadList.load_threads(state, "b1")
      flat = flatten_text(ThreadList.render(s))
      assert flat =~ "20 posts"
      assert flat =~ "3 posts"
      assert flat =~ "1 post"
    end

    test "thread rows include short-form time-ago", %{state: state} do
      {s, _} = ThreadList.load_threads(state, "b1")
      flat = flatten_text(ThreadList.render(s))
      assert flat =~ "ago"
    end

    test "missing handle falls back to @unknown" do
      defmodule HandlelessFakeThreads do
        def list_threads(_board_id) do
          [
            %{
              id: "t1",
              title: "Anonymous thread",
              sticky: false,
              last_post_at: DateTime.utc_now(),
              post_count: 1,
              created_by: nil
            }
          ]
        end

        def list_threads(board_id, _user_id), do: list_threads(board_id)
      end

      state =
        %Foglet.TUI.App{
          current_screen: :thread_list,
          current_user: %Foglet.Accounts.User{id: "u1", handle: "alice"},
          current_board: %{id: "b1", name: "General"},
          session_context: %{domain: %{threads: HandlelessFakeThreads}},
          terminal_size: {80, 24},
          screen_state: %{thread_list: %{selected_index: 0}}
        }
        |> Map.from_struct()

      {s, _} = ThreadList.load_threads(state, "b1")
      flat = flatten_text(ThreadList.render(s))
      assert flat =~ "@unknown"
    end

    test "nil last_post_at renders time segment as 'new'" do
      defmodule NiltimeFakeThreads do
        def list_threads(_board_id) do
          [
            %{
              id: "t1",
              title: "Brand new thread",
              sticky: false,
              last_post_at: nil,
              post_count: 1,
              created_by: %{handle: "alice"}
            }
          ]
        end

        def list_threads(board_id, _user_id), do: list_threads(board_id)
      end

      state =
        %Foglet.TUI.App{
          current_screen: :thread_list,
          current_user: %Foglet.Accounts.User{id: "u1", handle: "alice"},
          current_board: %{id: "b1", name: "General"},
          session_context: %{domain: %{threads: NiltimeFakeThreads}},
          terminal_size: {80, 24},
          screen_state: %{thread_list: %{selected_index: 0}}
        }
        |> Map.from_struct()

      {s, _} = ThreadList.load_threads(state, "b1")
      flat = flatten_text(ThreadList.render(s))
      assert flat =~ "new"
      refute flat == ""
    end
  end

  describe "load_threads/2 — domain dispatch (LIST-03)" do
    defmodule AnnotatingFakeThreads do
      def list_threads(board_id), do: stub_data(board_id)

      def list_threads(board_id, _user_id) do
        stub_data(board_id)
        |> Enum.map(&Map.put(&1, :has_unread, true))
      end

      defp stub_data(_board_id) do
        [
          %{
            id: "t1",
            title: "Unread thread",
            sticky: false,
            last_post_at: DateTime.utc_now(),
            post_count: 2,
            created_by: %{handle: "alice"}
          }
        ]
      end
    end

    test "prefers list_threads/2 when the domain module exports it" do
      state =
        %Foglet.TUI.App{
          current_screen: :thread_list,
          current_user: %Foglet.Accounts.User{id: "u1", handle: "alice"},
          current_board: %{id: "b1", name: "General"},
          session_context: %{domain: %{threads: AnnotatingFakeThreads}},
          terminal_size: {80, 24},
          screen_state: %{thread_list: %{selected_index: 0}}
        }
        |> Map.from_struct()

      {s, _} = ThreadList.load_threads(state, "b1")
      assert [t] = s.current_thread_list
      assert t.has_unread == true
    end

    test "falls back to list_threads/1 when only the 1-arity is exported", %{state: _state} do
      defmodule OneArityOnly do
        def list_threads(_board_id) do
          [
            %{
              id: "t1",
              title: "Legacy thread",
              sticky: false,
              last_post_at: DateTime.utc_now(),
              post_count: 1,
              created_by: %{handle: "ancient"}
            }
          ]
        end
      end

      state =
        %Foglet.TUI.App{
          current_screen: :thread_list,
          current_user: %Foglet.Accounts.User{id: "u1", handle: "alice"},
          current_board: %{id: "b1", name: "General"},
          session_context: %{domain: %{threads: OneArityOnly}},
          terminal_size: {80, 24},
          screen_state: %{thread_list: %{selected_index: 0}}
        }
        |> Map.from_struct()

      {s, _} = ThreadList.load_threads(state, "b1")
      assert [t] = s.current_thread_list
      assert Map.get(t, :has_unread) == false
    end
  end
end
