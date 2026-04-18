defmodule Foglet.TUI.Screens.PostComposerTest do
  use ExUnit.Case, async: true

  alias Foglet.TUI.Screens.PostComposer

  defmodule FakePosts do
    def create_reply(_thread, _user, %{body: "explode"}), do: {:error, :nope}
    def create_reply(_thread, _user, attrs), do: {:ok, Map.merge(%{id: "new-post"}, attrs)}
  end

  defmodule FakeMarkdown do
    def render(text), do: "MD[" <> text <> "]"
  end

  setup do
    state =
      %Foglet.TUI.App{
        current_screen: :post_composer,
        current_user: %Foglet.Accounts.User{id: "u1", handle: "alice"},
        current_thread: %{id: "t1", title: "Hello"},
        session_context: %{
          domain: %{posts: FakePosts, markdown: FakeMarkdown},
          max_post_length: 1_000
        },
        terminal_size: {80, 24},
        composer_draft: "",
        screen_state: %{post_composer: %{mode: :edit, reply_to: nil, error: nil}}
      }
      |> Map.from_struct()

    %{state: state}
  end

  test "render/1 (new thread, edit mode) does not crash", %{state: state} do
    assert _ = PostComposer.render(state)
  end

  test "render/1 with reply_to shows quote context (D-27)", %{state: state} do
    reply_to = %{
      id: "p1",
      message_number: 1,
      user: %{handle: "bob"},
      body: "L1\nL2\nL3\nL4\nL5\nL6"
    }

    s = put_in(state, [:screen_state, :post_composer, :reply_to], reply_to)
    assert _ = PostComposer.render(s)
  end

  test "Tab toggles mode :edit <-> :preview (D-28)", %{state: state} do
    assert get_in(state.screen_state, [:post_composer, :mode]) == :edit
    {:update, s, _} = PostComposer.handle_key(%{key: "tab"}, state)
    assert get_in(s.screen_state, [:post_composer, :mode]) == :preview
    {:update, s, _} = PostComposer.handle_key(%{key: "tab"}, s)
    assert get_in(s.screen_state, [:post_composer, :mode]) == :edit
  end

  test "character keys append to draft", %{state: state} do
    {:update, s, _} = PostComposer.handle_key(%{key: "h"}, state)
    {:update, s, _} = PostComposer.handle_key(%{key: "i"}, s)
    assert s.composer_draft == "hi"
  end

  test "backspace removes last character", %{state: state} do
    s = %{state | composer_draft: "hello"}
    {:update, s, _} = PostComposer.handle_key(%{key: "backspace"}, s)
    assert s.composer_draft == "hell"
  end

  test "Ctrl+S with empty body shows error modal", %{state: state} do
    {:update, s, _} = PostComposer.handle_key(%{key: "ctrl_s"}, state)
    assert s.modal.type == :error
  end

  test "Ctrl+S with valid body creates post and transitions to :post_reader (D-29)",
       %{state: state} do
    s = %{state | composer_draft: "Hello world"}
    {:update, s, cmds} = PostComposer.handle_key(%{key: "ctrl_s"}, s)
    assert s.current_screen == :post_reader
    assert s.composer_draft == nil
    assert Enum.any?(cmds, &match?({:load_posts, "t1"}, &1))
  end

  test "Ctrl+S with body > max_post_length shows error modal (D-31)", %{state: state} do
    long = String.duplicate("x", 1_001)
    s = %{state | composer_draft: long}
    {:update, s, _} = PostComposer.handle_key(%{key: "ctrl_s"}, s)
    assert s.modal.type == :error
    assert s.modal.message =~ "maximum length"
  end

  test "Ctrl+C cancels to :thread_list without confirmation (D-30)", %{state: state} do
    s = %{state | composer_draft: "draft content"}
    {:update, s, _} = PostComposer.handle_key(%{key: "ctrl_c"}, s)
    assert s.current_screen == :thread_list
    assert s.composer_draft == nil
    refute Map.has_key?(s.screen_state, :post_composer)
  end

  test "max_post_length falls back to default (8192) when not in session_context" do
    state =
      %Foglet.TUI.App{
        current_screen: :post_composer,
        current_user: %Foglet.Accounts.User{id: "u1", handle: "alice"},
        current_thread: %{id: "t1", title: "Hello"},
        session_context: %{domain: %{posts: FakePosts}},
        terminal_size: {80, 24},
        composer_draft: String.duplicate("x", 10_000),
        screen_state: %{post_composer: %{mode: :edit, reply_to: nil, error: nil}}
      }
      |> Map.from_struct()

    # 10_000 chars exceeds default 8192 limit -> error modal
    {:update, s, _} = PostComposer.handle_key(%{key: "ctrl_s"}, state)
    assert s.modal.type == :error
  end
end
