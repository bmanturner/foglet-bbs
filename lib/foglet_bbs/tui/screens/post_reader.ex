defmodule Foglet.TUI.Screens.PostReader do
  @moduledoc """
  Post reader for a single thread (SSH-07, SSH-08, SSH-09).

  Renders posts via Foglet.Markdown.render/1. Paginates with n/p keys.
  Local read-pointer state (state.read_position) updates on each advance;
  flush to DB happens on screen transition via {:flush_read_pointers, ctx}
  command handled by TUI.App.update/2 (SSH-09).
  """

  alias Foglet.TUI.Theme
  alias Foglet.TUI.Widgets.Chrome.ScreenFrame

  import Raxol.Core.Renderer.View

  @spec render(map()) :: any()
  def render(state) do
    thread = state.current_thread
    ss = get_in(state.screen_state, [:post_reader]) || %{selected_post_index: 0}
    theme = (Map.get(state, :session_context) || %{}) |> Map.get(:theme) || Theme.default()
    post_content = render_post_content(state, ss.selected_post_index, theme)
    thread_title = (thread && thread.title) || "?"

    ScreenFrame.render(state, "Thread: #{thread_title}", post_content, [
      {"N", "Next"},
      {"P", "Prev"},
      {"R", "Reply"},
      {"Q", "Back"}
    ])
  end

  defp render_post_content(state, _idx, theme) when state.posts == [] or state.posts == nil do
    column style: %{gap: 0} do
      [text("Loading posts...", fg: theme.dim.fg)]
    end
  end

  defp render_post_content(state, idx, theme) do
    posts = state.posts
    total = length(posts)

    if idx >= total do
      column style: %{gap: 0} do
        [text("No more posts.", fg: theme.warning.fg)]
      end
    else
      column style: %{gap: 0} do
        render_post_items(state, Enum.at(posts, idx), idx, total, theme)
      end
    end
  end

  @spec handle_key(map(), map()) :: {:update, map(), list()} | :no_match
  def handle_key(%{key: :char, char: c}, state) when c in ["n", "N"], do: advance_post(state, +1)
  def handle_key(%{key: :char, char: " "}, state), do: advance_post(state, +1)
  def handle_key(%{key: :page_down}, state), do: advance_post(state, +1)
  def handle_key(%{key: :char, char: c}, state) when c in ["p", "P"], do: advance_post(state, -1)
  def handle_key(%{key: :page_up}, state), do: advance_post(state, -1)

  def handle_key(%{key: :char, char: c}, state) when c in ["r", "R"] do
    posts = state.posts || []
    ss = get_in(state.screen_state, [:post_reader]) || %{selected_post_index: 0}
    reply_to = Enum.at(posts, ss.selected_post_index)
    {w, _h} = state.terminal_size || {80, 24}

    composer_ss =
      Foglet.TUI.Screens.PostComposer.init_screen_state(reply_to: reply_to, width: w)

    new_state = %{
      state
      | current_screen: :post_composer,
        composer_draft: "",
        screen_state: Map.put(state.screen_state, :post_composer, composer_ss)
    }

    {:update, new_state, []}
  end

  def handle_key(%{key: :char, char: c}, state) when c in ["q", "Q"] do
    # SSH-09: flush read pointer on leave
    ctx = build_flush_context(state)

    new_state = %{
      state
      | current_screen: :thread_list,
        posts: nil,
        screen_state: Map.delete(state.screen_state, :post_reader)
    }

    {:update, new_state, [{:flush_read_pointers, ctx}]}
  end

  def handle_key(_key, _state), do: :no_match

  @doc "Called by App.update/2 on {:load_posts, thread_id}."
  @spec load_posts(map(), String.t()) :: {map(), list()}
  def load_posts(state, thread_id) do
    ctx = Map.get(state, :session_context) || %{}
    posts_mod = get_in(ctx, [:domain, :posts]) || Foglet.Posts
    posts = posts_mod.list_posts(thread_id)
    {%{state | posts: posts}, []}
  end

  @doc """
  Flush board and thread read pointers to DB (SSH-09).
  Called by App.update/2 on {:flush_read_pointers, ctx}.
  """
  @spec flush_read_pointers(map(), map()) :: {map(), list()}
  def flush_read_pointers(state, ctx) do
    sc = Map.get(state, :session_context) || %{}
    boards_mod = get_in(sc, [:domain, :boards]) || Foglet.Boards
    threads_mod = get_in(sc, [:domain, :threads]) || Foglet.Threads
    user_id = ctx[:user_id] || (state.current_user && state.current_user.id)

    flush_board_pointer(boards_mod, user_id, ctx)
    flush_thread_pointer(threads_mod, user_id, ctx)

    new_rp = clear_read_position(state.read_position, ctx[:thread_id])
    {%{state | read_position: new_rp}, []}
  end

  # --- Private ---

  defp flush_board_pointer(_mod, nil, _ctx), do: :skip

  defp flush_board_pointer(boards_mod, user_id, ctx) do
    if ctx[:board_id] do
      boards_mod.advance_board_read_pointer(
        user_id,
        ctx[:board_id],
        ctx[:last_read_message_number] || 0
      )
    end
  end

  defp flush_thread_pointer(_mod, nil, _ctx), do: :skip

  defp flush_thread_pointer(threads_mod, user_id, ctx) do
    if ctx[:thread_id] do
      threads_mod.advance_thread_read_pointer(user_id, ctx[:thread_id], ctx[:last_read_post_id])
    end
  end

  defp clear_read_position(read_position, nil), do: read_position
  defp clear_read_position(read_position, thread_id), do: Map.delete(read_position, thread_id)

  defp advance_post(state, delta) do
    posts = state.posts || []

    if posts == [] do
      :no_match
    else
      ss = get_in(state.screen_state, [:post_reader]) || %{selected_post_index: 0}
      new_idx = (ss.selected_post_index + delta) |> max(0) |> min(length(posts) - 1)
      post = Enum.at(posts, new_idx)

      # Local read-pointer advance — flushed on screen transition
      new_rp =
        if post && state.current_thread do
          Map.put(state.read_position, state.current_thread.id, %{
            last_read_post_id: post.id,
            last_read_message_number: Map.get(post, :message_number, 0)
          })
        else
          state.read_position
        end

      new_screen_state =
        Map.put(state.screen_state, :post_reader, %{ss | selected_post_index: new_idx})

      {:update, %{state | screen_state: new_screen_state, read_position: new_rp}, []}
    end
  end

  defp render_post_items(state, post, idx, total, theme) do
    sc = Map.get(state, :session_context) || %{}
    markdown_mod = get_in(sc, [:domain, :markdown]) || Foglet.Markdown
    body = post.body || ""

    rendered =
      if function_exported?(markdown_mod, :render, 1) do
        render_markdown_tuples(markdown_mod.render(body), theme)
      else
        text(body, fg: theme.primary.fg)
      end

    author = get_post_author(post)

    [
      text("Post #{idx + 1} of #{total}", fg: theme.dim.fg),
      text("By @#{author} at #{post.inserted_at}", fg: theme.dim.fg),
      text(""),
      rendered
    ]
  end

  # Walks a [{text, style}] list from Foglet.Markdown.render/1 and produces
  # a column of text/2 elements styled appropriately.
  defp render_markdown_tuples(tuples, theme) when is_list(tuples) do
    column style: %{gap: 0} do
      Enum.map(tuples, fn
        {s, :bold} -> text(s, style: [:bold], fg: theme.primary.fg)
        {s, :italic} -> text(s, style: [:italic], fg: theme.primary.fg)
        {s, :dim} -> text(s, style: [:dim], fg: theme.dim.fg)
        {s, :underline} -> text(s, style: [:underline], fg: theme.primary.fg)
        {s, :plain} -> text(s, fg: theme.primary.fg)
        {s, _} -> text(s, fg: theme.primary.fg)
      end)
    end
  end

  defp get_post_author(%{user: %{handle: h}}), do: h
  defp get_post_author(_), do: "unknown"

  defp build_flush_context(state) do
    thread = state.current_thread
    board = state.current_board
    thread_id = thread && thread.id
    pos = Map.get(state.read_position, thread_id) || %{}

    %{
      user_id: state.current_user && state.current_user.id,
      board_id: board && board.id,
      thread_id: thread_id,
      last_read_post_id: pos[:last_read_post_id],
      last_read_message_number: pos[:last_read_message_number]
    }
  end
end
