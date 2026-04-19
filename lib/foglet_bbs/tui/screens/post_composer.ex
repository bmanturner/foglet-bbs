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
  alias Foglet.TUI.Input
  alias Foglet.TUI.Widgets.{KeyBar, StatusBar}
  alias Raxol.UI.Components.Input.MultiLineInput

  import Raxol.Core.Renderer.View

  @default_max_post_length 8192

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @spec render(map()) :: any()
  def render(state) do
    ss = composer_screen_state(state)
    input_st = ss.input_state
    draft = input_st.value

    body_items =
      if ss.reply_to do
        [
          text("Replying to @#{get_handle(ss.reply_to)}:", style: [:dim]),
          text(quote_preview(ss.reply_to), style: [:dim]),
          text("")
        ]
      else
        []
      end ++
        case ss.mode do
          :edit ->
            # Render the MultiLineInput component inline using its lines.
            # render/2 requires a context map; we supply a minimal one.
            [render_input(input_st, state)]

          :preview ->
            [text(render_preview(state, draft), fg: :green)]
        end ++
        if ss.error do
          [text(""), text(ss.error, fg: :red)]
        else
          []
        end ++
        [
          text(""),
          text("#{String.length(draft)} / #{max_len(state)} chars", style: [:dim])
        ]

    box style: %{border: :single, padding: 1} do
      column style: %{gap: 0} do
        [
          text(" #{title_for(ss.reply_to, state.current_thread)} ", style: [:bold]),
          divider(),
          StatusBar.render(%{
            handle: state.current_user && state.current_user.handle,
            location: "Composer (#{ss.mode})"
          }),
          column style: %{gap: 0} do
            body_items
          end,
          KeyBar.render([
            {"Tab", if(ss.mode == :edit, do: "Preview", else: "Edit")},
            {"Ctrl+S", "Send"},
            {"Ctrl+C", "Cancel"}
          ])
        ]
      end
    end
  end

  @spec handle_key(map(), map()) :: {:update, map(), list()} | :no_match
  def handle_key(%{key: :tab}, state), do: toggle_mode(state)
  def handle_key(%{key: :char, char: "s", ctrl: true}, state), do: submit(state)
  def handle_key(%{key: :char, char: "c", ctrl: true}, state), do: cancel(state)

  # Forward all other keys to MultiLineInput
  def handle_key(key_event, state) do
    case Input.translate_key(key_event) do
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
        {w, _h} = state.terminal_size || {80, 24}

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

  defp render_input(input_st, state) do
    ss = composer_screen_state(state)
    focused? = ss.mode == :edit
    render_input_as_text(input_st, focused?)
  end

  # Renders the MultiLineInput state as plain text/2 elements inside a column.
  # cursor_pos is {row, col} — confirmed from MultiLineInput struct definition.
  # This bypasses MultiLineInput.render/2, which returns tuple-shaped elements
  # that crash Flexbox.measure_flex_child/3 (Bug B).
  defp render_input_as_text(input_st, focused?) do
    lines =
      input_st.value
      |> String.split("\n")
      |> case do
        [] -> [""]
        ls -> ls
      end

    {cursor_row, cursor_col} = Map.get(input_st, :cursor_pos, {0, 0})

    column style: %{gap: 0} do
      lines
      |> Enum.with_index()
      |> Enum.map(fn {line, idx} ->
        rendered =
          if focused? and idx == cursor_row do
            {before, after_} = String.split_at(line, cursor_col)
            "#{before}█#{after_}"
          else
            line
          end

        text(rendered, fg: :green)
      end)
    end
  end

  defp title_for(nil, nil), do: "New Thread"
  defp title_for(nil, thread), do: "Reply to: #{thread.title}"
  defp title_for(reply_to, _), do: "Reply to post ##{Map.get(reply_to, :message_number, "?")}"

  defp render_preview(state, draft) do
    sc = Map.get(state, :session_context) || %{}
    markdown_mod = get_in(sc, [:domain, :markdown]) || Foglet.Markdown

    if function_exported?(markdown_mod, :render, 1) do
      markdown_mod.render(draft)
    else
      draft
    end
  end

  defp quote_preview(post) do
    body = Map.get(post, :body, "")

    body
    |> String.split("\n")
    |> Enum.take(5)
    |> Enum.map_join("\n", fn line -> "> #{line}" end)
  end

  defp get_handle(%{user: %{handle: h}}), do: h
  defp get_handle(_), do: "unknown"

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
        {:update, %{state | modal: %{type: :error, message: "Post body cannot be empty."}}, []}

      String.length(draft) > max ->
        modal = %{
          type: :error,
          message: "Post body exceeds maximum length of #{max} characters (D-31)."
        }

        {:update, %{state | modal: modal}, []}

      true ->
        do_submit(state, ss, draft)
    end
  end

  defp do_submit(state, ss, draft) do
    sc = Map.get(state, :session_context) || %{}
    posts_mod = get_in(sc, [:domain, :posts]) || Foglet.Posts
    thread = state.current_thread

    attrs = %{body: draft}
    reply_to_id = ss[:reply_to] && ss[:reply_to].id
    attrs = if reply_to_id, do: Map.put(attrs, :reply_to_id, reply_to_id), else: attrs

    case posts_mod.create_reply(thread.id, thread.board_id, state.current_user.id, attrs) do
      {:ok, _post} ->
        new_state = %{
          state
          | current_screen: :post_reader,
            composer_draft: nil,
            screen_state: Map.delete(state.screen_state, :post_composer)
        }

        {:update, new_state, [{:load_posts, thread.id}]}

      {:error, _cs} ->
        {:update, %{state | modal: %{type: :error, message: "Failed to create post."}}, []}
    end
  end

  # ---------------------------------------------------------------------------
  # Cancel (D-30)
  # ---------------------------------------------------------------------------

  defp cancel(state) do
    new_state = %{
      state
      | current_screen: :thread_list,
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
