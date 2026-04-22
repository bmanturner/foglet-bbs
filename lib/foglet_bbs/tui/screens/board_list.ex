defmodule Foglet.TUI.Screens.BoardList do
  @moduledoc "Subscribed-boards list (SSH-07, SSH-08)."

  alias Foglet.TUI.Screens.Domain
  alias Foglet.TUI.Theme
  alias Foglet.TUI.Widgets.Chrome.ScreenFrame
  alias Foglet.TUI.Widgets.List.{ListRow, SelectionList}
  alias Foglet.TUI.Widgets.Progress.Spinner
  import Raxol.Core.Renderer.View

  @spec init_screen_state(keyword()) :: map()
  def init_screen_state(_opts \\ []), do: %{selected_index: 0}

  @spec render(map()) :: any()
  def render(state) do
    ss = screen_state(state)

    ScreenFrame.render(
      state,
      "Boards",
      render_board_content(state, ss, Theme.from_state(state)),
      [
        {"j/k", "Select"},
        {"Enter", "Open"},
        {"Q", "Back"}
      ]
    )
  end

  defp render_board_content(state, _ss, theme) when state.board_list == [] do
    column style: %{gap: 0} do
      [text("No boards subscribed. Ask your sysop to subscribe you.", fg: theme.warning.fg)]
    end
  end

  defp render_board_content(state, _ss, theme) when state.board_list == nil do
    frame = System.monotonic_time(:millisecond) |> abs() |> div(Spinner.frame_duration_ms())

    column style: %{gap: 0} do
      [
        row(
          style: %{gap: 1},
          do: [
            Spinner.render(frame, style: :line, theme: theme),
            text("Loading…", fg: theme.dim.fg)
          ]
        )
      ]
    end
  end

  defp render_board_content(state, ss, theme) do
    SelectionList.render(state.board_list, ss.selected_index, fn {board, _idx, selected} ->
      unread =
        if match?(%{unread_count: n} when is_integer(n), board), do: board.unread_count, else: 0

      unread_str = if unread > 0, do: " (#{unread} unread)", else: ""
      ListRow.render("#{board.name}#{unread_str}", selected, theme)
    end)
  end

  @spec handle_key(map(), map()) :: {:update, map(), list()} | :no_match
  def handle_key(%{key: :char, char: "j"}, state), do: move_selection(state, +1)
  def handle_key(%{key: :down}, state), do: move_selection(state, +1)
  def handle_key(%{key: :char, char: "k"}, state), do: move_selection(state, -1)
  def handle_key(%{key: :up}, state), do: move_selection(state, -1)

  def handle_key(%{key: :enter}, state) do
    case Enum.at(state.board_list || [], screen_state(state).selected_index) do
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

  def handle_key(%{key: :char, char: c}, state) when c in ["q", "Q"],
    do: {:update, %{state | current_screen: :main_menu}, []}

  def handle_key(_key, _state), do: :no_match

  @doc false
  @spec load_boards(map()) :: {map(), list()}
  def load_boards(state) do
    # test seam retained for screen-level unit tests; production loading is owned by
    # Foglet.TUI.App.do_update({:load_boards}, state).
    boards_mod = domain_module(state, :boards)
    boards = boards_mod.list_subscribed_boards(state.current_user)
    {%{state | board_list: boards}, []}
  end

  defp move_selection(state, delta) do
    boards = state.board_list || []

    if boards == [] do
      :no_match
    else
      ss = screen_state(state)
      new_idx = (ss.selected_index + delta) |> max(0) |> min(length(boards) - 1)
      new_screen_state = Map.put(state.screen_state, :board_list, %{ss | selected_index: new_idx})
      {:update, %{state | screen_state: new_screen_state}, []}
    end
  end

  defp screen_state(state), do: get_in(state.screen_state, [:board_list]) || init_screen_state()

  defp domain_module(state, :boards) do
    ctx = Map.get(state, :session_context) || %{}

    case Domain.get(ctx, :boards) do
      {:ok, mod} -> mod
      {:error, :not_configured} -> Foglet.Boards
    end
  end
end
