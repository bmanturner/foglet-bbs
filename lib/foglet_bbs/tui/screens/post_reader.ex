defmodule Foglet.TUI.Screens.PostReader do
  @moduledoc """
  Post reader for a single thread (SSH-07, SSH-08, SSH-09).

  Renders posts via Post.PostCard + Post.MarkdownBody (RENDER-01, RENDER-02).
  Paginates with n/p keys; scrolls within a post with j/k keys.
  Local read-pointer state (state.read_position) updates on each advance;
  flush to DB happens on screen transition via {:flush_read_pointers, ctx}
  command handled by TUI.App.update/2 (SSH-09).

  ## Screen state

  `state.screen_state[:post_reader]` holds:

    - `selected_post_index` — 0-based post index in the thread
    - `scroll_offset` — within-post scroll position (logical lines)
    - `render_cache` — `%{{post_id, width} => tuples}` memoizing Markdown.parse

  The cache is discarded on `Q` (screen exit) and rebuilt on re-entry.
  """

  alias Foglet.TUI.Theme
  alias Foglet.TUI.Widgets.Chrome.ScreenFrame
  alias Foglet.TUI.Widgets.Post.PostCard

  import Raxol.Core.Renderer.View

  @spec render(map()) :: any()
  def render(state) do
    thread = state.current_thread
    ss = get_screen_state(state)
    theme = (Map.get(state, :session_context) || %{}) |> Map.get(:theme) || Theme.default()
    {w, h} = state.terminal_size || {80, 24}
    post_content = render_post_content(state, ss, theme, w, h)
    thread_title = (thread && thread.title) || "?"

    ScreenFrame.render(state, "Thread: #{thread_title}", post_content, [
      {"N", "Next"},
      {"P", "Prev"},
      {"J", "Scroll ↓"},
      {"K", "Scroll ↑"},
      {"R", "Reply"},
      {"Q", "Back"}
    ])
  end

  defp render_post_content(state, _ss, theme, _w, _h)
       when state.posts == [] or state.posts == nil do
    column style: %{gap: 0} do
      [text("Loading posts...", fg: theme.dim.fg)]
    end
  end

  defp render_post_content(state, ss, theme, w, h) do
    posts = state.posts
    total = length(posts)
    idx = ss.selected_post_index

    if idx >= total do
      column style: %{gap: 0} do
        [text("No more posts.", fg: theme.warning.fg)]
      end
    else
      post = Enum.at(posts, idx)
      available_height = max(h - 10, 5)
      tuples = ss.render_cache[{post.id, w}] || parse_body(state, post)

      PostCard.render_from_tuples(post, tuples, w, theme,
        index: idx,
        total: total,
        scroll_offset: ss.scroll_offset,
        max_lines: available_height
      )
    end
  end

  @spec handle_key(map(), map()) :: {:update, map(), list()} | :no_match
  def handle_key(%{key: :char, char: c}, state) when c in ["n", "N"], do: advance_post(state, +1)
  def handle_key(%{key: :char, char: " "}, state), do: advance_post(state, +1)
  def handle_key(%{key: :page_down}, state), do: advance_post(state, +1)
  def handle_key(%{key: :char, char: c}, state) when c in ["p", "P"], do: advance_post(state, -1)
  def handle_key(%{key: :page_up}, state), do: advance_post(state, -1)

  def handle_key(%{key: :char, char: c}, state) when c in ["j", "J"] do
    scroll_post(state, +1)
  end

  def handle_key(%{key: :char, char: c}, state) when c in ["k", "K"] do
    scroll_post(state, -1)
  end

  def handle_key(%{key: :char, char: c}, state) when c in ["r", "R"] do
    posts = state.posts || []
    ss = get_screen_state(state)
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

  # Default screen_state shape for post_reader.
  # `render_cache` is a map keyed on {post_id, width} → rendered tuples.
  defp default_screen_state do
    %{
      selected_post_index: 0,
      scroll_offset: 0,
      render_cache: %{}
    }
  end

  # Merges the default shape over any existing :post_reader entry so
  # legacy states (from pre-Phase-2 sessions mid-flight) get the new
  # keys without overwriting selected_post_index.
  defp get_screen_state(state) do
    existing = get_in(state.screen_state, [:post_reader]) || %{}
    Map.merge(default_screen_state(), existing)
  end

  # Cache-aware Foglet.Markdown.render/1 wrapper. Returns the parsed
  # tuple list. If the result was not cached, the caller should store
  # it via warm_cache/4.
  defp parse_body(state, post) do
    sc = Map.get(state, :session_context) || %{}
    markdown_mod = get_in(sc, [:domain, :markdown]) || Foglet.Markdown
    body = Map.get(post, :body) || ""

    if function_exported?(markdown_mod, :render, 1) do
      markdown_mod.render(body)
    else
      # Defensive fallback.
      [{body, :plain}]
    end
  end

  # Populates the render_cache for the currently-selected post if it's
  # not yet cached. Returns the updated screen_state map.
  defp warm_cache(ss, state, post, w) do
    key = {post.id, w}

    if Map.has_key?(ss.render_cache, key) do
      ss
    else
      tuples = parse_body(state, post)
      %{ss | render_cache: Map.put(ss.render_cache, key, tuples)}
    end
  end

  defp advance_post(state, delta) do
    posts = state.posts || []

    if posts == [] do
      :no_match
    else
      ss = get_screen_state(state)
      new_idx = (ss.selected_post_index + delta) |> max(0) |> min(length(posts) - 1)
      post = Enum.at(posts, new_idx)
      {w, _h} = state.terminal_size || {80, 24}

      # D-04: N/P resets scroll_offset to 0.
      ss = %{ss | selected_post_index: new_idx, scroll_offset: 0}
      ss = if post, do: warm_cache(ss, state, post, w), else: ss

      # Local read-pointer advance — flushed on screen transition.
      new_rp =
        if post && state.current_thread do
          Map.put(state.read_position, state.current_thread.id, %{
            last_read_post_id: post.id,
            last_read_message_number: Map.get(post, :message_number, 0)
          })
        else
          state.read_position
        end

      new_screen_state = Map.put(state.screen_state, :post_reader, ss)

      {:update, %{state | screen_state: new_screen_state, read_position: new_rp}, []}
    end
  end

  defp scroll_post(state, delta) do
    posts = state.posts || []

    if posts == [] do
      :no_match
    else
      ss = get_screen_state(state)
      post = Enum.at(posts, ss.selected_post_index)

      if is_nil(post) do
        :no_match
      else
        {w, h} = state.terminal_size || {80, 24}
        available_height = max(h - 10, 5)

        total_lines = PostCard.body_line_count(post.body)
        # Max offset: never scroll past (total - available_height).
        # Clamp at 0 for short posts.
        max_offset = max(total_lines - available_height, 0)
        new_offset = (ss.scroll_offset + delta) |> max(0) |> min(max_offset)

        ss = %{ss | scroll_offset: new_offset}
        ss = warm_cache(ss, state, post, w)

        new_screen_state = Map.put(state.screen_state, :post_reader, ss)
        {:update, %{state | screen_state: new_screen_state}, []}
      end
    end
  end

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
