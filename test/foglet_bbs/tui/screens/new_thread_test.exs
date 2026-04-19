defmodule Foglet.TUI.Screens.NewThreadTest do
  use ExUnit.Case, async: true

  alias Foglet.TUI.App
  alias Foglet.TUI.Screens.NewThread
  alias Raxol.UI.Components.Input.MultiLineInput

  # ---------------------------------------------------------------------------
  # Fake domain adapters
  # ---------------------------------------------------------------------------

  defmodule FakeBoards do
    def list_subscribed_boards(_user) do
      [
        %{id: "b1", name: "General", unread_count: 0},
        %{id: "b2", name: "Announcements", unread_count: 0}
      ]
    end
  end

  defmodule FakeBoardsEmpty do
    def list_subscribed_boards(_user), do: []
  end

  defmodule FakeThreadsOk do
    def create_thread(_board_id, _user_id, attrs) do
      thread = %{
        id: "t-new",
        title: Map.get(attrs, :title, ""),
        sticky: false,
        last_post_at: DateTime.utc_now()
      }

      {:ok, %{thread: thread, post: %{id: "p-new"}}}
    end
  end

  defmodule FakeThreadsError do
    def create_thread(_board_id, _user_id, _attrs) do
      {:error, "board is locked"}
    end
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp fresh_input(value \\ "") do
    {:ok, st} =
      MultiLineInput.init(%{
        value: value,
        placeholder: "Write your opening post…",
        width: 76,
        height: 10,
        wrap: :none,
        focused: false
      })

    st
  end

  defp base_state(overrides \\ %{}) do
    user = %{id: "u1", handle: "alice"}

    ss =
      NewThread.init_screen_state(
        boards: [
          %{id: "b1", name: "General", unread_count: 0},
          %{id: "b2", name: "Announcements", unread_count: 0}
        ],
        width: 80
      )

    state =
      %App{
        current_screen: :new_thread,
        current_user: user,
        session_context: %{domain: %{boards: FakeBoards, threads: FakeThreadsOk}},
        terminal_size: {80, 24},
        screen_state: %{new_thread: ss}
      }
      |> Map.from_struct()

    Map.merge(state, overrides)
  end

  defp compose_state(board \\ %{id: "b1", name: "General"}) do
    body_input = fresh_input()

    ss = %{
      step: :compose,
      boards: [board],
      selected_board_index: 0,
      board: board,
      title_input: "",
      body_input_state: body_input,
      focused: :title,
      error: nil
    }

    Map.put(base_state(), :screen_state, %{new_thread: ss})
  end

  defp get_ss(state), do: get_in(state, [:screen_state, :new_thread])

  # ---------------------------------------------------------------------------
  # init_screen_state/1
  # ---------------------------------------------------------------------------

  test "init_screen_state/1 defaults to board step" do
    ss = NewThread.init_screen_state()
    assert ss.step == :board
    assert ss.boards == nil
    assert ss.selected_board_index == 0
    assert ss.board == nil
    assert ss.title_input == ""
    assert is_struct(ss.body_input_state, MultiLineInput)
    assert ss.focused == :title
    assert ss.error == nil
  end

  test "init_screen_state/1 with boards pre-loaded stores them" do
    boards = [%{id: "b1", name: "General"}]
    ss = NewThread.init_screen_state(boards: boards)
    assert ss.boards == boards
  end

  # ---------------------------------------------------------------------------
  # Render — board step
  # ---------------------------------------------------------------------------

  test "render/1 board step does not crash" do
    state = base_state()
    assert _ = NewThread.render(state)
  end

  test "render/1 board step with nil boards does not crash" do
    ss = NewThread.init_screen_state(boards: nil)
    state = Map.put(base_state(), :screen_state, %{new_thread: ss})
    assert _ = NewThread.render(state)
  end

  # ---------------------------------------------------------------------------
  # Render — compose step
  # ---------------------------------------------------------------------------

  test "render/1 compose step does not crash" do
    state = compose_state()
    assert _ = NewThread.render(state)
  end

  # ---------------------------------------------------------------------------
  # Board step navigation
  # ---------------------------------------------------------------------------

  test "Esc on board step navigates to :main_menu" do
    state = base_state()
    {:update, new_state, _cmds} = NewThread.handle_key(%{key: :escape}, state)
    assert new_state.current_screen == :main_menu
  end

  test "j moves board selection down" do
    state = base_state()
    assert get_ss(state).selected_board_index == 0

    {:update, new_state, _} = NewThread.handle_key(%{key: :char, char: "j"}, state)
    assert get_ss(new_state).selected_board_index == 1
  end

  test "down arrow moves board selection down" do
    state = base_state()
    {:update, new_state, _} = NewThread.handle_key(%{key: :down}, state)
    assert get_ss(new_state).selected_board_index == 1
  end

  test "k moves board selection up (clamps at 0)" do
    state = base_state()
    # Already at 0, pressing k should stay at 0
    result = NewThread.handle_key(%{key: :char, char: "k"}, state)
    assert match?({:update, _, _}, result) or result == :no_match

    case result do
      {:update, new_state, _} ->
        assert get_ss(new_state).selected_board_index == 0

      :no_match ->
        :ok
    end
  end

  test "j clamps at last board index" do
    state = base_state()
    # Move to last board (index 1 of 2)
    {:update, s1, _} = NewThread.handle_key(%{key: :char, char: "j"}, state)
    assert get_ss(s1).selected_board_index == 1
    # Pressing j again should stay at 1
    {:update, s2, _} = NewThread.handle_key(%{key: :char, char: "j"}, s1)
    assert get_ss(s2).selected_board_index == 1
  end

  test "Enter on board step advances to compose step with selected board" do
    state = base_state()
    # Move to second board first
    {:update, s1, _} = NewThread.handle_key(%{key: :char, char: "j"}, state)
    {:update, s2, _} = NewThread.handle_key(%{key: :enter}, s1)

    ss = get_ss(s2)
    assert ss.step == :compose
    assert ss.board.id == "b2"
    assert ss.board.name == "Announcements"
  end

  test "Enter on board step with no boards returns :no_match" do
    ss = NewThread.init_screen_state(boards: [])
    state = Map.put(base_state(), :screen_state, %{new_thread: ss})
    result = NewThread.handle_key(%{key: :enter}, state)
    assert result == :no_match
  end

  # ---------------------------------------------------------------------------
  # Compose step — navigation
  # ---------------------------------------------------------------------------

  test "Tab switches focus from :title to :body" do
    state = compose_state()
    assert get_ss(state).focused == :title

    {:update, new_state, _} = NewThread.handle_key(%{key: :tab}, state)
    assert get_ss(new_state).focused == :body
  end

  test "Tab switches focus from :body to :title" do
    state = compose_state()
    {:update, s1, _} = NewThread.handle_key(%{key: :tab}, state)
    assert get_ss(s1).focused == :body

    {:update, s2, _} = NewThread.handle_key(%{key: :tab}, s1)
    assert get_ss(s2).focused == :title
  end

  test "Ctrl+C cancels from compose step to :main_menu" do
    state = compose_state()
    {:update, new_state, _} = NewThread.handle_key(%{key: :char, char: "c", ctrl: true}, state)
    assert new_state.current_screen == :main_menu
  end

  test "Esc cancels from compose step to :main_menu" do
    state = compose_state()
    {:update, new_state, _} = NewThread.handle_key(%{key: :escape}, state)
    assert new_state.current_screen == :main_menu
  end

  # ---------------------------------------------------------------------------
  # Compose step — title input
  # ---------------------------------------------------------------------------

  test "typing characters updates title_input when focused on :title" do
    state = compose_state()
    assert get_ss(state).focused == :title

    {:update, s1, _} = NewThread.handle_key(%{key: :char, char: "H"}, state)
    {:update, s2, _} = NewThread.handle_key(%{key: :char, char: "i"}, s1)

    assert get_ss(s2).title_input == "Hi"
  end

  test "spacebar appends a space to title" do
    state = compose_state()
    {:update, s1, _} = NewThread.handle_key(%{key: :char, char: "H"}, state)
    {:update, s2, _} = NewThread.handle_key(%{key: :char, char: " "}, s1)
    {:update, s3, _} = NewThread.handle_key(%{key: :char, char: "i"}, s2)

    assert get_ss(s3).title_input == "H i"
  end

  test "backspace removes the last character from title" do
    state = compose_state()

    s =
      Enum.reduce(~w[H e l l o], state, fn ch, acc ->
        {:update, next, _} = NewThread.handle_key(%{key: :char, char: ch}, acc)
        next
      end)

    {:update, s, _} = NewThread.handle_key(%{key: :backspace}, s)
    assert get_ss(s).title_input == "Hell"
  end

  test "backspace on empty title stays empty" do
    state = compose_state()
    {:update, new_state, _} = NewThread.handle_key(%{key: :backspace}, state)
    assert get_ss(new_state).title_input == ""
  end

  test "typing does NOT update title when focused on :body" do
    state = compose_state()
    # Switch to body
    {:update, s1, _} = NewThread.handle_key(%{key: :tab}, state)
    assert get_ss(s1).focused == :body

    # Typing 'H' should go to body input, not title
    result = NewThread.handle_key(%{key: :char, char: "H"}, s1)

    case result do
      {:update, new_state, _} ->
        assert get_ss(new_state).title_input == ""

      :no_match ->
        :ok
    end
  end

  # ---------------------------------------------------------------------------
  # Compose step — body input (forwarded to MultiLineInput)
  # ---------------------------------------------------------------------------

  test "typing appends to body when focused on :body" do
    state = compose_state()
    {:update, s1, _} = NewThread.handle_key(%{key: :tab}, state)
    assert get_ss(s1).focused == :body

    {:update, s2, _} = NewThread.handle_key(%{key: :char, char: "h"}, s1)
    {:update, s3, _} = NewThread.handle_key(%{key: :char, char: "i"}, s2)

    body_value = get_ss(s3).body_input_state.value
    assert body_value == "hi"
  end

  # ---------------------------------------------------------------------------
  # Submit — success path
  # ---------------------------------------------------------------------------

  test "Ctrl+S with valid title and body navigates to :post_reader" do
    state = compose_state()

    # Type title using :char events; space via " " char
    s =
      Enum.reduce(~w[M y   T h r e a d], state, fn ch, acc ->
        key =
          if ch == " " do
            %{key: :char, char: " "}
          else
            %{key: :char, char: ch}
          end

        {:update, next, _} = NewThread.handle_key(key, acc)
        next
      end)

    # Switch to body and type content
    {:update, s, _} = NewThread.handle_key(%{key: :tab}, s)

    s =
      Enum.reduce(~w[H e l l o], s, fn ch, acc ->
        {:update, next, _} = NewThread.handle_key(%{key: :char, char: ch}, acc)
        next
      end)

    {:update, final, cmds} = NewThread.handle_key(%{key: :char, char: "s", ctrl: true}, s)

    assert final.current_screen == :post_reader
    assert final.current_thread != nil
    assert Enum.any?(cmds, &match?({:load_posts, _}, &1))
  end

  test "Ctrl+S with {:ok, %{thread: thread}} sets current_board from wizard" do
    state = compose_state(%{id: "b1", name: "General"})

    # Set a title directly in ss
    ss = get_ss(state)
    s = Map.put(state, :screen_state, %{new_thread: %{ss | title_input: "Test Thread"}})

    # Type body
    {:update, s, _} = NewThread.handle_key(%{key: :tab}, s)

    s =
      Enum.reduce(~w[H i], s, fn ch, acc ->
        {:update, next, _} = NewThread.handle_key(%{key: :char, char: ch}, acc)
        next
      end)

    {:update, final, _cmds} = NewThread.handle_key(%{key: :char, char: "s", ctrl: true}, s)
    assert final.current_board.id == "b1"
  end

  # ---------------------------------------------------------------------------
  # Submit — error paths
  # ---------------------------------------------------------------------------

  test "Ctrl+S with empty title shows error, stays on compose" do
    state = compose_state()
    # Switch to body, type content, but leave title empty
    {:update, s, _} = NewThread.handle_key(%{key: :tab}, state)

    s =
      Enum.reduce(~w[H i], s, fn ch, acc ->
        {:update, next, _} = NewThread.handle_key(%{key: :char, char: ch}, acc)
        next
      end)

    {:update, final, _} = NewThread.handle_key(%{key: :char, char: "s", ctrl: true}, s)
    assert final.current_screen == :new_thread
    ss = get_ss(final)
    assert ss.error =~ "Title"
  end

  test "Ctrl+S with empty body shows error, stays on compose" do
    state = compose_state()
    # Set title but leave body empty
    ss = get_ss(state)
    s = Map.put(state, :screen_state, %{new_thread: %{ss | title_input: "Has Title"}})

    {:update, final, _} = NewThread.handle_key(%{key: :char, char: "s", ctrl: true}, s)
    assert final.current_screen == :new_thread
    assert get_ss(final).error =~ "body"
  end

  test "Ctrl+S on error from domain stays on compose with error set" do
    state =
      base_state(%{
        session_context: %{domain: %{boards: FakeBoards, threads: FakeThreadsError}}
      })

    board = %{id: "b1", name: "General"}

    ss = %{
      step: :compose,
      boards: [board],
      selected_board_index: 0,
      board: board,
      title_input: "My Thread",
      body_input_state: fresh_input("Hello"),
      focused: :title,
      error: nil
    }

    s = Map.put(state, :screen_state, %{new_thread: ss})
    {:update, final, _} = NewThread.handle_key(%{key: :char, char: "s", ctrl: true}, s)

    assert final.current_screen == :new_thread
    assert get_ss(final).error != nil
  end

  test "Ctrl+S without threads module exported shows coming-soon modal" do
    state =
      base_state(%{
        session_context: %{domain: %{boards: FakeBoards, threads: FakeBoardsEmpty}}
      })

    board = %{id: "b1", name: "General"}

    ss = %{
      step: :compose,
      boards: [board],
      selected_board_index: 0,
      board: board,
      title_input: "My Thread",
      body_input_state: fresh_input("Hello"),
      focused: :title,
      error: nil
    }

    s = Map.put(state, :screen_state, %{new_thread: ss})
    {:update, final, _} = NewThread.handle_key(%{key: :char, char: "s", ctrl: true}, s)

    assert final.modal != nil
    assert final.modal.type == :info
  end

  # ---------------------------------------------------------------------------
  # load_boards/1
  # ---------------------------------------------------------------------------

  test "load_boards/1 populates boards into screen_state" do
    state = base_state(%{session_context: %{domain: %{boards: FakeBoards}}})
    # Clear boards first
    ss = get_ss(state)
    s = Map.put(state, :screen_state, %{new_thread: %{ss | boards: nil}})

    {new_state, _cmds} = NewThread.load_boards(s)
    loaded = get_ss(new_state).boards
    assert length(loaded) == 2
    assert Enum.any?(loaded, &(&1.name == "General"))
    assert Enum.any?(loaded, &(&1.name == "Announcements"))
  end

  test "load_boards/1 with no domain module sets empty list" do
    state = base_state(%{session_context: %{domain: %{boards: FakeBoardsEmpty}}})
    {new_state, _} = NewThread.load_boards(state)
    assert get_ss(new_state).boards == []
  end
end
