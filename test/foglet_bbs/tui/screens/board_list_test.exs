defmodule Foglet.TUI.Screens.BoardListTest do
  use ExUnit.Case, async: true

  alias Foglet.TUI.Screens.BoardList

  defmodule FakeBoards do
    def list_subscribed_boards(_user) do
      [
        %{id: "b1", name: "General", slug: "general", unread_count: 3},
        %{id: "b2", name: "Tech", slug: "tech", unread_count: 0}
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

  test "init_screen_state/0 returns selected_index default" do
    assert BoardList.init_screen_state() == %{selected_index: 0}
  end

  test "load_boards/1 populates state.board_list from domain module", %{state: state} do
    {new_state, _} = BoardList.load_boards(state)
    assert length(new_state.board_list) == 2
    assert Enum.at(new_state.board_list, 0).name == "General"
  end

  test "render/1 with board_list: nil uses loading branch without crashing", %{state: state} do
    s = %{state | board_list: nil}
    assert _ = BoardList.render(s)
  end

  test "render/1 with boards loaded does not crash", %{state: state} do
    {s, _} = BoardList.load_boards(state)
    assert _ = BoardList.render(s)
  end

  test "'j'/'down' increments selection bounded by length-1", %{state: state} do
    {s, _} = BoardList.load_boards(state)
    {:update, s, _} = BoardList.handle_key(%{key: :char, char: "j"}, s)
    assert get_in(s.screen_state, [:board_list, :selected_index]) == 1
    # Bounded at max index
    {:update, s, _} = BoardList.handle_key(%{key: :char, char: "j"}, s)
    assert get_in(s.screen_state, [:board_list, :selected_index]) == 1
  end

  test "'k'/'up' decrements selection bounded at 0", %{state: state} do
    {s, _} = BoardList.load_boards(state)
    {:update, s, _} = BoardList.handle_key(%{key: :char, char: "k"}, s)
    assert get_in(s.screen_state, [:board_list, :selected_index]) == 0
  end

  test "'enter' transitions to :thread_list and emits {:load_threads, board_id}", %{state: state} do
    {s, _} = BoardList.load_boards(state)
    {:update, s, cmds} = BoardList.handle_key(%{key: :enter}, s)
    assert s.current_screen == :thread_list
    assert s.current_board.name == "General"
    assert {:load_threads, "b1"} in cmds
  end

  test "'Q' returns to :main_menu", %{state: state} do
    {:update, s, _} = BoardList.handle_key(%{key: :char, char: "Q"}, state)
    assert s.current_screen == :main_menu
  end
end
