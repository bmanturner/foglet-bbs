defmodule Foglet.TUI.Screens.PostComposer do
  @moduledoc """
  Post composer (SSH-07, D-26..D-31).

  Layout (D-27): header, quote context (when replying), text area, key bar.
  Tab toggles edit/preview (D-28). Ctrl+S submits (D-29). Ctrl+C cancels (D-30).
  Max body length enforced via Foglet.Config.get!("max_post_length") (D-31).

  Uses `Raxol.UI.Components.Input.MultiLineInput` component module (D-26) for
  the full-featured editor: cursor, word wrap, undo/redo, shift-select.
  Component state is stored in `state.screen_state[:post_composer].input_state`.
  `state.composer_draft` is NOT used for reading text — we always read from
  `input_state.value`. The struct field remains on App but is set to nil by
  cancel/submit to signal no active draft (unchanged contract).
  """

  alias Foglet.Config
  alias Foglet.TUI.Screens.Domain
  alias Foglet.TUI.Theme
  alias Foglet.TUI.Widgets.Chrome.ScreenFrame
  alias Foglet.TUI.Widgets.Compose
  alias Foglet.TUI.Widgets.Post.MarkdownBody
  alias Foglet.TUI.Widgets.Post.PostCard
  alias Raxol.UI.Components.Input.MultiLineInput

  import Raxol.Core.Renderer.View

  @default_max_post_length 8192
  @default_terminal_size {80, 24}

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @spec render(map()) :: any()
  def render(state) do
    ss = composer_screen_state(state)
    input_st = ss.input_state
    draft = input_st.value
    theme = Theme.from_state(state)

    body_items =
      if ss.reply_to do
        [
          text("Replying to @#{get_handle(ss.reply_to)}:", fg: theme.dim.fg),
          text(quote_preview(ss.reply_to), fg: theme.dim.fg),
          text("")
        ]
      else
        []
      end ++
        case ss.mode do
          :edit ->
            [render_input(input_st, state, theme)]

          :preview ->
            {w, _h} = state.terminal_size || @default_terminal_size
            body_width = max(w - 4, 20)
            [MarkdownBody.render(draft, body_width, theme)]
        end ++
        if ss.error do
          [text(""), text(ss.error, fg: theme.error.fg, style: [:bold])]
        else
          []
        end ++
        [
          text(""),
          text("#{String.length(draft)} / #{max_len(state)} chars", fg: theme.dim.fg)
        ]

    content =
      column style: %{gap: 0} do
        body_items
      end

    ScreenFrame.render(state, title_for(ss.reply_to, state.current_thread), content, [
      {"Tab", if(ss.mode == :edit, do: "Preview", else: "Edit")},
      {"Ctrl+S", "Send"},
      {"Ctrl+C", "Cancel"}
    ])
  end

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
  @spec init_screen_state(keyword()) :: map()
  def init_screen_state(opts \\ []) do
    reply_to = Keyword.get(opts, :reply_to, nil)
    width = Keyword.get(opts, :width, 80)
    height = Keyword.get(opts, :height, 10)

    {:ok, input_st} =
      MultiLineInput.init(%{
        value: "",
        placeholder: "Write your post…",
        width: width,
        height: height,
        wrap: :none,
        focused: true
      })

    %{mode: :edit, reply_to: reply_to, error: nil, input_state: input_st}
  end

  # ---------------------------------------------------------------------------
  # Private — helpers
  # ---------------------------------------------------------------------------

  # Returns a guaranteed screen_state with input_state initialised.
  defp composer_screen_state(state) do
    case get_in(state.screen_state, [:post_composer]) do
      %{input_state: _} = ss ->
        ss

      existing ->
        base = existing || %{mode: :edit, reply_to: nil, error: nil}
        {w, _h} = state.terminal_size || @default_terminal_size

        {:ok, input_st} =
          MultiLineInput.init(%{
            value: "",
            placeholder: "Write your post…",
            width: max(w - 4, 20),
            height: 10,
            wrap: :none,
            focused: true
          })

        Map.put(base, :input_state, input_st)
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

  defp title_for(nil, nil), do: "New Thread"
  defp title_for(nil, thread), do: "Reply to: #{thread.title}"
  defp title_for(reply_to, _), do: "Reply to post ##{Map.get(reply_to, :message_number, "?")}"

  defp quote_preview(post) do
    body = Map.get(post, :body, "")

    body
    |> String.split("\n")
    |> Enum.take(5)
    |> Enum.map_join("\n", fn line -> "> #{line}" end)
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
      {:error, _cs} ->
        {:update,
         %{state | modal: %Foglet.TUI.Modal{type: :error, message: "Failed to create post."}}, []}
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
