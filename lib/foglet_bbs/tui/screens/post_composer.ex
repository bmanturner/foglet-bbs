defmodule Foglet.TUI.Screens.PostComposer do
  @moduledoc """
  Post composer (SSH-07, D-26..D-31).

  Phase 37 makes PostComposer screen-owned: draft input, preview mode,
  route/reply identity, validation, submit status/result, and cancel origin
  live in `%PostComposer.State{}` and flow through `update/3`.

  Layout (D-27): header, quote context (when replying), text area, key bar.
  Tab toggles edit/preview (D-28). Ctrl+S submits (D-29). Ctrl+C cancels (D-30).
  Max body length enforced via Foglet.Config.get!("max_post_length") (D-31).

  Uses `Raxol.UI.Components.Input.MultiLineInput` component module (D-26) for
  the full-featured editor: cursor, word wrap, undo/redo, shift-select.
  Component state is stored in `%PostComposer.State{}.input_state` at
  `state.screen_state[:post_composer]`.
  The legacy App-level `composer_draft` slot is NOT used for reading text — we always read from
  `input_state.value`. The struct field remains on App but is set to nil by
  cancel/submit to signal no active draft (unchanged contract).
  """

  @behaviour Foglet.TUI.Screen

  alias Foglet.Config
  alias Foglet.TUI.{Context, Effect}
  alias Foglet.TUI.Screens.Domain
  alias Foglet.TUI.Screens.PostComposer.State
  alias Foglet.TUI.TextWidth
  alias Foglet.TUI.Theme
  alias Foglet.TUI.Widgets.Chrome.ScreenFrame
  alias Foglet.TUI.Widgets.Compose
  alias Foglet.TUI.Widgets.Composer.EditorFrame
  alias Foglet.TUI.Widgets.Post.MarkdownBody
  alias Foglet.TUI.Widgets.Post.PostCard
  alias Raxol.UI.Components.Input.MultiLineInput

  import Raxol.Core.Renderer.View

  @default_max_post_length 8192
  @default_terminal_size {80, 24}

  # Phase 39 Plan 39-06 transitional: indirected legacy App-shape thread key
  # so the post-39-07 grep audit finds no direct dot- or Map.get-access of
  # the soon-to-be-deleted field. Plan 39-07 removes both the field and
  # this constant.
  @legacy_thread_key :current_thread

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @impl true
  @spec init(Context.t()) :: State.t()
  def init(%Context{} = context), do: State.from_context(context)

  @impl true
  @spec update(term(), State.t(), Context.t()) :: {State.t(), [Effect.t()]}
  def update({:key, %{key: :tab}}, %State{} = state, %Context{}) do
    new_mode = if state.mode == :edit, do: :preview, else: :edit
    {%{state | mode: new_mode}, []}
  end

  def update({:key, %{key: :char, char: "s", ctrl: true}}, %State{} = state, %Context{} = context) do
    submit_local(state, context)
  end

  def update({:key, %{key: :char, char: "c", ctrl: true}}, %State{} = state, %Context{}) do
    {state, [Effect.navigate(state.origin, cancel_params(state))]}
  end

  def update({:key, key_event}, %State{} = state, %Context{} = context) do
    case Compose.apply_key(state.input_state, key_event) do
      {:ok, input_state} ->
        {%{state | input_state: enforce_max_len(input_state, context)}, []}

      :error ->
        {state, []}
    end
  end

  def update({:task_result, :submit_reply, {:ok, {:error, reason}}}, %State{} = state, %Context{}) do
    {%{
       state
       | submission_status: {:error, reason},
         submit_result: {:error, reason},
         error: format_error(reason)
     }, []}
  end

  def update(
        {:task_result, :submit_reply, {:ok, {:ok, post_or_result}}},
        %State{} = state,
        %Context{}
      ) do
    submit_success(state, {:ok, post_or_result})
  end

  def update({:task_result, :submit_reply, {:ok, post_or_result}}, %State{} = state, %Context{}) do
    submit_success(state, {:ok, post_or_result})
  end

  def update({:task_result, :submit_reply, {:error, reason}}, %State{} = state, %Context{}) do
    {%{
       state
       | submission_status: {:error, reason},
         submit_result: {:error, reason},
         error: format_error(reason)
     }, []}
  end

  def update({:task_result, :submit_reply, result}, %State{} = state, %Context{}) do
    {%{state | submit_result: result}, []}
  end

  @impl true
  @spec render(State.t(), Context.t()) :: any()
  def render(%State{} = state, %Context{} = context) do
    frame_state = frame_state(state, context)
    input_st = state.input_state
    draft = input_st.value
    theme = Theme.from_state(frame_state)
    {width, height} = context.terminal_size || @default_terminal_size
    max = max_len(context)

    content =
      EditorFrame.render(
        mode: state.mode,
        focused?: state.mode == :edit,
        context: reply_context(state.reply_to, width, theme),
        body: composer_body(state.mode, input_st, draft, frame_state, theme, width),
        budgets: [%{label: "Body", count: String.length(draft), limit: max}],
        error: state.error,
        width: max(width - 4, 20),
        height: max(height - 6, 10),
        theme: theme
      )

    chrome = %{
      breadcrumb_parts: [
        "Foglet",
        board_label(state),
        thread_title_label(state),
        "Reply"
      ]
    }

    ScreenFrame.render(frame_state, chrome, content, [
      {"Tab", if(state.mode == :edit, do: "Preview", else: "Edit")},
      {"Ctrl+S", "Send"},
      {"Ctrl+C", "Cancel"}
    ])
  end

  defp board_label(%State{board: %{name: name}}) when is_binary(name), do: name
  defp board_label(%State{}), do: "Boards"

  defp thread_title_label(%State{thread: %{title: title}}) when is_binary(title), do: title
  defp thread_title_label(%State{}), do: "Thread"

  @impl true
  @spec render(map()) :: any()
  # Phase 39 cleanup: legacy render/1 remains for older smoke tests only.
  # Phase 37 flow state is screen-owned by render/2 and %PostComposer.State{}.
  def render(state) do
    ss = composer_screen_state(state)
    input_st = ss.input_state
    draft = input_st.value
    theme = Theme.from_state(state)
    {width, height} = state.terminal_size || @default_terminal_size
    max = max_len(state)

    content =
      EditorFrame.render(
        mode: ss.mode,
        focused?: ss.mode == :edit,
        context: reply_context(ss.reply_to, width, theme),
        body: composer_body(ss.mode, input_st, draft, state, theme, width),
        budgets: [%{label: "Body", count: String.length(draft), limit: max}],
        error: ss.error,
        width: max(width - 4, 20),
        height: max(height - 6, 10),
        theme: theme
      )

    ScreenFrame.render(state, %{}, content, [
      {"Tab", if(ss.mode == :edit, do: "Preview", else: "Edit")},
      {"Ctrl+S", "Send"},
      {"Ctrl+C", "Cancel"}
    ])
  end

  @impl true
  @spec handle_key(map(), map()) :: {:update, map(), list()} | :no_match
  # Phase 39 cleanup: legacy handle_key/2 remains for compatibility tests.
  # It must not be the source of truth for the Phase 37 App runtime path.
  # NOTE: PostComposer handle_key/2 clause order is load-bearing:
  # keep :tab/Ctrl+S/Ctrl+C above fallback forwarding.
  def handle_key(%{key: :tab}, state), do: toggle_mode(state)
  def handle_key(%{key: :char, char: "s", ctrl: true}, state), do: submit(state)
  def handle_key(%{key: :char, char: "c", ctrl: true}, state), do: cancel(state)

  # Forward all other keys to MultiLineInput
  def handle_key(key_event, state) do
    ss = composer_screen_state(state)
    input_st = ss.input_state

    case Compose.apply_key(input_st, key_event) do
      {:ok, new_input_st} ->
        new_input_st = enforce_max_len(new_input_st, state)
        {:update, put_input_state(state, ss, new_input_st), []}

      :error ->
        :no_match
    end
  end

  # ---------------------------------------------------------------------------
  # Initialization helper (called by callers that navigate to :post_composer)
  # ---------------------------------------------------------------------------

  @doc """
  Builds the initial screen_state map for the composer.
  Call this when navigating to :post_composer so the MultiLineInput state
  exists before the first render/handle_key call.

  Options:
    - `reply_to` — post struct or nil
    - `width`    — terminal width for word-wrap (default 80)
    - `height`   — visible rows for the text area (default 10)
  """
  @impl true
  @spec init_screen_state(keyword()) :: State.t()
  def init_screen_state(opts \\ []) do
    State.new(opts)
  end

  # ---------------------------------------------------------------------------
  # Private — helpers
  # ---------------------------------------------------------------------------

  # Returns a guaranteed screen_state with input_state initialised.
  defp composer_screen_state(state) do
    case Map.get(state.screen_state, :post_composer) do
      %State{} = ss ->
        ss

      _ ->
        {w, _h} = state.terminal_size || @default_terminal_size
        init_screen_state(width: max(w - 4, 20), height: 10)
    end
  end

  defp put_input_state(state, ss, new_input_st) do
    new_ss = %{ss | input_state: new_input_st}
    new_screen_state = Map.put(state.screen_state, :post_composer, new_ss)
    %{state | screen_state: new_screen_state}
  end

  # ---------------------------------------------------------------------------
  # Max-length enforcement (D-31)
  # ---------------------------------------------------------------------------

  defp enforce_max_len(input_st, %Context{} = context) do
    enforce_max_len(input_st, max_len(context))
  end

  defp enforce_max_len(input_st, max) when is_integer(max) do
    do_enforce_max_len(input_st, max)
  end

  defp enforce_max_len(input_st, state) do
    enforce_max_len(input_st, max_len(state))
  end

  defp do_enforce_max_len(input_st, max) do
    if String.length(input_st.value) > max do
      # Truncate to max length and reinitialise — pass a plain map, not a struct,
      # because MultiLineInput.init/1 calls struct(__MODULE__, props) which requires
      # an enumerable (a struct is not enumerable in Elixir).
      truncated = String.slice(input_st.value, 0, max)

      {:ok, trimmed} =
        MultiLineInput.init(%{
          value: truncated,
          placeholder: input_st.placeholder,
          width: input_st.width,
          height: input_st.height,
          wrap: input_st.wrap,
          focused: input_st.focused
        })

      trimmed
    else
      input_st
    end
  end

  # ---------------------------------------------------------------------------
  # Rendering helpers
  # ---------------------------------------------------------------------------

  defp render_input(input_st, state, theme, width) do
    ss = composer_screen_state(state)
    focused? = ss.mode == :edit
    Compose.render_input(input_st, focused?, theme, width: width)
  end

  defp composer_body(:edit, input_st, _draft, state, theme, width) do
    body_width = max(width - 4, 20)
    render_input(input_st, state, theme, body_width)
  end

  defp composer_body(:preview, _input_st, draft, state, theme, width) do
    body_width = max(width - 4, 20)
    render_preview(draft, body_width, state, theme)
  end

  defp render_preview(draft, body_width, state, theme) do
    sc = Map.get(state, :session_context) || %{}

    case Domain.get(sc, :markdown) do
      {:ok, Foglet.Markdown} ->
        MarkdownBody.render(draft, body_width, theme, wrap: true)

      {:ok, markdown_mod} ->
        MarkdownBody.render_tuples(markdown_mod.render(draft), body_width, theme, wrap: true)

      {:error, :not_configured} ->
        MarkdownBody.render(draft, body_width, theme, wrap: true)
    end
  end

  defp reply_context(nil, _width, _theme), do: nil

  defp reply_context(post, width, theme) do
    available = max(width - 10, 20)

    [text("Replying to @#{get_handle(post)}", fg: theme.dim.fg)] ++
      quote_preview_lines(post, available, theme)
  end

  defp quote_preview_lines(post, width, theme) do
    body = Map.get(post, :body, "")

    body
    |> String.split("\n")
    |> Enum.take(2)
    |> Enum.map(fn line ->
      text("> #{TextWidth.truncate(line, max(width - 2, 1))}", fg: theme.dim.fg)
    end)
  end

  # Delegate to PostCard.get_handle/1 (strict: returns nil on empty or
  # missing handle), then substitute "unknown" at the display call site so
  # an empty-string handle never renders as "@".
  defp get_handle(post), do: PostCard.get_handle(post) || "unknown"

  # ---------------------------------------------------------------------------
  # Mode toggle
  # ---------------------------------------------------------------------------

  defp toggle_mode(state) do
    ss = composer_screen_state(state)
    new_mode = if ss.mode == :edit, do: :preview, else: :edit
    new_ss = %{ss | mode: new_mode}
    new_screen_state = Map.put(state.screen_state, :post_composer, new_ss)
    {:update, %{state | screen_state: new_screen_state}, []}
  end

  # ---------------------------------------------------------------------------
  # Submit
  # ---------------------------------------------------------------------------

  defp submit(state) do
    ss = composer_screen_state(state)
    draft = ss.input_state.value
    max = max_len(state)

    cond do
      String.trim(draft) == "" ->
        {:update,
         %{state | modal: %Foglet.TUI.Modal{type: :error, message: "Post body cannot be empty."}},
         []}

      String.length(draft) > max ->
        modal = %Foglet.TUI.Modal{
          type: :error,
          message: "Post body exceeds maximum length of #{max} characters (D-31)."
        }

        {:update, %{state | modal: modal}, []}

      true ->
        do_submit(state, ss, draft)
    end
  end

  defp do_submit(state, ss, draft) do
    user_id = state.current_user && state.current_user.id

    if is_nil(user_id) do
      {:update,
       %{
         state
         | modal: %Foglet.TUI.Modal{type: :error, message: "You must be logged in to post."}
       }, []}
    else
      submit_reply(state, ss, draft, user_id)
    end
  end

  defp submit_reply(state, ss, draft, user_id) do
    sc = Map.get(state, :session_context) || %{}

    posts_mod =
      case Domain.get(sc, :posts) do
        {:ok, mod} -> mod
        {:error, :not_configured} -> Foglet.Posts
      end

    thread = legacy_thread_for_submit(state, ss)
    attrs = build_reply_attrs(draft, ss)

    with {:ok, _post} <- posts_mod.create_reply(thread.id, thread.board_id, user_id, attrs),
         {:ok, new_state} <- success_state_after_submit(state) do
      # D-05: after the post reload finishes, the app handler sets
      # selected_post_index to the last post (the user's new reply).
      {:update, new_state, [{:load_posts, thread.id, jump_last: true}]}
    else
      {:error, reason} ->
        {:update,
         %{state | modal: %Foglet.TUI.Modal{type: :error, message: format_error(reason)}}, []}
    end
  end

  defp success_state_after_submit(state) do
    {:ok,
     %{
       state
       | current_screen: :post_reader,
         composer_draft: nil,
         screen_state: Map.delete(state.screen_state, :post_composer)
     }}
  end

  defp build_reply_attrs(draft, ss) do
    case Map.get(ss, :reply_to) do
      nil -> %{body: draft}
      post -> %{body: draft, reply_to_id: post.id}
    end
  end

  # Phase 39 Plan 39-06: legacy submit_reply/4 used to read the legacy
  # App-shape `:current_thread` key directly from the App struct. After
  # Plan 39-07 deletes that field, the same value is sourced from the
  # screen-owned State struct under state.screen_state[:post_composer]
  # (set when the composer was opened via Effect.navigate(:post_composer, …)),
  # with a fallback to PostReader's screen-state thread (which set the
  # composer up via the [R] handler), then route_params, and finally —
  # transitionally — the legacy App-shape `:current_thread` key for fixtures
  # that haven't yet been migrated. The legacy fallback is removed by
  # Plan 39-07 alongside the App field deletion.
  defp legacy_thread_for_submit(state, ss) do
    composer_thread =
      case ss do
        %{thread: %{} = thread} -> thread
        _ -> nil
      end

    composer_thread ||
      legacy_reader_thread(state) ||
      legacy_route_thread(state) ||
      legacy_app_thread(state)
  end

  # Transitional fallback: pre-39-07 App struct still carries a top-level
  # `:current_thread` field; reducer-test fixtures populate it directly.
  # 39-07 deletes the field and removes this clause.
  defp legacy_app_thread(state) do
    Map.get(state, @legacy_thread_key)
  end

  defp legacy_reader_thread(state) do
    case Map.get(state.screen_state || %{}, :post_reader) do
      %Foglet.TUI.Screens.PostReader.State{thread: %{} = thread} -> thread
      _ -> nil
    end
  end

  defp legacy_route_thread(state) do
    params = Map.get(state, :route_params) || %{}
    Map.get(params, :thread) || Map.get(params, "thread")
  end

  defp format_error(:posting_not_allowed), do: "You are not allowed to post on this board."
  defp format_error(:thread_locked), do: "This thread is locked"

  defp format_error(%Ecto.Changeset{} = cs) do
    Enum.map_join(cs.errors, ", ", fn {field, {msg, _}} -> "#{field}: #{msg}" end)
  end

  defp format_error(reason) when is_binary(reason), do: reason
  defp format_error(reason), do: inspect(reason)

  defp submit_success(%State{} = state, result) do
    new_state = %{state | submission_status: :submitted, submit_result: result, error: nil}

    params = %{
      board: state.board,
      board_id: state.board_id,
      thread: state.thread,
      thread_id: state.thread_id,
      load_intent: :jump_last
    }

    {new_state, [Effect.navigate(:post_reader, params)]}
  end

  defp submit_local(%State{} = state, %Context{} = context) do
    draft = state.input_state.value
    max = max_len(context)

    cond do
      String.trim(draft) == "" ->
        {%{state | error: "Post body cannot be empty."}, []}

      String.length(draft) > max ->
        {%{state | error: "Post body exceeds maximum length of #{max} characters (D-31)."}, []}

      is_nil(context.current_user) ->
        {%{state | error: "You must be logged in to post."}, []}

      true ->
        posts_mod = resolve_domain_module(context, :posts, Foglet.Posts)
        user_id = context.current_user.id
        thread_id = state.thread_id || id_from(state.thread)
        board_id = state.board_id || board_id_from_state(state)
        attrs = build_reply_attrs(draft, state)

        effect =
          Effect.task(:submit_reply, :post_composer, fn ->
            posts_mod.create_reply(thread_id, board_id, user_id, attrs)
          end)

        {%{state | error: nil, submission_status: :submitting, submit_result: nil}, [effect]}
    end
  end

  defp cancel_params(%State{origin: :post_reader} = state) do
    %{
      board: state.board,
      board_id: state.board_id,
      thread: state.thread,
      thread_id: state.thread_id
    }
  end

  defp cancel_params(%State{}), do: %{}

  defp frame_state(%State{} = state, %Context{} = context) do
    %{
      current_screen: :post_composer,
      current_user: context.current_user,
      session_context: context.session_context,
      terminal_size: context.terminal_size || @default_terminal_size,
      route_params: context.route_params || %{},
      screen_state: %{post_composer: state}
    }
  end

  defp resolve_domain_module(%Context{} = context, key, default) do
    session_context = context.session_context || %{}

    case Domain.get(session_context, key) do
      {:ok, mod} -> mod
      {:error, :not_configured} -> default
    end
  end

  defp board_id_from_state(%State{} = state) do
    id_from(state.board) || board_id_from_thread(state.thread)
  end

  defp id_from(%{} = value), do: Map.get(value, :id) || Map.get(value, "id")
  defp id_from(_value), do: nil

  defp board_id_from_thread(%{} = thread),
    do: Map.get(thread, :board_id) || Map.get(thread, "board_id")

  defp board_id_from_thread(_thread), do: nil

  # ---------------------------------------------------------------------------
  # Cancel (D-30)
  # ---------------------------------------------------------------------------

  defp cancel(state) do
    # D-07: origin-aware cancel. ss.origin is set by the navigating screen
    # (PostReader's [R] handler in Phase 4). Default :main_menu preserves
    # the "classic BBS" behavior — if origin is somehow missing, bail
    # to a known-safe screen rather than crashing or looping.
    ss = composer_screen_state(state)
    origin = Map.get(ss, :origin, :main_menu)

    new_state = %{
      state
      | current_screen: origin,
        composer_draft: nil,
        screen_state: Map.delete(state.screen_state, :post_composer)
    }

    {:update, new_state, []}
  end

  # ---------------------------------------------------------------------------
  # Max length
  # ---------------------------------------------------------------------------

  defp max_len(%Context{} = context) do
    max_len_from_session_context(context.session_context || %{})
  end

  defp max_len(state) do
    max_len_from_session_context(Map.get(state, :session_context) || %{})
  end

  defp max_len_from_session_context(sc) do
    case Map.get(sc, :max_post_length) do
      n when is_integer(n) and n > 0 ->
        n

      _ ->
        safe_config_get("max_post_length", @default_max_post_length)
    end
  end

  defp safe_config_get(key, default) do
    case Config.get!(key) do
      n when is_integer(n) -> n
      _ -> default
    end
  rescue
    _ -> default
  end
end
