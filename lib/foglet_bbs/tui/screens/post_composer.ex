defmodule Foglet.TUI.Screens.PostComposer do
  @moduledoc """
  Post composer (SSH-07, D-26..D-31).

  Layout (D-27): header, quote context (when replying), text area, key bar.
  Tab toggles edit/preview (D-28). Ctrl+S submits (D-29). Ctrl+C cancels (D-30).
  Max body length enforced via Foglet.Config.get!("max_post_length") (D-31).
  """

  alias Foglet.Config
  alias Foglet.TUI.Widgets.{KeyBar, StatusBar}

  import Raxol.Core.Renderer.View

  @default_max_post_length 8192

  @spec render(map()) :: any()
  def render(state) do
    ss =
      get_in(state.screen_state, [:post_composer]) ||
        %{mode: :edit, reply_to: nil, error: nil}

    draft = state.composer_draft || ""

    body_items =
      if ss.reply_to do
        [
          text("Replying to @#{get_handle(ss.reply_to)}:", color: :bright_black),
          text(quote_preview(ss.reply_to), color: :bright_black),
          text("")
        ]
      else
        []
      end ++
        case ss.mode do
          :edit -> [text(draft, color: :green)]
          :preview -> [text(render_preview(state, draft), color: :green)]
        end ++
        if ss.error do
          [text(""), text(ss.error, color: :red)]
        else
          []
        end ++
        [
          text(""),
          text("#{String.length(draft)} / #{max_len(state)} chars", color: :bright_black)
        ]

    panel(
      title: title_for(ss.reply_to, state.current_thread),
      border: :single,
      children: [
        StatusBar.render(%{
          handle: state.current_user && state.current_user.handle,
          location: "Composer (#{ss.mode})"
        }),
        box(children: body_items),
        KeyBar.render([
          {"Tab", if(ss.mode == :edit, do: "Preview", else: "Edit")},
          {"Ctrl+S", "Send"},
          {"Ctrl+C", "Cancel"}
        ])
      ]
    )
  end

  @spec handle_key(map(), map()) :: {:update, map(), list()} | :no_match
  def handle_key(%{key: "tab"}, state), do: toggle_mode(state)

  def handle_key(%{key: "ctrl_s"}, state), do: submit(state)
  def handle_key(%{key: "ctrl_c"}, state), do: cancel(state)

  def handle_key(%{key: "backspace"}, state) do
    draft = state.composer_draft || ""
    new_draft = String.slice(draft, 0, max(String.length(draft) - 1, 0))
    {:update, %{state | composer_draft: new_draft}, []}
  end

  def handle_key(%{key: "enter"}, state) do
    draft = state.composer_draft || ""
    {:update, %{state | composer_draft: draft <> "\n"}, []}
  end

  def handle_key(%{key: key}, state) when is_binary(key) and byte_size(key) == 1 do
    draft = state.composer_draft || ""
    {:update, %{state | composer_draft: draft <> key}, []}
  end

  def handle_key(_key, _state), do: :no_match

  # --- Private ---

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

  defp toggle_mode(state) do
    ss =
      get_in(state.screen_state, [:post_composer]) ||
        %{mode: :edit, reply_to: nil, error: nil}

    new_mode = if ss.mode == :edit, do: :preview, else: :edit
    new_screen_state = Map.put(state.screen_state, :post_composer, %{ss | mode: new_mode})
    {:update, %{state | screen_state: new_screen_state}, []}
  end

  defp submit(state) do
    draft = state.composer_draft || ""
    ss = get_in(state.screen_state, [:post_composer]) || %{reply_to: nil}
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

    if function_exported?(posts_mod, :create_reply, 3) && state.current_thread do
      attrs = %{body: draft}

      reply_to_id = ss[:reply_to] && ss[:reply_to].id
      attrs = if reply_to_id, do: Map.put(attrs, :reply_to_id, reply_to_id), else: attrs

      case posts_mod.create_reply(state.current_thread, state.current_user, attrs) do
        {:ok, _post} ->
          new_state = %{
            state
            | current_screen: :post_reader,
              composer_draft: nil,
              screen_state: Map.delete(state.screen_state, :post_composer)
          }

          {:update, new_state, [{:load_posts, state.current_thread.id}]}

        {:error, _cs} ->
          {:update, %{state | modal: %{type: :error, message: "Failed to create post."}}, []}
      end
    else
      # Dev-mode stub: Phase 2 not yet wired
      modal = %{type: :info, message: "Submitted (dev-mode; Phase 2 not fully wired)."}

      new_state = %{
        state
        | modal: modal,
          current_screen: :thread_list,
          composer_draft: nil,
          screen_state: Map.delete(state.screen_state, :post_composer)
      }

      {:update, new_state, []}
    end
  end

  defp cancel(state) do
    # D-30: immediate cancel, no confirmation
    new_state = %{
      state
      | current_screen: :thread_list,
        composer_draft: nil,
        screen_state: Map.delete(state.screen_state, :post_composer)
    }

    {:update, new_state, []}
  end

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
