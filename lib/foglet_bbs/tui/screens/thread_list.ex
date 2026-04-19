defmodule Foglet.TUI.Screens.ThreadList do
  @moduledoc """
  Thread list for a selected board (SSH-07, SSH-08).

  Sticky threads rendered first; within each group, newest-activity-first.
  Each row shows title and unread count.
  """

  alias Foglet.TUI.Theme
  alias Foglet.TUI.Widgets.Chrome.ScreenFrame
  alias Foglet.TUI.Widgets.List.{ListRow, SelectionList}

  import Raxol.Core.Renderer.View

  @spec render(map()) :: any()
  def render(state) do
    board = state.current_board
    ss = get_in(state.screen_state, [:thread_list]) || %{selected_index: 0}
    theme = get_in(state, [:session_context, :theme]) || Theme.default()
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

    if sorted == [] do
      column style: %{gap: 0} do
        [text("Loading...", fg: theme.dim.fg)]
      end
    else
      SelectionList.render(sorted, ss.selected_index, fn {thread, _idx, selected} ->
        sticky_mark = if thread.sticky, do: "[S] ", else: ""
        unread = Map.get(thread, :unread_count, 0)
        unread_str = if unread > 0, do: " (#{unread})", else: ""
        ListRow.render("#{sticky_mark}#{thread.title}#{unread_str}", selected, theme)
      end)
    end
  end

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
    {:update, %{state | current_screen: :post_composer, composer_draft: "", current_thread: nil},
     []}
  end

  def handle_key(%{key: :char, char: c}, state) when c in ["q", "Q"] do
    {:update, %{state | current_screen: :board_list}, []}
  end

  def handle_key(_key, _state), do: :no_match

  @doc "Called by App.update/2 on {:load_threads, board_id}."
  @spec load_threads(map(), String.t()) :: {map(), list()}
  def load_threads(state, board_id) do
    ctx = Map.get(state, :session_context) || %{}
    threads_mod = get_in(ctx, [:domain, :threads]) || Foglet.Threads

    if function_exported?(threads_mod, :list_threads, 1) do
      threads = threads_mod.list_threads(board_id)
      {%{state | current_thread_list: threads}, []}
    else
      {%{state | current_thread_list: []}, []}
    end
  end

  # --- Private ---

  defp sort_threads(threads) when is_list(threads) do
    {sticky, regular} = Enum.split_with(threads, &(&1.sticky == true))

    Enum.sort_by(sticky, & &1.last_post_at, {:desc, DateTime}) ++
      Enum.sort_by(regular, & &1.last_post_at, {:desc, DateTime})
  end

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
