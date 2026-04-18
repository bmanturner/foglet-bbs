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
          post_count: 20
        },
        %{
          id: "t2",
          title: "Recent non-sticky",
          sticky: false,
          last_post_at: DateTime.add(now, -10, :second),
          unread_count: 5,
          post_count: 3
        },
        %{
          id: "t3",
          title: "Older non-sticky",
          sticky: false,
          last_post_at: DateTime.add(now, -1_000, :second),
          unread_count: 0,
          post_count: 1
        }
      ]
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
    {:update, s, cmds} = ThreadList.handle_key(%{key: "enter"}, s)
    assert s.current_thread.sticky == true
    assert {:load_posts, "t1"} in cmds
  end

  test "non-sticky threads sort newest-first (t2 before t3)", %{state: state} do
    {s, _} = ThreadList.load_threads(state, "b1")
    # Index 0 = sticky t1; index 1 = t2 (recent); index 2 = t3 (older)
    {:update, s, _} = ThreadList.handle_key(%{key: "j"}, s)
    {:update, s, _} = ThreadList.handle_key(%{key: "enter"}, s)
    assert s.current_thread.id == "t2"
  end

  test "'C' opens :post_composer with current_thread == nil (new thread)", %{state: state} do
    {:update, s, _} = ThreadList.handle_key(%{key: "C"}, state)
    assert s.current_screen == :post_composer
    assert s.current_thread == nil
  end

  test "'Q' returns to :board_list", %{state: state} do
    {:update, s, _} = ThreadList.handle_key(%{key: "Q"}, state)
    assert s.current_screen == :board_list
  end

  test "render/1 does not crash with loaded threads", %{state: state} do
    {s, _} = ThreadList.load_threads(state, "b1")
    assert _ = ThreadList.render(s)
  end
end
