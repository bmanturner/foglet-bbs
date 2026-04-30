defmodule Foglet.TUI.Screens.PostReader do
  @moduledoc """
  Post reader for a single thread (SSH-07, SSH-08, SSH-09).

  Phase 37 makes PostReader screen-owned: loaded posts, selected index,
  viewport/cache state, route identity, pending read data, load status, and
  flush results live in `%PostReader.State{}` and flow through `update/3`.

  Renders posts via Post.PostCard + Post.MarkdownBody (RENDER-01, RENDER-02).
  Paginates with n/p keys; scrolls within a post with j/k keys.
  Local read-pointer state (`%State{}.pending_read_positions`) updates on each advance;
  flush to DB happens on screen transition via {:flush_read_pointers, ctx}
  command handled by TUI.App.update/2 (SSH-09).

  ## Load-absorb behavior (READER-07, AUDIT-18 deviation note)

  While posts are still loading (the screen-state `posts` slot is `[]` or
  `nil`), the navigation
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

  The cache is discarded on `Q` (screen exit) and rebuilt on re-entry.
  """

  @behaviour Foglet.TUI.Screen

  alias Foglet.TUI.{Context, Effect}
  alias Foglet.TUI.Screens.Domain
  alias Foglet.TUI.Screens.PostReader.Render
  alias Foglet.TUI.Screens.PostReader.State
  alias Foglet.TUI.Theme
  alias Foglet.TUI.Widgets.Post.PostCard
  alias Raxol.UI.Components.Display.Viewport

  @default_terminal_size {80, 24}
  @reader_window_size 50

  @impl true
  @spec init(Context.t()) :: State.t()
  def init(%Context{} = context), do: State.from_context(context)

  @impl true
  @spec update(term(), State.t(), Context.t()) :: {State.t(), [Effect.t()]}
  # Phase 39 D-01/D-03/D-14: screen owns its route-entry signal.
  # Today (app.ex:838-843) PostReader's per-screen App clause only dispatches
  # :load when route_param(params, :thread_id) is binary. The state-first
  # clause below preserves re-entry hydrated via local State (e.g. back-nav
  # with empty route_params), and the route_params-fallback clause matches
  # both atom and string keys to mirror subscriptions/2's shape.
  def update(:on_route_enter, %State{thread_id: thread_id} = state, %Context{} = context)
      when is_binary(thread_id) do
    update(:load, state, context)
  end

  def update(:on_route_enter, %State{} = state, %Context{route_params: params} = context) do
    case Map.get(params, :thread_id) || Map.get(params, "thread_id") do
      thread_id when is_binary(thread_id) -> update(:load, state, context)
      _other -> {state, []}
    end
  end

  def update(:load, %State{thread_id: thread_id} = state, %Context{} = context)
      when is_binary(thread_id) do
    posts_mod = resolve_domain_module(context, :posts, Foglet.Posts)
    direction = load_direction(state)
    limit = reader_window_limit(state)

    new_state = %{state | status: :loading, last_op: :load_posts_window, last_error: nil}

    effect =
      Effect.task(:load_posts_window, :post_reader, fn ->
        posts_mod.list_reader_window(thread_id, direction: direction, limit: limit)
      end)

    {new_state, [effect]}
  end

  def update(:load, %State{} = state, %Context{}) do
    {%{state | status: {:error, :missing_thread}, last_op: nil, last_error: :missing_thread}, []}
  end

  def update(
        {:task_result, :load_posts_window, {:ok, window}},
        %State{} = state,
        %Context{} = context
      ) do
    posts = Map.get(window, :posts) || []
    selected_index = selected_index_after_window_load(state, window, posts)
    status = if posts == [], do: :empty, else: :loaded

    state =
      %{
        state
        | posts: posts,
          status: status,
          selected_post_index: selected_index,
          window_first_message_number: Map.get(window, :first_message_number),
          window_last_message_number: Map.get(window, :last_message_number),
          window_has_previous?: Map.get(window, :has_previous?, false),
          window_has_next?: Map.get(window, :has_next?, false)
      }
      |> seed_pending_read_position()
      |> warm_selected_post(context)

    {%{state | last_op: nil, last_error: nil}, []}
  end

  def update({:task_result, :load_posts_window, {:error, reason}}, %State{} = state, %Context{}) do
    {%{state | status: {:error, reason}, last_op: nil, last_error: reason}, []}
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
    opts = thread_activity_window_opts(state)

    effect =
      Effect.task(:load_posts_window, :post_reader, fn ->
        posts_mod.list_reader_window(thread_id, opts)
      end)

    {%{state | last_op: :load_posts_window, last_error: nil}, [effect]}
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
  def render(%State{} = state, %Context{} = context), do: Render.render(state, context)

  @impl true
  @spec subscriptions(State.t() | nil, Context.t()) :: [String.t()]
  def subscriptions(%State{thread_id: thread_id}, _context) when is_binary(thread_id) do
    [Foglet.PubSub.thread_topic(thread_id)]
  end

  def subscriptions(_local_state, %Context{route_params: params}) do
    case Map.get(params, :thread_id) || Map.get(params, "thread_id") do
      thread_id when is_binary(thread_id) -> [Foglet.PubSub.thread_topic(thread_id)]
      _other -> []
    end
  end

  @doc """
  Called by App.update/2 on {:load_posts, thread_id}.

  Seeds the screen-owned `pending_read_positions[thread_id]` slot with post 0's
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

    load_thread_id = thread_id
    posts = posts_mod.list_posts(load_thread_id)

    new_pending_read_positions =
      seed_read_position_on_entry(
        get_screen_state(state).pending_read_positions,
        thread_id,
        posts
      )

    {w, _h} = state.terminal_size || @default_terminal_size

    # WR-01: warm the render cache for the first post on load so that the
    # initial render (before any keypress) does not re-parse on every frame.
    # Phase 39 Plan 39-07: posts now live on the screen-owned %State{}; pass
    # `posts` directly so warm_cache_for_index/warm_viewport don't have to
    # read them back through the deleted `state.posts` field.
    ss = get_screen_state(state)
    ss = %{ss | posts: posts, pending_read_positions: new_pending_read_positions}
    ss = warm_cache_for_index(ss, state, posts, 0, w)

    # Pre-populate the viewport children for post 0 so j/k have correct
    # content_height for clamping on first keypress.
    first_post = Enum.at(posts, 0)
    ss = if first_post, do: warm_viewport(ss, state, first_post, w), else: ss

    new_screen_state = Map.put(state.screen_state, :post_reader, ss)

    {%{state | screen_state: new_screen_state}, []}
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
  # Phase 39 Plan 39-07: writes the cleared pending_read_positions onto the
  # screen-owned %State{} under state.screen_state[:post_reader] (the legacy
  # App-shape `:read_position` field has been deleted).
  defp apply_flush_result(state, flush_ctx, board_result, thread_result) do
    if flush_result_ok?(board_result) and flush_result_ok?(thread_result) do
      ss = get_screen_state(state)
      new_pending = clear_read_position(ss.pending_read_positions, flush_ctx[:thread_id])
      new_ss = %{ss | pending_read_positions: new_pending}
      new_screen_state = Map.put(state.screen_state || %{}, :post_reader, new_ss)

      {%{state | screen_state: new_screen_state}, []}
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

  # Phase 39 Plan 39-07: legacy App-shape helper bodies (load_posts/2,
  # apply_flush_result/4) source what they need from the screen-owned State
  # struct under state.screen_state[:post_reader]. The pre-39-07 backfill from
  # the deleted App-shape top-level keys (`:posts`, `:read_position`,
  # `:current_thread`, `:current_board`) is gone alongside those fields.
  defp get_screen_state(%{screen_state: %{post_reader: %State{} = ss}}), do: ss
  defp get_screen_state(_state), do: State.new()

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

  @doc false
  @spec body_tuples_for(map(), map()) :: list()
  def body_tuples_for(frame_state, post) when is_map(frame_state) and is_map(post) do
    parse_body(frame_state, post)
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
    posts = ss.posts || get_screen_state(state).posts || []
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

  defp load_direction(%State{load_intent: intent}) when intent in [:jump_last, "jump_last"],
    do: :last

  defp load_direction(%State{}), do: :initial

  defp reader_window_limit(%State{reader_window_limit: limit})
       when is_integer(limit) and limit > 0,
       do: limit

  defp reader_window_limit(%State{}), do: @reader_window_size

  defp selected_index_after_load(%State{load_intent: intent}, posts)
       when intent in [:jump_last, "jump_last"] do
    max(length(posts) - 1, 0)
  end

  defp selected_index_after_load(_state, _posts), do: 0

  defp selected_index_after_window_load(%State{load_intent: intent}, _window, posts)
       when intent in [:jump_last, "jump_last"] do
    max(length(posts) - 1, 0)
  end

  defp selected_index_after_window_load(%State{} = state, window, posts) do
    case window_direction(window) do
      :last ->
        max(length(posts) - 1, 0)

      _other ->
        selected_index_matching_current_post(state, posts)
    end
  end

  defp window_direction(window), do: Map.get(window, :direction)

  defp selected_index_matching_current_post(%State{} = state, posts) do
    current = selected_post(state)

    posts
    |> Enum.find_index(fn post -> same_post?(post, current) end)
    |> case do
      nil -> 0
      idx -> idx
    end
  end

  defp same_post?(_post, nil), do: false

  defp same_post?(post, current) do
    (Map.get(post, :id) && Map.get(post, :id) == Map.get(current, :id)) ||
      (Map.get(post, :message_number) &&
         Map.get(post, :message_number) == Map.get(current, :message_number))
  end

  defp thread_activity_window_opts(%State{} = state) do
    selected_message_number =
      state
      |> selected_post()
      |> message_number()

    around_message_number =
      selected_message_number ||
        state.window_first_message_number ||
        state.window_last_message_number

    [
      direction: :around,
      around_message_number: around_message_number,
      limit: reader_window_limit(state)
    ]
  end

  defp message_number(nil), do: nil
  defp message_number(post), do: Map.get(post, :message_number)

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
        frame_state = Render.frame_state(state, context)
        state = warm_cache(state, frame_state, post, w)
        frame_state = Render.frame_state(state, context)
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
