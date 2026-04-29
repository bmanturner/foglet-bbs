defmodule Foglet.TUI.Screens.PostReader do
  @moduledoc """
  Post reader for a single thread (SSH-07, SSH-08, SSH-09).

  Phase 37 makes PostReader screen-owned: loaded posts, selected index,
  viewport/cache state, route identity, pending read data, load status, and
  flush results live in `%PostReader.State{}` and flow through `update/3`.

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

  `state.screen_state[:post_reader]` holds a `%PostReader.State{}` with:

    - `selected_post_index` — 0-based post index in the thread
    - `viewport` — Raxol.UI.Components.Display.Viewport state (owns scroll_top,
      content_height, visible_height, children). Replaces pre-Phase-7 `scroll_offset`.
    - `render_cache` — `%{{post_id, width} => tuples}` memoizing Markdown.parse

  `init_screen_state/1` returns this default struct (AUDIT-19).

  The cache is discarded on `Q` (screen exit) and rebuilt on re-entry.
  """

  @behaviour Foglet.TUI.Screen

  alias Foglet.TUI.{Context, Effect}
  alias Foglet.TUI.Screens.Domain
  alias Foglet.TUI.Screens.PostReader.State
  alias Foglet.TUI.Theme
  alias Foglet.TUI.Widgets.Chrome.ScreenFrame
  alias Foglet.TUI.Widgets.Post.PostCard
  alias Foglet.TUI.Widgets.Progress.Spinner
  alias Raxol.UI.Components.Display.Viewport

  import Raxol.Core.Renderer.View

  @default_terminal_size {80, 24}

  @impl true
  @spec init(Context.t()) :: State.t()
  def init(%Context{} = context), do: State.from_context(context)

  @impl true
  @spec update(term(), State.t(), Context.t()) :: {State.t(), [Effect.t()]}
  def update(:load, %State{thread_id: thread_id} = state, %Context{} = context)
      when is_binary(thread_id) do
    posts_mod = resolve_domain_module(context, :posts, Foglet.Posts)

    new_state = %{state | status: :loading, last_op: :load_posts, last_error: nil}
    effect = Effect.task(:load_posts, :post_reader, fn -> posts_mod.list_posts(thread_id) end)

    {new_state, [effect]}
  end

  def update(:load, %State{} = state, %Context{}) do
    {%{state | status: {:error, :missing_thread}, last_op: nil, last_error: :missing_thread}, []}
  end

  def update({:task_result, :load_posts, {:ok, posts}}, %State{} = state, %Context{} = context)
      when is_list(posts) do
    selected_index = selected_index_after_load(state, posts)
    status = if posts == [], do: :empty, else: :loaded

    state =
      %{state | posts: posts, status: status, selected_post_index: selected_index}
      |> seed_pending_read_position()
      |> warm_selected_post(context)

    {%{state | last_op: nil, last_error: nil}, []}
  end

  def update({:task_result, :load_posts, {:error, reason}}, %State{} = state, %Context{}) do
    {%{state | status: {:error, reason}, last_op: nil, last_error: reason}, []}
  end

  def update(
        {:thread_activity, thread_id, _event},
        %State{thread_id: thread_id} = state,
        %Context{} = context
      )
      when is_binary(thread_id) do
    posts_mod = resolve_domain_module(context, :posts, Foglet.Posts)

    effect = Effect.task(:load_posts, :post_reader, fn -> posts_mod.list_posts(thread_id) end)
    {%{state | last_op: :load_posts, last_error: nil}, [effect]}
  end

  def update({:thread_activity, _thread_id, _event}, %State{} = state, %Context{}) do
    {state, []}
  end

  def update(
        {:task_result, :flush_read_pointers, {:ok, {:read_pointers_flushed, thread_id}}},
        %State{} = state,
        %Context{}
      ) do
    {clear_pending_read_position(state, thread_id), []}
  end

  def update(
        {:task_result, :flush_read_pointers, {:ok, {:error, reason}}},
        %State{} = state,
        %Context{}
      ) do
    {%{state | last_error: reason}, []}
  end

  def update({:task_result, :flush_read_pointers, {:ok, thread_id}}, %State{} = state, %Context{}) do
    {clear_pending_read_position(state, thread_id), []}
  end

  def update({:task_result, :flush_read_pointers, {:error, reason}}, %State{} = state, %Context{}) do
    {%{state | last_error: reason}, []}
  end

  def update({:key, %{key: :char, char: c}}, %State{} = state, %Context{} = context)
      when c in ["n", "N"] do
    {advance_local_post(state, 1, context), []}
  end

  def update({:key, %{key: :char, char: " "}}, %State{} = state, %Context{} = context) do
    {advance_local_post(state, 1, context), []}
  end

  def update({:key, %{key: :page_down}}, %State{} = state, %Context{} = context) do
    {advance_local_post(state, 1, context), []}
  end

  def update({:key, %{key: :char, char: c}}, %State{} = state, %Context{} = context)
      when c in ["p", "P"] do
    {advance_local_post(state, -1, context), []}
  end

  def update({:key, %{key: :page_up}}, %State{} = state, %Context{} = context) do
    {advance_local_post(state, -1, context), []}
  end

  def update({:key, %{key: :char, char: c}}, %State{} = state, %Context{} = context)
      when c in ["j", "J"] do
    {scroll_local_post(state, 1, context), []}
  end

  def update({:key, %{key: :char, char: c}}, %State{} = state, %Context{} = context)
      when c in ["k", "K"] do
    {scroll_local_post(state, -1, context), []}
  end

  def update({:key, %{key: :char, char: c}}, %State{} = state, %Context{})
      when c in ["r", "R"] do
    params = %{
      origin: :post_reader,
      board: state.board,
      board_id: state.board_id,
      thread: state.thread,
      thread_id: state.thread_id,
      reply_to: selected_post(state)
    }

    {state, [Effect.navigate(:post_composer, params)]}
  end

  def update({:key, %{key: :char, char: c}}, %State{} = state, %Context{} = context)
      when c in ["q", "Q"] do
    effects = [Effect.navigate(:thread_list, %{board: state.board, board_id: state.board_id})]

    effects =
      case flush_effect(state, context) do
        nil -> effects
        effect -> effects ++ [effect]
      end

    {state, effects}
  end

  def update(_message, %State{} = state, %Context{}), do: {state, []}

  @impl true
  @spec render(State.t(), Context.t()) :: any()
  def render(%State{} = state, %Context{} = context) do
    frame_state = frame_state(state, context)
    theme = Theme.from_state(frame_state)
    {w, h} = context.terminal_size || @default_terminal_size
    post_content = render_local_post_content(state, frame_state, theme, w, h)

    ScreenFrame.render(frame_state, %{}, post_content, [
      {"N", "Next"},
      {"P", "Prev"},
      {"J", "Scroll ↓"},
      {"K", "Scroll ↑"},
      {"R", "Reply"},
      {"Q", "Back"}
    ])
  end

  @impl true
  @spec render(map()) :: any()
  # Phase 39 cleanup: legacy render/1 remains for older smoke tests only.
  # Phase 37 flow state is screen-owned by render/2 and %PostReader.State{}.
  def render(state) do
    ss = get_screen_state(state)
    theme = Theme.from_state(state)
    {w, h} = state.terminal_size || @default_terminal_size
    post_content = render_post_content(state, ss, theme, w, h)

    ScreenFrame.render(state, %{}, post_content, [
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
      available_height = max(h - 12, 5)

      tuples =
        case ss.render_cache[{post.id, w}] do
          nil ->
            require Logger
            Logger.warning("[PostReader] render cache miss for post=#{post.id} width=#{w}")
            parse_body(state, post)

          cached ->
            cached
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

  @impl true
  @spec handle_key(map(), map()) :: {:update, map(), list()} | :no_match
  # Phase 39 cleanup: legacy handle_key/2 remains for compatibility tests.
  # It must not be the source of truth for the Phase 37 App runtime path.
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
    {w, _h} = state.terminal_size || @default_terminal_size

    composer_ss =
      Foglet.TUI.Screens.PostComposer.init_screen_state(reply_to: reply_to, width: w)
      |> then(&%{&1 | origin: :post_reader})

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
    {w, _h} = state.terminal_size || @default_terminal_size

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

    board_result = flush_board_pointer(boards_mod, user_id, flush_ctx)
    thread_result = flush_thread_pointer(threads_mod, user_id, flush_ctx)

    apply_flush_result(state, flush_ctx, board_result, thread_result)
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
    else
      :skip
    end
  end

  defp flush_thread_pointer(_mod, nil, _ctx), do: :skip

  defp flush_thread_pointer(threads_mod, user_id, ctx) do
    if ctx[:thread_id] && ctx[:last_read_post_id] do
      threads_mod.advance_thread_read_pointer(user_id, ctx[:thread_id], ctx[:last_read_post_id])
    else
      :skip
    end
  end

  defp clear_read_position(read_position, nil), do: read_position
  defp clear_read_position(read_position, thread_id), do: Map.delete(read_position, thread_id)

  # Clears the local read-pointer only when both DB flushes succeeded (or were
  # skipped because there was nothing to flush). On failure, logs a warning and
  # returns state unchanged so the pointer is retried on the next transition.
  defp apply_flush_result(state, flush_ctx, board_result, thread_result) do
    if flush_result_ok?(board_result) and flush_result_ok?(thread_result) do
      new_rp = clear_read_position(state.read_position, flush_ctx[:thread_id])
      {%{state | read_position: new_rp}, []}
    else
      require Logger

      Logger.warning(
        "flush_read_pointers: flush failed — board: #{inspect(board_result)}, thread: #{inspect(thread_result)}"
      )

      {state, []}
    end
  end

  defp flush_result_ok?(:skip), do: true
  defp flush_result_ok?(:ok), do: true
  defp flush_result_ok?({:ok, _}), do: true
  defp flush_result_ok?(_), do: false

  @doc """
  Build the initial screen_state struct for PostReader (AUDIT-19).

  `render_cache` is a map keyed on `{post_id, width}` → rendered tuples.
  `viewport` is a `Raxol.UI.Components.Display.Viewport` state map — owns
  `scroll_top`, `content_height`, `visible_height`, and `children`.
  Replaces the pre-Phase-7 `scroll_offset` integer.

  `opts` accepts the struct fields and keeps the keyword-list shape used by
  other stateful screens' `init_screen_state/1` callbacks.
  """
  @impl true
  @spec init_screen_state(keyword()) :: State.t()
  def init_screen_state(opts \\ []) do
    State.new(opts)
  end

  @doc """
  Called by App.update/2 on {:posts_loaded, posts, opts} to warm the
  render cache for the post at `idx` and seed a correctly-shaped
  screen_state struct. Returns the updated screen_state struct for :post_reader.

  Initializes missing PostReader state with the struct shape.
  """
  @spec prepare_after_load(map(), [map()], non_neg_integer()) :: State.t()
  def prepare_after_load(state, posts, idx) do
    ss = get_screen_state(state)
    {w, _h} = state.terminal_size || @default_terminal_size
    ss = warm_cache_for_index(ss, state, posts, idx, w)

    # Also warm the viewport for the selected post so scroll math works.
    case Enum.at(posts, idx) do
      nil -> ss
      post -> warm_viewport(ss, state, post, w)
    end
  end

  defp get_screen_state(%{screen_state: %{post_reader: %State{} = ss}}), do: ss
  defp get_screen_state(_state), do: init_screen_state([])

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
    posts = state.posts || []
    idx = ss.selected_post_index
    total = length(posts)

    tuples = ss.render_cache[{post.id, w}] || parse_body(state, post)
    parts = reader_parts(post, tuples, w, theme, idx, total)

    {new_vp, _cmds} = Viewport.update({:set_children, parts.body_lines}, ss.viewport)
    %{ss | viewport: new_vp}
  end

  defp reader_parts(post, tuples, w, theme, idx, total) do
    PostCard.reader_parts(post, tuples, w, theme, index: idx, total: total)
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
      {w, _h} = state.terminal_size || @default_terminal_size

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
        {w, h} = state.terminal_size || @default_terminal_size
        available_height = max(h - 12, 5)

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

    pos =
      if thread_id do
        Map.get(state.read_position, thread_id, %{})
      else
        %{}
      end

    %{
      user_id: state.current_user && state.current_user.id,
      board_id: board && board.id,
      thread_id: thread_id,
      last_read_post_id: pos[:last_read_post_id],
      last_read_message_number: pos[:last_read_message_number]
    }
  end

  defp selected_index_after_load(%State{load_intent: intent}, posts)
       when intent in [:jump_last, "jump_last"] do
    max(length(posts) - 1, 0)
  end

  defp selected_index_after_load(_state, _posts), do: 0

  defp seed_pending_read_position(%State{thread_id: thread_id, posts: posts} = state)
       when is_binary(thread_id) and is_list(posts) do
    case selected_post(state) do
      nil ->
        state

      post ->
        pending = %{
          last_read_post_id: Map.get(post, :id),
          last_read_message_number: Map.get(post, :message_number) || 0
        }

        %{
          state
          | pending_read_positions: Map.put(state.pending_read_positions, thread_id, pending)
        }
    end
  end

  defp seed_pending_read_position(%State{} = state), do: state

  defp selected_post(%State{posts: posts, selected_post_index: idx}) when is_list(posts) do
    Enum.at(posts, idx)
  end

  defp selected_post(%State{}), do: nil

  defp advance_local_post(%State{posts: posts} = state, _delta, _context)
       when posts in [nil, []] do
    state
  end

  defp advance_local_post(%State{posts: posts} = state, delta, %Context{} = context) do
    new_idx = (state.selected_post_index + delta) |> max(0) |> min(length(posts) - 1)

    {reset_vp, _cmds} = Viewport.update({:scroll_to, 0}, state.viewport)

    %{state | selected_post_index: new_idx, viewport: reset_vp}
    |> seed_pending_read_position()
    |> warm_selected_post(context)
  end

  defp scroll_local_post(%State{posts: posts} = state, _delta, _context)
       when posts in [nil, []] do
    state
  end

  defp scroll_local_post(%State{} = state, delta, %Context{} = context) do
    case selected_post(state) do
      nil ->
        state

      _post ->
        {_w, h} = context.terminal_size || @default_terminal_size
        available_height = max(h - 12, 5)

        state = warm_selected_post(state, context)
        {new_vp, _cmds} = Viewport.update({:set_visible_height, available_height}, state.viewport)
        {new_vp, _cmds} = Viewport.update({:scroll_by, delta}, new_vp)
        %{state | viewport: new_vp}
    end
  end

  defp warm_selected_post(%State{} = state, %Context{} = context) do
    case selected_post(state) do
      nil ->
        state

      post ->
        {w, _h} = context.terminal_size || @default_terminal_size
        frame_state = frame_state(state, context)
        state = warm_cache(state, frame_state, post, w)
        frame_state = frame_state(state, context)
        warm_viewport(state, frame_state, post, w)
    end
  end

  defp flush_effect(
         %State{thread_id: thread_id, pending_read_positions: pending} = state,
         %Context{} = context
       )
       when is_binary(thread_id) do
    case Map.get(pending, thread_id) do
      nil ->
        nil

      pos ->
        boards_mod = resolve_domain_module(context, :boards, Foglet.Boards)
        threads_mod = resolve_domain_module(context, :threads, Foglet.Threads)

        flush_ctx = %{
          user_id: context.current_user && context.current_user.id,
          board_id: state.board_id,
          thread_id: state.thread_id,
          last_read_post_id: pos.last_read_post_id,
          last_read_message_number: pos.last_read_message_number
        }

        Effect.task(:flush_read_pointers, :post_reader, fn ->
          with :ok <- flush_local_board_pointer(boards_mod, flush_ctx),
               :ok <- flush_local_thread_pointer(threads_mod, flush_ctx) do
            {:read_pointers_flushed, thread_id}
          end
        end)
    end
  end

  defp flush_effect(%State{}, %Context{}), do: nil

  defp flush_local_board_pointer(_mod, %{user_id: nil}), do: :ok
  defp flush_local_board_pointer(_mod, %{board_id: nil}), do: :ok

  defp flush_local_board_pointer(boards_mod, ctx) do
    normalize_flush_result(
      boards_mod.advance_board_read_pointer(
        ctx.user_id,
        ctx.board_id,
        ctx.last_read_message_number || 0
      )
    )
  end

  defp flush_local_thread_pointer(_mod, %{user_id: nil}), do: :ok
  defp flush_local_thread_pointer(_mod, %{thread_id: nil}), do: :ok
  defp flush_local_thread_pointer(_mod, %{last_read_post_id: nil}), do: :ok

  defp flush_local_thread_pointer(threads_mod, ctx) do
    normalize_flush_result(
      threads_mod.advance_thread_read_pointer(ctx.user_id, ctx.thread_id, ctx.last_read_post_id)
    )
  end

  defp normalize_flush_result(:ok), do: :ok
  defp normalize_flush_result({:ok, _}), do: :ok
  defp normalize_flush_result(other), do: {:error, other}

  defp clear_pending_read_position(%State{} = state, thread_id) do
    %{state | pending_read_positions: Map.delete(state.pending_read_positions, thread_id)}
  end

  defp frame_state(%State{} = state, %Context{} = context) do
    %{
      current_user: context.current_user,
      current_screen: :post_reader,
      current_board: state.board,
      current_thread: state.thread,
      posts: state.posts,
      read_position: state.pending_read_positions,
      session_context: context.session_context,
      terminal_size: context.terminal_size,
      route_params: context.route_params,
      screen_state: %{post_reader: state}
    }
  end

  defp resolve_domain_module(%Context{domain: domain} = context, key, fallback)
       when is_map(domain) do
    case Map.get(domain, key) do
      mod when is_atom(mod) and not is_nil(mod) -> mod
      _ -> resolve_domain_module_from_session(context, key, fallback)
    end
  end

  defp resolve_domain_module(%Context{} = context, key, fallback) do
    resolve_domain_module_from_session(context, key, fallback)
  end

  defp resolve_domain_module_from_session(%Context{session_context: ctx}, key, fallback) do
    case Domain.get(ctx || %{}, key) do
      {:ok, mod} -> mod
      {:error, :not_configured} -> fallback
    end
  end
end
