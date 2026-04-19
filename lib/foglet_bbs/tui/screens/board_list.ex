defmodule Foglet.TUI.Screens.BoardList do
  @moduledoc """
  Subscribed-boards list (SSH-07, SSH-08).

  Uses a domain-adapter pattern so tests can inject a fake Foglet.Boards.
  state.screen_state[:board_list] holds %{selected_index: integer()}.
  """

  alias Foglet.TUI.Widgets.{KeyBar, StatusBar}

  import Raxol.Core.Renderer.View

  @spec render(map()) :: any()
  def render(state) do
    ss = get_in(state.screen_state, [:board_list]) || %{selected_index: 0}
    board_rows = render_board_rows(state, ss)

    box style: %{border: :single, padding: 1} do
      column style: %{gap: 0} do
        [
          text(" Boards ", style: [:bold]),
          divider(),
          StatusBar.render(%{
            handle: state.current_user && state.current_user.handle,
            location: "Boards"
          }),
          column style: %{gap: 0} do
            board_rows
          end,
          KeyBar.render([{"j/k", "Select"}, {"Enter", "Open"}, {"Q", "Back"}])
        ]
      end
    end
  end

  defp render_board_rows(state, _ss) when state.board_list == [] do
    [text("No boards subscribed. Ask your sysop to subscribe you.", fg: :yellow)]
  end

  defp render_board_rows(state, ss) do
    boards = state.board_list || []

    if boards == [] do
      [text("Loading...", style: [:dim])]
    else
      Enum.with_index(boards)
      |> Enum.map(fn {board, idx} ->
        render_board_row(board, idx, ss.selected_index)
      end)
    end
  end

  defp render_board_row(board, idx, selected_index) do
    marker = if idx == selected_index, do: "> ", else: "  "
    unread = board_unread(board)
    unread_str = if unread > 0, do: " (#{unread} unread)", else: ""

    if idx == selected_index do
      text("#{marker}#{board.name}#{unread_str}", fg: :green, style: [:bold])
    else
      text("#{marker}#{board.name}#{unread_str}", fg: :green)
    end
  end

  @spec handle_key(map(), map()) :: {:update, map(), list()} | :no_match
  def handle_key(%{key: "j"}, state), do: move_selection(state, +1)
  def handle_key(%{key: "down"}, state), do: move_selection(state, +1)
  def handle_key(%{key: "k"}, state), do: move_selection(state, -1)
  def handle_key(%{key: "up"}, state), do: move_selection(state, -1)

  def handle_key(%{key: "enter"}, state) do
    boards = state.board_list || []
    ss = get_in(state.screen_state, [:board_list]) || %{selected_index: 0}

    case Enum.at(boards, ss.selected_index) do
      nil ->
        :no_match

      board ->
        new_state = %{
          state
          | current_board: board,
            current_screen: :thread_list,
            screen_state: Map.put(state.screen_state, :thread_list, %{selected_index: 0})
        }

        {:update, new_state, [{:load_threads, board.id}]}
    end
  end

  def handle_key(%{key: key}, state) when key in ["q", "Q"] do
    {:update, %{state | current_screen: :main_menu}, []}
  end

  def handle_key(_key, _state), do: :no_match

  @doc """
  Called by App.update/2 in response to a {:load_boards} command.
  Populates state.board_list by calling the configured domain module.
  """
  @spec load_boards(map()) :: {map(), list()}
  def load_boards(state) do
    boards_mod = domain_module(state, :boards)

    if function_exported?(boards_mod, :list_subscribed_boards, 1) do
      boards = boards_mod.list_subscribed_boards(state.current_user)
      {%{state | board_list: boards}, []}
    else
      # Phase 2 not yet executed — leave empty so render shows "No boards" message
      {%{state | board_list: []}, []}
    end
  end

  # --- Private ---

  defp move_selection(state, delta) do
    boards = state.board_list || []

    if boards == [] do
      :no_match
    else
      ss = get_in(state.screen_state, [:board_list]) || %{selected_index: 0}
      new_idx = (ss.selected_index + delta) |> max(0) |> min(length(boards) - 1)
      new_screen_state = Map.put(state.screen_state, :board_list, %{ss | selected_index: new_idx})
      {:update, %{state | screen_state: new_screen_state}, []}
    end
  end

  defp board_unread(%{unread_count: n}) when is_integer(n), do: n
  defp board_unread(_), do: 0

  defp domain_module(state, key) do
    ctx = Map.get(state, :session_context) || %{}
    get_in(ctx, [:domain, key]) || default_domain(key)
  end

  defp default_domain(:boards), do: Foglet.Boards
  defp default_domain(:threads), do: Foglet.Threads
  defp default_domain(:posts), do: Foglet.Posts
  defp default_domain(:markdown), do: Foglet.Markdown
end
