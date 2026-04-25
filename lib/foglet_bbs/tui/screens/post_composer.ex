defmodule Foglet.TUI.Screens.PostComposer do
  @moduledoc """
  Post composer (SSH-07, D-26..D-31).

  Layout (D-27): header, quote context (when replying), text area, key bar.
  Tab toggles edit/preview (D-28). Ctrl+S submits (D-29). Ctrl+C cancels (D-30).
  Max body length enforced via Foglet.Config.get!("max_post_length") (D-31).

  Uses `Raxol.UI.Components.Input.MultiLineInput` component module (D-26) for
  the full-featured editor: cursor, word wrap, undo/redo, shift-select.
  Component state is stored in `%PostComposer.State{}.input_state` at
  `state.screen_state[:post_composer]`.
  `state.composer_draft` is NOT used for reading text — we always read from
  `input_state.value`. The struct field remains on App but is set to nil by
  cancel/submit to signal no active draft (unchanged contract).
  """

  @behaviour Foglet.TUI.Screen

  alias Foglet.Config
  alias Foglet.TUI.Screens.Domain
  alias Foglet.TUI.Screens.PostComposer.State
  alias Foglet.TUI.Theme
  alias Foglet.TUI.TextWidth
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
  @spec render(map()) :: any()
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
  # NOTE: PostComposer handle_key/2 clause order is load-bearing:
  # keep :tab/Ctrl+S/Ctrl+C above fallback forwarding.
  def handle_key(%{key: :tab}, state), do: toggle_mode(state)
  def handle_key(%{key: :char, char: "s", ctrl: true}, state), do: submit(state)
  def handle_key(%{key: :char, char: "c", ctrl: true}, state), do: cancel(state)

  # Forward all other keys to MultiLineInput
  def handle_key(key_event, state) do
    case Compose.translate_key(key_event) do
      nil ->
        :no_match

      msg ->
        ss = composer_screen_state(state)
        input_st = ss.input_state

        case MultiLineInput.update(msg, input_st) do
          {:noreply, new_input_st, _cmds} ->
            new_input_st = enforce_max_len(new_input_st, state)
            {:update, put_input_state(state, ss, new_input_st), []}

          # update/2 occasionally returns a plain state struct (e.g., focus/blur)
          new_input_st when is_struct(new_input_st, MultiLineInput) ->
            new_input_st = enforce_max_len(new_input_st, state)
            {:update, put_input_state(state, ss, new_input_st), []}

          _other ->
            :no_match
        end
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

  defp enforce_max_len(input_st, state) do
    max = max_len(state)

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

  defp render_input(input_st, state, theme) do
    ss = composer_screen_state(state)
    focused? = ss.mode == :edit
    Compose.render_input(input_st, focused?, theme)
  end

  defp composer_body(:edit, input_st, _draft, state, theme, _width),
    do: render_input(input_st, state, theme)

  defp composer_body(:preview, _input_st, draft, state, theme, width) do
    body_width = max(width - 4, 20)
    render_preview(draft, body_width, state, theme)
  end

  defp render_preview(draft, body_width, state, theme) do
    sc = Map.get(state, :session_context) || %{}

    case Domain.get(sc, :markdown) do
      {:ok, Foglet.Markdown} ->
        MarkdownBody.render(draft, body_width, theme)

      {:ok, markdown_mod} ->
        MarkdownBody.render_tuples(markdown_mod.render(draft), body_width, theme)

      {:error, :not_configured} ->
        MarkdownBody.render(draft, body_width, theme)
    end
  end

  defp reply_context(nil, _width, _theme), do: nil

  defp reply_context(post, width, theme) do
    available = max(width - 10, 20)

    [
      text("Replying to @#{get_handle(post)}", fg: theme.dim.fg),
      text(quote_preview(post, available), fg: theme.dim.fg)
    ]
  end

  defp quote_preview(post, width) do
    body = Map.get(post, :body, "")

    body
    |> String.split("\n")
    |> Enum.take(2)
    |> Enum.map_join("\n", fn line -> "> #{TextWidth.truncate(line, width)}" end)
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

    thread = state.current_thread
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

  defp format_error(:posting_not_allowed), do: "You are not allowed to post on this board."
  defp format_error(:thread_locked), do: "This thread is locked"

  defp format_error(%Ecto.Changeset{} = cs) do
    Enum.map_join(cs.errors, ", ", fn {field, {msg, _}} -> "#{field}: #{msg}" end)
  end

  defp format_error(reason) when is_binary(reason), do: reason
  defp format_error(reason), do: inspect(reason)

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

  defp max_len(state) do
    sc = Map.get(state, :session_context) || %{}

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
