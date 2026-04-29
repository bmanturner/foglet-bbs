defmodule Foglet.TUI.Screens.ThreadList do
  @moduledoc """
  Thread list for a selected board (SSH-07, SSH-08).

  ThreadList is a screen-owned reducer over `ThreadList.State` and route
  params; App only routes keys, task results, and effects.

  Sticky threads rendered first; within each group, newest-activity-first.
  Each row shows title and unread count.
  """

  @behaviour Foglet.TUI.Screen

  alias Foglet.Threads.ThreadEntry
  alias Foglet.TimeAgo
  alias Foglet.TUI.{Context, Effect}
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

    new_state = %{state | status: :loading, last_op: :load_threads, last_error: nil}

    effect =
      Effect.task(:load_threads, :thread_list, fn ->
        dispatch_thread_load(threads_mod, board_id, user_id)
      end)

    {new_state, [effect]}
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

  def update({:key, %{key: :char, char: c}}, %State{} = state, %Context{})
      when c in ["c", "C"] do
    params = %{origin: :thread_list, board: state.board, board_id: state.board_id}
    {state, [Effect.navigate(:new_thread, params)]}
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

    ScreenFrame.render(frame_state, chrome, thread_content, [
      {"j/k", "Select"},
      {"Enter", "Open"},
      {"C", "Compose"},
      {"Q", "Back"}
    ])
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

  defp render_thread_content(%State{status: :loading}, _context, theme) do
    column style: %{gap: 0} do
      [
        row style: %{gap: 1} do
          [
            Spinner.render(0, theme: theme, style: :dots),
            text("Loading...", fg: theme.dim.fg)
          ]
        end
      ]
    end
  end

  defp render_thread_content(%State{status: :empty}, _context, theme) do
    column style: %{gap: 0} do
      [text("No threads in this board yet. Press [C] to compose.", fg: theme.warning.fg)]
    end
  end

  defp render_thread_content(%State{status: {:error, _reason}}, _context, theme) do
    column style: %{gap: 0} do
      [text("Unable to load threads.", fg: theme.error.fg)]
    end
  end

  defp render_thread_content(%State{} = state, %Context{} = context, theme) do
    sorted = sort_threads(state.threads || [])
    {width, _h} = context.terminal_size || {80, 24}
    inner_width = max(width - 4, 40)

    SelectionList.render(sorted, state.selected_index, fn {thread, _idx, selected} ->
      render_thread_row(thread, selected, inner_width, theme)
    end)
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

  defp dispatch_thread_load(threads_mod, board_id, user_id) do
    loaded? = match?({:module, _}, Code.ensure_loaded(threads_mod))

    cond do
      loaded? and function_exported?(threads_mod, :list_threads, 2) ->
        threads_mod.list_threads(board_id, user_id)

      loaded? and function_exported?(threads_mod, :list_threads, 1) ->
        threads_mod.list_threads(board_id) |> Enum.map(&annotate_fallback/1)

      true ->
        []
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
    state
    |> select_index(state.selected_index, threads)
    |> Map.put(:select_thread_id, nil)
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
