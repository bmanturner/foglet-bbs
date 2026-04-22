# ---------------------------------------------------------------------------
# Fake domain adapters (defined outside test module per project convention)
# ---------------------------------------------------------------------------

defmodule Foglet.TUI.Screens.NewThreadTest.FakeBoards do
  def list_subscribed_boards(_user) do
    [
      %{id: "b1", name: "General", unread_count: 0},
      %{id: "b2", name: "Announcements", unread_count: 0}
    ]
  end
end

defmodule Foglet.TUI.Screens.NewThreadTest.FakeThreadsOk do
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

defmodule Foglet.TUI.Screens.NewThreadTest.FakeThreadsMissing do
  # Does NOT export create_thread/3 — simulates unauthenticated user path.
end

defmodule Foglet.TUI.Screens.NewThreadTest.FakeThreadsError do
  def create_thread(_board_id, _user_id, _attrs) do
    {:error, "board is locked"}
  end
end

defmodule Foglet.TUI.Screens.NewThreadTest do
  use ExUnit.Case, async: true

  alias Foglet.TUI.App
  alias Foglet.TUI.Screens.NewThread
  alias Foglet.TUI.Screens.NewThread.State
  alias Foglet.TUI.Widgets.Input.TextInput
  alias Raxol.UI.Components.Input.MultiLineInput

  alias Foglet.TUI.Screens.NewThreadTest.FakeBoards
  alias Foglet.TUI.Screens.NewThreadTest.FakeThreadsError
  alias Foglet.TUI.Screens.NewThreadTest.FakeThreadsMissing
  alias Foglet.TUI.Screens.NewThreadTest.FakeThreadsOk

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

    ss =
      NewThread.init_screen_state(
        step: :compose,
        boards: [board],
        board: board,
        title_input_state: TextInput.init(value: ""),
        body_input_state: body_input
      )

    Map.put(base_state(), :screen_state, %{new_thread: ss})
  end

  defp get_ss(state), do: get_in(state, [:screen_state, :new_thread])
  defp title_value(state), do: get_ss(state).title_input_state.raxol_state.value

  defp put_title(state, title, max_length \\ 60) do
    title_input =
      Enum.reduce(String.graphemes(title), TextInput.init(max_length: max_length), fn ch, acc ->
        {next, _} = TextInput.handle_event(%{key: :char, char: ch}, acc)
        next
      end)

    put_in(state.screen_state.new_thread.title_input_state, title_input)
  end

  # ---------------------------------------------------------------------------
  # init_screen_state/1
  # ---------------------------------------------------------------------------

  test "init_screen_state/1 defaults to board step" do
    ss = NewThread.init_screen_state()
    assert %State{} = ss
    assert ss.step == :board
    assert ss.boards == nil
    assert ss.selected_board_index == 0
    assert ss.board == nil
    assert is_struct(ss.title_input_state, TextInput)
    assert ss.title_input_state.raxol_state.value == ""
    assert is_struct(ss.body_input_state, MultiLineInput)
    assert ss.focused == :title
    assert ss.error == nil
    assert ss.origin == :main_menu
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

  test "Tab on :body toggles mode to :preview (Gap 4 — Test 8)" do
    state = compose_state()
    # Advance focus to :body first
    {:update, s1, _} = NewThread.handle_key(%{key: :tab}, state)
    assert get_ss(s1).focused == :body
    assert get_ss(s1).mode == :edit

    # Tab on body toggles mode, does NOT switch focus back to :title
    {:update, s2, _} = NewThread.handle_key(%{key: :tab}, s1)
    assert get_ss(s2).mode == :preview
    assert get_ss(s2).focused == :body
  end

  test "Tab on :body in :preview mode toggles back to :edit (Gap 4 — Test 9)" do
    state = compose_state()
    {:update, s1, _} = NewThread.handle_key(%{key: :tab}, state)
    assert get_ss(s1).focused == :body

    # First Tab: :edit -> :preview
    {:update, s2, _} = NewThread.handle_key(%{key: :tab}, s1)
    assert get_ss(s2).mode == :preview

    # Second Tab: :preview -> :edit
    {:update, s3, _} = NewThread.handle_key(%{key: :tab}, s2)
    assert get_ss(s3).mode == :edit
    assert get_ss(s3).focused == :body
  end

  test "Tab on :title advances focus to :body and does NOT toggle mode (Gap 4 — Test 10)" do
    state = compose_state()
    assert get_ss(state).focused == :title
    assert get_ss(state).mode == :edit

    {:update, new_state, _} = NewThread.handle_key(%{key: :tab}, state)
    assert get_ss(new_state).focused == :body
    assert get_ss(new_state).mode == :edit
  end

  test "Ctrl+C cancels from compose step to origin screen (default :main_menu)" do
    state = compose_state()
    {:update, new_state, _} = NewThread.handle_key(%{key: :char, char: "c", ctrl: true}, state)
    assert new_state.current_screen == :main_menu
  end

  test "Ctrl+C with origin: :thread_list routes back to :thread_list" do
    state = compose_state()
    s = put_in(state.screen_state.new_thread.origin, :thread_list)

    {:update, new_state, _} = NewThread.handle_key(%{key: :char, char: "c", ctrl: true}, s)
    assert new_state.current_screen == :thread_list
  end

  test "Esc cancels from compose step to origin screen (default :main_menu)" do
    state = compose_state()
    {:update, new_state, _} = NewThread.handle_key(%{key: :escape}, state)
    assert new_state.current_screen == :main_menu
  end

  test "Esc with origin: :thread_list routes back to :thread_list" do
    state = compose_state()
    s = put_in(state.screen_state.new_thread.origin, :thread_list)

    {:update, new_state, _} = NewThread.handle_key(%{key: :escape}, s)
    assert new_state.current_screen == :thread_list
  end

  # ---------------------------------------------------------------------------
  # Compose step — title input
  # ---------------------------------------------------------------------------

  test "typing characters updates title_input when focused on :title" do
    state = compose_state()
    assert get_ss(state).focused == :title

    {:update, s1, _} = NewThread.handle_key(%{key: :char, char: "H"}, state)
    {:update, s2, _} = NewThread.handle_key(%{key: :char, char: "i"}, s1)

    assert title_value(s2) == "Hi"
  end

  test "spacebar appends a space to title" do
    state = compose_state()
    {:update, s1, _} = NewThread.handle_key(%{key: :char, char: "H"}, state)
    {:update, s2, _} = NewThread.handle_key(%{key: :char, char: " "}, s1)
    {:update, s3, _} = NewThread.handle_key(%{key: :char, char: "i"}, s2)

    assert title_value(s3) == "H i"
  end

  test "backspace removes the last character from title" do
    state = compose_state()

    s =
      Enum.reduce(~w[H e l l o], state, fn ch, acc ->
        {:update, next, _} = NewThread.handle_key(%{key: :char, char: ch}, acc)
        next
      end)

    {:update, s, _} = NewThread.handle_key(%{key: :backspace}, s)
    assert title_value(s) == "Hell"
  end

  test "backspace on empty title stays empty" do
    state = compose_state()
    {:update, new_state, _} = NewThread.handle_key(%{key: :backspace}, state)
    assert title_value(new_state) == ""
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
        assert title_value(new_state) == ""

      :no_match ->
        :ok
    end
  end

  # ---------------------------------------------------------------------------
  # Title length cap (D-13, D-14)
  # ---------------------------------------------------------------------------

  describe "title length cap (D-13, D-14)" do
    test "accepts characters below the cap" do
      s = compose_state() |> put_title("abc")

      {:update, new_state, []} = NewThread.handle_key(%{key: :char, char: "d"}, s)
      assert title_value(new_state) == "abcd"
    end

    test "rejects characters that would exceed the cap" do
      # 60-char title; next char must be rejected.
      long_title = String.duplicate("x", 60)
      s = compose_state() |> put_title(long_title)

      assert NewThread.handle_key(%{key: :char, char: "y"}, s) == :no_match
    end

    test "accepts the final allowed character at cap - 1" do
      title = String.duplicate("x", 59)
      s = compose_state() |> put_title(title)

      {:update, new_state, []} = NewThread.handle_key(%{key: :char, char: "y"}, s)
      assert String.length(title_value(new_state)) == 60
    end

    test "backspace still works at the cap" do
      s = compose_state() |> put_title(String.duplicate("x", 60))

      {:update, new_state, []} = NewThread.handle_key(%{key: :backspace}, s)
      assert String.length(title_value(new_state)) == 59
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

  test "Ctrl+S with valid title and body navigates to :thread_list and dispatches {:load_threads}" do
    state = compose_state()

    # Type title using :char events
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

    assert final.current_screen == :thread_list
    assert final.current_board.id == "b1"
    assert Enum.any?(cmds, &match?({:load_threads, "b1"}, &1))
  end

  test "Ctrl+S with {:ok, %{thread: thread}} preserves current_board from wizard" do
    state = compose_state(%{id: "b1", name: "General"})

    s =
      put_in(
        state.screen_state.new_thread.title_input_state,
        TextInput.init(value: "Test Thread", max_length: 60)
      )

    # Type body
    {:update, s, _} = NewThread.handle_key(%{key: :tab}, s)

    s =
      Enum.reduce(~w[H i], s, fn ch, acc ->
        {:update, next, _} = NewThread.handle_key(%{key: :char, char: ch}, acc)
        next
      end)

    {:update, final, _cmds} = NewThread.handle_key(%{key: :char, char: "s", ctrl: true}, s)
    assert final.current_board.id == "b1"
    assert final.current_screen == :thread_list
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
    s =
      put_in(
        state.screen_state.new_thread.title_input_state,
        TextInput.init(value: "Has Title", max_length: 60)
      )

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

    ss =
      NewThread.init_screen_state(
        step: :compose,
        boards: [board],
        board: board,
        title_input_state: TextInput.init(value: "My Thread", max_length: 60),
        body_input_state: fresh_input("Hello")
      )

    s = Map.put(state, :screen_state, %{new_thread: ss})
    {:update, final, _} = NewThread.handle_key(%{key: :char, char: "s", ctrl: true}, s)

    assert final.current_screen == :new_thread
    assert get_ss(final).error != nil
  end

  test "Ctrl+S without current_user shows error modal" do
    state =
      base_state(%{
        current_user: nil,
        session_context: %{domain: %{boards: FakeBoards, threads: FakeThreadsMissing}}
      })

    board = %{id: "b1", name: "General"}

    ss =
      NewThread.init_screen_state(
        step: :compose,
        boards: [board],
        board: board,
        title_input_state: TextInput.init(value: "My Thread", max_length: 60),
        body_input_state: fresh_input("Hello")
      )

    s = Map.put(state, :screen_state, %{new_thread: ss})
    {:update, final, _} = NewThread.handle_key(%{key: :char, char: "s", ctrl: true}, s)

    assert final.modal != nil
    assert final.modal.type == :error
    assert final.modal.message =~ "logged in"
  end

  # ---------------------------------------------------------------------------
  # Preview mode — D-11 delegation to Post.MarkdownBody
  # ---------------------------------------------------------------------------

  test "Tab on body toggles to :preview mode" do
    state = compose_state()
    # Tab to body
    {:update, s, _} = NewThread.handle_key(%{key: :tab}, state)
    assert get_ss(s).focused == :body
    assert get_ss(s).mode == :edit

    # Tab on body toggles to preview
    {:update, s, _} = NewThread.handle_key(%{key: :tab}, s)
    assert get_ss(s).mode == :preview
    assert get_ss(s).focused == :body
  end

  test "render/1 in :compose step + :preview mode does not crash on markdown input" do
    {:ok, body_input} =
      MultiLineInput.init(%{
        value: "# Thread Title\n\nOpening post with **emphasis**.",
        placeholder: "Write your opening post…",
        width: 76,
        height: 10,
        wrap: :none,
        focused: false
      })

    board = %{id: "b1", name: "General"}

    ss =
      NewThread.init_screen_state(
        step: :compose,
        boards: [board],
        board: board,
        title_input_state: TextInput.init(value: "Test Thread", max_length: 60),
        body_input_state: body_input,
        focused: :body,
        mode: :preview
      )

    state =
      Map.put(
        base_state(%{session_context: %{domain: %{boards: FakeBoards, threads: FakeThreadsOk}}}),
        :screen_state,
        %{new_thread: ss}
      )

    # render/1 is pure — calling it should not raise.
    assert NewThread.render(state) != nil
  end
end
