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

  alias Foglet.Accounts.PublicProfile
  alias Foglet.TUI.{Context, Effect, KeyBinding}
  alias Foglet.TUI.Guest
  alias Foglet.TUI.Screens.Domain
  alias Foglet.TUI.Screens.PostReader.Render
  alias Foglet.TUI.Screens.PostReader.State
  alias Foglet.TUI.Screens.Shared.Reporting
  alias Foglet.TUI.Theme
  alias Foglet.TUI.Widgets.Post.PostCard
  alias Foglet.TUI.Widgets.Post.ReplyContext
  alias Raxol.UI.Components.Display.Viewport

  @default_terminal_size {80, 24}
  @reader_window_size 50

  # FOG-652 / FOG-651: minimum number of body rows a trailing long post must
  # have visible before it is rendered as a partial selectable region under
  # preceding short posts. Below this threshold the long post is deferred to
  # its own screenful instead of being shown as a noisy 1-3 row stub.
  @partial_min_body_rows 4

  # Chrome rows consumed by a partial card itself (separator above + header +
  # progress line). Subtracted from the remaining-height budget when deciding
  # whether the partial fits and how many body rows are visible.
  @partial_chrome_rows 3

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
    limit = reader_window_limit(state)

    # IN-03: route-entry loads now honor the screen-local read pointer just
    # like the test-seam path (`load_posts/2`). Previously `update(:load, …)`
    # always emitted `:initial` or `:last`, ignoring `pending_read_positions`,
    # so a user re-entering a 200-post thread with their pointer at message
    # 150 landed at index 0 — a partial break of the moduledoc's
    # "if you saw it, you read it" promise. When a pointer exists we now
    # emit `:around` with `around_message_number: pointer`.
    read_pointer_msg_no = read_pointer_message_number(state, thread_id)
    opts = load_window_opts(read_pointer_msg_no, state.load_intent) ++ [limit: limit]

    new_state = %{state | status: :loading, last_op: :load_posts_window, last_error: nil}

    effect =
      Effect.task(:load_posts_window, fn ->
        load_reader_window(posts_mod, context.current_user, thread_id, opts)
      end)

    {new_state, [effect]}
  end

  def update(:load, %State{} = state, %Context{}) do
    {%{state | status: {:error, :missing_thread}, last_op: nil, last_error: :missing_thread}, []}
  end

  def update(
        {:task_result, :load_posts_window, {:ok, {:error, reason}}},
        %State{} = state,
        %Context{}
      ) do
    {reader_window_error_state(state, reason), []}
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
          selected_action_post_index: selected_index,
          window_first_message_number: Map.get(window, :first_message_number),
          window_last_message_number: Map.get(window, :last_message_number),
          window_has_previous?: Map.get(window, :has_previous?, false),
          window_has_next?: reader_window_has_next?(state, window, posts),
          pending_window_direction: nil
      }
      |> warm_selected_post(context)
      |> seed_pending_read_position_through_visible(context)

    {%{state | last_op: nil, last_error: nil}, []}
  end

  def update({:task_result, :load_posts_window, {:error, reason}}, %State{} = state, %Context{}) do
    {reader_window_error_state(state, reason), []}
  end

  def update({:task_result, :load_posts, {:ok, posts}}, %State{} = state, %Context{} = context)
      when is_list(posts) do
    selected_index = selected_index_after_load(state, posts)
    status = if posts == [], do: :empty, else: :loaded

    state =
      %{
        state
        | posts: posts,
          status: status,
          selected_post_index: selected_index,
          selected_action_post_index: selected_index
      }
      |> warm_selected_post(context)
      |> seed_pending_read_position_through_visible(context)

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
      Effect.task(:load_posts_window, fn ->
        load_reader_window(posts_mod, context.current_user, thread_id, opts)
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

  def update({:task_result, :toggle_upvote, result}, %State{} = state, %Context{} = context) do
    case Effect.unwrap_task_result(result) do
      {:ok, refreshed_post} when is_map(refreshed_post) ->
        state =
          state
          |> replace_loaded_post(refreshed_post)
          |> warm_selected_post(context)

        {%{state | last_op: nil, last_error: nil}, []}

      {:error, reason} ->
        {%{state | last_op: nil, last_error: reason}, []}
    end
  end

  def update({:task_result, :load_reply_context, result}, %State{} = state, %Context{} = context) do
    case Effect.unwrap_task_result(result) do
      {:ok, post} when is_map(post) ->
        reply_context = build_reply_context(post, context)
        modal = reply_context_modal(reply_context)

        {%{state | reply_context: reply_context, last_op: nil, last_error: nil},
         [Effect.open_modal(modal)]}

      {:error, _reason} ->
        {%{state | last_op: nil, last_error: :reply_context_unavailable},
         [Effect.open_modal(reply_context_unavailable_modal())]}
    end
  end

  def update(
        {:task_result, :toggle_reply_context_upvote, result},
        %State{} = state,
        %Context{} = context
      ) do
    case Effect.unwrap_task_result(result) do
      {:ok, refreshed_post} when is_map(refreshed_post) ->
        scroll_top = if state.reply_context, do: state.reply_context.scroll_top, else: 0
        reply_context = build_reply_context(refreshed_post, context, scroll_top: scroll_top)
        modal = reply_context_modal(reply_context)

        {%{state | reply_context: reply_context, last_op: nil, last_error: nil},
         [Effect.open_modal(modal)]}

      {:error, reason} ->
        {%{state | last_op: nil, last_error: reason}, []}
    end
  end

  def update({:reply_context_upvote, post_id, scroll_top}, %State{} = state, %Context{} = context)
      when is_binary(post_id) do
    if Guest.guest?(context) do
      {state, []}
    else
      posts_mod = resolve_domain_module(context, :posts, Foglet.Posts)
      user_id = user_id(context.current_user)
      state = update_reply_context_scroll(state, scroll_top)

      effect =
        Effect.task(:toggle_reply_context_upvote, fn ->
          posts_mod.toggle_upvote(user_id, post_id)
        end)

      {%{state | last_op: :toggle_reply_context_upvote, last_error: nil}, [effect]}
    end
  end

  def update({:key, event}, %State{} = state, %Context{} = context) when is_map(event) do
    handle_key(event, state, context)
  end

  def update(
        {:modal_submit, :report_selected_user, %{target_user: user}},
        %State{} = state,
        %Context{}
      )
      when is_map(user) do
    modal =
      Reporting.report_modal(
        :post_reader,
        :submit_user_report,
        %{
          target_kind: :user,
          target_id: Map.get(user, :id) || Map.get(user, "id"),
          target_label: "@#{Map.get(user, :handle) || Map.get(user, "handle") || "unknown"}"
        },
        title: "Report User"
      )

    {state, [Effect.open_modal(modal)]}
  end

  def update(
        {:modal_submit, :submit_user_report, payload},
        %State{} = state,
        %Context{} = context
      ) do
    moderation_mod = resolve_domain_module(context, :moderation, Foglet.Moderation)

    effect =
      Effect.task(:submit_user_report, fn ->
        moderation_mod.create_report(context.current_user, %{
          target_kind: Map.get(payload, :target_kind),
          target_id: Map.get(payload, :target_id),
          reason: Map.get(payload, :reason),
          notes: Map.get(payload, :notes)
        })
      end)

    {state, [effect]}
  end

  def update(
        {:modal_submit, :submit_post_report, payload},
        %State{} = state,
        %Context{} = context
      ) do
    moderation_mod = resolve_domain_module(context, :moderation, Foglet.Moderation)

    effect =
      Effect.task(:submit_post_report, fn ->
        moderation_mod.create_report(context.current_user, %{
          target_kind: Map.get(payload, :target_kind),
          target_id: Map.get(payload, :target_id),
          reason: Map.get(payload, :reason),
          notes: Map.get(payload, :notes)
        })
      end)

    {state, [effect]}
  end

  def update({:task_result, op, result}, %State{} = state, %Context{})
      when op in [:submit_user_report, :submit_post_report] do
    handle_report_submission_result(op, result, state)
  end

  def update(_message, %State{} = state, %Context{}), do: {state, []}

  defp handle_key(event, %State{} = state, %Context{} = context) do
    case movement_key(event) do
      {:advance, delta} ->
        advance_local_post(state, delta, context)

      {:arrow, delta} ->
        scroll_or_move_action_target(state, delta, context)

      {:tab, delta} ->
        move_action_target_for_visible_post(state, delta, context)

      {:scroll, delta} ->
        {scroll_local_post(state, delta, context), []}

      nil ->
        handle_action_key(event, state, context)
    end
  end

  defp movement_key(event) do
    advance_key(event) || selection_key(event) || reader_scroll_key(event)
  end

  defp advance_key(event) do
    cond do
      next_post?(event) -> {:advance, 1}
      previous_post?(event) -> {:advance, -1}
      true -> nil
    end
  end

  defp selection_key(event) do
    cond do
      arrow_down?(event) -> {:arrow, 1}
      arrow_up?(event) -> {:arrow, -1}
      tab_next?(event) -> {:tab, 1}
      tab_previous?(event) -> {:tab, -1}
      true -> nil
    end
  end

  defp reader_scroll_key(event) do
    cond do
      reader_scroll_down?(event) -> {:scroll, 1}
      reader_scroll_up?(event) -> {:scroll, -1}
      true -> nil
    end
  end

  defp handle_action_key(event, %State{} = state, %Context{} = context) do
    cond do
      plain_char?(event, ["u", "U"]) ->
        toggle_selected_post_upvote(state, context)

      plain_char?(event, ["v", "V"]) ->
        open_selected_author_profile(state, context)

      plain_char?(event, ["!"]) ->
        open_selected_post_report(state, context)

      plain_char?(event, ["c", "C"]) ->
        open_selected_reply_context(state, context)

      plain_char?(event, ["r", "R"]) ->
        reply_to_selected_post(state, context)

      cancel_reader?(event) ->
        leave_reader(state, context)

      true ->
        {state, []}
    end
  end

  defp next_post?(event), do: KeyBinding.page_down?(event) or plain_char?(event, ["n", "N", " "])

  defp previous_post?(event), do: KeyBinding.page_up?(event) or plain_char?(event, ["p", "P"])

  # Arrow movement has reader-specific behavior distinct from j/k: arrows move
  # the selected action target in packed layouts, while j/k scroll body content.
  defp arrow_down?(event), do: match?(%{key: :down}, event) and plain_event?(event)

  defp arrow_up?(event), do: match?(%{key: :up}, event) and plain_event?(event)

  defp tab_next?(event), do: match?(%{key: :tab}, event) and plain_event?(event)

  defp tab_previous?(event), do: match?(%{key: :backtab}, event) and plain_event?(event)

  defp reader_scroll_down?(event), do: plain_char?(event, ["j", "J"])

  defp reader_scroll_up?(event), do: plain_char?(event, ["k", "K"])

  defp cancel_reader?(event), do: KeyBinding.cancel?(event) or plain_char?(event, ["q", "Q"])

  defp plain_char?(%{key: :char, char: char} = event, chars) when is_list(chars) do
    char in chars and plain_event?(event)
  end

  defp plain_char?(_event, _chars), do: false

  defp plain_event?(event) when is_map(event) do
    Enum.all?(
      [:ctrl, :control, :alt, :meta, :shift],
      &(Map.get(event, &1, false) in [false, nil])
    )
  end

  defp reply_to_selected_post(%State{} = state, %Context{} = context) do
    cond do
      Guest.guest?(context) ->
        {state, [Effect.open_modal(Guest.denial_modal(:post))]}

      locked_thread?(state) or archived_board?(state) ->
        {state, []}

      true ->
        params = %{
          origin: :post_reader,
          board: state.board,
          board_id: state.board_id,
          thread: state.thread,
          thread_id: state.thread_id,
          reply_to: selected_action_post(state)
        }

        {state, [Effect.navigate(:post_composer, params)]}
    end
  end

  defp leave_reader(%State{} = state, %Context{} = context) do
    effects = [Effect.navigate(:thread_list, %{board: state.board, board_id: state.board_id})]

    effects =
      case flush_effect(state, context) do
        nil -> effects
        effect -> effects ++ [effect]
      end

    {state, effects}
  end

  @doc """
  Returns true when the screen-local thread is locked.

  FOG-91: PostReader uses this both to gate the `R` reply key and to surface
  a locked-thread affordance in render. Public so the render module and
  tests can call it without re-deriving the predicate.
  """
  @spec locked_thread?(State.t()) :: boolean()
  def locked_thread?(%State{thread: thread}) when is_map(thread) do
    Map.get(thread, :locked) == true
  end

  def locked_thread?(%State{}), do: false

  @doc """
  Returns true when the screen-local board is archived.

  FOG-96: PostReader uses this to gate the `R` reply key and to surface an
  archived-board affordance before the composer can be opened.
  """
  @spec archived_board?(State.t()) :: boolean()
  def archived_board?(%State{board: board}) when is_map(board) do
    Map.get(board, :archived, Map.get(board, "archived", false)) == true
  end

  def archived_board?(%State{}), do: false

  @impl true
  @spec render(State.t(), Context.t()) :: any()
  def render(%State{} = state, %Context{} = context), do: Render.render(state, context)

  @doc false
  @spec visible_screenful(State.t(), Context.t()) :: %{
          available_height: pos_integer(),
          indexes: [non_neg_integer()],
          mode: :packed | :long | :packed_partial,
          partial:
            nil
            | %{
                index: non_neg_integer(),
                post_id: String.t() | nil,
                body_visible_rows: pos_integer(),
                total_body_rows: non_neg_integer(),
                scroll_top: non_neg_integer()
              }
        }
  def visible_screenful(%State{posts: posts} = state, %Context{} = context)
      when is_list(posts) and posts != [] do
    {terminal_w, h} = context.terminal_size || @default_terminal_size
    w = Render.reader_width(terminal_w)
    available_height = reader_available_height(h)
    total = length(posts)
    top_idx = state.selected_post_index |> max(0) |> min(total - 1)
    frame_state = Render.frame_state(state, context)

    first_rows =
      post_card_row_count(frame_state, state, Enum.at(posts, top_idx), w, top_idx, total)

    if total == 1 or first_rows > available_height do
      %{available_height: available_height, indexes: [top_idx], mode: :long, partial: nil}
    else
      {indexes, used_rows} =
        pack_screenful_indexes(posts, frame_state, state, w, top_idx, total, available_height)

      next_idx = (List.last(indexes) || top_idx) + 1
      remaining = available_height - used_rows

      case maybe_partial(posts, next_idx, total, frame_state, state, w, remaining) do
        nil ->
          %{
            available_height: available_height,
            indexes: indexes,
            mode: :packed,
            partial: nil
          }

        partial ->
          %{
            available_height: available_height,
            indexes: indexes ++ [partial.index],
            mode: :packed_partial,
            partial: partial
          }
      end
    end
  end

  def visible_screenful(%State{}, %Context{} = context) do
    {_w, h} = context.terminal_size || @default_terminal_size

    %{
      available_height: reader_available_height(h),
      indexes: [],
      mode: :packed,
      partial: nil
    }
  end

  # FOG-652 / FOG-651: includes a trailing long post as a clipped, selectable
  # partial region when there is enough remaining space for the documented
  # minimum useful threshold (separator + header + progress + 4 body rows).
  defp maybe_partial(posts, next_idx, total, frame_state, state, w, remaining)
       when next_idx < total do
    body_budget = remaining - @partial_chrome_rows

    if body_budget >= @partial_min_body_rows do
      post = Enum.at(posts, next_idx)
      total_body_rows = post_card_body_row_count(frame_state, state, post, w, next_idx, total)

      # Only carve out a partial when the post would not have fit fully — a
      # post whose body fits inside `body_budget` is trivially a normal packed
      # card and should be added by the standard packer instead.
      if total_body_rows > body_budget do
        post_id = Map.get(post, :id)
        raw_scroll_top = partial_scroll_top_for(state, post_id)
        max_scroll = max(total_body_rows - body_budget, 0)
        scroll_top = raw_scroll_top |> max(0) |> min(max_scroll)

        %{
          index: next_idx,
          post_id: post_id,
          body_visible_rows: body_budget,
          total_body_rows: total_body_rows,
          scroll_top: scroll_top
        }
      end
    end
  end

  defp maybe_partial(_posts, _next_idx, _total, _frame_state, _state, _w, _remaining), do: nil

  defp partial_scroll_top_for(%State{partial_scroll_tops: tops}, post_id)
       when is_binary(post_id) do
    Map.get(tops, post_id, 0)
  end

  defp partial_scroll_top_for(_state, _post_id), do: 0

  @doc false
  @spec partial_at_bottom?(map() | nil) :: boolean()
  def partial_at_bottom?(%{scroll_top: s, body_visible_rows: v, total_body_rows: t}) do
    s + v >= t
  end

  def partial_at_bottom?(_), do: false

  @doc """
  Returns the post targeted by reader actions such as reply.

  In packed mode this may differ from `selected_post_index`, which remains the
  top/screenful anchor. In single-post and long-post mode it intentionally
  falls back to the anchor post. This is the named extension seam for future
  selected-post actions such as viewing the posting user's profile.
  """
  @spec selected_action_post(State.t()) :: map() | nil
  def selected_action_post(%State{posts: posts} = state) when is_list(posts) do
    idx = selected_action_post_index(state)
    Enum.at(posts, idx)
  end

  def selected_action_post(%State{}), do: nil

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
  Legacy/direct-invocation load seam for tests and callers outside the screen reducer.

  Seeds the screen-owned `pending_read_positions[thread_id]` slot through the
  visible reader screenful immediately on entry (LIST-01 D-05). For packed
  multi-post pages this means pressing Q right after opening a thread advances
  board/thread read pointers through the last fully visible post; a trailing
  partial long post is only marked read once it has been scrolled to bottom.

  **Dead-code audit (READER-02, D-03, D-04):** This public callback is
  intentional contract surface. Production orchestration is owned by the
  screen reducer's `:load` / `:load_posts_window` task path. This function
  exists as a stable screen-level test seam (verified in
  `post_reader_test.exs`) and as the callable entry point should direct
  invocation be needed. Do not delete or privatize without a corresponding
  context decision update.
  """
  @spec load_posts(map(), String.t()) :: {map(), list()}
  def load_posts(state, thread_id) do
    posts_mod = resolve_posts_mod(state)
    ss_before = get_screen_state(state)
    read_pointer_msg_no = read_pointer_message_number(ss_before, thread_id)

    opts = load_window_opts(read_pointer_msg_no, ss_before.load_intent)

    ss =
      case reader_window_result(posts_mod, Map.get(state, :current_user), thread_id, opts) do
        {:ok, window} ->
          posts = Map.get(window, :posts) || []

          {terminal_w, _h} = state.terminal_size || @default_terminal_size
          w = Render.reader_width(terminal_w)

          ss_before
          |> apply_window_to_screen_state(window, posts, thread_id)
          |> place_selection_after_load(window, posts, read_pointer_msg_no)
          |> warm_selected_post_artifacts(state, posts, w)
          |> seed_pending_read_position_through_visible(context_from_legacy_state(state))

        {:error, reason} ->
          reader_window_error_state(ss_before, reason)
      end

    # WR-03: mirror the `state.screen_state || %{}` guard from
    # apply_flush_result/4. `load_posts/2` is documented (READER-02) as a
    # public test seam and direct-invocation entry point; partial fixtures
    # whose `screen_state` is nil would otherwise raise `BadMapError`.
    {%{state | screen_state: Map.put(state.screen_state || %{}, :post_reader, ss)}, []}
  end

  # Phase 47 R2 (D-02 / D-03): route through list_reader_window/2 with
  # anchor mapping derived from screen-local read pointer + load_intent.
  # The read-pointer lookup stays where it already lives — the screen-owned
  # `pending_read_positions` map (D-03 forbids calling Threads here, and D-03
  # forbids adding a new :read_pointer direction — :around is the primitive).
  defp load_window_opts(_msg_no, {:around, message_number}) when is_integer(message_number) do
    [direction: :around, around_message_number: message_number]
  end

  defp load_window_opts(_msg_no, %{"around" => message_number}) when is_integer(message_number) do
    [direction: :around, around_message_number: message_number]
  end

  defp load_window_opts(message_number, _load_intent) when is_integer(message_number) do
    [direction: :around, around_message_number: message_number]
  end

  defp load_window_opts(_msg_no, {:around_message_number, message_number})
       when is_integer(message_number) and message_number > 0 do
    [direction: :around, around_message_number: message_number]
  end

  defp load_window_opts(_msg_no, intent) when intent in [:jump_last, "jump_last"] do
    [direction: :last]
  end

  defp load_window_opts(_msg_no, _intent), do: [direction: :initial]

  defp read_pointer_message_number(%State{pending_read_positions: positions}, thread_id) do
    case Map.get(positions || %{}, thread_id) do
      %{last_read_message_number: n} when is_integer(n) and n > 0 -> n
      _ -> nil
    end
  end

  defp resolve_posts_mod(state) do
    ctx = Map.get(state, :session_context) || %{}

    case Domain.get(ctx, :posts) do
      {:ok, mod} -> mod
      {:error, :not_configured} -> Foglet.Posts
    end
  end

  defp apply_window_to_screen_state(%State{} = ss, window, posts, thread_id) do
    %{
      ss
      | posts: posts,
        pending_read_positions:
          seed_read_position_on_entry(ss.pending_read_positions, thread_id, posts),
        window_first_message_number: Map.get(window, :first_message_number),
        window_last_message_number: Map.get(window, :last_message_number),
        window_has_previous?: Map.get(window, :has_previous?, false),
        window_has_next?: reader_window_has_next?(ss, window, posts)
    }
  end

  # D-04: when a read pointer drove the :around window, land selection on
  # the post matching that message_number (this is what makes the
  # "200 posts + pointer at 150" acceptance assertion pass). Otherwise,
  # defer to the Phase 44 helper, which handles :jump_last and :initial.
  #
  # WR-04: when the pointer is set but the exact message_number is not in
  # the window (post was soft-deleted, moved, or the pointer is otherwise
  # stale), fall back to the closest post with `message_number >= pointer`
  # rather than silently dropping the user at index 0.
  defp place_selection_after_load(%State{} = ss, window, posts, read_pointer_msg_no) do
    selected_index =
      if is_integer(read_pointer_msg_no) do
        index_of_message_number(posts, read_pointer_msg_no) ||
          index_of_first_message_number_at_or_after(posts, read_pointer_msg_no) ||
          if pointer_past_window_tail?(window, read_pointer_msg_no),
            do: max(length(posts) - 1, 0),
            else: selected_index_after_window_load(ss, window, posts)
      else
        selected_index_after_window_load(ss, window, posts)
      end

    %{ss | selected_post_index: selected_index, selected_action_post_index: selected_index}
  end

  # IN-02: when the read pointer is greater than every loaded message_number,
  # prefer the last loaded index over the generic-fallback's index 0 — the
  # user's pointer is past the loaded window, so landing them at the start
  # of an already-read window is worse than landing at its tail.
  defp pointer_past_window_tail?(window, pointer) do
    case Map.get(window, :last_message_number) do
      last when is_integer(last) -> pointer > last
      _ -> false
    end
  end

  # WR-04: locate the index of the first post whose `message_number` is
  # `>= target` — used as a fallback when the read-pointer's exact
  # message_number is missing from the loaded window.
  defp index_of_first_message_number_at_or_after(posts, target)
       when is_list(posts) and is_integer(target) do
    Enum.find_index(posts, fn post ->
      case Map.get(post, :message_number) do
        mn when is_integer(mn) -> mn >= target
        _ -> false
      end
    end)
  end

  defp index_of_first_message_number_at_or_after(_posts, _target), do: nil

  # WR-01: warm the render cache and viewport for the SELECTED post so the
  # initial render (before any keypress) does not re-parse on every frame and
  # j/k have the correct content_height for clamping on first keypress.
  defp warm_selected_post_artifacts(%State{} = ss, state, posts, w) do
    idx = ss.selected_post_index
    ss = warm_cache_for_index(ss, state, posts, idx, w)

    case Enum.at(posts, idx) do
      nil -> ss
      post -> warm_viewport(ss, state, post, w)
    end
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
    {terminal_w, _h} = state.terminal_size || @default_terminal_size
    w = Render.reader_width(terminal_w)
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

  defp context_from_legacy_state(state) when is_map(state) do
    Context.new(
      current_user: Map.get(state, :current_user),
      session_context: Map.get(state, :session_context) || %{},
      session_pid: Map.get(state, :session_pid),
      terminal_size: Map.get(state, :terminal_size) || @default_terminal_size,
      route: :post_reader,
      route_params: Map.get(state, :route_params) || %{}
    )
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

  @doc false
  @spec body_tuples_for(map(), map()) :: list()
  def body_tuples_for(frame_state, post) when is_map(frame_state) and is_map(post) do
    parse_body(frame_state, post)
  end

  # Populates the render_cache for the currently-selected post if it's
  # not yet cached. Returns the updated screen_state map.
  defp warm_cache(ss, state, post, w) do
    cache = render_cache_for_width(ss.render_cache, w)
    key = {post.id, w}

    if Map.has_key?(cache, key) do
      %{ss | render_cache: cache}
    else
      tuples = parse_body(state, post)
      %{ss | render_cache: Map.put(cache, key, tuples)}
    end
  end

  defp render_cache_for_width(render_cache, width) do
    render_cache
    |> Enum.reject(fn {{_post_id, cached_width}, _tuples} -> cached_width != width end)
    |> Map.new()
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

  defp reader_available_height(h) when is_integer(h), do: max(h - 12, 5)
  defp reader_available_height(_h), do: 12

  defp pack_screenful_indexes(posts, frame_state, state, w, top_idx, total, available_height) do
    top_idx..(total - 1)
    |> Enum.reduce_while({[], 0}, fn idx, {indexes, used_rows} ->
      rows = post_card_row_count(frame_state, state, Enum.at(posts, idx), w, idx, total)
      separator_rows = if indexes == [], do: 0, else: 1
      next_used_rows = used_rows + separator_rows + rows

      cond do
        indexes == [] ->
          {:cont, {[idx], rows}}

        next_used_rows <= available_height ->
          {:cont, {indexes ++ [idx], next_used_rows}}

        true ->
          {:halt, {indexes, used_rows}}
      end
    end)
  end

  defp post_card_row_count(_frame_state, _state, nil, _w, _idx, _total), do: 0

  defp post_card_row_count(frame_state, state, post, w, idx, total) do
    theme = Theme.from_state(frame_state)
    tuples = state.render_cache[{post.id, w}] || parse_body(frame_state, post)
    parts = reader_parts(post, tuples, w, theme, idx, total)

    header_rows = [parts.header, parts.progress] |> Enum.reject(&is_nil/1) |> length()
    header_rows + length(parts.body_lines)
  end

  defp post_card_body_row_count(_frame_state, _state, nil, _w, _idx, _total), do: 0

  defp post_card_body_row_count(frame_state, state, post, w, idx, total) do
    theme = Theme.from_state(frame_state)
    tuples = state.render_cache[{post.id, w}] || parse_body(frame_state, post)
    parts = reader_parts(post, tuples, w, theme, idx, total)

    length(parts.body_lines)
  end

  defp previous_screenful_anchor(%State{selected_post_index: current_idx}, %Context{})
       when current_idx <= 0,
       do: 0

  defp previous_screenful_anchor(%State{posts: posts} = state, %Context{} = context) do
    current_idx = state.selected_post_index

    0..(current_idx - 1)
    |> Enum.reduce(0, fn idx, best ->
      prior = visible_screenful(%{state | selected_post_index: idx}, context)
      last_visible = List.last(prior.indexes) || idx

      if last_visible < current_idx, do: idx, else: best
    end)
    |> min(length(posts) - 1)
  end

  defp seed_pending_read_position_through_visible(%State{} = state, %Context{} = context) do
    case visible_screenful(state, context) do
      %{indexes: []} ->
        state

      %{mode: :packed_partial, indexes: indexes, partial: partial} ->
        if partial_at_bottom?(partial) do
          seed_pending_read_position_at(state, List.last(indexes))
        else
          # FOG-652 / FOG-651: a partial long post must not be marked read
          # purely because its header or first slice is visible. Seed the
          # read pointer through the post immediately preceding the partial.
          before_partial =
            indexes
            |> Enum.reject(&(&1 == partial.index))
            |> List.last()

          if is_integer(before_partial),
            do: seed_pending_read_position_at(state, before_partial),
            else: state
        end

      %{indexes: indexes} ->
        seed_pending_read_position_at(state, List.last(indexes))
    end
  end

  defp seed_pending_read_position_at(%State{thread_id: thread_id, posts: posts} = state, idx)
       when is_binary(thread_id) and is_list(posts) and is_integer(idx) do
    case Enum.at(posts, idx) do
      nil ->
        state

      post ->
        next = %{
          last_read_post_id: Map.get(post, :id),
          last_read_message_number: Map.get(post, :message_number) || 0
        }

        pending =
          Map.update(state.pending_read_positions, thread_id, next, fn current ->
            if next.last_read_message_number >= Map.get(current, :last_read_message_number, 0),
              do: next,
              else: current
          end)

        %{state | pending_read_positions: pending}
    end
  end

  defp seed_pending_read_position_at(%State{} = state, _idx), do: state

  # IN-03: `load_direction/1` removed — `update(:load, …)` now uses
  # `load_window_opts/2`, which already encodes the same `:jump_last → :last`,
  # `else → :initial` mapping plus the new pointer-aware `:around` branch.

  defp reader_window_limit(%State{reader_window_limit: limit})
       when is_integer(limit) and limit > 0,
       do: limit

  defp reader_window_limit(%State{}), do: @reader_window_size

  defp selected_index_after_load(%State{load_intent: intent}, posts)
       when intent in [:jump_last, "jump_last"] do
    max(length(posts) - 1, 0)
  end

  defp selected_index_after_load(_state, _posts), do: 0

  defp selected_index_after_window_load(%State{pending_window_direction: :next}, _window, _posts),
    do: 0

  defp selected_index_after_window_load(
         %State{pending_window_direction: :previous},
         _window,
         posts
       ) do
    max(length(posts) - 1, 0)
  end

  defp selected_index_after_window_load(%State{load_intent: intent}, _window, posts)
       when intent in [:jump_last, "jump_last"] do
    max(length(posts) - 1, 0)
  end

  defp selected_index_after_window_load(
         %State{load_intent: {:around_message_number, message_number}},
         _window,
         posts
       ) do
    index_of_message_number(posts, message_number) || 0
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

  # Phase 47 R2 (D-04): locates a post in the loaded window by its
  # `message_number`. Used by load_posts/2 to land selection on the read
  # pointer after an :around window load.
  defp index_of_message_number(posts, message_number)
       when is_list(posts) and is_integer(message_number) do
    Enum.find_index(posts, fn post -> Map.get(post, :message_number) == message_number end)
  end

  defp index_of_message_number(_posts, _message_number), do: nil

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

  defp selected_post(%State{posts: posts, selected_post_index: idx}) when is_list(posts) do
    Enum.at(posts, idx)
  end

  defp selected_post(%State{}), do: nil

  defp selected_action_post_index(%State{selected_action_post_index: idx, posts: posts})
       when is_integer(idx) and is_list(posts) do
    idx |> max(0) |> min(max(length(posts) - 1, 0))
  end

  defp selected_action_post_index(%State{selected_post_index: idx}), do: idx

  defp load_public_profile(user, %Context{} = context) when is_map(user) do
    profile_mod = resolve_domain_module(context, :public_profile, PublicProfile)

    with user_id when is_binary(user_id) <- Map.get(user, :id) || Map.get(user, "id"),
         {:ok, %PublicProfile{} = profile} <- profile_mod.load(user_id) do
      profile
    else
      _ -> PublicProfile.from_user(user)
    end
  end

  defp toggle_selected_post_upvote(%State{} = state, %Context{} = context) do
    with %{id: user_id} when is_binary(user_id) <- context.current_user,
         %{id: post_id} when is_binary(post_id) <- selected_action_post(state) do
      posts_mod = resolve_domain_module(context, :posts, Foglet.Posts)

      effect =
        Effect.task(:toggle_upvote, fn ->
          posts_mod.toggle_upvote(user_id, post_id)
        end)

      {%{state | last_op: :toggle_upvote, last_error: nil}, [effect]}
    else
      _ -> {state, []}
    end
  end

  defp open_selected_author_profile(%State{} = state, %Context{} = context) do
    with false <- Guest.guest?(context),
         %{user: user} when is_map(user) <- selected_action_post(state),
         user_id when is_binary(user_id) <- Map.get(user, :id) || Map.get(user, "id") do
      profile = load_public_profile(user, context)

      modal =
        Reporting.public_profile_modal(
          :post_reader,
          :report_selected_user,
          profile,
          %{target_user: user}
        )

      {state, [Effect.open_modal(modal)]}
    else
      _ -> {state, []}
    end
  end

  defp open_selected_post_report(%State{} = state, %Context{} = context) do
    with false <- Guest.guest?(context),
         %{id: post_id} = post when is_binary(post_id) <- selected_action_post(state) do
      modal =
        Reporting.report_modal(
          :post_reader,
          :submit_post_report,
          %{
            target_kind: :post,
            target_id: post_id,
            target_label: "post ##{Map.get(post, :message_number) || "?"}"
          },
          title: "Report Post"
        )

      {state, [Effect.open_modal(modal)]}
    else
      _ -> {state, []}
    end
  end

  defp open_selected_reply_context(%State{} = state, %Context{} = context) do
    with post when is_map(post) <- selected_action_post(state),
         reply_to_id when is_binary(reply_to_id) <- reply_target_id(post) do
      posts_mod = resolve_domain_module(context, :posts, Foglet.Posts)

      effect =
        Effect.task(:load_reply_context, fn ->
          posts_mod.fetch_readable_post(context.current_user, reply_to_id)
        end)

      {%{state | last_op: :load_reply_context, last_error: nil}, [effect]}
    else
      _ -> {state, []}
    end
  end

  defp reply_target_id(%{reply_to_id: id}) when is_binary(id), do: id
  defp reply_target_id(%{"reply_to_id" => id}) when is_binary(id), do: id
  defp reply_target_id(%{reply_to: %{id: id}}) when is_binary(id), do: id
  defp reply_target_id(%{"reply_to" => %{"id" => id}}) when is_binary(id), do: id
  defp reply_target_id(_post), do: nil

  @doc false
  @spec reply_context_available?(map() | nil) :: boolean()
  def reply_context_available?(post), do: is_binary(reply_target_id(post))

  defp build_reply_context(post, %Context{} = context, opts \\ []) do
    {terminal_w, terminal_h} = context.terminal_size || @default_terminal_size
    frame_state = %{current_user: context.current_user, session_context: context.session_context}
    body_tuples = body_tuples_for(frame_state, post)

    ReplyContext.new(post, body_tuples,
      visible_body_rows: reply_context_body_rows(terminal_h),
      scroll_top: Keyword.get(opts, :scroll_top, 0),
      upvote?: not Guest.guest?(context),
      profile?: false,
      width: Render.reader_width(terminal_w)
    )
  end

  defp reply_context_body_rows(terminal_h) when is_integer(terminal_h),
    do: (terminal_h - 14) |> max(4) |> min(10)

  defp reply_context_body_rows(_terminal_h), do: 8

  defp reply_context_modal(%ReplyContext{} = reply_context) do
    %Foglet.TUI.Modal{
      type: :reply_context,
      title: "Reply context",
      message: reply_context,
      on_cancel: :dismiss_modal,
      on_confirm: :dismiss_modal
    }
  end

  defp reply_context_unavailable_modal do
    %Foglet.TUI.Modal{
      type: :warning,
      title: "Reply unavailable",
      message: "That replied-to post is no longer available to this session."
    }
  end

  defp update_reply_context_scroll(
         %State{reply_context: %ReplyContext{} = reply_context} = state,
         scroll_top
       ) do
    %{state | reply_context: %{reply_context | scroll_top: max(scroll_top || 0, 0)}}
  end

  defp update_reply_context_scroll(%State{} = state, _scroll_top), do: state

  defp user_id(%{id: id}) when is_binary(id), do: id
  defp user_id(_user), do: nil

  defp replace_loaded_post(%State{posts: posts} = state, refreshed_post) when is_list(posts) do
    refreshed_id = Map.get(refreshed_post, :id)

    posts =
      Enum.map(posts, fn post ->
        if same_post_id?(post, refreshed_id),
          do: merge_refreshed_post(post, refreshed_post),
          else: post
      end)

    %{state | posts: posts}
  end

  defp replace_loaded_post(%State{} = state, _refreshed_post), do: state

  defp same_post_id?(post, refreshed_id) when is_binary(refreshed_id) do
    Map.get(post, :id) == refreshed_id
  end

  defp same_post_id?(_post, _refreshed_id), do: false

  defp merge_refreshed_post(original, refreshed_post) do
    Map.merge(
      original,
      Map.take(refreshed_post, [:upvote_count, :user, :reply_to, :body, :deleted_at])
    )
  end

  defp advance_local_post(%State{posts: posts} = state, _delta, _context)
       when posts in [nil, []] do
    {state, []}
  end

  defp advance_local_post(%State{posts: posts} = state, delta, %Context{} = context) do
    current_idx = state.selected_post_index
    screenful = visible_screenful(state, context)
    last_visible_idx = List.last(screenful.indexes) || current_idx

    cond do
      # FOG-652 / FOG-651: when the screenful contains a partial long post
      # that has not been scrolled to its bottom (read-condition), N promotes
      # that long post to the next main viewport instead of skipping past it.
      # The partial's preserved scroll offset is carried into the viewport so
      # the user does not lose their place.
      delta > 0 and screenful.mode == :packed_partial and
          not partial_at_bottom?(screenful.partial) ->
        promote_partial_to_anchor(state, screenful.partial, context)

      should_load_next_window?(state, posts, delta, last_visible_idx) ->
        load_adjacent_window(state, :next, context)

      should_load_previous_window?(state, delta, current_idx) ->
        load_adjacent_window(state, :previous, context)

      true ->
        new_idx = next_post_index(state, posts, delta, current_idx, last_visible_idx, context)
        {reset_vp, _cmds} = Viewport.update({:scroll_to, 0}, state.viewport)

        state =
          %{
            state
            | selected_post_index: new_idx,
              selected_action_post_index: new_idx,
              viewport: reset_vp
          }
          |> warm_selected_post(context)
          |> seed_pending_read_position_through_visible(context)

        {state, []}
    end
  end

  defp should_load_next_window?(%State{} = state, posts, delta, last_visible_idx) do
    delta > 0 and last_visible_idx == length(posts) - 1 and state.window_has_next? and
      length(posts) >= reader_window_limit(state)
  end

  defp reader_window_has_next?(%State{} = state, window, posts) when is_list(posts) do
    Map.get(window, :has_next?, false) and length(posts) >= reader_window_limit(state)
  end

  defp reader_window_has_next?(%State{}, _window, _posts), do: false

  defp should_load_previous_window?(%State{} = state, delta, current_idx) do
    delta < 0 and current_idx == 0 and state.window_has_previous?
  end

  defp next_post_index(_state, posts, delta, _current_idx, last_visible_idx, _context)
       when delta > 0 do
    min(last_visible_idx + 1, length(posts) - 1)
  end

  defp next_post_index(state, _posts, delta, _current_idx, _last_visible_idx, context)
       when delta < 0 do
    previous_screenful_anchor(state, context)
  end

  defp next_post_index(_state, _posts, _delta, current_idx, _last_visible_idx, _context) do
    current_idx
  end

  defp load_adjacent_window(%State{thread_id: thread_id} = state, direction, %Context{} = context)
       when is_binary(thread_id) do
    posts_mod = resolve_domain_module(context, :posts, Foglet.Posts)
    opts = adjacent_window_opts(state, direction)

    effect =
      Effect.task(:load_posts_window, fn ->
        load_reader_window(posts_mod, context.current_user, thread_id, opts)
      end)

    {%{
       state
       | status: :loading,
         last_op: :load_posts_window,
         pending_window_direction: direction
     }, [effect]}
  end

  defp load_adjacent_window(%State{} = state, _direction, %Context{}), do: {state, []}

  defp adjacent_window_opts(%State{} = state, :next) do
    [
      direction: :next,
      after_message_number: state.window_last_message_number,
      limit: reader_window_limit(state)
    ]
  end

  defp adjacent_window_opts(%State{} = state, :previous) do
    [
      direction: :previous,
      before_message_number: state.window_first_message_number,
      limit: reader_window_limit(state)
    ]
  end

  defp load_reader_window(posts_mod, actor, thread_id, opts) do
    case reader_window_result(posts_mod, actor, thread_id, opts) do
      {:ok, window} -> window
      {:error, reason} -> {:error, reason}
    end
  end

  defp reader_window_result(posts_mod, actor, thread_id, opts) do
    if function_exported?(posts_mod, :list_reader_window_for, 3) do
      posts_mod.list_reader_window_for(actor, thread_id, opts)
    else
      {:ok, posts_mod.list_reader_window(thread_id, opts)}
    end
  end

  defp reader_window_error_state(%State{} = state, reason) do
    %{
      state
      | posts: [],
        status: {:error, reason},
        selected_post_index: 0,
        selected_action_post_index: 0,
        window_first_message_number: nil,
        window_last_message_number: nil,
        window_has_previous?: false,
        window_has_next?: false,
        pending_window_direction: nil,
        last_op: nil,
        last_error: reason
    }
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
        state = warm_selected_post(state, context)
        screenful = visible_screenful(state, context)
        action_idx = selected_action_post_index(state)

        cond do
          screenful.mode == :long ->
            {_w, h} = context.terminal_size
            available_height = reader_available_height(h)

            {new_vp, _cmds} =
              Viewport.update({:set_visible_height, available_height}, state.viewport)

            {new_vp, _cmds} = Viewport.update({:scroll_by, delta}, new_vp)
            %{state | viewport: new_vp}

          screenful.mode == :packed_partial and action_idx == screenful.partial.index ->
            scroll_partial_post(state, delta, screenful.partial, context)

          true ->
            state
        end
    end
  end

  # FOG-652 / FOG-651: J/K scroll for the selected partial long post under
  # preceding short-post context. Updates the per-post scroll_top, clamps at
  # top/bottom (no wrap), and seeds the read pointer through the partial only
  # once the bottom is reached.
  # FOG-652 / FOG-651: promote a partial long post to the main viewport while
  # preserving any scroll offset that was accumulated in the partial region.
  defp promote_partial_to_anchor(%State{} = state, partial, %Context{} = context) do
    state =
      %{
        state
        | selected_post_index: partial.index,
          selected_action_post_index: partial.index
      }
      |> warm_selected_post(context)

    {new_vp, _cmds} = Viewport.update({:scroll_to, partial.scroll_top}, state.viewport)

    state =
      %{state | viewport: new_vp}
      |> seed_pending_read_position_through_visible(context)

    {state, []}
  end

  defp scroll_partial_post(%State{} = state, delta, partial, %Context{} = context) do
    max_scroll = max(partial.total_body_rows - partial.body_visible_rows, 0)
    new_scroll = (partial.scroll_top + delta) |> max(0) |> min(max_scroll)

    new_tops =
      if is_binary(partial.post_id) do
        Map.put(state.partial_scroll_tops, partial.post_id, new_scroll)
      else
        state.partial_scroll_tops
      end

    state = %{state | partial_scroll_tops: new_tops}
    seed_pending_read_position_through_visible(state, context)
  end

  defp scroll_or_move_action_target(%State{} = state, delta, %Context{} = context) do
    state = warm_selected_post(state, context)
    screenful = visible_screenful(state, context)
    action_idx = selected_action_post_index(state)

    cond do
      screenful.mode == :long ->
        {scroll_local_post(state, delta, context), []}

      screenful.mode == :packed_partial and action_idx == screenful.partial.index ->
        maybe_scroll_selected_partial_or_move(state, delta, screenful.partial, context)

      true ->
        move_action_target_for_visible_post(state, delta, context)
    end
  end

  defp maybe_scroll_selected_partial_or_move(
         %State{} = state,
         delta,
         partial,
         %Context{} = context
       ) do
    max_scroll = max(partial.total_body_rows - partial.body_visible_rows, 0)

    cond do
      delta > 0 and partial.scroll_top < max_scroll ->
        {scroll_partial_post(state, delta, partial, context), []}

      delta < 0 and partial.scroll_top > 0 ->
        {scroll_partial_post(state, delta, partial, context), []}

      true ->
        move_action_target_for_visible_post(state, delta, context)
    end
  end

  defp move_action_target_for_visible_post(%State{posts: posts} = state, _delta, _context)
       when posts in [nil, []] do
    {state, []}
  end

  defp move_action_target_for_visible_post(%State{} = state, delta, %Context{} = context) do
    screenful = visible_screenful(state, context)

    case screenful do
      %{mode: mode, indexes: indexes}
      when mode in [:packed, :packed_partial] and length(indexes) > 1 ->
        move_selected_action_post(state, indexes, delta, context)

      %{indexes: [_single]} when delta < 0 and state.selected_post_index > 0 ->
        move_to_previous_screenful_tail(state, context)

      _other ->
        {state, []}
    end
  end

  defp move_selected_action_post(%State{} = state, visible_indexes, delta, %Context{} = context)
       when is_list(visible_indexes) and visible_indexes != [] do
    current_position = visible_position(visible_indexes, selected_action_post_index(state))
    last_position = length(visible_indexes) - 1

    move_selected_action_post_at_position(
      state,
      visible_indexes,
      delta,
      context,
      current_position,
      last_position
    )
  end

  defp move_selected_action_post(%State{} = state, _visible_indexes, _delta, %Context{}),
    do: {state, []}

  defp visible_position(visible_indexes, current) do
    case Enum.find_index(visible_indexes, &(&1 == current)) do
      nil -> 0
      position -> position
    end
  end

  defp move_selected_action_post_at_position(
         %State{} = state,
         visible_indexes,
         delta,
         %Context{} = context,
         current_position,
         last_position
       )
       when delta > 0 and current_position == last_position do
    if can_advance_beyond_visible_posts?(state, visible_indexes) do
      advance_local_post(state, 1, context)
    else
      {state, []}
    end
  end

  defp move_selected_action_post_at_position(
         %State{} = state,
         _visible_indexes,
         delta,
         %Context{} = context,
         0,
         _last_position
       )
       when delta < 0 do
    move_to_previous_screenful_tail(state, context)
  end

  defp move_selected_action_post_at_position(
         %State{} = state,
         visible_indexes,
         delta,
         %Context{},
         current_position,
         last_position
       ) do
    next_position = (current_position + delta) |> max(0) |> min(last_position)
    {%{state | selected_action_post_index: Enum.at(visible_indexes, next_position)}, []}
  end

  defp can_advance_beyond_visible_posts?(%State{} = state, visible_indexes) do
    List.last(visible_indexes) < length(state.posts || []) - 1 or state.window_has_next?
  end

  defp move_to_previous_screenful_tail(%State{} = state, %Context{} = context) do
    cond do
      should_load_previous_window?(state, -1, state.selected_post_index) ->
        load_adjacent_window(state, :previous, context)

      state.selected_post_index > 0 ->
        new_anchor = previous_screenful_anchor(state, context)

        previous_screenful =
          visible_screenful(%{state | selected_post_index: new_anchor}, context)

        new_action_idx = List.last(previous_screenful.indexes) || new_anchor
        {reset_vp, _cmds} = Viewport.update({:scroll_to, 0}, state.viewport)

        state =
          %{
            state
            | selected_post_index: new_anchor,
              selected_action_post_index: new_action_idx,
              viewport: reset_vp
          }
          |> warm_selected_post(context)
          |> seed_pending_read_position_through_visible(context)

        {state, []}

      true ->
        {state, []}
    end
  end

  defp warm_selected_post(%State{} = state, %Context{} = context) do
    case selected_post(state) do
      nil ->
        state

      post ->
        {terminal_w, _h} = context.terminal_size || @default_terminal_size
        w = Render.reader_width(terminal_w)
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

        Effect.task(:flush_read_pointers, fn ->
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

  defp handle_report_submission_result(op, result, %State{} = state) do
    case Effect.unwrap_task_result(result) do
      {:ok, _report} ->
        {state, [Effect.open_modal(Reporting.success_modal("Report submitted."))]}

      {:error, %Ecto.Changeset{} = changeset} ->
        {state, [Effect.open_modal(report_submission_error_modal(op, changeset))]}

      {:error, reason} ->
        {state,
         [
           Effect.open_modal(%Foglet.TUI.Modal{
             type: :error,
             title: "Error",
             message: "Unable to submit report: #{inspect(reason)}"
           })
         ]}
    end
  end

  defp report_submission_error_modal(_op, %Ecto.Changeset{} = changeset) do
    target_kind =
      Map.get(changeset.changes, :target_kind) || Map.get(changeset.data, :target_kind)

    op = if(target_kind == :user, do: :submit_user_report, else: :submit_post_report)
    title = if(target_kind == :user, do: "Report User", else: "Report Post")

    Reporting.report_modal(
      :post_reader,
      op,
      %{
        target_kind: target_kind,
        target_id: Map.get(changeset.changes, :target_id) || Map.get(changeset.data, :target_id),
        target_label: "selected target"
      },
      title: title,
      values: %{
        reason: Map.get(changeset.changes, :reason) || Map.get(changeset.data, :reason),
        notes: Map.get(changeset.changes, :notes) || Map.get(changeset.data, :notes)
      },
      errors: Reporting.changeset_errors(changeset)
    )
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
