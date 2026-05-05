defmodule Foglet.TUI.Screens.ThreadList do
  @moduledoc """
  Thread list for a selected board (SSH-07, SSH-08).

  ThreadList is a screen-owned reducer over `ThreadList.State` and route
  params; App only routes keys, task results, and effects.

  Sticky threads rendered first; within each group, newest-activity-first.
  Each row shows title and unread count.
  """

  @behaviour Foglet.TUI.Screen

  alias Foglet.Accounts.User
  alias Foglet.Boards.Board
  alias Foglet.PostingPolicy
  alias Foglet.Threads.ThreadEntry
  alias Foglet.TimeAgo
  alias Foglet.TUI.{Context, Effect}
  alias Foglet.TUI.Guest
  alias Foglet.TUI.Screens.Domain
  alias Foglet.TUI.Screens.ThreadList.State
  alias Foglet.TUI.Theme
  alias Foglet.TUI.Widgets.Chrome.ScreenFrame
  alias Foglet.TUI.Widgets.List.{RichRow, SelectionList}
  alias Foglet.TUI.Widgets.Progress.Spinner

  import Raxol.Core.Renderer.View

  @impl true
  @spec init(Context.t()) :: State.t()
  def init(%Context{} = context), do: State.from_context(context)

  @impl true
  @spec update(term(), State.t(), Context.t()) :: {State.t(), [Effect.t()]}
  # Phase 39 D-01/D-03/D-14: screen owns its route-entry signal.
  # Today (app.ex:834-836) ThreadList's per-screen App clause unconditionally
  # dispatches :load — there is no current_user gate. The :load clause itself
  # carries the missing-board guard (the second :load clause below), so
  # unconditional delegation is safe.
  def update(:on_route_enter, %State{} = state, %Context{} = context) do
    update(:load, state, context)
  end

  def update(:load, %State{board_id: board_id} = state, %Context{} = context)
      when is_binary(board_id) do
    threads_mod = resolve_threads_module(context)
    user_id = context.current_user && context.current_user.id

    if threads_mod_supported?(threads_mod) do
      new_state = %{state | status: :loading, last_op: :load_threads, last_error: nil}

      effect =
        Effect.task(:load_threads, :thread_list, fn ->
          dispatch_thread_load(threads_mod, board_id, user_id)
        end)

      {new_state, [effect]}
    else
      require Logger

      Logger.warning(
        "[ThreadList] threads_mod #{inspect(threads_mod)} exports neither " <>
          "list_threads/1 nor list_threads/2; returning empty result"
      )

      {%{
         state
         | threads: [],
           status: :empty,
           last_op: nil,
           last_error: :threads_mod_unsupported
       }, []}
    end
  end

  def update(:load, %State{} = state, %Context{}) do
    {%{state | status: {:error, :missing_board}, last_op: nil, last_error: :missing_board}, []}
  end

  def update({:task_result, :load_threads, {:ok, threads}}, %State{} = state, %Context{})
      when is_list(threads) do
    sorted = sort_threads(threads)
    status = if sorted == [], do: :empty, else: :loaded

    {%{state | threads: sorted, status: status, last_op: nil, last_error: nil}
     |> apply_selection_intent(sorted), []}
  end

  def update({:task_result, :load_threads, {:error, reason}}, %State{} = state, %Context{}) do
    {%{state | status: {:error, reason}, last_op: nil, last_error: reason} |> clamp_selection(),
     []}
  end

  def update({:key, %{key: key}}, %State{} = state, %Context{})
      when key in [:down, :up] do
    delta = if key == :down, do: 1, else: -1
    {move_selection(state, delta), []}
  end

  def update({:key, %{key: :char, char: c}}, %State{} = state, %Context{})
      when c in ["j", "k"] do
    delta = if c == "j", do: 1, else: -1
    {move_selection(state, delta), []}
  end

  def update({:key, %{key: :enter}}, %State{} = state, %Context{}) do
    case selected_thread(state) do
      nil ->
        {state, []}

      thread ->
        params = %{
          board: state.board,
          board_id: state.board_id,
          thread: thread,
          thread_id: Map.get(thread, :id)
        }

        {state, [Effect.navigate(:post_reader, params)]}
    end
  end

  def update({:key, %{key: :char, char: c}}, %State{} = state, %Context{} = context)
      when c in ["c", "C"] do
    cond do
      Guest.guest?(context) ->
        {state, [Effect.open_modal(Guest.denial_modal(:compose))]}

      posting_disabled?(state, context.current_user) ->
        {state, []}

      true ->
        params = %{origin: :thread_list, board: state.board, board_id: state.board_id}
        {state, [Effect.navigate(:new_thread, params)]}
    end
  end

  def update({:key, %{key: :char, char: c}}, %State{} = state, %Context{} = context)
      when c in ["q", "Q"] do
    boards_mod = resolve_boards_module(context)
    current_user = context.current_user

    refresh =
      Effect.task(:load_boards, :board_list, fn ->
        boards_mod.board_directory_for(current_user)
      end)

    {state, [Effect.navigate(:board_list, %{}), refresh]}
  end

  def update(_message, %State{} = state, %Context{}), do: {state, []}

  @impl true
  @spec render(State.t(), Context.t()) :: any()
  def render(%State{} = state, %Context{} = context) do
    frame_state = frame_state(state, context)
    theme = Theme.from_state(frame_state)
    thread_content = render_thread_content(state, context, theme)
    chrome = %{breadcrumb_parts: ["Foglet", board_label(state)]}

    ScreenFrame.render(frame_state, chrome, thread_content, keybar_groups(state, context))
  end

  @doc false
  # Public-but-internal helper used by `Foglet.TUI.Screens.BoardScreen` (FOG-253
  # C5) to compose the ThreadList content under a tab strip on chat-enabled
  # boards. Returns the inner content view without the surrounding screen
  # frame so the wrapper can place a tab strip above it.
  @spec render_inner_content(State.t(), Context.t()) :: any()
  def render_inner_content(%State{} = state, %Context{} = context) do
    frame_state = frame_state(state, context)
    theme = Theme.from_state(frame_state)
    render_thread_content(state, context, theme)
  end

  @doc false
  # Public-but-internal helper used by `Foglet.TUI.Screens.BoardScreen` (FOG-253
  # C5) to merge ThreadList's keybar entries with the wrapper's tab keybar.
  @spec keybar_groups(State.t(), Context.t()) :: [map()]
  def keybar_groups(%State{} = state, %Context{} = context) do
    keybar_groups_internal(state, context)
  end

  defp keybar_groups_internal(%State{} = state, %Context{} = context) do
    action_commands =
      if Guest.guest?(context) or posting_disabled?(state, context.current_user) do
        []
      else
        [%{key: "C", label: "Compose", priority: 5}]
      end

    [
      %{
        label: "Navigate",
        commands: [
          %{key: "↑/↓", label: "Select", priority: 10},
          %{key: "Enter", label: "Open", priority: 10}
        ]
      },
      %{
        label: "Actions",
        commands: action_commands
      },
      %{
        label: "System",
        commands: [%{key: "Q", label: "Back", priority: 0}]
      }
    ]
  end

  defp board_label(%State{board: %{name: name}}) when is_binary(name), do: name
  defp board_label(%State{}), do: "Boards"

  @impl true
  @spec subscriptions(State.t() | nil, Context.t()) :: [String.t()]
  def subscriptions(%State{board_id: board_id}, _context) when is_binary(board_id) do
    [Foglet.PubSub.board_topic(board_id)]
  end

  def subscriptions(_local_state, %Context{route_params: params}) do
    case Map.get(params, :board_id) || Map.get(params, "board_id") do
      board_id when is_binary(board_id) -> [Foglet.PubSub.board_topic(board_id)]
      _other -> []
    end
  end

  defp render_thread_content(%State{status: :loading} = state, context, theme) do
    column style: %{gap: 0} do
      banner_nodes(state, context, theme) ++
        [
          row style: %{gap: 1} do
            [
              Spinner.render(0, theme: theme, style: :dots),
              text("Loading…", fg: theme.dim.fg)
            ]
          end
        ]
    end
  end

  defp render_thread_content(%State{status: :empty} = state, context, theme) do
    empty_copy =
      if Guest.guest?(context) or posting_disabled?(state, context.current_user) do
        "No threads in this board yet."
      else
        "No threads in this board yet. Press C to start one."
      end

    column style: %{gap: 0} do
      banner_nodes(state, context, theme) ++ [text(empty_copy, fg: theme.warning.fg)]
    end
  end

  defp render_thread_content(%State{status: {:error, _reason}} = state, context, theme) do
    column style: %{gap: 0} do
      banner_nodes(state, context, theme) ++
        [text("Couldn't load threads. Press Q to back out and try again.", fg: theme.error.fg)]
    end
  end

  defp render_thread_content(%State{} = state, %Context{} = context, theme) do
    sorted = sort_threads(state.threads || [])
    {width, _h} = context.terminal_size || {80, 24}
    inner_width = max(width - 4, 40)

    list =
      SelectionList.render(sorted, state.selected_index, fn {thread, _idx, selected} ->
        render_thread_row(thread, selected, inner_width, theme)
      end)

    column style: %{gap: 0} do
      banner_nodes(state, context, theme) ++ [list]
    end
  end

  defp banner_nodes(%State{} = state, %Context{} = context, theme) do
    case board_state_banner(state, context.current_user) do
      nil -> []
      copy -> [text(copy, fg: theme.warning.fg)]
    end
  end

  defp board_state_banner(%State{} = state, user) do
    cond do
      archived?(state.board) ->
        "This board is archived. New threads and replies are disabled."

      read_only?(state.board, user) ->
        "This board is read-only."

      state.subscribed? == false ->
        "You're not subscribed to this board. Press S on Boards to subscribe."

      true ->
        nil
    end
  end

  defp archived?(%{} = board) do
    Map.get(board, :archived, Map.get(board, "archived", false)) == true
  end

  defp archived?(_board), do: false

  defp read_only?(board, %User{} = user) do
    case normalize_board(board) do
      %Board{} = normalized -> not PostingPolicy.can_post?(user, normalized)
      nil -> false
    end
  end

  defp read_only?(_board, _user), do: false

  defp normalize_board(%Board{} = board), do: board

  defp normalize_board(%{} = board) do
    postable_by = Map.get(board, :postable_by, Map.get(board, "postable_by"))

    if is_nil(postable_by) do
      nil
    else
      %Board{
        id: Map.get(board, :id, Map.get(board, "id")),
        name: Map.get(board, :name, Map.get(board, "name")),
        postable_by: postable_by,
        archived: Map.get(board, :archived, Map.get(board, "archived", false))
      }
    end
  end

  defp normalize_board(_board), do: nil

  defp posting_disabled?(%State{} = state, current_user) do
    not is_nil(board_state_banner(state, current_user))
  end

  defp render_thread_row(thread, selected, width, theme) do
    title = Map.get(thread, :title, "?")
    metadata = thread_metadata(thread)
    unread? = Map.get(thread, :has_unread, false)
    state_cluster = thread_state_cluster(thread, unread?)
    emphasis = if unread?, do: :bold, else: nil

    RichRow.render(
      title: title,
      metadata: metadata,
      state_cluster: state_cluster,
      selected: selected,
      theme: theme,
      width: width,
      emphasis: emphasis
    )
  end

  # Builds the RichRow state_cluster from a ThreadEntry-shaped map.
  #
  # RichRow places each glyph in a fixed cluster position by membership, so list
  # order has no visual effect. We construct the list top-to-bottom in priority
  # order (unread → sticky → locked) for human readability per 20-REVIEWS LOW #9.
  #
  # Uses the Map.get(thread, key, false) pattern so the helper works with both
  # %ThreadEntry{} structs and bare maps from FakeThreads test adapters
  # (Pitfall 5 in 20-RESEARCH.md).
  defp thread_state_cluster(thread, unread?) do
    [
      unread? && :unread,
      Map.get(thread, :sticky, false) && :sticky,
      Map.get(thread, :locked, false) && :locked
    ]
    |> Enum.filter(& &1)
  end

  defp thread_metadata(thread) do
    handle = thread_handle(thread)
    count = Map.get(thread, :post_count, 1) |> max(1)
    post_word = if count == 1, do: "post", else: "posts"
    time_segment = thread_time_segment(thread)
    "@#{handle} · #{count} #{post_word} · #{time_segment}"
  end

  defp thread_handle(%{created_by: %{handle: h}}) when is_binary(h) and h != "", do: h
  defp thread_handle(_), do: "unknown"

  defp thread_time_segment(%{last_post_at: %DateTime{} = dt}), do: "#{TimeAgo.format(dt)} ago"
  defp thread_time_segment(_), do: "new"

  defp resolve_threads_module(%Context{} = context) do
    case domain_module(context, :threads) do
      {:ok, mod} -> mod
      {:error, :not_configured} -> Foglet.Threads
    end
  end

  defp resolve_boards_module(%Context{} = context) do
    case domain_module(context, :boards) do
      {:ok, mod} -> mod
      {:error, :not_configured} -> Foglet.Boards
    end
  end

  defp domain_module(%Context{domain: domain}, key) when is_map(domain) do
    case Map.get(domain, key) do
      mod when is_atom(mod) and not is_nil(mod) -> {:ok, mod}
      _ -> Domain.get(%{domain: domain}, key)
    end
  end

  defp domain_module(%Context{session_context: ctx}, key), do: Domain.get(ctx || %{}, key)

  # Dispatches the bounded thread-list query against whichever arity the
  # configured `threads_mod` exports. Both real arities are bounded since
  # Phase 47 (R3/R4): `list_threads/1` and `list_threads/2` delegate to
  # `list_threads/3` and clamp at `@page_size` (50 by default, hard-ceiling
  # `@max_page_size` of 500 — see WR-07/WR-02). The `/1` fallback exists
  # for minimal test adapter modules (e.g. FakeThreads) that only export
  # the no-user shape; result-size semantics no longer differ between the
  # two paths (IN-01 iteration 2).
  defp dispatch_thread_load(threads_mod, board_id, user_id) do
    loaded? = match?({:module, _}, Code.ensure_loaded(threads_mod))

    cond do
      loaded? and function_exported?(threads_mod, :list_threads, 2) ->
        threads_mod.list_threads(board_id, user_id)

      loaded? and function_exported?(threads_mod, :list_threads, 1) ->
        threads_mod.list_threads(board_id) |> Enum.map(&annotate_fallback/1)

      true ->
        require Logger

        Logger.warning(
          "[ThreadList] threads_mod #{inspect(threads_mod)} exports neither " <>
            "list_threads/1 nor list_threads/2; returning empty result"
        )

        []
    end
  end

  defp threads_mod_supported?(threads_mod) do
    case Code.ensure_loaded(threads_mod) do
      {:module, _} ->
        function_exported?(threads_mod, :list_threads, 2) or
          function_exported?(threads_mod, :list_threads, 1)

      _ ->
        false
    end
  end

  defp annotate_fallback(%Foglet.Threads.Thread{} = t) do
    %ThreadEntry{
      id: t.id,
      title: t.title,
      board_id: t.board_id,
      sticky: t.sticky,
      locked: t.locked,
      post_count: t.post_count,
      first_post_id: t.first_post_id,
      last_post_at: t.last_post_at,
      deleted_at: t.deleted_at,
      inserted_at: t.inserted_at,
      created_by_id: t.created_by_id,
      has_unread: false,
      created_by: t.created_by
    }
  end

  defp annotate_fallback(%{} = t), do: struct(ThreadEntry, Map.put_new(t, :has_unread, false))

  # --- Private ---

  defp sort_threads(threads) when is_list(threads) do
    {sticky, regular} = Enum.split_with(threads, &(Map.get(&1, :sticky, false) == true))
    sort_by_recency(sticky) ++ sort_by_recency(regular)
  end

  # Sort threads newest-first within a group. Threads with nil last_post_at
  # sort last (they are brand-new and have no post activity yet).
  defp sort_by_recency(threads) do
    Enum.sort_by(
      threads,
      fn t ->
        case Map.get(t, :last_post_at) do
          %DateTime{} = dt -> {0, -DateTime.to_unix(dt, :microsecond)}
          # nil sorts last within the group
          _ -> {1, 0}
        end
      end,
      :asc
    )
  end

  defp move_selection(%State{} = state, delta) do
    threads = sort_threads(state.threads || [])
    select_index(state, state.selected_index + delta, threads)
  end

  defp clamp_selection(%State{} = state) do
    select_index(state, state.selected_index, sort_threads(state.threads || []))
  end

  defp apply_selection_intent(%State{select_thread_id: nil} = state, threads) do
    # IN-01: select_thread_id is already nil per the head match, so the
    # previous `Map.put(:select_thread_id, nil)` was a no-op.
    select_index(state, state.selected_index, threads)
  end

  defp apply_selection_intent(%State{select_thread_id: select_thread_id} = state, threads) do
    selected_index =
      Enum.find_index(threads, &(Map.get(&1, :id) == select_thread_id)) ||
        clamped_index(state.selected_index, threads)

    %{state | selected_index: selected_index, select_thread_id: nil}
  end

  defp select_index(%State{} = state, _index, []), do: %{state | selected_index: 0}

  defp select_index(%State{} = state, index, threads) do
    %{state | selected_index: clamped_index(index, threads)}
  end

  defp clamped_index(_index, []), do: 0
  defp clamped_index(index, threads), do: index |> max(0) |> min(length(threads) - 1)

  defp selected_thread(%State{} = state) do
    state.threads
    |> Kernel.||([])
    |> sort_threads()
    |> Enum.at(state.selected_index)
  end

  defp frame_state(%State{} = _state, %Context{} = context) do
    %{
      current_screen: :thread_list,
      current_user: context.current_user,
      session_context: context.session_context,
      terminal_size: context.terminal_size,
      route: context.route,
      route_params: context.route_params
    }
  end
end
