defmodule Foglet.TUI.Screens.PostReader.Render do
  @moduledoc """
  Pure render entry point for the PostReader screen.

  This module owns frame/content/keybar assembly for the reader while the
  top-level `PostReader` module keeps reducer logic, task effects, read-pointer
  flushing, and render-cache mutation.
  """

  alias Foglet.TUI.{Context, Guest}
  alias Foglet.TUI.Screens.PostReader
  alias Foglet.TUI.Screens.PostReader.State
  alias Foglet.TUI.TextWidth
  alias Foglet.TUI.Theme
  alias Foglet.TUI.Widgets.Chrome.ScreenFrame
  alias Foglet.TUI.Widgets.Post.PostCard
  alias Foglet.TUI.Widgets.Progress.Spinner
  alias Raxol.UI.Components.Display.Viewport

  import Raxol.Core.Renderer.View

  def render(%State{} = state, %Context{} = context) do
    frame_state = frame_state(state, context)
    theme = Theme.from_state(frame_state)
    {w, h} = context.terminal_size
    locked? = PostReader.locked_thread?(state)
    archived? = PostReader.archived_board?(state)
    reply_state = reply_state(locked?, archived?)
    post_content = render_local_post_content(state, frame_state, theme, w, h, reply_state)

    chrome = %{
      breadcrumb_parts: ["Foglet", board_label(state), thread_title_label(state)]
    }

    ScreenFrame.render(frame_state, chrome, post_content, [
      %{
        label: "Navigate",
        commands: navigation_commands(state, context)
      },
      %{
        label: "Actions",
        commands: action_commands(reply_state, context)
      },
      %{
        label: "System",
        commands: [%{key: "Q", label: "Back", priority: 0}]
      }
    ])
  end

  defp reply_state(true, _archived?), do: :locked
  defp reply_state(false, true), do: :archived
  defp reply_state(false, false), do: :open

  defp navigation_commands(%State{} = state, %Context{} = context) do
    base_commands = [
      %{key: "N", label: "Next", priority: 10},
      %{key: "P", label: "Prev", priority: 10}
    ]

    case PostReader.visible_screenful(state, context) do
      %{mode: :packed_partial, indexes: indexes, partial: partial} = sf ->
        cmds = [%{key: "Up/Down", label: "Select", priority: 6} | base_commands]

        # FOG-652 / FOG-651: only advertise J/K Scroll when the partial long
        # post is the current action target — keep the keybar restrained for
        # ordinary packed short-post selection.
        if length(indexes) > 1 and action_index(state, sf) == partial.index do
          cmds ++ [%{key: "↑/↓", label: "Scroll", priority: 8}]
        else
          cmds
        end

      %{mode: :packed, indexes: indexes} when length(indexes) > 1 ->
        [%{key: "Up/Down", label: "Select", priority: 6} | base_commands]

      %{mode: :packed} ->
        # FOG-694: at the cramped FOG-651 negative threshold the screenful
        # carries a single packed short card with no partial region, so J is
        # a no-op (`viewport.scroll_top` stays 0 and `partial_scroll_tops`
        # stays empty). Do not advertise J/K Scroll in that state.
        base_commands

      _long ->
        base_commands ++ [%{key: "↑/↓", label: "Scroll", priority: 10}]
    end
  end

  defp action_commands(reply_state, %Context{} = context) do
    if Guest.guest?(context), do: [], else: [upvote_command(), reply_command(reply_state)]
  end

  defp upvote_command, do: %{key: "U", label: "Upvote", priority: 8}

  defp reply_command(:locked), do: %{key: "R", label: "Reply (locked)", priority: 5}
  defp reply_command(:archived), do: %{key: "R", label: "Reply (archived)", priority: 5}
  defp reply_command(:open), do: %{key: "R", label: "Reply", priority: 5}

  @doc false
  @spec frame_state(State.t(), Context.t()) :: map()
  def frame_state(%State{} = state, %Context{} = context) do
    # `posts:` is a plain-map key consumed by the shared render_post_content/5
    # helper; its value is read from `%State{}.posts` (the new-contract
    # screen-owned field, which survives the 39-07 struct cleanup). It is
    # NOT the deleted `%App{}.posts` field — see 39-RESEARCH Pitfall 5. The
    # `Map.get/2` access form keeps the post-39-07 grep audit
    # (`grep` for legacy app-shape dot-access) clean.
    %{
      current_user: context.current_user,
      current_screen: :post_reader,
      posts: Map.get(state, :posts),
      session_context: context.session_context,
      terminal_size: context.terminal_size,
      route_params: context.route_params,
      screen_state: %{post_reader: state}
    }
  end

  defp board_label(%State{board: %{name: name}}) when is_binary(name), do: name
  defp board_label(%State{}), do: "Boards"

  defp thread_title_label(%State{thread: %{title: title}}) when is_binary(title), do: title
  defp thread_title_label(%State{}), do: "Thread"

  defp render_post_content(%{posts: posts}, _ss, theme, _w, _h)
       when posts in [[], nil] do
    render_loading(theme)
  end

  defp render_post_content(frame_view, ss, theme, w, h) do
    posts = frame_view.posts
    total = length(posts)
    idx = ss.selected_post_index

    if idx >= total do
      column style: %{gap: 0} do
        [text("You're at the end of this thread.", fg: theme.warning.fg)]
      end
    else
      screenful = PostReader.visible_screenful(ss, context_from_frame_view(frame_view, w, h))

      case screenful.mode do
        :long ->
          render_long_post(frame_view, ss, theme, w, screenful, total)

        mode when mode in [:packed, :packed_partial] ->
          render_packed_posts(frame_view, ss, theme, w, screenful, total)
      end
    end
  end

  defp render_long_post(frame_view, ss, theme, w, screenful, total) do
    post = Enum.at(frame_view.posts, List.first(screenful.indexes) || ss.selected_post_index)

    tuples =
      case ss.render_cache[{post.id, w}] do
        nil -> PostReader.body_tuples_for(frame_view, post)
        cached -> cached
      end

    parts = reader_parts(post, tuples, w, theme, ss.selected_post_index, total)

    # Wire visible_height and children for this frame. render_post_content
    # is a read-only function — the Viewport state built here is transient,
    # not written back into screen_state. State-writing happens in
    # scroll_post / advance_post / load_posts via warm_viewport.
    {vp, _cmds} = Viewport.update({:set_visible_height, screenful.available_height}, ss.viewport)
    {vp, _cmds} = Viewport.update({:set_children, parts.body_lines}, vp)
    body_rendered = Viewport.render(vp, %{})

    column style: %{gap: 0} do
      [parts.header, parts.progress, body_rendered]
    end
  end

  defp render_packed_posts(frame_view, ss, theme, w, screenful, total) do
    partial_idx =
      case screenful do
        %{mode: :packed_partial, partial: %{index: i}} -> i
        _ -> nil
      end

    children =
      screenful.indexes
      |> Enum.with_index()
      |> Enum.flat_map(fn {idx, position} ->
        post = Enum.at(frame_view.posts, idx)

        tuples =
          case ss.render_cache[{post.id, w}] do
            nil -> PostReader.body_tuples_for(frame_view, post)
            cached -> cached
          end

        selected_action? = idx == action_index(ss, screenful)
        parts = reader_parts(post, tuples, w, theme, idx, total, action_target?: selected_action?)

        {progress_node, body_nodes} =
          if idx == partial_idx do
            partial = screenful.partial

            body_nodes =
              parts.body_lines
              |> Enum.slice(partial.scroll_top, partial.body_visible_rows)

            {partial_progress(idx, total, partial, selected_action?, w, theme), body_nodes}
          else
            {parts.progress, parts.body_lines}
          end

        prefix = if position == 0, do: [], else: [packed_post_separator(theme)]
        prefix ++ [parts.header, progress_node | body_nodes]
      end)

    column style: %{gap: 0} do
      children
    end
  end

  # FOG-652 / FOG-651: progress/affordance line for a partial long post.
  # Selected: explicit J/K hint plus a visible slice indicator (or `end of
  # post` when scrolled to the bottom).
  # Unselected: a dim `More below` so the user knows there is unread content
  # below the visible slice without claiming any keyboard affordance.
  defp partial_progress(index, total, partial, selected?, w, theme) do
    label = partial_progress_label(index, total, partial, selected?)
    fg = if selected?, do: theme.accent.fg, else: theme.dim.fg

    text(TextWidth.truncate(label, max(w - 2, 1)), fg: fg)
  end

  defp partial_progress_label(index, total, partial, true) do
    cond do
      partial.total_body_rows <= 0 ->
        "Posts #{index + 1}/#{total}  ▶ Selected — J/K scroll"

      PostReader.partial_at_bottom?(partial) ->
        "Posts #{index + 1}/#{total}  ▶ Selected — end of post"

      true ->
        first = partial.scroll_top + 1

        last =
          (partial.scroll_top + partial.body_visible_rows)
          |> min(partial.total_body_rows)

        "Posts #{index + 1}/#{total}  ▶ Selected — J/K scroll • lines #{first}-#{last}/#{partial.total_body_rows}"
    end
  end

  defp partial_progress_label(index, total, partial, false) do
    if PostReader.partial_at_bottom?(partial) do
      "Posts #{index + 1}/#{total}"
    else
      "Posts #{index + 1}/#{total}  More below"
    end
  end

  defp packed_post_separator(theme), do: divider(char: "─", style: %{fg: theme.border.fg})

  defp context_from_frame_view(frame_view, w, h) do
    Context.new(
      current_user: Map.get(frame_view, :current_user),
      session_context: Map.get(frame_view, :session_context) || %{},
      terminal_size: {w, h},
      route: Map.get(frame_view, :current_screen) || :post_reader,
      route_params: Map.get(frame_view, :route_params) || %{}
    )
  end

  defp render_local_post_content(
         %State{status: :loading},
         _frame_state,
         theme,
         _w,
         _h,
         _reply_state
       ),
       do: render_loading(theme)

  defp render_local_post_content(%State{status: :empty}, _frame_state, theme, _w, _h, reply_state) do
    column style: %{gap: 0} do
      Enum.reject(
        [
          reply_notice(theme, reply_state),
          text("This thread has no readable posts.", fg: theme.warning.fg)
        ],
        &is_nil/1
      )
    end
  end

  defp render_local_post_content(
         %State{status: {:error, _}},
         _frame_state,
         theme,
         _w,
         _h,
         reply_state
       ) do
    column style: %{gap: 0} do
      Enum.reject(
        [
          reply_notice(theme, reply_state),
          text("Couldn't load posts. Press Q to back out and try again.", fg: theme.error.fg)
        ],
        &is_nil/1
      )
    end
  end

  defp render_local_post_content(%State{} = state, frame_state, theme, w, h, reply_state) do
    body = render_post_content(frame_state, state, theme, w, h)

    case reply_notice(theme, reply_state) do
      nil ->
        body

      notice ->
        column style: %{gap: 0} do
          [notice, body]
        end
    end
  end

  defp reply_notice(_theme, :open), do: nil

  defp reply_notice(theme, :locked) do
    text("Thread locked — replies disabled.", fg: theme.warning.fg)
  end

  defp reply_notice(theme, :archived) do
    text("Archived board — replies are closed.", fg: theme.warning.fg)
  end

  # Spinner-based loading affordance used when posts is nil/[]
  # (post_reader was opened but {:posts_loaded, posts} hasn't landed yet).
  # One-row composition: gap-1 row with spinner glyph + label text.
  # Row count is identical to the old plain-text path — no visible row growth (D-05, D-06).
  defp render_loading(theme) do
    frame = System.monotonic_time(:millisecond) |> abs() |> div(Spinner.frame_duration_ms())

    column style: %{gap: 0} do
      [
        row style: %{gap: 1} do
          [
            Spinner.render(frame, style: :line, theme: theme),
            text("Loading…", fg: theme.dim.fg)
          ]
        end
      ]
    end
  end

  defp action_index(ss, %{mode: mode, indexes: indexes})
       when mode in [:packed, :packed_partial] and length(indexes) > 1 do
    idx = Map.get(ss, :selected_action_post_index, ss.selected_post_index)

    if idx in indexes do
      idx
    else
      List.first(indexes)
    end
  end

  defp action_index(ss, _screenful), do: ss.selected_post_index

  defp reader_parts(post, tuples, w, theme, idx, total, opts \\ []) do
    PostCard.reader_parts(post, tuples, w, theme, Keyword.merge([index: idx, total: total], opts))
  end
end
