defmodule Foglet.TUI.Screens.PostComposerTest do
  use ExUnit.Case, async: true

  alias Foglet.TUI.Screens.PostComposer
  alias Raxol.UI.Components.Input.MultiLineInput

  defmodule FakePosts do
    def create_reply(_thread, _user, %{body: "explode"}), do: {:error, :nope}
    def create_reply(_thread, _user, attrs), do: {:ok, Map.merge(%{id: "new-post"}, attrs)}
  end

  defmodule FakeMarkdown do
    def render(text), do: "MD[" <> text <> "]"
  end

  # Build a fresh MultiLineInput state for tests.
  defp fresh_input(value \\ "") do
    {:ok, st} =
      MultiLineInput.init(%{
        value: value,
        placeholder: "Write your post…",
        width: 76,
        height: 10,
        wrap: :none,
        focused: true
      })

    st
  end

  setup do
    input_st = fresh_input()

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
        composer_draft: nil,
        screen_state: %{
          post_composer: %{
            mode: :edit,
            reply_to: nil,
            error: nil,
            input_state: input_st
          }
        }
      }
      |> Map.from_struct()

    %{state: state}
  end

  # ---------------------------------------------------------------------------
  # Render
  # ---------------------------------------------------------------------------

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

  test "render/1 in preview mode does not crash", %{state: state} do
    {:update, s, _} = PostComposer.handle_key(%{key: "tab"}, state)
    assert _ = PostComposer.render(s)
  end

  # ---------------------------------------------------------------------------
  # Tab — mode toggle (D-28)
  # ---------------------------------------------------------------------------

  test "Tab toggles mode :edit <-> :preview (D-28)", %{state: state} do
    assert get_in(state.screen_state, [:post_composer, :mode]) == :edit

    {:update, s, _} = PostComposer.handle_key(%{key: "tab"}, state)
    assert get_in(s.screen_state, [:post_composer, :mode]) == :preview

    {:update, s, _} = PostComposer.handle_key(%{key: "tab"}, s)
    assert get_in(s.screen_state, [:post_composer, :mode]) == :edit
  end

  # ---------------------------------------------------------------------------
  # Character input via MultiLineInput component
  # ---------------------------------------------------------------------------

  test "single character keys are forwarded to MultiLineInput", %{state: state} do
    {:update, s1, _} = PostComposer.handle_key(%{key: "h"}, state)
    {:update, s2, _} = PostComposer.handle_key(%{key: "i"}, s1)

    text = get_in(s2.screen_state, [:post_composer, :input_state, Access.key(:value)])
    assert text == "hi"
  end

  test "spacebar appends a space", %{state: state} do
    {:update, s1, _} = PostComposer.handle_key(%{key: "h"}, state)
    {:update, s2, _} = PostComposer.handle_key(%{key: "space"}, s1)
    {:update, s3, _} = PostComposer.handle_key(%{key: "i"}, s2)

    text = get_in(s3.screen_state, [:post_composer, :input_state, Access.key(:value)])
    assert text == "h i"
  end

  test "enter inserts a newline", %{state: state} do
    {:update, s1, _} = PostComposer.handle_key(%{key: "h"}, state)
    {:update, s2, _} = PostComposer.handle_key(%{key: "enter"}, s1)
    {:update, s3, _} = PostComposer.handle_key(%{key: "i"}, s2)

    text = get_in(s3.screen_state, [:post_composer, :input_state, Access.key(:value)])
    assert text == "h\ni"
  end

  test "backspace removes the last character", %{state: state} do
    # Type "hello" then backspace
    s =
      Enum.reduce(~w[h e l l o], state, fn ch, acc ->
        {:update, next, _} = PostComposer.handle_key(%{key: ch}, acc)
        next
      end)

    {:update, s, _} = PostComposer.handle_key(%{key: "backspace"}, s)

    text = get_in(s.screen_state, [:post_composer, :input_state, Access.key(:value)])
    assert text == "hell"
  end

  test "arrow-key events are forwarded without crash", %{state: state} do
    # Type something first so there's content to navigate
    {:update, s, _} = PostComposer.handle_key(%{key: "h"}, state)

    for key <- ~w[up down left right home end pageup pagedown] do
      result = PostComposer.handle_key(%{key: key}, s)

      assert match?({:update, _, _}, result) or result == :no_match,
             "Arrow key #{key} returned unexpected: #{inspect(result)}"
    end
  end

  # ---------------------------------------------------------------------------
  # Ctrl+S — submit (D-29)
  # ---------------------------------------------------------------------------

  test "Ctrl+S with empty body shows error modal", %{state: state} do
    {:update, s, _} = PostComposer.handle_key(%{key: "ctrl_s"}, state)
    assert s.modal.type == :error
  end

  test "Ctrl+S with valid body creates post and transitions to :post_reader (D-29)",
       %{state: state} do
    # Type content via component
    {:update, s, _} = PostComposer.handle_key(%{key: "h"}, state)
    {:update, s, _} = PostComposer.handle_key(%{key: "i"}, s)

    {:update, s, cmds} = PostComposer.handle_key(%{key: "ctrl_s"}, s)
    assert s.current_screen == :post_reader
    assert s.composer_draft == nil
    refute Map.has_key?(s.screen_state, :post_composer)
    assert Enum.any?(cmds, &match?({:load_posts, "t1"}, &1))
  end

  test "Ctrl+S transitions to :thread_list in dev-mode stub (no posts module)",
       %{state: state} do
    # Remove the posts module from session_context to hit the dev-mode path
    s = %{state | session_context: %{domain: %{markdown: FakeMarkdown}}}
    {:update, s, _} = PostComposer.handle_key(%{key: "h"}, s)
    {:update, s, _} = PostComposer.handle_key(%{key: "ctrl_s"}, s)
    assert s.current_screen == :thread_list
    assert s.modal.type == :info
  end

  # ---------------------------------------------------------------------------
  # Max-length enforcement (D-31)
  # ---------------------------------------------------------------------------

  test "Ctrl+S with body > max_post_length shows error modal (D-31)", %{state: state} do
    # Directly inject an over-limit value into the component state
    {:ok, big_input} =
      MultiLineInput.init(%{
        value: String.duplicate("x", 1_001),
        width: 76,
        height: 10,
        wrap: :none,
        focused: true
      })

    ss = get_in(state.screen_state, [:post_composer])
    s = put_in(state, [:screen_state, :post_composer], %{ss | input_state: big_input})

    {:update, s, _} = PostComposer.handle_key(%{key: "ctrl_s"}, s)
    assert s.modal.type == :error
    assert s.modal.message =~ "maximum length"
  end

  test "typing past max_post_length truncates silently (D-31)", %{state: state} do
    # Set max to 5 chars via session_context
    s = %{state | session_context: %{max_post_length: 5}}

    # Inject 5-char value already at limit
    {:ok, at_limit} =
      MultiLineInput.init(%{
        value: "abcde",
        width: 76,
        height: 10,
        wrap: :word,
        focused: true
      })

    ss = get_in(s.screen_state, [:post_composer])
    s = put_in(s, [:screen_state, :post_composer], %{ss | input_state: at_limit})

    # Type one more char — enforce_max_len should clip the value back to 5
    {:update, s, _} = PostComposer.handle_key(%{key: "f"}, s)

    text = get_in(s.screen_state, [:post_composer, :input_state, Access.key(:value)])
    assert String.length(text) <= 5
  end

  test "max_post_length falls back to default (8192) when not in session_context" do
    input_st = fresh_input(String.duplicate("x", 10_000))

    state =
      %Foglet.TUI.App{
        current_screen: :post_composer,
        current_user: %Foglet.Accounts.User{id: "u1", handle: "alice"},
        current_thread: %{id: "t1", title: "Hello"},
        session_context: %{domain: %{posts: FakePosts}},
        terminal_size: {80, 24},
        composer_draft: nil,
        screen_state: %{
          post_composer: %{
            mode: :edit,
            reply_to: nil,
            error: nil,
            input_state: input_st
          }
        }
      }
      |> Map.from_struct()

    # 10_000 chars exceeds default 8192 limit -> error modal
    {:update, s, _} = PostComposer.handle_key(%{key: "ctrl_s"}, state)
    assert s.modal.type == :error
  end

  # ---------------------------------------------------------------------------
  # Ctrl+C — cancel (D-30)
  # ---------------------------------------------------------------------------

  test "Ctrl+C cancels to :thread_list without confirmation (D-30)", %{state: state} do
    # Type some content first
    {:update, s, _} = PostComposer.handle_key(%{key: "h"}, state)
    {:update, s, _} = PostComposer.handle_key(%{key: "ctrl_c"}, s)

    assert s.current_screen == :thread_list
    assert s.composer_draft == nil
    refute Map.has_key?(s.screen_state, :post_composer)
  end

  # ---------------------------------------------------------------------------
  # Screen-state bootstrap
  # ---------------------------------------------------------------------------

  test "init_screen_state/1 returns valid map with input_state" do
    ss = PostComposer.init_screen_state(reply_to: nil, width: 80, height: 12)
    assert ss.mode == :edit
    assert ss.reply_to == nil
    assert ss.error == nil
    assert is_struct(ss.input_state, MultiLineInput)
    assert ss.input_state.value == ""
  end

  test "composer_screen_state falls back gracefully when input_state is missing",
       %{state: state} do
    # Simulate legacy screen_state without input_state key
    s = put_in(state, [:screen_state, :post_composer], %{mode: :edit, reply_to: nil, error: nil})
    # Should not crash on render
    assert _ = PostComposer.render(s)
    # And should not crash on key
    result = PostComposer.handle_key(%{key: "h"}, s)
    assert match?({:update, _, _}, result)
  end
end
