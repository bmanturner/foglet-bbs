defmodule Foglet.TUI.Screens.BoardList do
  @moduledoc "Category-tree board directory (SSH-07, SSH-08)."

  @behaviour Foglet.TUI.Screen

  alias Foglet.TUI.Screens.Domain
  alias Foglet.TUI.Screens.BoardList.State
  alias Foglet.TUI.Theme
  alias Foglet.TUI.Widgets.Chrome.ScreenFrame
  alias Foglet.TUI.Widgets.Display.Tree
  alias Foglet.TUI.Widgets.Progress.Spinner
  import Raxol.Core.Renderer.View

  @impl true
  @spec init_screen_state(keyword()) :: State.t()
  def init_screen_state(opts \\ []), do: State.new(opts)

  @impl true
  @spec render(map()) :: any()
  def render(state) do
    ss = screen_state(state)

    ScreenFrame.render(
      state,
      "Boards",
      render_board_content(state, ss, Theme.from_state(state)),
      [
        {"j/k", "Select"},
        {"←/→", "Collapse/Expand"},
        {"Enter", "Open"},
        {"Q", "Back"}
      ]
    )
  end

  defp render_board_content(state, ss, theme) when state.board_list == [] do
    column style: %{gap: 0} do
      maybe_feedback(ss, theme) ++
        [text("No active boards are available.", fg: theme.warning.fg)]
    end
  end

  defp render_board_content(state, ss, theme) when state.board_list == nil do
    frame = System.monotonic_time(:millisecond) |> abs() |> div(Spinner.frame_duration_ms())

    column style: %{gap: 0} do
      maybe_feedback(ss, theme) ++
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
    tree = ss.tree || build_tree(state.board_list)

    column style: %{gap: 0} do
      maybe_feedback(ss, theme) ++ [Tree.render(tree, theme: theme)]
    end
  end

  @impl true
  @spec handle_key(map(), map()) :: {:update, map(), list()} | :no_match
  def handle_key(%{key: :char, char: "j"}, state), do: handle_tree_key(%{key: :down}, state)
  def handle_key(%{key: :down}, state), do: handle_tree_key(%{key: :down}, state)
  def handle_key(%{key: :char, char: "k"}, state), do: handle_tree_key(%{key: :up}, state)
  def handle_key(%{key: :up}, state), do: handle_tree_key(%{key: :up}, state)
  def handle_key(%{key: :left}, state), do: handle_tree_key(%{key: :left}, state)
  def handle_key(%{key: :right}, state), do: handle_tree_key(%{key: :right}, state)

  def handle_key(%{key: :enter}, state) do
    ss = screen_state(state)
    tree = ss.tree || build_tree(state.board_list || [])

    case Tree.handle_event(%{key: :enter}, tree) do
      {%Tree{} = new_tree, :node_activated} ->
        case focused_board(new_tree) do
          nil ->
            :no_match

          board ->
            new_state = %{
              state
              | current_board: board,
                current_screen: :thread_list,
                screen_state:
                  state.screen_state
                  |> Map.put(:board_list, %{ss | tree: new_tree})
                  |> Map.put(:thread_list, %{selected_index: 0})
            }

            {:update, new_state, [{:load_threads, board.id}]}
        end

      _other ->
        :no_match
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
    directory = boards_mod.board_directory_for(state.current_user)
    {%{state | board_list: directory} |> put_tree_for_directory(directory), []}
  end

  defp handle_tree_key(_key, %{board_list: nil}), do: :no_match
  defp handle_tree_key(_key, %{board_list: []}), do: :no_match

  defp handle_tree_key(key, state) do
    ss = screen_state(state)
    tree = ss.tree || build_tree(state.board_list || [])
    {new_tree, _action} = Tree.handle_event(key, tree)
    {:update, put_ss(state, %{ss | tree: new_tree}), []}
  end

  defp screen_state(state) do
    case get_in(state.screen_state, [:board_list]) do
      %State{} = ss -> ss
      _ -> init_screen_state()
    end
  end

  defp put_tree_for_directory(state, directory) do
    put_ss(state, %{screen_state(state) | tree: build_tree(directory)})
  end

  defp put_ss(state, %State{} = ss) do
    %{state | screen_state: Map.put(state.screen_state || %{}, :board_list, ss)}
  end

  defp build_tree(directory) when is_list(directory) do
    nodes = Enum.map(directory, &category_node/1)
    tree = Tree.init(id: "board-directory", nodes: nodes)
    expanded = nodes |> Enum.map(& &1.id) |> MapSet.new()
    put_in(tree.raxol_state.expanded, expanded)
  end

  defp category_node(%{category: category, boards: boards}) do
    %{
      id: :"category-#{category.id}",
      label: category.name,
      children: Enum.map(boards, &board_node/1),
      data: %{kind: :category, category: category}
    }
  end

  defp board_node(%{
         board: board,
         subscribed?: subscribed?,
         required_subscription?: required?,
         unread_count: unread_count
       }) do
    %{
      id: :"board-#{board.id}",
      label: board_label(board, subscribed?, required?, unread_count),
      children: [],
      data: %{
        kind: :board,
        board: board,
        subscribed?: subscribed?,
        required_subscription?: required?
      }
    }
  end

  defp board_label(board, _subscribed?, true, unread_count) do
    "#{board.name} [required]#{unread_suffix(unread_count)}"
  end

  defp board_label(board, true, _required?, unread_count) do
    "#{board.name} [subscribed]#{unread_suffix(unread_count)}"
  end

  defp board_label(board, false, _required?, _unread_count), do: "#{board.name} [unsubscribed]"

  defp unread_suffix(n) when is_integer(n) and n > 0, do: " (#{n} unread)"
  defp unread_suffix(_), do: ""

  defp focused_board(%Tree{raxol_state: %{cursor: cursor, nodes: nodes}}) do
    case find_node(nodes, cursor) do
      %{data: %{kind: :board, board: board}} -> board
      _ -> nil
    end
  end

  defp find_node(_nodes, nil), do: nil

  defp find_node(nodes, id) do
    Enum.find_value(nodes, fn
      %{id: ^id} = node -> node
      %{children: children} -> find_node(children, id)
      _ -> nil
    end)
  end

  defp maybe_feedback(%State{feedback: feedback}, theme) when is_binary(feedback) do
    [text(feedback, fg: theme.accent.fg), text("")]
  end

  defp maybe_feedback(_ss, _theme), do: []

  defp domain_module(state, :boards) do
    ctx = Map.get(state, :session_context) || %{}

    case Domain.get(ctx, :boards) do
      {:ok, mod} -> mod
      {:error, :not_configured} -> Foglet.Boards
    end
  end
end
