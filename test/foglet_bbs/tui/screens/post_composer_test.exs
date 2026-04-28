defmodule Foglet.TUI.Screens.PostComposerTest do
  use ExUnit.Case, async: true

  alias Foglet.TUI.Screens.PostComposer
  alias Foglet.TUI.Screens.PostComposer.State
  alias Raxol.UI.Components.Input.MultiLineInput

  defmodule FakePosts do
    def create_reply(_thread_id, _board_id, _user_id, %{body: "explode"}), do: {:error, :nope}

    def create_reply(_thread_id, _board_id, _user_id, %{body: "policy"}),
      do: {:error, :posting_not_allowed}

    def create_reply(_thread_id, _board_id, _user_id, %{body: "locked"}),
      do: {:error, :thread_locked}

    def create_reply(_thread_id, _board_id, _user_id, attrs) do
      Process.put(:post_composer_last_reply_body, Map.fetch!(attrs, :body))
      {:ok, Map.merge(%{id: "new-post"}, attrs)}
    end
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
          post_composer: PostComposer.init_screen_state(input_state: input_st)
        }
      }
      |> Map.from_struct()

    %{state: state}
  end

  defp composer_ss(state), do: state.screen_state.post_composer
  defp input_value(state), do: composer_ss(state).input_state.value

  defp run_content(%{content: content}) when is_binary(content), do: content
  defp run_content(%{text: text}) when is_binary(text), do: text
  defp run_content(_run), do: ""

  defp reply_post do
    %{
      id: "p1",
      body:
        "This is the quoted post body\nwith a second line\nand more text that should collapse",
      user: %{handle: "alice"}
    }
  end

  defp with_reply(state, body \\ "") do
    input_st = fresh_input(body)

    ss =
      PostComposer.init_screen_state(
        reply_to: reply_post(),
        input_state: input_st
      )

    put_in(state.screen_state.post_composer, ss)
  end

  # ---------------------------------------------------------------------------
  # Render
  # ---------------------------------------------------------------------------

  test "render/1 (new thread, edit mode) does not crash", %{state: state} do
    assert _ = PostComposer.render(state)
  end

  test "render/1 in preview mode does not crash", %{state: state} do
    {:update, s, _} = PostComposer.handle_key(%{key: :tab}, state)
    assert _ = PostComposer.render(s)
  end

  test "render/1 delegates reply breadcrumb formatting to shared chrome" do
    source =
      __ENV__.file
      |> Path.dirname()
      |> Path.join("../../../../lib/foglet_bbs/tui/screens/post_composer.ex")
      |> Path.expand()
      |> File.read!()

    refute source =~ "Reply to:"
  end

  test "render/1 in edit mode uses the composer shell with body counter", %{state: state} do
    state = with_reply(state)
    text = PostComposer.render(state) |> Foglet.TUI.WidgetHelpers.flatten_text()

    assert text =~ "Composer"
    assert text =~ "Edit"
    assert text =~ "Preview"
    assert text =~ "0 / 1000 chars"
  end

  test "render/1 in edit mode includes reply body editor text", %{state: state} do
    state = with_reply(state, "draft body")
    text = PostComposer.render(state) |> Foglet.TUI.WidgetHelpers.flatten_text()

    assert text =~ "draft body"
  end

  test "render/1 in compact edit mode visually wraps reply body without mutating value", %{
    state: state
  } do
    long_body = "alpha beta gamma delta epsilon zeta eta theta iota kappa lambda mu"
    state = %{with_reply(state, long_body) | terminal_size: {64, 22}}

    text = PostComposer.render(state) |> Foglet.TUI.WidgetHelpers.flatten_text()

    assert text =~ "alpha beta"
    assert text =~ "iota kappa"
    assert input_value(state) == long_body
    refute input_value(state) =~ "\n"
  end

  test "render/1 reflows reply body between 80x24 and 64x22 without changing logical value",
       %{state: state} do
    long_body = "alpha beta gamma delta epsilon zeta eta theta iota kappa lambda mu"
    wide_state = %{with_reply(state, long_body) | terminal_size: {80, 24}}
    compact_state = %{wide_state | terminal_size: {64, 22}}

    wide_text = PostComposer.render(wide_state) |> Foglet.TUI.WidgetHelpers.flatten_text()
    compact_text = PostComposer.render(compact_state) |> Foglet.TUI.WidgetHelpers.flatten_text()

    assert input_value(wide_state) == long_body
    assert input_value(compact_state) == long_body
    refute input_value(compact_state) =~ "\n"
    assert wide_text =~ long_body
    refute compact_text =~ long_body
    assert compact_text =~ "alpha beta"
    assert compact_text =~ "iota kappa"
  end

  test "Ctrl+S submits the one-line reply body exactly after compact render", %{state: state} do
    long_body = "alpha beta gamma delta epsilon zeta eta theta iota kappa lambda mu"
    state = %{with_reply(state, long_body) | terminal_size: {64, 22}}

    _ = PostComposer.render(state)

    {:update, final_state, cmds} =
      PostComposer.handle_key(%{key: :char, char: "s", ctrl: true}, state)

    assert final_state.current_screen == :post_reader
    assert Process.get(:post_composer_last_reply_body) == long_body
    refute Process.get(:post_composer_last_reply_body) =~ "\n"

    assert Enum.any?(cmds, fn
             {:load_posts, "t1", _opts} -> true
             _ -> false
           end)
  end

  test "render/1 in preview mode keeps markdown preview inside the composer shell", %{
    state: state
  } do
    state = with_reply(state, "# hi")
    {:update, state, _} = PostComposer.handle_key(%{key: :tab}, state)

    text = PostComposer.render(state) |> Foglet.TUI.WidgetHelpers.flatten_text()

    assert text =~ "Composer"
    assert text =~ "Edit"
    assert text =~ "Preview"
    assert text =~ "MD[# hi]"
  end

  test "render/1 in compact preview mode wraps markdown preview without mutating value", %{
    state: state
  } do
    long_body = "alpha beta gamma delta epsilon zeta eta theta iota kappa lambda mu"
    state = %{with_reply(state, long_body) | terminal_size: {40, 22}}
    {:update, state, _} = PostComposer.handle_key(%{key: :tab}, state)

    rendered = PostComposer.render(state)
    runs = rendered |> Foglet.TUI.WidgetHelpers.text_runs() |> Enum.map(&run_content/1)

    assert input_value(state) == long_body
    refute input_value(state) =~ "\n"
    refute "MD[#{long_body}]" in runs
    assert Enum.any?(runs, &String.starts_with?(&1, "MD[alpha beta"))
    assert Enum.any?(runs, &String.ends_with?(&1, "lambda mu]"))
  end

  test "render/1 shows compact reply context with a quote gutter", %{state: state} do
    state = with_reply(state)
    text = PostComposer.render(state) |> Foglet.TUI.WidgetHelpers.flatten_text()

    assert text =~ "Replying to @alice"
    assert text =~ ">" or text =~ "┃"
  end

  test "PostComposer render source delegates to EditorFrame and keeps preview off PostCard" do
    source =
      __ENV__.file
      |> Path.dirname()
      |> Path.join("../../../../lib/foglet_bbs/tui/screens/post_composer.ex")
      |> Path.expand()
      |> File.read!()

    assert source =~ "EditorFrame.render"
    refute source =~ "PostCard.render"
  end

  # ---------------------------------------------------------------------------
  # Tab — mode toggle (D-28)
  # ---------------------------------------------------------------------------

  test "Tab toggles mode :edit <-> :preview (D-28)", %{state: state} do
    assert composer_ss(state).mode == :edit

    {:update, s, _} = PostComposer.handle_key(%{key: :tab}, state)
    assert composer_ss(s).mode == :preview

    {:update, s, _} = PostComposer.handle_key(%{key: :tab}, s)
    assert composer_ss(s).mode == :edit
  end

  # ---------------------------------------------------------------------------
  # Character input via MultiLineInput component
  # ---------------------------------------------------------------------------

  test "single character keys are forwarded to MultiLineInput", %{state: state} do
    {:update, s1, _} = PostComposer.handle_key(%{key: :char, char: "h"}, state)
    {:update, s2, _} = PostComposer.handle_key(%{key: :char, char: "i"}, s1)

    assert input_value(s2) == "hi"
  end

  test "spacebar appends a space (no special-casing — native :char shape)", %{state: state} do
    {:update, s1, _} = PostComposer.handle_key(%{key: :char, char: "h"}, state)
    {:update, s2, _} = PostComposer.handle_key(%{key: :char, char: " "}, s1)
    {:update, s3, _} = PostComposer.handle_key(%{key: :char, char: "i"}, s2)

    assert input_value(s3) == "h i"
  end

  test "enter inserts a newline", %{state: state} do
    {:update, s1, _} = PostComposer.handle_key(%{key: :char, char: "h"}, state)
    {:update, s2, _} = PostComposer.handle_key(%{key: :enter}, s1)
    {:update, s3, _} = PostComposer.handle_key(%{key: :char, char: "i"}, s2)

    assert input_value(s3) == "h\ni"
  end

  test "backspace removes the last character", %{state: state} do
    # Type "hello" then backspace
    s =
      Enum.reduce(~w[h e l l o], state, fn ch, acc ->
        {:update, next, _} = PostComposer.handle_key(%{key: :char, char: ch}, acc)
        next
      end)

    {:update, s, _} = PostComposer.handle_key(%{key: :backspace}, s)

    assert input_value(s) == "hell"
  end

  test "emoji grapheme is forwarded to MultiLineInput (unicode end-to-end)", %{state: state} do
    # 🐸 is a 4-byte UTF-8 sequence — verify the :char path handles it correctly
    {:update, s, _} = PostComposer.handle_key(%{key: :char, char: "🐸"}, state)
    text = input_value(s)
    # The frog emoji maps to codepoint 0x1F438 (>= 32), so it should be inserted
    assert String.length(text) == 1
    assert text == "🐸"
  end

  test "multi-codepoint grapheme keys keep combining marks and joiners", %{state: state} do
    decomposed = "e\u0301"
    zwj_sequence = "👩\u200D💻"

    {:update, s1, _} = PostComposer.handle_key(%{key: :char, char: decomposed}, state)
    {:update, s2, _} = PostComposer.handle_key(%{key: :char, char: zwj_sequence}, s1)

    assert input_value(s2) == decomposed <> zwj_sequence
  end

  # ---------------------------------------------------------------------------
  # Ctrl+S — submit (D-29)
  # ---------------------------------------------------------------------------

  test "Ctrl+S with empty body shows error modal", %{state: state} do
    {:update, s, _} = PostComposer.handle_key(%{key: :char, char: "s", ctrl: true}, state)
    assert s.modal.type == :error
    assert input_value(s) == ""
  end

  test "Ctrl+S with no current_user shows login-required modal", %{state: state} do
    s0 = %{state | current_user: nil}
    {:update, s1, _} = PostComposer.handle_key(%{key: :char, char: "h"}, s0)

    {:update, s2, _} = PostComposer.handle_key(%{key: :char, char: "s", ctrl: true}, s1)

    assert s2.modal.type == :error
    assert s2.modal.message == "You must be logged in to post."
    assert input_value(s2) == "h"
  end

  test "Ctrl+S create failure shows domain-error modal", %{state: state} do
    for ch <- String.graphemes("explode"), reduce: state do
      acc ->
        {:update, next, _} = PostComposer.handle_key(%{key: :char, char: ch}, acc)
        next
    end
    |> then(fn s ->
      {:update, new_state, _} = PostComposer.handle_key(%{key: :char, char: "s", ctrl: true}, s)
      assert new_state.modal.type == :error
      assert new_state.modal.message == ":nope"
      assert new_state.current_screen == :post_composer
      assert Map.has_key?(new_state.screen_state, :post_composer)
    end)
  end

  test "Ctrl+S posting-policy denial shows clear modal and stays composing (POST-04)",
       %{state: state} do
    s =
      for ch <- String.graphemes("policy"), reduce: state do
        acc ->
          {:update, next, _} = PostComposer.handle_key(%{key: :char, char: ch}, acc)
          next
      end

    {:update, new_state, _} = PostComposer.handle_key(%{key: :char, char: "s", ctrl: true}, s)

    assert new_state.modal.type == :error
    assert new_state.modal.message == "You are not allowed to post on this board."
    assert new_state.current_screen == :post_composer
    assert Map.has_key?(new_state.screen_state, :post_composer)
  end

  test "Ctrl+S locked-thread denial shows exact modal and stays composing (POST-04)",
       %{state: state} do
    s =
      for ch <- String.graphemes("locked"), reduce: state do
        acc ->
          {:update, next, _} = PostComposer.handle_key(%{key: :char, char: ch}, acc)
          next
      end

    {:update, new_state, _} = PostComposer.handle_key(%{key: :char, char: "s", ctrl: true}, s)

    assert new_state.modal.type == :error
    assert new_state.modal.message == "This thread is locked"
    assert new_state.current_screen == :post_composer
    assert Map.has_key?(new_state.screen_state, :post_composer)
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

    s = put_in(state.screen_state.post_composer.input_state, big_input)

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

    s = put_in(s.screen_state.post_composer.input_state, at_limit)

    # Type one more char — enforce_max_len should clip the value back to 5
    {:update, s, _} = PostComposer.handle_key(%{key: :char, char: "f"}, s)

    assert String.length(input_value(s)) <= 5
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
          post_composer: PostComposer.init_screen_state(input_state: input_st)
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

  test "Ctrl+S and Ctrl+C are intercepted by explicit clauses, not char forwarding", %{
    state: state
  } do
    {:update, save_state, _} =
      PostComposer.handle_key(%{key: :char, char: "s", ctrl: true}, state)

    assert save_state.modal.type == :error

    assert input_value(save_state) == ""

    {:update, cancel_state, _} =
      PostComposer.handle_key(%{key: :char, char: "c", ctrl: true}, state)

    assert cancel_state.current_screen == :main_menu
    assert cancel_state.composer_draft == nil
  end

  # Regression: handle_key/2 clause order is load-bearing. Compose.translate_key/1
  # does NOT filter ctrl-modified char events — it produces {:input, ?s} for
  # `%{key: :char, char: "s", ctrl: true}`. If anyone moves the catch-all
  # forwarding clause above the Ctrl+S / Ctrl+C clauses, the body will silently
  # eat "s" / "c" and Submit/Cancel will stop working. These tests prove the
  # interceptors run first by typing real content first and asserting the body
  # is unchanged after the ctrl shortcut fires.
  describe "handle_key/2 clause order regression (TODO #7)" do
    test "Ctrl+S submits even when body already has content (does not insert 's')",
         %{state: state} do
      state =
        Enum.reduce(~w[h e l l o], state, fn ch, acc ->
          {:update, next, _} = PostComposer.handle_key(%{key: :char, char: ch}, acc)
          next
        end)

      assert input_value(state) == "hello"

      {:update, after_save, cmds} =
        PostComposer.handle_key(%{key: :char, char: "s", ctrl: true}, state)

      # Submit fired (transitioned away from composer) and the body did NOT
      # grow an "s" — i.e., the explicit clause intercepted before forwarding.
      assert after_save.current_screen == :post_reader
      refute Map.has_key?(after_save.screen_state, :post_composer)

      assert Enum.any?(cmds, fn
               {:load_posts, "t1"} -> true
               {:load_posts, "t1", _} -> true
               _ -> false
             end)
    end

    test "Ctrl+C cancels even when body already has content (does not insert 'c')",
         %{state: state} do
      state =
        Enum.reduce(~w[h e l l o], state, fn ch, acc ->
          {:update, next, _} = PostComposer.handle_key(%{key: :char, char: ch}, acc)
          next
        end)

      assert input_value(state) == "hello"

      {:update, after_cancel, _} =
        PostComposer.handle_key(%{key: :char, char: "c", ctrl: true}, state)

      # Cancel fired and the body did NOT grow a "c".
      assert after_cancel.current_screen == :main_menu
      refute Map.has_key?(after_cancel.screen_state, :post_composer)
    end
  end

  # ---------------------------------------------------------------------------
  # Cancel — origin-aware (D-07)
  # ---------------------------------------------------------------------------

  describe "cancel (origin-aware)" do
    test "Ctrl+C with origin: :post_reader routes back to :post_reader", %{state: state} do
      s = put_in(state.screen_state.post_composer.origin, :post_reader)

      {:update, new_state, []} =
        PostComposer.handle_key(%{key: :char, char: "c", ctrl: true}, s)

      assert new_state.current_screen == :post_reader
    end

    test "Ctrl+C with no origin defaults to :main_menu (safety net)", %{state: state} do
      s = put_in(state.screen_state.post_composer.origin, :main_menu)

      {:update, new_state, []} =
        PostComposer.handle_key(%{key: :char, char: "c", ctrl: true}, s)

      assert new_state.current_screen == :main_menu
    end

    test "Ctrl+C clears the composer screen_state", %{state: state} do
      s = put_in(state.screen_state.post_composer.origin, :post_reader)

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

  test "init_screen_state/1 returns valid State struct with input_state" do
    ss = PostComposer.init_screen_state(reply_to: nil, width: 80, height: 12)
    assert %State{} = ss
    assert ss.mode == :edit
    assert ss.reply_to == nil
    assert ss.error == nil
    assert is_struct(ss.input_state, MultiLineInput)
    assert ss.input_state.value == ""
  end

  test "composer_screen_state falls back gracefully when screen_state is missing",
       %{state: state} do
    s = put_in(state.screen_state, %{})
    # Should not crash on render
    assert _ = PostComposer.render(s)
    # And should not crash on key
    result = PostComposer.handle_key(%{key: :char, char: "h"}, s)
    assert match?({:update, _, _}, result)
  end

  # ---------------------------------------------------------------------------
  # Preview mode — D-11 delegation to Post.MarkdownBody
  # ---------------------------------------------------------------------------

  test "Tab toggles to :preview mode with markdown body", %{state: state} do
    # Type some content first
    {:update, s, _} = PostComposer.handle_key(%{key: :char, char: "#"}, state)
    {:update, s, _} = PostComposer.handle_key(%{key: :char, char: " "}, s)
    {:update, s, _} = PostComposer.handle_key(%{key: :char, char: "h"}, s)
    {:update, s, _} = PostComposer.handle_key(%{key: :char, char: "i"}, s)

    assert composer_ss(s).mode == :edit

    {:update, s, _} = PostComposer.handle_key(%{key: :tab}, s)
    assert composer_ss(s).mode == :preview
  end
end
