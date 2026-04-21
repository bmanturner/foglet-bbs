defmodule Foglet.TUI.Screens.BoardList do
  @moduledoc """
  Subscribed-boards list (SSH-07, SSH-08).

  Uses a domain-adapter pattern so tests can inject a fake Foglet.Boards.
  state.screen_state[:board_list] holds %{selected_index: integer()}.
  """

  alias Foglet.TUI.Screens.Domain
  alias Foglet.TUI.Theme
  alias Foglet.TUI.Widgets.Chrome.ScreenFrame
  alias Foglet.TUI.Widgets.List.{ListRow, SelectionList}

  import Raxol.Core.Renderer.View

  @spec render(map()) :: any()
  def render(state) do
    ss = get_in(state.screen_state, [:board_list]) || %{selected_index: 0}
    theme = Theme.from_state(state)
    board_content = render_board_content(state, ss, theme)

    ScreenFrame.render(state, "Boards", board_content, [
      {"j/k", "Select"},
      {"Enter", "Open"},
      {"Q", "Back"}
    ])
  end

  defp render_board_content(state, _ss, theme) when state.board_list == [] do
    column style: %{gap: 0} do
      [text("No boards subscribed. Ask your sysop to subscribe you.", fg: theme.warning.fg)]
    end
  end

  defp render_board_content(state, ss, theme) do
    boards = state.board_list || []

    if boards == [] do
      column style: %{gap: 0} do
        [text("Loading...", fg: theme.dim.fg)]
      end
    else
      SelectionList.render(boards, ss.selected_index, fn {board, _idx, selected} ->
        unread = board_unread(board)
        unread_str = if unread > 0, do: " (#{unread} unread)", else: ""
        ListRow.render("#{board.name}#{unread_str}", selected, theme)
      end)
    end
  end

  @spec handle_key(map(), map()) :: {:update, map(), list()} | :no_match
  def handle_key(%{key: :char, char: "j"}, state), do: move_selection(state, +1)
  def handle_key(%{key: :down}, state), do: move_selection(state, +1)
  def handle_key(%{key: :char, char: "k"}, state), do: move_selection(state, -1)
  def handle_key(%{key: :up}, state), do: move_selection(state, -1)

  def handle_key(%{key: :enter}, state) do
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

  def handle_key(%{key: :char, char: c}, state) when c in ["q", "Q"] do
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
    boards = boards_mod.list_subscribed_boards(state.current_user)
    {%{state | board_list: boards}, []}
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

  defp domain_module(state, :boards) do
    ctx = Map.get(state, :session_context) || %{}

    case Domain.get(ctx, :boards) do
      {:ok, mod} -> mod
      {:error, :not_configured} -> Foglet.Boards
    end
  end
end
