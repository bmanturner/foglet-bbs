defmodule Foglet.TUI.Screens.BoardListTest do
  use ExUnit.Case, async: true

  alias Foglet.TUI.Context
  alias Foglet.TUI.Effect
  alias Foglet.TUI.Screens.BoardList
  alias Foglet.TUI.Widgets.List.BoardTree

  import Foglet.TUI.WidgetHelpers, only: [flatten_text: 1]

  defmodule FakeBoards do
    def board_directory_for(_user), do: Foglet.TUI.Screens.BoardListTest.directory()
    def subscribe_user_to_board(_user, "b2"), do: {:ok, :subscribed}
    def subscribe_user_to_board(_user, "archived"), do: {:error, :board_archived}
    def unsubscribe_user_from_board(_user, "b1"), do: {:ok, :unsubscribed}
    def unsubscribe_user_from_board(_user, "b3"), do: {:error, :required_subscription}
  end

  def directory do
    ten_min_ago = DateTime.add(DateTime.utc_now(), -600, :second)
    two_h_ago = DateTime.add(DateTime.utc_now(), -7200, :second)

    [
      %{
        category: %{id: "c1", name: "Town Square"},
        boards: [
          %{
            board: %{id: "b1", name: "General", slug: "general"},
            subscribed?: true,
            required_subscription?: false,
            unread_count: 3,
            last_post_at: ten_min_ago
          },
          %{
            board: %{id: "b2", name: "Tech", slug: "tech"},
            subscribed?: false,
            required_subscription?: false,
            unread_count: nil,
            last_post_at: nil
          },
          %{
            board: %{id: "b3", name: "Announcements", slug: "announcements"},
            subscribed?: true,
            required_subscription?: true,
            unread_count: 0,
            last_post_at: two_h_ago
          }
        ]
      }
    ]
  end

  defp overlarge_directory(count \\ 28) do
    boards =
      for index <- 1..count do
        %{
          board: %{
            id: "big-#{index}",
            name: "Overlarge Board #{String.pad_leading(Integer.to_string(index), 2, "0")}",
            slug: "overlarge-#{index}"
          },
          subscribed?: true,
          required_subscription?: false,
          unread_count: rem(index, 5),
          last_post_at: DateTime.add(DateTime.utc_now(), -600, :second)
        }
      end

    [%{category: %{id: "big", name: "Overlarge"}, boards: boards}]
  end

  defp context(attrs \\ []) do
    Context.new(
      Keyword.merge(
        [
          current_user: %Foglet.Accounts.User{id: "u1", handle: "alice"},
          terminal_size: {80, 24},
          route: :board_list,
          domain: %{boards: FakeBoards}
        ],
        attrs
      )
    )
  end

  defp load_state(ctx \\ context()) do
    state = BoardList.init(ctx)
    {state, [effect]} = BoardList.update(:load, state, ctx)
    directory = run_task(effect)
    {state, []} = BoardList.update({:task_result, :load_boards, {:ok, directory}}, state, ctx)
    state
  end

  defp run_task(%Effect{type: :task, payload: %{fun: fun}}), do: fun.()

  defp assert_task(%Effect{type: :task, payload: payload}, op) do
    assert payload.op == op
    assert payload.screen_key == :board_list
    assert is_function(payload.fun, 0)
  end

  defp assert_navigate(%Effect{type: :navigate, payload: payload}, screen, params) do
    assert payload.screen == screen
    assert payload.params == params
  end

  defp move_to_board(state, ctx, board_index) do
    Enum.reduce(1..board_index, state, fn _index, acc ->
      {next, []} = BoardList.update({:key, %{key: :down}}, acc, ctx)
      next
    end)
  end

  test "BoardList.State.new/0 returns directory-owner defaults" do
    assert BoardList.State.new() == %BoardList.State{
             directory: nil,
             board_tree: nil,
             status: :loading,
             feedback: nil,
             last_op: nil,
             last_error: nil
           }
  end

  test "init/1 returns loading local state" do
    assert %BoardList.State{status: :loading, directory: nil, board_tree: nil} =
             BoardList.init(context())
  end

  test "initial load emits BoardList-targeted load task" do
    ctx = context()
    state = BoardList.init(ctx)

    {%BoardList.State{} = state, [effect]} = BoardList.update(:load, state, ctx)

    assert state.status == :loading
    assert state.last_op == :load_boards
    assert_task(effect, :load_boards)
    assert [%{category: %{name: "Town Square"}, boards: boards}] = run_task(effect)
    assert Enum.map(boards, & &1.board.name) == ["General", "Tech", "Announcements"]
  end

  test "load success stores directory and initializes tree" do
    ctx = context()
    state = BoardList.init(ctx)
    directory = directory()

    {state, []} = BoardList.update({:task_result, :load_boards, {:ok, directory}}, state, ctx)

    assert state.directory == directory
    assert state.status == :loaded
    assert %BoardTree{} = state.board_tree
    assert state.last_op == nil
    assert state.last_error == nil
  end

  test "empty load success sets empty status" do
    {state, []} =
      BoardList.update(
        {:task_result, :load_boards, {:ok, []}},
        BoardList.init(context()),
        context()
      )

    assert state.directory == []
    assert state.status == :empty
    assert %BoardTree{} = state.board_tree
  end

  test "load failure stores error status without clearing previous directory" do
    ctx = context()
    state = load_state(ctx)
    reason = :database_timeout

    {state, []} = BoardList.update({:task_result, :load_boards, {:error, reason}}, state, ctx)

    assert state.status == {:error, reason}
    assert state.last_error == reason
    assert [%{boards: boards}] = state.directory
    assert Enum.map(boards, & &1.board.id) == ["b1", "b2", "b3"]
    assert %BoardTree{} = state.board_tree
  end

  test "arrow and vim keys update local BoardTree cursor only" do
    ctx = context()
    state = load_state(ctx)

    {state, []} = BoardList.update({:key, %{key: :char, char: "j"}}, state, ctx)

    assert %{board: %{id: "b1"}} = BoardTree.focused_board_entry(state.board_tree)
    assert [%{boards: boards}] = state.directory
    assert Enum.map(boards, & &1.board.id) == ["b1", "b2", "b3"]
  end

  test "enter on a category parent toggles expanded state without effects" do
    ctx = context(terminal_size: {64, 22})
    state = load_state(ctx)

    initial_text = BoardList.render(state, ctx) |> flatten_text()
    assert initial_text =~ "▾"
    assert initial_text =~ "Tech"

    {collapsed, []} = BoardList.update({:key, %{key: :enter}}, state, ctx)
    collapsed_text = BoardList.render(collapsed, ctx) |> flatten_text()

    assert collapsed_text =~ "▸"
    refute collapsed_text =~ "Tech"

    {expanded, []} = BoardList.update({:key, %{key: :enter}}, collapsed, ctx)
    expanded_text = BoardList.render(expanded, ctx) |> flatten_text()

    assert expanded_text =~ "▾"
    assert expanded_text =~ "Tech"
  end

  test "enter on a board leaf navigates to ThreadList with route params" do
    ctx = context()
    state = load_state(ctx) |> move_to_board(ctx, 1)

    {state, [effect]} = BoardList.update({:key, %{key: :enter}}, state, ctx)

    assert %{board: %{id: "b1"}} = BoardTree.focused_board_entry(state.board_tree)

    assert effect ==
             Effect.navigate(:thread_list, %{
               board_id: "b1",
               board: %{id: "b1", name: "General", slug: "general"}
             })
  end

  test "'s' on an unsubscribed board emits subscribe task" do
    ctx = context()
    state = load_state(ctx) |> move_to_board(ctx, 2)

    {state, [effect]} = BoardList.update({:key, %{key: :char, char: "s"}}, state, ctx)

    assert state.feedback == nil
    assert state.last_op == :subscribe_to_board
    assert_task(effect, :subscribe_to_board)
    assert run_task(effect) == {:ok, :subscribed}
  end

  test "'u' on a subscribed non-required board emits unsubscribe task" do
    ctx = context()
    state = load_state(ctx) |> move_to_board(ctx, 1)

    {state, [effect]} = BoardList.update({:key, %{key: :char, char: "u"}}, state, ctx)

    assert state.feedback == nil
    assert state.last_op == :unsubscribe_from_board
    assert_task(effect, :unsubscribe_from_board)
    assert run_task(effect) == {:ok, :unsubscribed}
  end

  test "'u' on a required board renders feedback and emits no task" do
    ctx = context()
    state = load_state(ctx) |> move_to_board(ctx, 3)

    {state, []} = BoardList.update({:key, %{key: :char, char: "u"}}, state, ctx)

    assert state.feedback == "This board is a required subscription."
    flat = BoardList.render(state, ctx) |> flatten_text()
    assert flat =~ "required subscription"
    assert flat =~ "⚿"
    refute flat =~ "[required]"
  end

  test "subscribe success sets feedback and emits reload task" do
    ctx = context()
    state = load_state(ctx)

    {state, [effect]} =
      BoardList.update({:task_result, :subscribe_to_board, {:ok, :subscribed}}, state, ctx)

    assert state.feedback == "Subscribed."
    assert state.last_op == nil
    assert_task(effect, :load_boards)
  end

  test "unsubscribe success sets feedback and emits reload task" do
    ctx = context()
    state = load_state(ctx)

    {state, [effect]} =
      BoardList.update({:task_result, :unsubscribe_from_board, {:ok, :unsubscribed}}, state, ctx)

    assert state.feedback == "Unsubscribed."
    assert state.last_op == nil
    assert_task(effect, :load_boards)
  end

  test "subscription task errors set specific feedback" do
    ctx = context()
    state = load_state(ctx)

    {state, []} =
      BoardList.update(
        {:task_result, :unsubscribe_from_board, {:error, :required_subscription}},
        state,
        ctx
      )

    assert state.feedback == "This board is a required subscription."

    {state, []} =
      BoardList.update({:task_result, :subscribe_to_board, {:error, :board_archived}}, state, ctx)

    assert state.feedback == "That board is archived."

    {state, []} =
      BoardList.update({:task_result, :subscribe_to_board, {:error, :unavailable}}, state, ctx)

    assert state.feedback == "Subscription change failed: :unavailable"
  end

  test "board activity emits reload task" do
    ctx = context()
    state = load_state(ctx)

    {state, [effect]} = BoardList.update({:board_activity, "b1", :post_created}, state, ctx)

    assert state.last_op == :load_boards
    assert_task(effect, :load_boards)
  end

  test "'Q' returns to main menu through navigation effect" do
    {state, [effect]} =
      BoardList.update({:key, %{key: :char, char: "Q"}}, load_state(), context())

    assert %BoardList.State{} = state
    assert_navigate(effect, :main_menu, %{})
  end

  test "render/2 with loading state uses loading branch without crashing" do
    assert _rendered = BoardList.render(BoardList.init(context()), context())
  end

  test "render/2 with boards loaded renders rows with glyph state and age metadata" do
    state = load_state()
    text = BoardList.render(state, context()) |> flatten_text()

    assert text =~ "Town Square"
    assert text =~ "▾"
    assert text =~ "General"
    assert text =~ "Tech"
    assert text =~ "Announcements"
    assert text =~ "✓"
    assert text =~ "+"
    assert text =~ "⚿"
    assert text =~ "◆"
    refute text =~ "◇"
    assert text =~ "3 unread"
    assert text =~ "all read"
    assert text =~ ~r/\d+(s|m|h|d|w|mo|y)\b/
    assert text =~ "—"
    refute text =~ "[required]"
    refute text =~ "[subscribed]"
    refute text =~ "[unsubscribed]"
    assert text =~ "Town Square • 3 boards • 3 unread total"
  end

  test "render/2 shows focused board details strip at compact width" do
    ctx = context(terminal_size: {64, 22})
    state = load_state(ctx) |> move_to_board(ctx, 1)

    text = BoardList.render(state, ctx) |> flatten_text()

    assert text =~ "General • subscribed • 3 unread"
    assert text =~ ~r/General • subscribed • 3 unread • \d+m ago/
    refute text =~ "Inspector • board"
  end

  test "render/2 bounds overlarge compact directories while navigation reaches hidden boards" do
    ctx = context(terminal_size: {64, 22})

    state =
      BoardList.State.new(
        directory: overlarge_directory(),
        board_tree: BoardTree.init(directory: overlarge_directory(), id: "board-directory"),
        status: :loaded
      )

    initial_text = BoardList.render(state, ctx) |> flatten_text()
    initial_rows = String.split(initial_text, "\n", trim: true)

    visible_board_rows =
      Regex.scan(~r/Overlarge Board \d+/, initial_text)
      |> length()

    assert length(initial_rows) <= 22
    assert initial_text =~ "Overlarge"
    assert initial_text =~ "Overlarge Board 06"
    assert visible_board_rows >= 8
    refute initial_text =~ "Overlarge Board 28"

    moved =
      Enum.reduce(1..25, state, fn _index, acc ->
        {next, []} = BoardList.update({:key, %{key: :down}}, acc, ctx)
        next
      end)

    moved_text = BoardList.render(moved, ctx) |> flatten_text()

    assert length(String.split(moved_text, "\n", trim: true)) <= 22
    assert moved_text =~ "Overlarge Board 25"
  end

  describe "subscriptions/2 export (Phase 39 R7, D-22)" do
    @tag :phase39_target
    test "module exports subscriptions/2" do
      assert function_exported?(Foglet.TUI.Screens.BoardList, :subscriptions, 2)
    end
  end
end
