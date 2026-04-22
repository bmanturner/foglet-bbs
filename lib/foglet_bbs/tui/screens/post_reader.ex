defmodule Foglet.TUI.Screens.PostReader do
  @moduledoc """
  Post reader for a single thread (SSH-07, SSH-08, SSH-09).

  Renders posts via Post.PostCard + Post.MarkdownBody (RENDER-01, RENDER-02).
  Paginates with n/p keys; scrolls within a post with j/k keys.
  Local read-pointer state (state.read_position) updates on each advance;
  flush to DB happens on screen transition via {:flush_read_pointers, ctx}
  command handled by TUI.App.update/2 (SSH-09).

  ## Load-absorb behavior (READER-07, AUDIT-18 deviation note)

  While posts are still loading (`state.posts == [] or nil`), the navigation
  and scroll key handlers (`advance_post/2` via n/p/space/page_down/page_up,
  and `scroll_post/2` via j/k) return `{:update, state, []}` to absorb the
  keypress rather than falling through to the global key handler. This prevents
  global handlers from acting on PostReader-intended keys (WR-02) and avoids
  command churn during the async load window (T-09-02).

  ## Public callbacks (READER-02, D-03, D-04)

  `load_posts/2` and `flush_read_pointers/2` are intentionally public. They
  serve as stable contract surface for screen-level unit tests and for direct
  invocation by `Foglet.TUI.App.do_update/2` command handlers. See each
  function's `@doc` for details. Do not privatize or delete these without a
  corresponding context decision update.

  ## Render-path purity (READER-05, D-07, D-08)

  No `defp render_*` helper may perform state writes (`put_in`, `%{state | …}`,
  `Map.put`). Mutations are confined to non-render helpers (`load_posts/2`,
  `advance_post/2`, `scroll_post/2`, `warm_cache/4`, `warm_viewport/4`).
  The `render_cache` warming plumbing sits in §9 state-plumbing scope (not §8
  render helpers) precisely because it mutates state.

  ## Screen state

  `state.screen_state[:post_reader]` holds:

    - `selected_post_index` — 0-based post index in the thread
    - `viewport` — Raxol.UI.Components.Display.Viewport state (owns scroll_top,
      content_height, visible_height, children). Replaces pre-Phase-7 `scroll_offset`.
    - `render_cache` — `%{{post_id, width} => tuples}` memoizing Markdown.parse

  The cache is discarded on `Q` (screen exit) and rebuilt on re-entry.
  """

  alias Foglet.TUI.Screens.Domain
  alias Foglet.TUI.Theme
  alias Foglet.TUI.Widgets.Chrome.ScreenFrame
  alias Foglet.TUI.Widgets.Post.PostCard
  alias Foglet.TUI.Widgets.Progress.Spinner
  alias Raxol.UI.Components.Display.Viewport

  import Raxol.Core.Renderer.View

  @spec render(map()) :: any()
  def render(state) do
    thread = state.current_thread
    ss = get_screen_state(state)
    theme = Theme.from_state(state)
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

  defp render_post_content(%{posts: posts}, _ss, theme, _w, _h)
       when posts in [[], nil] do
    render_loading(theme)
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

      # Non-scrolling header (Post X of N, author, divider).
      header_line_1 = text("Post #{idx + 1} of #{total}", fg: theme.dim.fg)
      header_line_2 = text(PostCard.author_line(post), fg: theme.dim.fg)
      header_divider = divider(char: "─", style: %{fg: theme.border.fg})

      # Pre-themed body lines — Viewport passes them through unmodified.
      body_lines = PostCard.render_body_lines(tuples, w, theme)

      # Wire visible_height and children for this frame. render_post_content
      # is a read-only function — the Viewport state built here is transient,
      # not written back into screen_state. State-writing happens in
      # scroll_post / advance_post / load_posts via warm_viewport.
      {vp, _cmds} = Viewport.update({:set_visible_height, available_height}, ss.viewport)
      {vp, _cmds} = Viewport.update({:set_children, body_lines}, vp)
      body_rendered = Viewport.render(vp, %{})

      column style: %{gap: 0} do
        [header_line_1, header_line_2, header_divider, body_rendered]
      end
    end
  end

  # Spinner-based loading affordance used when posts is nil/[]
  # (post_reader was opened but {:posts_loaded, posts} hasn't landed yet).
  # One-row composition: gap-1 row with spinner glyph + label text.
  # Row count is identical to the old plain-text path — no visible row growth (D-05, D-06).
  defp render_loading(theme) do
    frame = System.monotonic_time(:millisecond) |> abs() |> div(Spinner.frame_duration_ms())

    column style: %{gap: 0} do
      [
        row(
          style: %{gap: 1},
          do: [
            Spinner.render(frame, style: :line, theme: theme),
            text("Loading…", fg: theme.dim.fg)
          ]
        )
      ]
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
      |> Map.put(:origin, :post_reader)

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

  @doc """
  Called by App.update/2 on {:load_posts, thread_id}.

  Seeds `state.read_position[thread_id]` with post 0's
  `{last_read_post_id, last_read_message_number}` tuple immediately on
  entry (LIST-01 D-05). This means pressing Q right after opening a
  thread still advances the board read pointer past the first post on
  flush — "if you saw it, you read it."

  **Dead-code audit (READER-02, D-03, D-04):** This public callback is
  intentional contract surface. Production orchestration is owned by
  `Foglet.TUI.App.do_update({:load_posts, thread_id, opts}, state)`, which
  runs the real load off-process via `Command.task`. This function exists as
  a stable screen-level test seam (verified in `post_reader_test.exs`) and
  as the callable entry point should direct invocation be needed. Do not
  delete or privatize without a corresponding context decision update.
  """
  @spec load_posts(map(), String.t()) :: {map(), list()}
  def load_posts(state, thread_id) do
    ctx = Map.get(state, :session_context) || %{}

    posts_mod =
      case Domain.get(ctx, :posts) do
        {:ok, mod} -> mod
        {:error, :not_configured} -> Foglet.Posts
      end

    posts = posts_mod.list_posts(thread_id)
    new_read_position = seed_read_position_on_entry(state.read_position, thread_id, posts)
    {w, _h} = state.terminal_size || {80, 24}

    # WR-01: warm the render cache for the first post on load so that the
    # initial render (before any keypress) does not re-parse on every frame.
    ss = get_screen_state(state)
    state_with_posts = %{state | posts: posts}
    ss = warm_cache_for_index(ss, state_with_posts, posts, 0, w)

    # Pre-populate the viewport children for post 0 so j/k have correct
    # content_height for clamping on first keypress.
    first_post = Enum.at(posts, 0)
    ss = if first_post, do: warm_viewport(ss, state_with_posts, first_post, w), else: ss

    new_screen_state = Map.put(state.screen_state, :post_reader, ss)

    {%{state | posts: posts, read_position: new_read_position, screen_state: new_screen_state},
     []}
  end

  defp seed_read_position_on_entry(read_position, _thread_id, []), do: read_position
  defp seed_read_position_on_entry(read_position, _thread_id, nil), do: read_position

  defp seed_read_position_on_entry(read_position, thread_id, [first_post | _]) do
    Map.put(read_position, thread_id, %{
      last_read_post_id: first_post.id,
      last_read_message_number: Map.get(first_post, :message_number, 0)
    })
  end

  @doc """
  Flush board and thread read pointers to DB (SSH-09).
  Called by App.update/2 on {:flush_read_pointers, ctx}.

  **Dead-code audit (READER-02, D-03, D-04):** This public callback is
  intentional contract surface. Production flushing is owned by
  `Foglet.TUI.App.do_update({:flush_read_pointers, ctx}, state)`, which
  runs the real flush off-process via `Command.task`. This function exists as
  a stable screen-level test seam (verified in `post_reader_test.exs`) and as
  the callable entry point for direct invocation. Do not delete or privatize
  without a corresponding context decision update.
  """
  @spec flush_read_pointers(map(), map()) :: {map(), list()}
  # `flush_ctx` is a flush-data bag — %{user_id:, board_id:, thread_id:, ...}.
  # Domain modules are read from state.session_context, not from flush_ctx.
  def flush_read_pointers(state, flush_ctx) do
    sc = Map.get(state, :session_context) || %{}

    boards_mod =
      case Domain.get(sc, :boards) do
        {:ok, mod} -> mod
        {:error, :not_configured} -> Foglet.Boards
      end

    threads_mod =
      case Domain.get(sc, :threads) do
        {:ok, mod} -> mod
        {:error, :not_configured} -> Foglet.Threads
      end

    user_id = flush_ctx[:user_id] || (state.current_user && state.current_user.id)

    flush_board_pointer(boards_mod, user_id, flush_ctx)
    flush_thread_pointer(threads_mod, user_id, flush_ctx)

    new_rp = clear_read_position(state.read_position, flush_ctx[:thread_id])
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
    if ctx[:thread_id] && ctx[:last_read_post_id] do
      threads_mod.advance_thread_read_pointer(user_id, ctx[:thread_id], ctx[:last_read_post_id])
    end
  end

  defp clear_read_position(read_position, nil), do: read_position
  defp clear_read_position(read_position, thread_id), do: Map.delete(read_position, thread_id)

  # Default screen_state shape for post_reader.
  # `render_cache` is a map keyed on {post_id, width} → rendered tuples.
  # `viewport` is a Raxol.UI.Components.Display.Viewport state map — owns
  # scroll_top, content_height, visible_height, and children. Replaces the
  # pre-Phase-7 `scroll_offset` integer.
  defp default_screen_state do
    {:ok, vp} =
      Viewport.init(%{
        id: "post_reader_vp",
        children: [],
        visible_height: 10,
        scroll_top: 0,
        show_scrollbar: false
      })

    %{
      selected_post_index: 0,
      viewport: vp,
      render_cache: %{}
    }
  end

  # Merges the default shape over any existing :post_reader entry so
  # legacy states (from pre-Phase-7 sessions mid-flight) get the new
  # :viewport field without overwriting selected_post_index. Legacy
  # :scroll_offset is explicitly dropped — Viewport owns scroll now.
  defp get_screen_state(state) do
    existing =
      (get_in(state.screen_state, [:post_reader]) || %{})
      |> Map.drop([:scroll_offset])

    Map.merge(default_screen_state(), existing)
  end

  # Parses the post body via Foglet.Markdown.render/1. Returns the
  # rendered tuple list but does NOT write to render_cache — it is a
  # pure read-only helper.
  #
  # The cache is populated via warm_cache/4, which is called from:
  #   - load_posts/2    (on initial thread load — warms post 0)
  #   - advance_post/2  (on n/p navigation)
  #   - scroll_post/2   (on j/k scroll)
  #
  # render_post_content/5 uses the cache when available and falls back
  # to parse_body/2 for any post not yet cached (e.g. a PubSub-triggered
  # reload before the user has navigated). Since render_post_content/5 is
  # pure (read-only from state) it intentionally cannot write the result
  # back into the cache.
  defp parse_body(state, post) do
    sc = Map.get(state, :session_context) || %{}

    markdown_mod =
      case Domain.get(sc, :markdown) do
        {:ok, mod} -> mod
        {:error, :not_configured} -> Foglet.Markdown
      end

    body = Map.get(post, :body) || ""

    # Ensure the module is loaded before checking function_exported? — the
    # check returns false for modules that haven't been called yet in the
    # current runtime session even if the function exists (lazy loading).
    _ = Code.ensure_loaded(markdown_mod)

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

  # Warms the cache for the post at the given index (used by load_posts/2
  # to pre-populate the cache for the first post so render/1 never parses
  # on the first frame). Returns the updated screen_state.
  defp warm_cache_for_index(ss, state, posts, idx, w) do
    post = Enum.at(posts, idx)
    if post, do: warm_cache(ss, state, post, w), else: ss
  end

  # Populates the viewport's children with pre-themed body lines for the
  # currently-selected post. Required before any scroll_by/scroll_to call
  # so the Viewport has the correct content_height for clamping.
  # Width-aware: re-runs whenever width changes (via scroll_post caller).
  defp warm_viewport(ss, state, post, w) do
    theme = Theme.from_state(state)

    tuples = ss.render_cache[{post.id, w}] || parse_body(state, post)
    body_lines = PostCard.render_body_lines(tuples, w, theme)

    {new_vp, _cmds} = Viewport.update({:set_children, body_lines}, ss.viewport)
    %{ss | viewport: new_vp}
  end

  defp advance_post(state, delta) do
    posts = state.posts || []

    if posts == [] do
      # Absorb the keypress during loading rather than falling through to the
      # global key handler — prevents future global handlers from acting on
      # PostReader-intended keys (n/p/space/page_down/page_up) while the
      # thread is still loading.
      {:update, state, []}
    else
      ss = get_screen_state(state)
      new_idx = (ss.selected_post_index + delta) |> max(0) |> min(length(posts) - 1)
      post = Enum.at(posts, new_idx)
      {w, _h} = state.terminal_size || {80, 24}

      # D-04: N/P/space/page_down/page_up resets scroll to the top of the new post.
      {reset_vp, _cmds} = Viewport.update({:scroll_to, 0}, ss.viewport)
      ss = %{ss | selected_post_index: new_idx, viewport: reset_vp}
      ss = if post, do: warm_cache(ss, state, post, w), else: ss
      ss = if post, do: warm_viewport(ss, state, post, w), else: ss

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
      # WR-02: absorb scroll keys during loading so they don't escape to the
      # global key handler.
      {:update, state, []}
    else
      ss = get_screen_state(state)
      post = Enum.at(posts, ss.selected_post_index)

      if is_nil(post) do
        {:update, state, []}
      else
        {w, h} = state.terminal_size || {80, 24}
        available_height = max(h - 10, 5)

        # Warm the cache + viewport BEFORE scrolling so Viewport has the
        # correct content_height for clamping. Also sync visible_height from
        # the current terminal size so max_scroll reflects the real window.
        ss = warm_cache(ss, state, post, w)
        ss = warm_viewport(ss, state, post, w)

        {new_vp, _cmds} = Viewport.update({:set_visible_height, available_height}, ss.viewport)
        # Viewport.update/2 handles all clamping — no max_offset math needed.
        {new_vp, _cmds} = Viewport.update({:scroll_by, delta}, new_vp)
        ss = %{ss | viewport: new_vp}

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
