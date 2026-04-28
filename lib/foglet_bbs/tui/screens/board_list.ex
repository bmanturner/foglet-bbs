defmodule Foglet.TUI.Screens.BoardList do
  @moduledoc "Category-tree board directory (SSH-07, SSH-08)."

  @behaviour Foglet.TUI.Screen

  alias Foglet.TimeAgo
  alias Foglet.TUI.Screens.BoardList.State
  alias Foglet.TUI.Screens.Domain
  alias Foglet.TUI.TextWidth
  alias Foglet.TUI.Theme
  alias Foglet.TUI.Widgets.Chrome.ScreenFrame
  alias Foglet.TUI.Widgets.List.BoardTree
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
        {"s/u", "Subscribe/Unsubscribe"},
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
    board_tree = ss.board_tree || build_tree(state.board_list)
    width = row_width(state)
    height = body_height(state)
    feedback_rows = feedback_row_count(ss)
    detail? = detail_strip?(height, feedback_rows)

    reserved_rows =
      feedback_rows +
        if(detail?, do: 1, else: 0)

    visible_height = visible_tree_rows(max(height - reserved_rows, 3))

    column style: %{gap: 0} do
      [
        maybe_feedback(ss, theme),
        BoardTree.render(board_tree, theme: theme, width: width, visible_height: visible_height),
        if(detail?, do: details_strip(board_tree, state.board_list, theme, width))
      ]
      |> List.flatten()
      |> Enum.reject(&is_nil/1)
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
  def handle_key(%{key: :char, char: "s"}, state), do: subscribe_focused_board(state)
  def handle_key(%{key: :char, char: "u"}, state), do: unsubscribe_focused_board(state)

  def handle_key(%{key: :enter}, state) do
    ss = screen_state(state)
    tree = ss.board_tree || build_tree(state.board_list || [])

    case BoardTree.handle_event(%{key: :enter}, tree) do
      {%BoardTree{} = new_tree, action} when action in [:node_expanded, :node_collapsed] ->
        {:update, put_ss(state, %{ss | board_tree: new_tree}), []}

      {%BoardTree{} = new_tree, :node_activated} ->
        case BoardTree.focused_board_entry(new_tree) do
          nil ->
            :no_match

          %{board: board} ->
            new_state = %{
              state
              | current_board: board,
                current_screen: :thread_list,
                screen_state:
                  state.screen_state
                  |> Map.put(:board_list, %{ss | board_tree: new_tree})
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
    tree = ss.board_tree || build_tree(state.board_list || [])
    {new_tree, _action} = BoardTree.handle_event(key, tree)
    {:update, put_ss(state, %{ss | board_tree: new_tree}), []}
  end

  defp subscribe_focused_board(state) do
    ss = screen_state(state)
    tree = ss.board_tree || build_tree(state.board_list || [])

    case BoardTree.focused_board_entry(tree) do
      %{board: board, subscribed?: false} ->
        {:update, put_ss(state, %{ss | board_tree: tree, feedback: nil}),
         [{:subscribe_to_board, board.id}]}

      %{subscribed?: true} ->
        {:update, put_ss(state, %{ss | board_tree: tree, feedback: "Already subscribed."}), []}

      _other ->
        :no_match
    end
  end

  defp unsubscribe_focused_board(state) do
    ss = screen_state(state)
    tree = ss.board_tree || build_tree(state.board_list || [])

    case BoardTree.focused_board_entry(tree) do
      %{required_subscription?: true} ->
        feedback = "This board is a required subscription."
        {:update, put_ss(state, %{ss | board_tree: tree, feedback: feedback}), []}

      %{board: board, subscribed?: true} ->
        {:update, put_ss(state, %{ss | board_tree: tree, feedback: nil}),
         [{:unsubscribe_from_board, board.id}]}

      %{subscribed?: false} ->
        {:update, put_ss(state, %{ss | board_tree: tree, feedback: "Not subscribed."}), []}

      _other ->
        :no_match
    end
  end

  defp screen_state(state) do
    case get_in(state.screen_state, [:board_list]) do
      %State{} = ss -> ss
      _ -> init_screen_state()
    end
  end

  defp put_tree_for_directory(state, directory) do
    put_ss(state, %{screen_state(state) | board_tree: build_tree(directory)})
  end

  defp put_ss(state, %State{} = ss) do
    %{state | screen_state: Map.put(state.screen_state || %{}, :board_list, ss)}
  end

  defp build_tree(directory) when is_list(directory) do
    BoardTree.init(directory: directory, id: "board-directory")
  end

  defp maybe_feedback(%State{feedback: feedback}, theme) when is_binary(feedback) do
    [text(feedback, fg: theme.accent.fg), text("")]
  end

  defp maybe_feedback(_ss, _theme), do: []

  defp feedback_row_count(%State{feedback: feedback}) when is_binary(feedback), do: 2
  defp feedback_row_count(_ss), do: 0

  defp detail_strip?(height, feedback_rows), do: height - feedback_rows >= 4

  defp visible_tree_rows(row_budget), do: max(row_budget, 3)

  defp details_strip(board_tree, directory, theme, width) do
    line =
      board_tree
      |> BoardTree.focused_entry()
      |> detail_text(directory || [])
      |> TextWidth.truncate(max(width, 2))

    text(line, fg: theme.dim.fg)
  end

  defp detail_text(%{kind: :board} = entry, _directory) do
    [
      entry.board.name,
      subscription_label(entry),
      unread_label(entry.unread_count),
      age_label(entry.last_post_at)
    ]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(" • ")
  end

  defp detail_text(%{kind: :category, category: category}, directory) do
    boards =
      directory
      |> Enum.find_value([], fn
        %{category: %{id: id}, boards: boards} when id == category.id -> boards
        _ -> nil
      end)

    unread_total =
      boards
      |> Enum.map(&Map.get(&1, :unread_count))
      |> Enum.filter(&is_integer/1)
      |> Enum.sum()

    "#{category.name} • #{length(boards)} boards • #{unread_total} unread total"
  end

  defp detail_text(_entry, _directory), do: ""

  defp subscription_label(%{required_subscription?: true}), do: "required"
  defp subscription_label(%{subscribed?: true}), do: "subscribed"
  defp subscription_label(_entry), do: "subscribe"

  defp unread_label(nil), do: nil
  defp unread_label(0), do: "all read"
  defp unread_label(count) when is_integer(count), do: "#{count} unread"

  defp age_label(nil), do: "no posts yet"
  defp age_label(%DateTime{} = dt), do: TimeAgo.format(dt) <> " ago"

  defp row_width(state) do
    case Map.get(state, :terminal_size) do
      {cols, _rows} when is_integer(cols) and cols > 4 -> cols - 4
      _ -> 80
    end
  end

  defp body_height(state) do
    case Map.get(state, :terminal_size) do
      {_cols, rows} when is_integer(rows) -> max(rows - 4, 0)
      _ -> 20
    end
  end

  defp domain_module(state, :boards) do
    ctx = Map.get(state, :session_context) || %{}

    case Domain.get(ctx, :boards) do
      {:ok, mod} -> mod
      {:error, :not_configured} -> Foglet.Boards
    end
  end
end
