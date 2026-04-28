defmodule Foglet.TUI.Screens.ThreadList do
  @moduledoc """
  Thread list for a selected board (SSH-07, SSH-08).

  Sticky threads rendered first; within each group, newest-activity-first.
  Each row shows title and unread count.
  """

  @behaviour Foglet.TUI.Screen

  alias Foglet.Threads.ThreadEntry
  alias Foglet.TimeAgo
  alias Foglet.TUI.Context
  alias Foglet.TUI.Screens.ThreadList.State
  alias Foglet.TUI.Screens.Domain
  alias Foglet.TUI.Screens.PostReader
  alias Foglet.TUI.Theme
  alias Foglet.TUI.Widgets.Chrome.ScreenFrame
  alias Foglet.TUI.Widgets.List.{RichRow, SelectionList}
  alias Foglet.TUI.Widgets.Progress.Spinner

  import Raxol.Core.Renderer.View

  @impl true
  @spec init(Context.t()) :: State.t()
  def init(%Context{} = context), do: State.from_context(context)

  @impl true
  @spec init_screen_state(keyword()) :: State.t()
  def init_screen_state(_opts \\ []), do: State.new(selected_index: 0)

  @impl true
  @spec render(map()) :: any()
  def render(state) do
    ss = get_in(state.screen_state, [:thread_list]) || init_screen_state()
    theme = Theme.from_state(state)
    thread_content = render_thread_content(state, ss, theme)

    ScreenFrame.render(state, %{}, thread_content, [
      {"j/k", "Select"},
      {"Enter", "Open"},
      {"C", "Compose"},
      {"Q", "Back"}
    ])
  end

  defp render_thread_content(state, _ss, theme) when state.current_thread_list == nil do
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

  defp render_thread_content(state, _ss, theme) when state.current_thread_list == [] do
    column style: %{gap: 0} do
      [text("No threads in this board yet. Press [C] to compose.", fg: theme.warning.fg)]
    end
  end

  defp render_thread_content(state, ss, theme) do
    sorted = sort_threads(state.current_thread_list)
    {width, _h} = state.terminal_size || {80, 24}
    inner_width = max(width - 4, 40)

    SelectionList.render(sorted, ss.selected_index, fn {thread, _idx, selected} ->
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

  @impl true
  @spec handle_key(map(), map()) :: {:update, map(), list()} | :no_match
  def handle_key(%{key: :char, char: "j"}, state), do: move_selection(state, +1)
  def handle_key(%{key: :down}, state), do: move_selection(state, +1)
  def handle_key(%{key: :char, char: "k"}, state), do: move_selection(state, -1)
  def handle_key(%{key: :up}, state), do: move_selection(state, -1)

  def handle_key(%{key: :enter}, state) do
    threads = sort_threads(state.current_thread_list || [])
    ss = get_in(state.screen_state, [:thread_list]) || init_screen_state()

    case Enum.at(threads, ss.selected_index) do
      nil ->
        :no_match

      thread ->
        new_state = %{
          state
          | current_thread: thread,
            current_screen: :post_reader,
            screen_state:
              Map.put(state.screen_state, :post_reader, PostReader.init_screen_state([]))
        }

        {:update, new_state, [{:load_posts, thread.id}]}
    end
  end

  def handle_key(%{key: :char, char: c}, state) when c in ["c", "C"] do
    {w, _h} = state.terminal_size || {80, 24}

    # COMPOSE-01 / COMPOSE-03: skip the board picker since we're already
    # inside a board. Pre-fill board, jump straight to :compose step, and
    # stash origin so Cancel returns to this ThreadList.
    ss =
      Foglet.TUI.Screens.NewThread.init_screen_state(width: w)
      |> then(
        &%{&1 | step: :compose, board: state.current_board, boards: nil, origin: :thread_list}
      )

    new_screen_state = Map.put(state.screen_state, :new_thread, ss)

    {:update, %{state | current_screen: :new_thread, screen_state: new_screen_state}, []}
  end

  def handle_key(%{key: :char, char: c}, state) when c in ["q", "Q"] do
    {:update, %{state | current_screen: :board_list}, [{:load_boards}]}
  end

  def handle_key(_key, _state), do: :no_match

  # Production load orchestration is owned by Foglet.TUI.App.do_update({:load_threads, board_id}, state).
  @doc false
  @spec load_threads(map(), String.t()) :: {map(), list()}
  def load_threads(state, board_id) do
    ctx = Map.get(state, :session_context) || %{}
    threads_mod = resolve_threads_module(ctx)

    user_id = state.current_user && state.current_user.id
    threads = dispatch_thread_load(threads_mod, board_id, user_id)
    {%{state | current_thread_list: threads}, []}
  end

  defp resolve_threads_module(ctx) do
    case Domain.get(ctx, :threads) do
      {:ok, mod} -> mod
      {:error, :not_configured} -> Foglet.Threads
    end
  end

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

  defp move_selection(state, delta) do
    threads = sort_threads(state.current_thread_list || [])

    if threads == [] do
      :no_match
    else
      ss = get_in(state.screen_state, [:thread_list]) || init_screen_state()
      new_idx = (ss.selected_index + delta) |> max(0) |> min(length(threads) - 1)

      new_screen_state =
        Map.put(state.screen_state, :thread_list, %{ss | selected_index: new_idx})

      {:update, %{state | screen_state: new_screen_state}, []}
    end
  end
end
