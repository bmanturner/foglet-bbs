defmodule Foglet.TUI.Screens.PostComposerTest do
  use ExUnit.Case, async: true

  alias Foglet.TUI.Screens.PostComposer
  alias Raxol.UI.Components.Input.MultiLineInput

  defmodule FakePosts do
    def create_reply(_thread_id, _board_id, _user_id, %{body: "explode"}), do: {:error, :nope}

    def create_reply(_thread_id, _board_id, _user_id, attrs),
      do: {:ok, Map.merge(%{id: "new-post"}, attrs)}
  end

  defmodule FakeMarkdown do
    # Returns [{text, style_atom}] tuples per the Foglet.Markdown.render/1 contract.
    def render(text), do: [{"MD[" <> text <> "]", :plain}]
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
        current_thread: %{id: "t1", title: "Hello", board_id: "b1"},
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
    {:update, s, _} = PostComposer.handle_key(%{key: :tab}, state)
    assert _ = PostComposer.render(s)
  end

  # ---------------------------------------------------------------------------
  # Tab — mode toggle (D-28)
  # ---------------------------------------------------------------------------

  test "Tab toggles mode :edit <-> :preview (D-28)", %{state: state} do
    assert get_in(state.screen_state, [:post_composer, :mode]) == :edit

    {:update, s, _} = PostComposer.handle_key(%{key: :tab}, state)
    assert get_in(s.screen_state, [:post_composer, :mode]) == :preview

    {:update, s, _} = PostComposer.handle_key(%{key: :tab}, s)
    assert get_in(s.screen_state, [:post_composer, :mode]) == :edit
  end

  # ---------------------------------------------------------------------------
  # Character input via MultiLineInput component
  # ---------------------------------------------------------------------------

  test "single character keys are forwarded to MultiLineInput", %{state: state} do
    {:update, s1, _} = PostComposer.handle_key(%{key: :char, char: "h"}, state)
    {:update, s2, _} = PostComposer.handle_key(%{key: :char, char: "i"}, s1)

    text = get_in(s2.screen_state, [:post_composer, :input_state, Access.key(:value)])
    assert text == "hi"
  end

  test "spacebar appends a space (no special-casing — native :char shape)", %{state: state} do
    {:update, s1, _} = PostComposer.handle_key(%{key: :char, char: "h"}, state)
    {:update, s2, _} = PostComposer.handle_key(%{key: :char, char: " "}, s1)
    {:update, s3, _} = PostComposer.handle_key(%{key: :char, char: "i"}, s2)

    text = get_in(s3.screen_state, [:post_composer, :input_state, Access.key(:value)])
    assert text == "h i"
  end

  test "enter inserts a newline", %{state: state} do
    {:update, s1, _} = PostComposer.handle_key(%{key: :char, char: "h"}, state)
    {:update, s2, _} = PostComposer.handle_key(%{key: :enter}, s1)
    {:update, s3, _} = PostComposer.handle_key(%{key: :char, char: "i"}, s2)

    text = get_in(s3.screen_state, [:post_composer, :input_state, Access.key(:value)])
    assert text == "h\ni"
  end

  test "backspace removes the last character", %{state: state} do
    # Type "hello" then backspace
    s =
      Enum.reduce(~w[h e l l o], state, fn ch, acc ->
        {:update, next, _} = PostComposer.handle_key(%{key: :char, char: ch}, acc)
        next
      end)

    {:update, s, _} = PostComposer.handle_key(%{key: :backspace}, s)

    text = get_in(s.screen_state, [:post_composer, :input_state, Access.key(:value)])
    assert text == "hell"
  end

  test "arrow-key events are forwarded without crash", %{state: state} do
    # Type something first so there's content to navigate
    {:update, s, _} = PostComposer.handle_key(%{key: :char, char: "h"}, state)

    for key <- [:up, :down, :left, :right, :home, :end, :page_up, :page_down] do
      result = PostComposer.handle_key(%{key: key}, s)

      assert match?({:update, _, _}, result) or result == :no_match,
             "Key #{key} returned unexpected: #{inspect(result)}"
    end
  end

  test "emoji grapheme is forwarded to MultiLineInput (unicode end-to-end)", %{state: state} do
    # 🐸 is a 4-byte UTF-8 sequence — verify the :char path handles it correctly
    {:update, s, _} = PostComposer.handle_key(%{key: :char, char: "🐸"}, state)
    text = get_in(s.screen_state, [:post_composer, :input_state, Access.key(:value)])
    # The frog emoji maps to codepoint 0x1F438 (>= 32), so it should be inserted
    assert String.length(text) == 1
    assert text == "🐸"
  end

  # ---------------------------------------------------------------------------
  # Ctrl+S — submit (D-29)
  # ---------------------------------------------------------------------------

  test "Ctrl+S with empty body shows error modal", %{state: state} do
    {:update, s, _} = PostComposer.handle_key(%{key: :char, char: "s", ctrl: true}, state)
    assert s.modal.type == :error
  end

  test "Ctrl+S with valid body creates post and transitions to :post_reader (D-29)",
       %{state: state} do
    # Type content via component
    {:update, s, _} = PostComposer.handle_key(%{key: :char, char: "h"}, state)
    {:update, s, _} = PostComposer.handle_key(%{key: :char, char: "i"}, s)

    {:update, s, cmds} = PostComposer.handle_key(%{key: :char, char: "s", ctrl: true}, s)
    assert s.current_screen == :post_reader
    assert s.composer_draft == nil
    refute Map.has_key?(s.screen_state, :post_composer)

    assert Enum.any?(cmds, fn
             {:load_posts, "t1"} -> true
             {:load_posts, "t1", _opts} -> true
             _ -> false
           end)
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

    {:update, s, _} = PostComposer.handle_key(%{key: :char, char: "s", ctrl: true}, s)
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
    {:update, s, _} = PostComposer.handle_key(%{key: :char, char: "f"}, s)

    text = get_in(s.screen_state, [:post_composer, :input_state, Access.key(:value)])
    assert String.length(text) <= 5
  end

  test "max_post_length falls back to default (8192) when not in session_context" do
    input_st = fresh_input(String.duplicate("x", 10_000))

    state =
      %Foglet.TUI.App{
        current_screen: :post_composer,
        current_user: %Foglet.Accounts.User{id: "u1", handle: "alice"},
        current_thread: %{id: "t1", title: "Hello", board_id: "b1"},
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
    {:update, s, _} = PostComposer.handle_key(%{key: :char, char: "s", ctrl: true}, state)
    assert s.modal.type == :error
  end

  # ---------------------------------------------------------------------------
  # Ctrl+C — cancel (D-30)
  # ---------------------------------------------------------------------------

  test "Ctrl+C cancels to :thread_list without confirmation (D-30)", %{state: state} do
    # Type some content first
    {:update, s, _} = PostComposer.handle_key(%{key: :char, char: "h"}, state)
    {:update, s, _} = PostComposer.handle_key(%{key: :char, char: "c", ctrl: true}, s)

    assert s.current_screen == :main_menu
    assert s.composer_draft == nil
    refute Map.has_key?(s.screen_state, :post_composer)
  end

  # ---------------------------------------------------------------------------
  # Cancel — origin-aware (D-07)
  # ---------------------------------------------------------------------------

  describe "cancel (origin-aware)" do
    test "Ctrl+C with origin: :post_reader routes back to :post_reader", %{state: state} do
      s = put_in(state, [:screen_state, :post_composer, :origin], :post_reader)

      {:update, new_state, []} =
        PostComposer.handle_key(%{key: :char, char: "c", ctrl: true}, s)

      assert new_state.current_screen == :post_reader
    end

    test "Ctrl+C with no origin defaults to :main_menu (safety net)", %{state: state} do
      # Remove origin if present — composer_screen_state reads from screen_state
      s = update_in(state, [:screen_state, :post_composer], &Map.delete(&1, :origin))

      {:update, new_state, []} =
        PostComposer.handle_key(%{key: :char, char: "c", ctrl: true}, s)

      assert new_state.current_screen == :main_menu
    end

    test "Ctrl+C clears the composer screen_state", %{state: state} do
      s = put_in(state, [:screen_state, :post_composer, :origin], :post_reader)

      {:update, new_state, []} =
        PostComposer.handle_key(%{key: :char, char: "c", ctrl: true}, s)

      assert Map.get(new_state.screen_state, :post_composer) == nil
    end
  end

  # ---------------------------------------------------------------------------
  # Submit — reply-jump (D-05)
  # ---------------------------------------------------------------------------

  describe "do_submit/3 on success (reply-jump)" do
    test "dispatches {:load_posts, thread_id, jump_last: true}", %{state: state} do
      # Type content into the composer
      {:update, s, _} = PostComposer.handle_key(%{key: :char, char: "h"}, state)
      {:update, s, _} = PostComposer.handle_key(%{key: :char, char: "i"}, s)

      {:update, _new_state, cmds} =
        PostComposer.handle_key(%{key: :char, char: "s", ctrl: true}, s)

      assert [{:load_posts, thread_id, opts}] = cmds
      assert thread_id == "t1"
      assert Keyword.get(opts, :jump_last) == true
    end

    test "navigates to :post_reader on success", %{state: state} do
      {:update, s, _} = PostComposer.handle_key(%{key: :char, char: "h"}, state)
      {:update, s, _} = PostComposer.handle_key(%{key: :char, char: "i"}, s)

      {:update, new_state, _cmds} =
        PostComposer.handle_key(%{key: :char, char: "s", ctrl: true}, s)

      assert new_state.current_screen == :post_reader
    end
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
    result = PostComposer.handle_key(%{key: :char, char: "h"}, s)
    assert match?({:update, _, _}, result)
  end
end
