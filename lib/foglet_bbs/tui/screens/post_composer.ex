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
  `state.screen_state[:post_composer]`. The pre-39-07 App-level
  `composer_draft` slot has been deleted; draft text always reads from
  `input_state.value`, and submit/cancel discard the per-screen state via
  `Map.delete(state.screen_state, :post_composer)`.
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

  # ---------------------------------------------------------------------------
  # Private — helpers
  # ---------------------------------------------------------------------------

  # ---------------------------------------------------------------------------
  # Max-length enforcement (D-31)
  # ---------------------------------------------------------------------------

  defp enforce_max_len(input_st, %Context{} = context) do
    enforce_max_len(input_st, max_len(context))
  end

  defp enforce_max_len(input_st, max) when is_integer(max) do
    do_enforce_max_len(input_st, max)
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
    focused? = state.mode == :edit
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

  defp build_reply_attrs(draft, ss) do
    case Map.get(ss, :reply_to) do
      nil -> %{body: draft}
      post -> %{body: draft, reply_to_id: post.id}
    end
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

  defp max_len(%Context{} = context) do
    max_len_from_session_context(context.session_context || %{})
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
