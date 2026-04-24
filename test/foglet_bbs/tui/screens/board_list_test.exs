defmodule Foglet.TUI.Screens.BoardListTest do
  use ExUnit.Case, async: true

  alias Foglet.TUI.Screens.BoardList

  import Foglet.TUI.WidgetHelpers, only: [flatten_text: 1]

  defmodule FakeBoards do
    def board_directory_for(_user) do
      [
        %{
          category: %{id: "c1", name: "Town Square"},
          boards: [
            %{
              board: %{id: "b1", name: "General", slug: "general"},
              subscribed?: true,
              required_subscription?: false,
              unread_count: 3
            },
            %{
              board: %{id: "b2", name: "Tech", slug: "tech"},
              subscribed?: false,
              required_subscription?: false,
              unread_count: nil
            },
            %{
              board: %{id: "b3", name: "Announcements", slug: "announcements"},
              subscribed?: true,
              required_subscription?: true,
              unread_count: 0
            }
          ]
        }
      ]
    end
  end

  setup do
    state =
      %Foglet.TUI.App{
        current_screen: :board_list,
        current_user: %Foglet.Accounts.User{id: "u1", handle: "alice"},
        session_context: %{domain: %{boards: FakeBoards}},
        terminal_size: {80, 24},
        board_list: nil,
        screen_state: %{}
      }
      |> Map.from_struct()

    %{state: state}
  end

  test "init_screen_state/0 returns tree-ready defaults" do
    ss = BoardList.init_screen_state()

    assert ss.tree == nil
    assert ss.feedback == nil
  end

  test "load_boards/1 populates state.board_list with board directory from domain module", %{
    state: state
  } do
    {new_state, _} = BoardList.load_boards(state)
    assert [%{category: %{name: "Town Square"}, boards: boards}] = new_state.board_list
    assert Enum.map(boards, & &1.board.name) == ["General", "Tech", "Announcements"]
  end

  test "render/1 with board_list: nil uses loading branch without crashing", %{state: state} do
    s = %{state | board_list: nil}
    assert _ = BoardList.render(s)
  end

  test "render/1 with boards loaded renders one category tree with subscription labels", %{
    state: state
  } do
    {s, _} = BoardList.load_boards(state)
    text = BoardList.render(s) |> flatten_text()

    assert text =~ "Town Square"
    assert text =~ "General [subscribed] (3 unread)"
    assert text =~ "Tech [unsubscribed]"
    assert text =~ "Announcements [required]"
  end

  test "left collapses the category and right expands it again", %{state: state} do
    {s, _} = BoardList.load_boards(state)
    {:update, expanded, _} = BoardList.handle_key(%{key: :right}, s)
    assert BoardList.render(expanded) |> flatten_text() =~ "Tech [unsubscribed]"

    {:update, collapsed, _} = BoardList.handle_key(%{key: :left}, expanded)
    refute BoardList.render(collapsed) |> flatten_text() =~ "Tech [unsubscribed]"

    {:update, expanded_again, _} = BoardList.handle_key(%{key: :right}, collapsed)
    assert BoardList.render(expanded_again) |> flatten_text() =~ "Tech [unsubscribed]"
  end

  test "enter on a board leaf transitions to :thread_list and emits {:load_threads, board_id}", %{
    state: state
  } do
    {s, _} = BoardList.load_boards(state)
    {:update, s, _} = BoardList.handle_key(%{key: :right}, s)
    {:update, s, _} = BoardList.handle_key(%{key: :down}, s)

    {:update, s, cmds} = BoardList.handle_key(%{key: :enter}, s)

    assert s.current_screen == :thread_list
    assert s.current_board.name == "General"
    assert {:load_threads, "b1"} in cmds
  end

  test "enter on a category parent does not open a board", %{state: state} do
    {s, _} = BoardList.load_boards(state)
    assert BoardList.handle_key(%{key: :enter}, s) == :no_match
  end

  test "'Q' returns to :main_menu", %{state: state} do
    {:update, s, _} = BoardList.handle_key(%{key: :char, char: "Q"}, state)
    assert s.current_screen == :main_menu
  end
end
