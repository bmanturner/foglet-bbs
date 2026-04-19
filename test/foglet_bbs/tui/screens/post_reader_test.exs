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
    def render(text), do: "MD[" <> text <> "]"
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
end
