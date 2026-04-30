defmodule Foglet.TUI.Screens.PostReader.Render do
  @moduledoc """
  Pure render entry point for the PostReader screen.

  This module owns frame/content/keybar assembly for the reader while the
  top-level `PostReader` module keeps reducer logic, task effects, read-pointer
  flushing, and render-cache mutation.
  """

  alias Foglet.TUI.Context
  alias Foglet.TUI.Screens.PostReader
  alias Foglet.TUI.Screens.PostReader.State
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
    post_content = render_local_post_content(state, frame_state, theme, w, h)

    chrome = %{
      breadcrumb_parts: ["Foglet", board_label(state), thread_title_label(state)]
    }

    ScreenFrame.render(frame_state, chrome, post_content, [
      %{
        label: "Navigate",
        commands: [
          %{key: "N", label: "Next", priority: 10},
          %{key: "P", label: "Prev", priority: 10},
          %{key: "J", label: "Scroll ↓", priority: 10},
          %{key: "K", label: "Scroll ↑", priority: 10}
        ]
      },
      %{
        label: "Actions",
        commands: [%{key: "R", label: "Reply", priority: 30}]
      },
      %{
        label: "System",
        commands: [%{key: "Q", label: "Back", priority: 0}]
      }
    ])
  end

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
        [text("No more posts.", fg: theme.warning.fg)]
      end
    else
      post = Enum.at(posts, idx)
      available_height = max(h - 12, 5)

      tuples =
        case ss.render_cache[{post.id, w}] do
          nil -> PostReader.body_tuples_for(frame_view, post)
          cached -> cached
        end

      parts = reader_parts(post, tuples, w, theme, idx, total)

      # Wire visible_height and children for this frame. render_post_content
      # is a read-only function — the Viewport state built here is transient,
      # not written back into screen_state. State-writing happens in
      # scroll_post / advance_post / load_posts via warm_viewport.
      {vp, _cmds} = Viewport.update({:set_visible_height, available_height}, ss.viewport)
      {vp, _cmds} = Viewport.update({:set_children, parts.body_lines}, vp)
      body_rendered = Viewport.render(vp, %{})

      column style: %{gap: 0} do
        [parts.header, parts.progress, body_rendered]
      end
    end
  end

  defp render_local_post_content(%State{status: :loading}, _frame_state, theme, _w, _h),
    do: render_loading(theme)

  defp render_local_post_content(%State{status: :empty}, _frame_state, theme, _w, _h) do
    column style: %{gap: 0} do
      [text("No more posts.", fg: theme.warning.fg)]
    end
  end

  defp render_local_post_content(%State{status: {:error, _}}, _frame_state, theme, _w, _h) do
    column style: %{gap: 0} do
      [text("Unable to load posts.", fg: theme.error.fg)]
    end
  end

  defp render_local_post_content(%State{} = state, frame_state, theme, w, h) do
    render_post_content(frame_state, state, theme, w, h)
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

  defp reader_parts(post, tuples, w, theme, idx, total) do
    PostCard.reader_parts(post, tuples, w, theme, index: idx, total: total)
  end
end
