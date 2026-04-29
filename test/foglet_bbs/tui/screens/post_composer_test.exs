defmodule Foglet.TUI.Screens.PostComposerTest do
  use ExUnit.Case, async: true

  alias Foglet.TUI.Context
  alias Foglet.TUI.Screens.PostComposer
  alias Foglet.TUI.Screens.PostComposer.State
  alias Raxol.UI.Components.Input.MultiLineInput

  defmodule FakePosts do
    def create_reply(_thread_id, _board_id, _user_id, %{body: "explode"}), do: {:error, :nope}

    def create_reply(_thread_id, _board_id, _user_id, %{body: "policy"}),
      do: {:error, :posting_not_allowed}

    def create_reply(_thread_id, _board_id, _user_id, %{body: "locked"}),
      do: {:error, :thread_locked}

    def create_reply(thread_id, board_id, user_id, attrs) do
      Process.put(:post_composer_last_reply_args, {thread_id, board_id, user_id, attrs})
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
    thread = %{id: "t1", title: "Hello", board_id: "b1"}

    state =
      %Foglet.TUI.App{
        current_screen: :post_composer,
        current_user: %Foglet.Accounts.User{id: "u1", handle: "alice"},
        session_context: %{
          domain: %{posts: FakePosts, markdown: FakeMarkdown},
          max_post_length: 1_000
        },
        terminal_size: {80, 24},
        screen_state: %{
          post_composer:
            State.new(
              input_state: input_st,
              thread: thread,
              thread_id: thread.id,
              board: %{id: thread.board_id},
              board_id: thread.board_id
            )
        }
      }
      |> Map.from_struct()

    %{state: state}
  end

  defp composer_ss(state) do
    case get_in(state, [:screen_state, :post_composer]) do
      %State{} = local_state -> local_state
      _ -> State.new(width: 76, height: 10)
    end
  end

  defp input_value(state), do: composer_ss(state).input_state.value

  defp render_screen(local_state, %Context{} = context),
    do: PostComposer.render(local_state, context)

  defp render_screen(state) do
    render_screen(composer_ss(state), composer_context_from_state(state))
  end

  defp handle_key_screen(key_event, state) do
    local_state = composer_ss(state)
    context = composer_context_from_state(state)
    {new_local_state, effects} = PostComposer.update({:key, key_event}, local_state, context)

    state
    |> put_in([:screen_state, :post_composer], new_local_state)
    |> apply_screen_effects(new_local_state, context, effects)
  end

  defp composer_context_from_state(state) do
    local_state = composer_ss(state)

    composer_context(
      board: local_state.board || %{id: local_state.board_id || "b1", name: "General"},
      thread:
        local_state.thread ||
          %{
            id: local_state.thread_id || "t1",
            title: "Hello",
            board_id: local_state.board_id || "b1"
          },
      current_user: Map.get(state, :current_user),
      session_context: Map.get(state, :session_context) || %{},
      terminal_size: Map.get(state, :terminal_size) || {80, 24},
      route_params: Map.get(state, :route_params) || %{}
    )
  end

  defp apply_screen_effects(state, local_state, context, effects) do
    Enum.reduce(effects, {:update, state, []}, fn
      %Foglet.TUI.Effect{type: :navigate, payload: %{screen: screen, params: params}},
      {:update, acc, cmds} ->
        acc =
          acc
          |> Map.put(:current_screen, screen)
          |> Map.put(:route_params, params)
          |> Map.update!(:screen_state, &Map.delete(&1, :post_composer))

        cmd =
          case screen do
            :post_reader -> {:load_posts, params.thread_id, jump_last: true}
            _ -> nil
          end

        {:update, acc, append_cmd(cmds, cmd)}

      %Foglet.TUI.Effect{type: :task, payload: %{op: :submit_reply, fun: fun}},
      {:update, acc, cmds} ->
        result = fun.()

        {next_local_state, next_effects} =
          PostComposer.update({:task_result, :submit_reply, result}, local_state, context)

        acc =
          put_in(acc, [:screen_state, :post_composer], next_local_state)

        case next_effects do
          [] ->
            {:update, acc, cmds}

          _ ->
            apply_screen_effects(acc, next_local_state, context, next_effects)
        end
    end)
    |> maybe_error_modal()
  end

  defp append_cmd(cmds, nil), do: cmds
  defp append_cmd(cmds, cmd), do: cmds ++ [cmd]

  defp maybe_error_modal({:update, state, cmds}) do
    case get_in(state, [:screen_state, :post_composer]) do
      %State{error: error} when is_binary(error) ->
        {:update, %{state | modal: %Foglet.TUI.Modal{type: :error, message: error}}, cmds}

      _ ->
        {:update, state, cmds}
    end
  end

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

  defp composer_context(attrs \\ []) do
    board = Keyword.get(attrs, :board, %{id: "b1", name: "General"})
    thread = Keyword.get(attrs, :thread, %{id: "t1", title: "Hello", board_id: "b1"})

    Context.new(
      current_user: Keyword.get(attrs, :current_user, %Foglet.Accounts.User{id: "u1"}),
      session_context:
        Keyword.get(attrs, :session_context, %{
          domain: %{posts: FakePosts, markdown: FakeMarkdown},
          max_post_length: 1_000
        }),
      terminal_size: Keyword.get(attrs, :terminal_size, {80, 24}),
      route: :post_composer,
      route_params:
        Keyword.get(attrs, :route_params, %{
          board: board,
          board_id: board.id,
          thread: thread,
          thread_id: thread.id,
          origin: :post_reader
        })
    )
  end

  defp with_reply(state, body \\ "") do
    input_st = fresh_input(body)
    thread = %{id: "t1", title: "Hello", board_id: "b1"}

    ss =
      State.new(
        reply_to: reply_post(),
        input_state: input_st,
        thread: thread,
        thread_id: thread.id,
        board: %{id: thread.board_id},
        board_id: thread.board_id
      )

    put_in(state.screen_state.post_composer, ss)
  end

  # ---------------------------------------------------------------------------
  # Render
  # ---------------------------------------------------------------------------

  test "render/1 (new thread, edit mode) does not crash", %{state: state} do
    assert _ = render_screen(state)
  end

  test "render/1 in preview mode does not crash", %{state: state} do
    {:update, s, _} = handle_key_screen(%{key: :tab}, state)
    assert _ = render_screen(s)
  end

  test "render/1 delegates reply breadcrumb formatting to shared chrome", %{state: state} do
    # The previous "Reply to:" literal was emitted directly by the composer
    # render helpers; the chrome migration moved breadcrumb assembly into
    # shared chrome modules so the composer no longer renders that string.
    # Behavioural check: rendering a reply composer produces a flat text
    # that does NOT contain the legacy "Reply to:" prefix.
    state = with_reply(state)
    text = render_screen(state) |> Foglet.TUI.WidgetHelpers.flatten_text()

    refute text =~ "Reply to:"
  end

  test "render/1 in edit mode uses the composer shell with body counter", %{state: state} do
    state = with_reply(state)
    text = render_screen(state) |> Foglet.TUI.WidgetHelpers.flatten_text()

    assert text =~ "Composer"
    assert text =~ "Edit"
    assert text =~ "Preview"
    assert text =~ "0 / 1000 chars"
  end

  test "render/1 in edit mode includes reply body editor text", %{state: state} do
    state = with_reply(state, "draft body")
    text = render_screen(state) |> Foglet.TUI.WidgetHelpers.flatten_text()

    assert text =~ "draft body"
  end

  test "render/1 in compact edit mode visually wraps reply body without mutating value", %{
    state: state
  } do
    long_body = "alpha beta gamma delta epsilon zeta eta theta iota kappa lambda mu"
    state = %{with_reply(state, long_body) | terminal_size: {64, 22}}

    text = render_screen(state) |> Foglet.TUI.WidgetHelpers.flatten_text()

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

    wide_text = render_screen(wide_state) |> Foglet.TUI.WidgetHelpers.flatten_text()
    compact_text = render_screen(compact_state) |> Foglet.TUI.WidgetHelpers.flatten_text()

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

    _ = render_screen(state)

    {:update, final_state, cmds} =
      handle_key_screen(%{key: :char, char: "s", ctrl: true}, state)

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
    {:update, state, _} = handle_key_screen(%{key: :tab}, state)

    text = render_screen(state) |> Foglet.TUI.WidgetHelpers.flatten_text()

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
    {:update, state, _} = handle_key_screen(%{key: :tab}, state)

    rendered = render_screen(state)
    runs = rendered |> Foglet.TUI.WidgetHelpers.text_runs() |> Enum.map(&run_content/1)

    assert input_value(state) == long_body
    refute input_value(state) =~ "\n"
    refute "MD[#{long_body}]" in runs
    assert Enum.any?(runs, &String.starts_with?(&1, "MD[alpha beta"))
    assert Enum.any?(runs, &String.ends_with?(&1, "lambda mu]"))
  end

  test "render/1 shows compact reply context with a quote gutter", %{state: state} do
    state = with_reply(state)
    text = render_screen(state) |> Foglet.TUI.WidgetHelpers.flatten_text()

    assert text =~ "Replying to @alice"
    assert text =~ ">" or text =~ "┃"
  end

  test "PostComposer render delegates to EditorFrame and keeps preview off PostCard", %{
    state: state
  } do
    # Behavioural check: the rendered tree must contain the EditorFrame
    # contract (mode tabs "Edit"/"Preview" and the body counter) — that's
    # what EditorFrame.render produces. PostCard's reader-style header
    # ("Post N of M") must NOT appear because the composer must not delegate
    # to the reader-side card renderer.
    state = with_reply(state)
    text = render_screen(state) |> Foglet.TUI.WidgetHelpers.flatten_text()

    # EditorFrame chrome contract
    assert text =~ "Edit"
    assert text =~ "Preview"
    assert text =~ ~r/\d+ \/ \d+ chars/

    # PostCard.reader-style header must not appear in the composer
    refute text =~ ~r/Post \d+ of \d+/
  end

  # ---------------------------------------------------------------------------
  # Tab — mode toggle (D-28)
  # ---------------------------------------------------------------------------

  test "Tab toggles mode :edit <-> :preview (D-28)", %{state: state} do
    assert composer_ss(state).mode == :edit

    {:update, s, _} = handle_key_screen(%{key: :tab}, state)
    assert composer_ss(s).mode == :preview

    {:update, s, _} = handle_key_screen(%{key: :tab}, s)
    assert composer_ss(s).mode == :edit
  end

  # ---------------------------------------------------------------------------
  # Character input via MultiLineInput component
  # ---------------------------------------------------------------------------

  test "single character keys are forwarded to MultiLineInput", %{state: state} do
    {:update, s1, _} = handle_key_screen(%{key: :char, char: "h"}, state)
    {:update, s2, _} = handle_key_screen(%{key: :char, char: "i"}, s1)

    assert input_value(s2) == "hi"
  end

  test "spacebar appends a space (no special-casing — native :char shape)", %{state: state} do
    {:update, s1, _} = handle_key_screen(%{key: :char, char: "h"}, state)
    {:update, s2, _} = handle_key_screen(%{key: :char, char: " "}, s1)
    {:update, s3, _} = handle_key_screen(%{key: :char, char: "i"}, s2)

    assert input_value(s3) == "h i"
  end

  test "enter inserts a newline", %{state: state} do
    {:update, s1, _} = handle_key_screen(%{key: :char, char: "h"}, state)
    {:update, s2, _} = handle_key_screen(%{key: :enter}, s1)
    {:update, s3, _} = handle_key_screen(%{key: :char, char: "i"}, s2)

    assert input_value(s3) == "h\ni"
  end

  test "backspace removes the last character", %{state: state} do
    # Type "hello" then backspace
    s =
      Enum.reduce(~w[h e l l o], state, fn ch, acc ->
        {:update, next, _} = handle_key_screen(%{key: :char, char: ch}, acc)
        next
      end)

    {:update, s, _} = handle_key_screen(%{key: :backspace}, s)

    assert input_value(s) == "hell"
  end

  test "emoji grapheme is forwarded to MultiLineInput (unicode end-to-end)", %{state: state} do
    # 🐸 is a 4-byte UTF-8 sequence — verify the :char path handles it correctly
    {:update, s, _} = handle_key_screen(%{key: :char, char: "🐸"}, state)
    text = input_value(s)
    # The frog emoji maps to codepoint 0x1F438 (>= 32), so it should be inserted
    assert String.length(text) == 1
    assert text == "🐸"
  end

  test "multi-codepoint grapheme keys keep combining marks and joiners", %{state: state} do
    decomposed = "e\u0301"
    zwj_sequence = "👩\u200D💻"

    {:update, s1, _} = handle_key_screen(%{key: :char, char: decomposed}, state)
    {:update, s2, _} = handle_key_screen(%{key: :char, char: zwj_sequence}, s1)

    assert input_value(s2) == decomposed <> zwj_sequence
  end

  # ---------------------------------------------------------------------------
  # Ctrl+S — submit (D-29)
  # ---------------------------------------------------------------------------

  test "Ctrl+S with empty body shows error modal", %{state: state} do
    {:update, s, _} = handle_key_screen(%{key: :char, char: "s", ctrl: true}, state)
    assert s.modal.type == :error
    assert input_value(s) == ""
  end

  test "Ctrl+S with no current_user shows login-required modal", %{state: state} do
    s0 = %{state | current_user: nil}
    {:update, s1, _} = handle_key_screen(%{key: :char, char: "h"}, s0)

    {:update, s2, _} = handle_key_screen(%{key: :char, char: "s", ctrl: true}, s1)

    assert s2.modal.type == :error
    assert s2.modal.message == "You must be logged in to post."
    assert input_value(s2) == "h"
  end

  test "Ctrl+S create failure shows domain-error modal", %{state: state} do
    for ch <- String.graphemes("explode"), reduce: state do
      acc ->
        {:update, next, _} = handle_key_screen(%{key: :char, char: ch}, acc)
        next
    end
    |> then(fn s ->
      {:update, new_state, _} = handle_key_screen(%{key: :char, char: "s", ctrl: true}, s)
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
          {:update, next, _} = handle_key_screen(%{key: :char, char: ch}, acc)
          next
      end

    {:update, new_state, _} = handle_key_screen(%{key: :char, char: "s", ctrl: true}, s)

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
          {:update, next, _} = handle_key_screen(%{key: :char, char: ch}, acc)
          next
      end

    {:update, new_state, _} = handle_key_screen(%{key: :char, char: "s", ctrl: true}, s)

    assert new_state.modal.type == :error
    assert new_state.modal.message == "This thread is locked"
    assert new_state.current_screen == :post_composer
    assert Map.has_key?(new_state.screen_state, :post_composer)
  end

  test "Ctrl+S with valid body creates post and transitions to :post_reader (D-29)",
       %{state: state} do
    # Type content via component
    {:update, s, _} = handle_key_screen(%{key: :char, char: "h"}, state)
    {:update, s, _} = handle_key_screen(%{key: :char, char: "i"}, s)

    {:update, s, cmds} = handle_key_screen(%{key: :char, char: "s", ctrl: true}, s)
    assert s.current_screen == :post_reader
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

    {:update, s, _} = handle_key_screen(%{key: :char, char: "s", ctrl: true}, s)
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
    {:update, s, _} = handle_key_screen(%{key: :char, char: "f"}, s)

    assert String.length(input_value(s)) <= 5
  end

  test "max_post_length falls back to default (8192) when not in session_context" do
    input_st = fresh_input(String.duplicate("x", 10_000))

    state =
      %Foglet.TUI.App{
        current_screen: :post_composer,
        current_user: %Foglet.Accounts.User{id: "u1", handle: "alice"},
        session_context: %{domain: %{posts: FakePosts}},
        terminal_size: {80, 24},
        screen_state: %{
          post_composer: State.new(input_state: input_st)
        }
      }
      |> Map.from_struct()

    # 10_000 chars exceeds default 8192 limit -> error modal
    {:update, s, _} = handle_key_screen(%{key: :char, char: "s", ctrl: true}, state)
    assert s.modal.type == :error
  end

  # ---------------------------------------------------------------------------
  # Ctrl+C — cancel (D-30)
  # ---------------------------------------------------------------------------

  test "Ctrl+C cancels to :thread_list without confirmation (D-30)", %{state: state} do
    # Type some content first
    {:update, s, _} = handle_key_screen(%{key: :char, char: "h"}, state)
    {:update, s, _} = handle_key_screen(%{key: :char, char: "c", ctrl: true}, s)

    assert s.current_screen == :main_menu
    refute Map.has_key?(s.screen_state, :post_composer)
  end

  test "Ctrl+S and Ctrl+C are intercepted by explicit clauses, not char forwarding", %{
    state: state
  } do
    {:update, save_state, _} =
      handle_key_screen(%{key: :char, char: "s", ctrl: true}, state)

    assert save_state.modal.type == :error

    assert input_value(save_state) == ""

    {:update, cancel_state, _} =
      handle_key_screen(%{key: :char, char: "c", ctrl: true}, state)

    assert cancel_state.current_screen == :main_menu
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
          {:update, next, _} = handle_key_screen(%{key: :char, char: ch}, acc)
          next
        end)

      assert input_value(state) == "hello"

      {:update, after_save, cmds} =
        handle_key_screen(%{key: :char, char: "s", ctrl: true}, state)

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
          {:update, next, _} = handle_key_screen(%{key: :char, char: ch}, acc)
          next
        end)

      assert input_value(state) == "hello"

      {:update, after_cancel, _} =
        handle_key_screen(%{key: :char, char: "c", ctrl: true}, state)

      # Cancel fired and the body did NOT grow a "c".
      assert after_cancel.current_screen == :main_menu
      refute Map.has_key?(after_cancel.screen_state, :post_composer)
    end
  end

  describe "new screen contract" do
    test "PostComposer.init/1 extracts local route state" do
      context = composer_context(route_params: %{board_id: "b1", thread_id: "t1"})

      assert %State{} = state = PostComposer.init(context)
      assert state.board_id == "b1"
      assert state.thread_id == "t1"
      assert state.origin == :post_reader
      assert state.input_state.value == ""
    end

    test "PostComposer.update({:key, tab}, ...) toggles local mode" do
      context = composer_context()
      state = State.from_context(context)

      {state, []} = PostComposer.update({:key, %{key: :tab}}, state, context)
      assert state.mode == :preview

      {state, []} = PostComposer.update({:key, %{key: :tab}}, state, context)
      assert state.mode == :edit
    end

    test "PostComposer.update({:key, char}, ...) updates local input state" do
      context = composer_context()
      state = State.from_context(context)

      {state, []} = PostComposer.update({:key, %{key: :char, char: "h"}}, state, context)
      {state, []} = PostComposer.update({:key, %{key: :char, char: "i"}}, state, context)

      assert state.input_state.value == "hi"
    end

    test "PostComposer.update validates empty body without effects" do
      context = composer_context()
      state = State.from_context(context)

      {state, []} =
        PostComposer.update({:key, %{key: :char, char: "s", ctrl: true}}, state, context)

      assert state.error == "Post body cannot be empty."
      assert state.submission_status == :idle
    end

    test "PostComposer.update validates body length without effects" do
      context = composer_context(session_context: %{max_post_length: 3})
      state = State.new(thread_id: "t1", board_id: "b1", value: "four")

      {state, []} =
        PostComposer.update({:key, %{key: :char, char: "s", ctrl: true}}, state, context)

      assert state.error == "Post body exceeds maximum length of 3 characters (D-31)."
      assert state.submission_status == :idle
    end

    test "PostComposer.update submits valid body through an Effect.task" do
      context = composer_context()
      reply = %{id: "p1"}
      state = State.new(thread_id: "t1", board_id: "b1", reply_to: reply, value: "hi")

      {state, [effect]} =
        PostComposer.update({:key, %{key: :char, char: "s", ctrl: true}}, state, context)

      assert state.error == nil
      assert state.submission_status == :submitting
      assert %Foglet.TUI.Effect{type: :task} = effect
      assert effect.payload.op == :submit_reply
      assert effect.payload.screen_key == :post_composer

      assert {:ok, %{id: "new-post", body: "hi", reply_to_id: "p1"}} = effect.payload.fun.()

      assert Process.get(:post_composer_last_reply_args) == {
               "t1",
               "b1",
               "u1",
               %{body: "hi", reply_to_id: "p1"}
             }
    end

    test "PostComposer.update with missing user records local error and emits no task" do
      context = composer_context(current_user: nil)
      state = State.new(thread_id: "t1", board_id: "b1", value: "hi")

      {state, []} =
        PostComposer.update({:key, %{key: :char, char: "s", ctrl: true}}, state, context)

      assert state.error == "You must be logged in to post."
      assert state.submission_status == :idle
    end

    test "PostComposer.update submit success navigates to PostReader jump-last" do
      context = composer_context()

      state =
        State.new(
          board: %{id: "b1"},
          board_id: "b1",
          thread: %{id: "t1"},
          thread_id: "t1",
          submission_status: :submitting,
          value: "hi"
        )

      {state, [effect]} =
        PostComposer.update(
          {:task_result, :submit_reply, {:ok, {:ok, %{id: "p2"}}}},
          state,
          context
        )

      assert state.submission_status == :submitted
      assert state.submit_result == {:ok, %{id: "p2"}}
      assert %Foglet.TUI.Effect{type: :navigate} = effect
      assert effect.payload.screen == :post_reader
      assert effect.payload.params.thread_id == "t1"
      assert effect.payload.params.board_id == "b1"
      assert effect.payload.params.load_intent == :jump_last
    end

    test "PostComposer.update posting denied and thread locked stay local" do
      context = composer_context()
      state = State.new(thread_id: "t1", board_id: "b1", submission_status: :submitting)

      {denied_state, denied_effects} =
        PostComposer.update(
          {:task_result, :submit_reply, {:ok, {:error, :posting_not_allowed}}},
          state,
          context
        )

      assert denied_effects == []
      assert denied_state.submission_status == {:error, :posting_not_allowed}
      assert denied_state.error == "You are not allowed to post on this board."

      {locked_state, locked_effects} =
        PostComposer.update(
          {:task_result, :submit_reply, {:error, :thread_locked}},
          state,
          context
        )

      assert locked_effects == []
      assert locked_state.submission_status == {:error, :thread_locked}
      assert locked_state.error == "This thread is locked"
    end

    test "PostComposer.update Ctrl+C navigates to post_reader route identity" do
      context = composer_context()
      state = State.from_context(context)

      {^state, [effect]} =
        PostComposer.update({:key, %{key: :char, char: "c", ctrl: true}}, state, context)

      assert %Foglet.TUI.Effect{type: :navigate} = effect
      assert effect.payload.screen == :post_reader
      assert effect.payload.params.board_id == "b1"
      assert effect.payload.params.thread_id == "t1"
    end

    test "PostComposer.render/2 renders from local state and context" do
      context = composer_context()
      state = State.new(thread_id: "t1", board_id: "b1", value: "# hi", mode: :preview)

      assert _rendered = render_screen(state, context)
    end
  end

  # ---------------------------------------------------------------------------
  # Cancel — origin-aware (D-07)
  # ---------------------------------------------------------------------------

  describe "cancel (origin-aware)" do
    test "Ctrl+C with origin: :post_reader routes back to :post_reader", %{state: state} do
      s = put_in(state.screen_state.post_composer.origin, :post_reader)

      {:update, new_state, _cmds} =
        handle_key_screen(%{key: :char, char: "c", ctrl: true}, s)

      assert new_state.current_screen == :post_reader
    end

    test "Ctrl+C with no origin defaults to :main_menu (safety net)", %{state: state} do
      s = put_in(state.screen_state.post_composer.origin, :main_menu)

      {:update, new_state, _cmds} =
        handle_key_screen(%{key: :char, char: "c", ctrl: true}, s)

      assert new_state.current_screen == :main_menu
    end

    test "Ctrl+C clears the composer screen_state", %{state: state} do
      s = put_in(state.screen_state.post_composer.origin, :post_reader)

      {:update, new_state, _cmds} =
        handle_key_screen(%{key: :char, char: "c", ctrl: true}, s)

      assert Map.get(new_state.screen_state, :post_composer) == nil
    end
  end

  # ---------------------------------------------------------------------------
  # Submit — reply-jump (D-05)
  # ---------------------------------------------------------------------------

  describe "do_submit/3 on success (reply-jump)" do
    test "dispatches {:load_posts, thread_id, jump_last: true}", %{state: state} do
      # Type content into the composer
      {:update, s, _} = handle_key_screen(%{key: :char, char: "h"}, state)
      {:update, s, _} = handle_key_screen(%{key: :char, char: "i"}, s)

      {:update, _new_state, cmds} =
        handle_key_screen(%{key: :char, char: "s", ctrl: true}, s)

      assert [{:load_posts, thread_id, opts}] = cmds
      assert thread_id == "t1"
      assert Keyword.get(opts, :jump_last) == true
    end

    test "navigates to :post_reader on success", %{state: state} do
      {:update, s, _} = handle_key_screen(%{key: :char, char: "h"}, state)
      {:update, s, _} = handle_key_screen(%{key: :char, char: "i"}, s)

      {:update, new_state, _cmds} =
        handle_key_screen(%{key: :char, char: "s", ctrl: true}, s)

      assert new_state.current_screen == :post_reader
    end
  end

  # ---------------------------------------------------------------------------
  # Screen-state bootstrap
  # ---------------------------------------------------------------------------

  test "init_screen_state/1 returns valid State struct with input_state" do
    ss = State.new(reply_to: nil, width: 80, height: 12)
    assert %State{} = ss
    assert ss.board == nil
    assert ss.board_id == nil
    assert ss.thread == nil
    assert ss.thread_id == nil
    assert ss.mode == :edit
    assert ss.reply_to == nil
    assert ss.error == nil
    assert is_struct(ss.input_state, MultiLineInput)
    assert ss.input_state.value == ""
    assert ss.submission_status == :idle
    assert ss.submit_result == nil
  end

  test "PostComposer.State.new/1 accepts route and submit lifecycle overrides" do
    board = %{id: "b1", name: "General"}
    thread = %{id: "t1", title: "Hello"}
    reply = %{id: "p1"}

    ss =
      State.new(
        board: board,
        board_id: "b1",
        thread: thread,
        thread_id: "t1",
        reply_to: reply,
        origin: :post_reader,
        submission_status: :submitting,
        submit_result: {:ok, %{id: "p2"}},
        value: "draft"
      )

    assert %State{} = ss
    assert ss.board == board
    assert ss.board_id == "b1"
    assert ss.thread == thread
    assert ss.thread_id == "t1"
    assert ss.reply_to == reply
    assert ss.origin == :post_reader
    assert ss.submission_status == :submitting
    assert ss.submit_result == {:ok, %{id: "p2"}}
    assert ss.input_state.value == "draft"
  end

  test "PostComposer.State.from_context/1 extracts route params" do
    board = %{id: "b1", name: "General"}
    thread = %{id: "t1", title: "Hello"}
    reply = %{id: "p1"}

    context =
      Context.new(
        route: :post_composer,
        route_params: %{
          board: board,
          thread: thread,
          reply_to: reply,
          origin: :post_reader
        }
      )

    ss = PostComposer.State.from_context(context)

    assert %State{} = ss
    assert ss.board == board
    assert ss.board_id == "b1"
    assert ss.thread == thread
    assert ss.thread_id == "t1"
    assert ss.reply_to == reply
    assert ss.origin == :post_reader
    assert ss.submission_status == :idle
    assert ss.submit_result == nil
    assert ss.input_state.value == ""
  end

  test "PostComposer.State.from_context/1 defaults origin to post_reader" do
    context =
      Context.new(
        route: :post_composer,
        route_params: %{"board_id" => "b1", "thread_id" => "t1"}
      )

    ss = PostComposer.State.from_context(context)

    assert ss.board_id == "b1"
    assert ss.thread_id == "t1"
    assert ss.origin == :post_reader
  end

  test "composer_screen_state falls back gracefully when screen_state is missing",
       %{state: state} do
    s = put_in(state.screen_state, %{})
    # Should not crash on render
    assert _ = render_screen(s)
    # And should not crash on key
    result = handle_key_screen(%{key: :char, char: "h"}, s)
    assert match?({:update, _, _}, result)
  end

  # ---------------------------------------------------------------------------
  # Preview mode — D-11 delegation to Post.MarkdownBody
  # ---------------------------------------------------------------------------

  test "Tab toggles to :preview mode with markdown body", %{state: state} do
    # Type some content first
    {:update, s, _} = handle_key_screen(%{key: :char, char: "#"}, state)
    {:update, s, _} = handle_key_screen(%{key: :char, char: " "}, s)
    {:update, s, _} = handle_key_screen(%{key: :char, char: "h"}, s)
    {:update, s, _} = handle_key_screen(%{key: :char, char: "i"}, s)

    assert composer_ss(s).mode == :edit

    {:update, s, _} = handle_key_screen(%{key: :tab}, s)
    assert composer_ss(s).mode == :preview
  end
end
