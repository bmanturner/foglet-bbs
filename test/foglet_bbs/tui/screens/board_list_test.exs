defmodule Foglet.TUI.Screens.BoardListTest do
  use ExUnit.Case, async: true

  alias Foglet.TUI.Screens.BoardList

  import Foglet.TUI.WidgetHelpers, only: [flatten_text: 1]

  defmodule FakeBoards do
    def board_directory_for(_user) do
      # Timestamps are built at runtime so wall-clock drift between compile
      # and execution does not flip an `Nm` age on slow CI runs.
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

    assert ss.board_tree == nil
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

  test "render/1 includes Chrome V2 boards breadcrumb", %{state: state} do
    text = BoardList.render(%{state | board_list: nil}) |> flatten_text()

    assert text =~ "Foglet"
    assert text =~ "Boards"
  end

  test "render/1 with boards loaded renders board rows with glyph subscription state and age", %{
    state: state
  } do
    {s, _} = BoardList.load_boards(state)
    text = BoardList.render(s) |> flatten_text()

    # Category row.
    assert text =~ "Town Square"
    assert text =~ "▾"

    # Board names appear (not concatenated with glyphs into title - glyphs ride in cluster).
    assert text =~ "General"
    assert text =~ "Tech"
    assert text =~ "Announcements"

    # Subscription cluster glyphs.
    assert text =~ "✓"
    assert text =~ "+"
    assert text =~ "⚿"

    # Read-state cluster glyph (◆ for unread; whitespace for read - refute ◇).
    assert text =~ "◆"
    refute text =~ "◇"

    # Trailing metadata: "3 unread" + age for General; "all read" + age for Announcements.
    assert text =~ "3 unread"
    assert text =~ "all read"

    # Age magnitude (regex; do not use exact magnitudes).
    assert text =~ ~r/\d+(s|m|h|d|w|mo|y)\b/

    # Em-dash for the nil-last_post_at board (Tech).
    assert text =~ "—"

    # Bracketed-text labels MUST be gone.
    refute text =~ "[required]"
    refute text =~ "[subscribed]"
    refute text =~ "[unsubscribed]"

    # Detail-strip words are allowed; bracketed row labels are not.
    assert text =~ "Town Square • 3 boards • 3 unread total"
  end

  test "render/1 shows focused board details strip at compact width", %{state: state} do
    {s, _} = BoardList.load_boards(%{state | terminal_size: {64, 22}})
    {:update, s, _} = BoardList.handle_key(%{key: :right}, s)
    {:update, s, _} = BoardList.handle_key(%{key: :down}, s)

    text = BoardList.render(s) |> flatten_text()

    assert text =~ "General • subscribed • 3 unread"
    assert text =~ ~r/General • subscribed • 3 unread • \d+m ago/
    refute text =~ "Inspector • board"
  end

  test "render/1 shows focused category details strip at compact width", %{state: state} do
    {s, _} = BoardList.load_boards(%{state | terminal_size: {64, 22}})

    text = BoardList.render(s) |> flatten_text()

    assert text =~ "Town Square • 3 boards • 3 unread total"
    refute text =~ "Inspector • category"
  end

  test "render/1 bounds overlarge compact directories while navigation reaches hidden boards", %{
    state: state
  } do
    s = %{state | terminal_size: {64, 22}, board_list: overlarge_directory()}

    initial_text = BoardList.render(s) |> flatten_text()
    initial_rows = String.split(initial_text, "\n", trim: true)
    visible_board_rows =
      Regex.scan(~r/Overlarge Board \d+/, initial_text)
      |> length()

    assert length(initial_rows) <= 22
    assert initial_text =~ "Overlarge"
    assert initial_text =~ "Overlarge Board 06"
    assert visible_board_rows >= 8
    refute initial_text =~ "Overlarge Board 28"

    s =
      Enum.reduce(1..25, s, fn _index, acc ->
        {:update, next, _cmds} = BoardList.handle_key(%{key: :down}, acc)
        next
      end)

    moved_text = BoardList.render(s) |> flatten_text()

    assert length(String.split(moved_text, "\n", trim: true)) <= 22
    assert moved_text =~ "Overlarge Board 25"
  end

  test "render/1 shows wide inspector only when terminal width permits", %{state: state} do
    {compact, _} = BoardList.load_boards(%{state | terminal_size: {80, 24}})
    {wide, _} = BoardList.load_boards(%{state | terminal_size: {132, 50}})

    compact_text = BoardList.render(compact) |> flatten_text()
    wide_text = BoardList.render(wide) |> flatten_text()

    refute compact_text =~ "Inspector • category"
    assert wide_text =~ "Inspector • category • Town Square • 3 boards"
  end

  test "render/1 board rows render TimeAgo short-form age (regex magnitude) for populated last_post_at",
       %{
         state: state
       } do
    {s, _} = BoardList.load_boards(state)
    text = BoardList.render(s) |> flatten_text()

    # General has ten_min_ago -> some `Nm` magnitude.
    assert text =~ ~r/\d+m\b/, "expected an `Nm` magnitude in #{inspect(text)}"
    # Announcements has two_h_ago -> some `Nh` magnitude.
    assert text =~ ~r/\d+h/, "expected an `Nh` magnitude in #{inspect(text)}"
  end

  test "render/1 board row with nil last_post_at renders em-dash, not '?'", %{state: state} do
    {s, _} = BoardList.load_boards(state)
    text = BoardList.render(s) |> flatten_text()

    assert text =~ "—"
    refute text =~ "?"
  end

  test "left collapses the category and right expands it again", %{state: state} do
    {s, _} = BoardList.load_boards(state)
    {:update, expanded, _} = BoardList.handle_key(%{key: :right}, s)
    assert BoardList.render(expanded) |> flatten_text() =~ "Tech"

    {:update, collapsed, _} = BoardList.handle_key(%{key: :left}, expanded)
    refute BoardList.render(collapsed) |> flatten_text() =~ "Tech"

    {:update, expanded_again, _} = BoardList.handle_key(%{key: :right}, collapsed)
    assert BoardList.render(expanded_again) |> flatten_text() =~ "Tech"
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

  test "'s' on an unsubscribed board emits subscribe command", %{state: state} do
    {s, _} = BoardList.load_boards(state)
    {:update, s, _} = BoardList.handle_key(%{key: :right}, s)
    {:update, s, _} = BoardList.handle_key(%{key: :down}, s)
    {:update, s, _} = BoardList.handle_key(%{key: :down}, s)

    {:update, _s, cmds} = BoardList.handle_key(%{key: :char, char: "s"}, s)

    assert {:subscribe_to_board, "b2"} in cmds
  end

  test "'u' on a subscribed non-required board emits unsubscribe command", %{state: state} do
    {s, _} = BoardList.load_boards(state)
    {:update, s, _} = BoardList.handle_key(%{key: :right}, s)
    {:update, s, _} = BoardList.handle_key(%{key: :down}, s)

    {:update, _s, cmds} = BoardList.handle_key(%{key: :char, char: "u"}, s)

    assert {:unsubscribe_from_board, "b1"} in cmds
  end

  test "'u' on a required board renders feedback and emits no command", %{state: state} do
    {s, _} = BoardList.load_boards(state)
    {:update, s, _} = BoardList.handle_key(%{key: :right}, s)
    {:update, s, _} = BoardList.handle_key(%{key: :down}, s)
    {:update, s, _} = BoardList.handle_key(%{key: :down}, s)
    {:update, s, _} = BoardList.handle_key(%{key: :down}, s)

    {:update, s, cmds} = BoardList.handle_key(%{key: :char, char: "u"}, s)

    assert cmds == []
    flat = BoardList.render(s) |> flatten_text()
    # Feedback flash preserved verbatim (top-of-tree).
    assert flat =~ "required subscription"
    # Row content uses glyph form (no [required] bracket).
    assert flat =~ "⚿"
    assert flat =~ "Announcements"
    refute flat =~ "[required]"
  end

  test "'Q' returns to :main_menu", %{state: state} do
    {:update, s, _} = BoardList.handle_key(%{key: :char, char: "Q"}, state)
    assert s.current_screen == :main_menu
  end
end
