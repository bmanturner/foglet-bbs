defmodule Foglet.TUI.Screens.ThreadList do
  @moduledoc """
  Thread list for a selected board (SSH-07, SSH-08).

  Sticky threads rendered first; within each group, newest-activity-first.
  Each row shows title and unread count.
  """

  alias Foglet.TimeAgo
  alias Foglet.TUI.Theme
  alias Foglet.TUI.Widgets.Chrome.ScreenFrame
  alias Foglet.TUI.Widgets.List.{ListRow, SelectionList}

  import Raxol.Core.Renderer.View

  @spec render(map()) :: any()
  def render(state) do
    board = state.current_board
    ss = get_in(state.screen_state, [:thread_list]) || %{selected_index: 0}
    theme = (Map.get(state, :session_context) || %{}) |> Map.get(:theme) || Theme.default()
    thread_content = render_thread_content(state, ss, theme)
    board_name = (board && board.name) || "?"

    ScreenFrame.render(state, "Threads — #{board_name}", thread_content, [
      {"j/k", "Select"},
      {"Enter", "Open"},
      {"C", "Compose"},
      {"Q", "Back"}
    ])
  end

  defp render_thread_content(state, _ss, theme) when state.current_thread_list == [] do
    column style: %{gap: 0} do
      [text("No threads in this board yet. Press [C] to compose.", fg: theme.warning.fg)]
    end
  end

  defp render_thread_content(state, ss, theme) do
    sorted = sort_threads(state.current_thread_list || [])
    {width, _h} = state.terminal_size || {80, 24}
    inner_width = max(width - 4, 40)

    if sorted == [] do
      column style: %{gap: 0} do
        [text("Loading...", fg: theme.dim.fg)]
      end
    else
      SelectionList.render(sorted, ss.selected_index, fn {thread, _idx, selected} ->
        render_thread_row(thread, selected, inner_width, theme)
      end)
    end
  end

  defp render_thread_row(thread, selected, width, theme) do
    sticky_mark = if Map.get(thread, :sticky, false), do: "[S] ", else: ""
    title = "#{sticky_mark}#{Map.get(thread, :title, "?")}"
    metadata = thread_metadata(thread)
    unread? = Map.get(thread, :has_unread, false)
    ListRow.render_with_metadata(title, metadata, selected, unread?, theme, width: width)
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

  @spec handle_key(map(), map()) :: {:update, map(), list()} | :no_match
  def handle_key(%{key: :char, char: "j"}, state), do: move_selection(state, +1)
  def handle_key(%{key: :down}, state), do: move_selection(state, +1)
  def handle_key(%{key: :char, char: "k"}, state), do: move_selection(state, -1)
  def handle_key(%{key: :up}, state), do: move_selection(state, -1)

  def handle_key(%{key: :enter}, state) do
    threads = sort_threads(state.current_thread_list || [])
    ss = get_in(state.screen_state, [:thread_list]) || %{selected_index: 0}

    case Enum.at(threads, ss.selected_index) do
      nil ->
        :no_match

      thread ->
        new_state = %{
          state
          | current_thread: thread,
            current_screen: :post_reader,
            screen_state: Map.put(state.screen_state, :post_reader, %{selected_post_index: 0})
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
      |> Map.merge(%{
        step: :compose,
        board: state.current_board,
        boards: nil,
        origin: :thread_list
      })

    new_screen_state = Map.put(state.screen_state, :new_thread, ss)

    {:update, %{state | current_screen: :new_thread, screen_state: new_screen_state}, []}
  end

  def handle_key(%{key: :char, char: c}, state) when c in ["q", "Q"] do
    {:update, %{state | current_screen: :board_list}, [{:load_boards}]}
  end

  def handle_key(_key, _state), do: :no_match

  @doc "Called by App.update/2 on {:load_threads, board_id}."
  @spec load_threads(map(), String.t()) :: {map(), list()}
  def load_threads(state, board_id) do
    ctx = Map.get(state, :session_context) || %{}
    threads_mod = get_in(ctx, [:domain, :threads]) || Foglet.Threads
    user_id = state.current_user && state.current_user.id

    cond do
      function_exported?(threads_mod, :list_threads, 2) ->
        threads = threads_mod.list_threads(board_id, user_id)
        {%{state | current_thread_list: threads}, []}

      function_exported?(threads_mod, :list_threads, 1) ->
        threads = threads_mod.list_threads(board_id) |> Enum.map(&annotate_fallback/1)
        {%{state | current_thread_list: threads}, []}

      true ->
        {%{state | current_thread_list: []}, []}
    end
  end

  defp annotate_fallback(%Foglet.Threads.Thread{} = t) do
    t
    |> Map.from_struct()
    |> Map.put(:has_unread, false)
  end

  defp annotate_fallback(t) when is_map(t), do: Map.put_new(t, :has_unread, false)

  # --- Private ---

  defp sort_threads(threads) when is_list(threads) do
    {sticky, regular} = Enum.split_with(threads, &(Map.get(&1, :sticky, false) == true))

    Enum.sort_by(sticky, &last_post_sort_key/1, :desc) ++
      Enum.sort_by(regular, &last_post_sort_key/1, :desc)
  end

  defp last_post_sort_key(%{last_post_at: %DateTime{} = dt}),
    do: DateTime.to_unix(dt, :microsecond)

  defp last_post_sort_key(_), do: -1

  defp move_selection(state, delta) do
    threads = sort_threads(state.current_thread_list || [])

    if threads == [] do
      :no_match
    else
      ss = get_in(state.screen_state, [:thread_list]) || %{selected_index: 0}
      new_idx = (ss.selected_index + delta) |> max(0) |> min(length(threads) - 1)

      new_screen_state =
        Map.put(state.screen_state, :thread_list, %{ss | selected_index: new_idx})

      {:update, %{state | screen_state: new_screen_state}, []}
    end
  end
end
