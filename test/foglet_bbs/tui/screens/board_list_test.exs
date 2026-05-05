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

  defmodule FakeGuestVisibilityBoards do
    def board_directory_for(nil),
      do: Foglet.TUI.Screens.BoardListTest.guest_visibility_directory(:guest)

    def board_directory_for(_user),
      do: Foglet.TUI.Screens.BoardListTest.guest_visibility_directory(:member)
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

  def guest_visibility_directory(kind) when kind in [:guest, :member] do
    public_board = %{
      board: %{id: "public-board", name: "Public Square", slug: "public", readable_by: :public},
      subscribed?: false,
      required_subscription?: false,
      unread_count: nil,
      last_post_at: nil
    }

    members_only_board = %{
      board: %{
        id: "members-board",
        name: "Members Hidden Board",
        slug: "members-hidden",
        readable_by: :members
      },
      subscribed?: false,
      required_subscription?: false,
      unread_count: nil,
      last_post_at: nil
    }

    boards = if kind == :guest, do: [public_board], else: [public_board, members_only_board]
    [%{category: %{id: "c-public", name: "Public Category"}, boards: boards}]
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
          domain: %{boards: FakeBoards},
          session_context: %{guest: false, user: %Foglet.Accounts.User{id: "u1"}}
        ],
        attrs
      )
    )
  end

  defp guest_context(attrs \\ []) do
    context(
      Keyword.merge(
        [
          current_user: nil,
          session_context: %{guest: true, user: nil, user_id: nil},
          route: :board_list
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

  # FOG-105: BoardList now parks the initial cursor on the first board
  # (`b1`) instead of the category, so reaching the N-th board only
  # requires N-1 downs. Callers still pass the 1-based board index.
  defp move_to_board(state, _ctx, 1), do: state

  defp move_to_board(state, ctx, board_index) when board_index > 1 do
    Enum.reduce(2..board_index, state, fn _index, acc ->
      {next, []} = BoardList.update({:key, %{key: :down}}, acc, ctx)
      next
    end)
  end

  # FOG-105 helper: walk the cursor up onto the parent category from the
  # initial-board cursor position. Used by tests that need to exercise
  # category-row rendering or category detail-strip behavior.
  defp focus_category(state, ctx) do
    {next, []} = BoardList.update({:key, %{key: :up}}, state, ctx)
    next
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

    # FOG-105: initial cursor parks on b1, so `j` advances to b2.
    {state, []} = BoardList.update({:key, %{key: :char, char: "j"}}, state, ctx)

    assert %{board: %{id: "b2"}} = BoardTree.focused_board_entry(state.board_tree)
    assert [%{boards: boards}] = state.directory
    assert Enum.map(boards, & &1.board.id) == ["b1", "b2", "b3"]
  end

  test "enter on a category parent toggles expanded state without effects" do
    ctx = context(terminal_size: {64, 22})
    # FOG-105: initial cursor parks on the first board, where Enter
    # opens the board. To exercise the category expand/collapse path we
    # walk the cursor up to the parent category first.
    state = load_state(ctx) |> focus_category(ctx)

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
               subscribed?: true,
               board: %{
                 id: "b1",
                 name: "General",
                 slug: "general",
                 archived: false,
                 readable_by: :public,
                 postable_by: :members,
                 chat_enabled: false,
                 chat_storage_mode: nil,
                 chat_message_ttl_seconds: nil
               }
             })
  end

  test "guest board list can open boards but cannot subscribe or unsubscribe" do
    ctx = guest_context()
    state = load_state(ctx) |> move_to_board(ctx, 2)

    {state, [effect]} = BoardList.update({:key, %{key: :enter}}, state, ctx)

    assert_navigate(effect, :thread_list, %{
      board_id: "b2",
      subscribed?: false,
      board: %{
        id: "b2",
        name: "Tech",
        slug: "tech",
        archived: false,
        readable_by: :public,
        postable_by: :members,
        chat_enabled: false,
        chat_storage_mode: nil,
        chat_message_ttl_seconds: nil
      }
    })

    {state, []} = BoardList.update({:key, %{key: :char, char: "s"}}, state, ctx)
    assert state.feedback == "Guests can browse boards, but only registered users can subscribe."
    assert state.last_op == nil

    state = load_state(ctx) |> move_to_board(ctx, 1)
    {state, []} = BoardList.update({:key, %{key: :char, char: "u"}}, state, ctx)
    assert state.feedback == "Guests can browse boards, but only registered users can subscribe."
    assert state.last_op == nil
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

    assert state.feedback == "Required subscriptions can't be cancelled."
    flat = BoardList.render(state, ctx) |> flatten_text()
    assert flat =~ "Required subscriptions"
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

    assert state.feedback == "Required subscriptions can't be cancelled."

    {state, []} =
      BoardList.update({:task_result, :subscribe_to_board, {:error, :board_archived}}, state, ctx)

    assert state.feedback == "This board is archived; you can't subscribe."

    {state, []} =
      BoardList.update({:task_result, :subscribe_to_board, {:error, :unavailable}}, state, ctx)

    assert state.feedback == "Couldn't change your subscription. Try again in a moment."
    refute state.feedback =~ ":"
  end

  test "load failure renders friendly retry copy without raw reason" do
    ctx = context()
    state = BoardList.init(ctx)

    {state, []} =
      BoardList.update({:task_result, :load_boards, {:error, :database_timeout}}, state, ctx)

    text = BoardList.render(state, ctx) |> flatten_text()

    assert text =~ "Couldn't load boards. Press R to retry."
    refute text =~ ":database_timeout"
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
    # FOG-105: initial cursor parks on the first board, so the detail
    # strip reflects that board's identity rather than the parent
    # category summary.
    assert text =~ "General • subscribed • 3 unread"
  end

  test "render/2 pluralizes the category board count by length" do
    one_board_directory = [
      %{
        category: %{id: "c1", name: "Solo"},
        boards: [
          %{
            board: %{id: "b1", name: "Only", slug: "only"},
            subscribed?: true,
            required_subscription?: false,
            unread_count: 2,
            last_post_at: DateTime.add(DateTime.utc_now(), -600, :second)
          }
        ]
      }
    ]

    empty_category_directory = [
      %{category: %{id: "c1", name: "Empty"}, boards: []}
    ]

    ctx = context()

    one_state =
      BoardList.update(
        {:task_result, :load_boards, {:ok, one_board_directory}},
        BoardList.init(ctx),
        ctx
      )
      |> elem(0)

    empty_state =
      BoardList.update(
        {:task_result, :load_boards, {:ok, empty_category_directory}},
        BoardList.init(ctx),
        ctx
      )
      |> elem(0)

    # FOG-105: initial cursor parks on the first board. Move it up onto
    # the category so the detail strip exercises the category-summary
    # pluralization branch under test. The empty-category state has no
    # boards, so its cursor is already on the category.
    one_state = focus_category(one_state, ctx)
    many_state = focus_category(load_state(ctx), ctx)

    one_text = BoardList.render(one_state, ctx) |> flatten_text()
    empty_text = BoardList.render(empty_state, ctx) |> flatten_text()
    many_text = BoardList.render(many_state, ctx) |> flatten_text()

    assert one_text =~ "Solo • 1 board • 2 unread total"
    refute one_text =~ "1 boards"
    assert empty_text =~ "Empty • 0 boards • 0 unread total"
    assert many_text =~ "Town Square • 3 boards • 3 unread total"
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

  test "rendered guest board directory shows public boards without members-only rows from context-owned load" do
    ctx = guest_context(domain: %{boards: FakeGuestVisibilityBoards})
    state = BoardList.init(ctx)

    {loading_state, [effect]} = BoardList.update(:load, state, ctx)
    assert loading_state.last_op == :load_boards
    assert [%{boards: [public_entry]}] = run_task(effect)
    assert public_entry.board.name == "Public Square"

    {loaded_state, []} =
      BoardList.update(
        {:task_result, :load_boards, {:ok, guest_visibility_directory(:guest)}},
        state,
        ctx
      )

    rendered_text = BoardList.render(loaded_state, ctx) |> flatten_text()

    assert rendered_text =~ "Public Square"
    refute rendered_text =~ "Members Hidden Board"
    refute rendered_text =~ "members-hidden"
  end

  describe "subscriptions/2 export (Phase 39 R7, D-22)" do
    test "module exports subscriptions/2" do
      Code.ensure_loaded!(Foglet.TUI.Screens.BoardList)
      assert function_exported?(Foglet.TUI.Screens.BoardList, :subscriptions, 2)
    end

    test "returns boards aggregate topic unconditionally" do
      ctx = %Foglet.TUI.Context{route_params: %{}}

      assert Foglet.TUI.Screens.BoardList.subscriptions(nil, ctx) == ["boards"]
    end
  end
end
