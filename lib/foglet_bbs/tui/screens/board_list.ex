defmodule Foglet.TUI.Screens.BoardList do
  @moduledoc """
  Category-tree board directory (SSH-07, SSH-08).

  BoardList is a screen-owned reducer over `BoardList.State` and
  `Foglet.TUI.Context`; App only routes keys, task results, and effects.
  """

  @behaviour Foglet.TUI.Screen

  alias Foglet.TimeAgo
  alias Foglet.TUI.Context
  alias Foglet.TUI.Effect
  alias Foglet.TUI.Screens.BoardList.State
  alias Foglet.TUI.Screens.Domain
  alias Foglet.TUI.TextWidth
  alias Foglet.TUI.Theme
  alias Foglet.TUI.Widgets.Chrome.ScreenFrame
  alias Foglet.TUI.Widgets.List.BoardTree
  alias Foglet.TUI.Widgets.Progress.Spinner

  import Raxol.Core.Renderer.View

  @subscription_ops [:subscribe_to_board, :unsubscribe_from_board]

  @impl true
  @spec init(Context.t()) :: State.t()
  def init(%Context{}), do: State.new(status: :loading)

  @impl true
  @spec update(term(), State.t() | nil, Context.t()) :: {State.t(), [Effect.t()]}
  def update(:load, local_state, %Context{} = context) do
    local_state =
      local_state
      |> normalize_state()
      |> Map.merge(%{status: :loading, last_op: :load_boards, last_error: nil})

    {local_state, [load_boards_effect(context)]}
  end

  def update({:task_result, :load_boards, {:ok, directory}}, local_state, %Context{})
      when is_list(directory) do
    local_state =
      local_state
      |> normalize_state()
      |> Map.merge(%{
        directory: directory,
        board_tree: build_tree(directory),
        status: directory_status(directory),
        last_op: nil,
        last_error: nil
      })

    {local_state, []}
  end

  def update({:task_result, :load_boards, {:error, reason}}, local_state, %Context{}) do
    local_state =
      local_state
      |> normalize_state()
      |> Map.merge(%{status: {:error, reason}, last_op: nil, last_error: reason})

    {local_state, []}
  end

  def update({:key, %{key: :char, char: "j"}}, local_state, %Context{}),
    do: update_tree(%{key: :down}, local_state)

  def update({:key, %{key: :down}}, local_state, %Context{}),
    do: update_tree(%{key: :down}, local_state)

  def update({:key, %{key: :char, char: "k"}}, local_state, %Context{}),
    do: update_tree(%{key: :up}, local_state)

  def update({:key, %{key: :up}}, local_state, %Context{}),
    do: update_tree(%{key: :up}, local_state)

  def update({:key, %{key: :left}}, local_state, %Context{}),
    do: update_tree(%{key: :left}, local_state)

  def update({:key, %{key: :right}}, local_state, %Context{}),
    do: update_tree(%{key: :right}, local_state)

  def update({:key, %{key: :enter}}, local_state, %Context{}) do
    local_state = normalize_state(local_state)

    with %BoardTree{} = tree <- tree_for_state(local_state),
         {%BoardTree{} = new_tree, action} <- BoardTree.handle_event(%{key: :enter}, tree) do
      local_state = %{local_state | board_tree: new_tree}

      case action do
        action when action in [:node_expanded, :node_collapsed] ->
          {local_state, []}

        :node_activated ->
          case BoardTree.focused_board_entry(new_tree) do
            %{board: board} ->
              {local_state,
               [
                 Effect.navigate(:thread_list, %{
                   board: board_identity(board),
                   board_id: Map.get(board, :id)
                 })
               ]}

            _other ->
              {local_state, []}
          end

        _other ->
          {local_state, []}
      end
    else
      _other -> {local_state, []}
    end
  end

  def update({:key, %{key: :char, char: "s"}}, local_state, %Context{} = context) do
    local_state = normalize_state(local_state)

    with %BoardTree{} = tree <- tree_for_state(local_state),
         %{board: board, subscribed?: false} <- BoardTree.focused_board_entry(tree) do
      local_state = %{local_state | board_tree: tree, feedback: nil, last_op: :subscribe_to_board}
      {local_state, [subscription_effect(:subscribe_to_board, board, context)]}
    else
      %{subscribed?: true} ->
        {%{local_state | feedback: "Already subscribed."}, []}

      _other ->
        {local_state, []}
    end
  end

  def update({:key, %{key: :char, char: "u"}}, local_state, %Context{} = context) do
    local_state = normalize_state(local_state)

    with %BoardTree{} = tree <- tree_for_state(local_state),
         focused when is_map(focused) <- BoardTree.focused_board_entry(tree) do
      case focused do
        %{required_subscription?: true} ->
          {%{local_state | board_tree: tree, feedback: "This board is a required subscription."},
           []}

        %{board: board, subscribed?: true} ->
          local_state = %{
            local_state
            | board_tree: tree,
              feedback: nil,
              last_op: :unsubscribe_from_board
          }

          {local_state, [subscription_effect(:unsubscribe_from_board, board, context)]}

        %{subscribed?: false} ->
          {%{local_state | board_tree: tree, feedback: "Not subscribed."}, []}
      end
    else
      _other -> {local_state, []}
    end
  end

  def update({:task_result, op, result}, local_state, %Context{} = context)
      when op in @subscription_ops do
    local_state = normalize_state(local_state)

    case unwrap_task_result(result) do
      {:ok, _value} ->
        feedback =
          case op do
            :subscribe_to_board -> "Subscribed."
            :unsubscribe_from_board -> "Unsubscribed."
          end

        {%{local_state | feedback: feedback, last_op: nil, last_error: nil},
         [load_boards_effect(context)]}

      {:error, :required_subscription} ->
        {%{
           local_state
           | feedback: "This board is a required subscription.",
             last_op: nil,
             last_error: :required_subscription
         }, []}

      {:error, :board_archived} ->
        {%{
           local_state
           | feedback: "That board is archived.",
             last_op: nil,
             last_error: :board_archived
         }, []}

      {:error, reason} ->
        {%{
           local_state
           | feedback: "Subscription change failed: #{inspect(reason)}",
             last_op: nil,
             last_error: reason
         }, []}
    end
  end

  def update({:board_activity, board_id, _event}, local_state, %Context{} = context)
      when is_binary(board_id) do
    local_state = normalize_state(local_state)
    {%{local_state | last_op: :load_boards}, [load_boards_effect(context)]}
  end

  def update({:key, %{key: :char, char: c}}, local_state, %Context{}) when c in ["q", "Q"] do
    {normalize_state(local_state), [Effect.navigate(:main_menu, %{})]}
  end

  def update(_message, local_state, %Context{}), do: {normalize_state(local_state), []}

  @impl true
  @spec render(State.t(), Context.t()) :: any()
  def render(%State{} = local_state, %Context{} = context) do
    render_model = render_model(context, local_state)
    theme = Theme.from_state(render_model)

    ScreenFrame.render(
      render_model,
      %{breadcrumb_parts: ["Foglet", "Boards"]},
      render_board_content(local_state, context, theme),
      [
        %{
          label: "Navigate",
          commands: [
            %{key: "j/k", label: "Select", priority: 10},
            %{key: "←/→", label: "Collapse/Expand", priority: 10},
            %{key: "Enter", label: "Open", priority: 10}
          ]
        },
        %{
          label: "Actions",
          commands: [%{key: "s/u", label: "Subscribe/Unsubscribe", priority: 30}]
        },
        %{
          label: "System",
          commands: [%{key: "Q", label: "Back", priority: 0}]
        }
      ]
    )
  end

  # WR-03: previously had a `def render(local_state, %Context{})` fallback that
  # called `normalize_state/1`. Routing.render_local_state/4 always either
  # returns a stored `%State{}` or calls `init/1` (which returns `%State{}`),
  # so the fallback was unreachable and Dialyzer flagged its `@spec`.

  @impl true
  @spec subscriptions(State.t() | map() | nil, Context.t()) :: [String.t()]
  def subscriptions(_local_state, _context) do
    [Foglet.PubSub.boards_aggregate()]
  end

  defp render_board_content(%State{status: :empty} = state, _context, theme) do
    column style: %{gap: 0} do
      maybe_feedback(state, theme) ++
        [text("No active boards are available.", fg: theme.warning.fg)]
    end
  end

  defp render_board_content(%State{status: :loading} = state, _context, theme) do
    frame = System.monotonic_time(:millisecond) |> abs() |> div(Spinner.frame_duration_ms())

    column style: %{gap: 0} do
      maybe_feedback(state, theme) ++
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

  defp render_board_content(%State{status: {:error, reason}} = state, _context, theme) do
    column style: %{gap: 0} do
      maybe_feedback(state, theme) ++
        [text("Unable to load boards: #{inspect(reason)}", fg: theme.warning.fg)]
    end
  end

  defp render_board_content(%State{} = state, %Context{} = context, theme) do
    directory = state.directory || []
    board_tree = state.board_tree || build_tree(directory)
    width = row_width(context)
    height = body_height(context)
    feedback_rows = feedback_row_count(state)
    detail? = detail_strip?(height, feedback_rows)

    reserved_rows =
      feedback_rows +
        if(detail?, do: 1, else: 0)

    visible_height = visible_tree_rows(max(height - reserved_rows, 3))

    column style: %{gap: 0} do
      [
        maybe_feedback(state, theme),
        BoardTree.render(board_tree, theme: theme, width: width, visible_height: visible_height),
        if(detail?, do: details_strip(board_tree, directory, theme, width))
      ]
      |> List.flatten()
      |> Enum.reject(&is_nil/1)
    end
  end

  defp update_tree(key, local_state) do
    local_state = normalize_state(local_state)

    case tree_for_state(local_state) do
      %BoardTree{} = tree ->
        {new_tree, _action} = BoardTree.handle_event(key, tree)
        {%{local_state | board_tree: new_tree}, []}

      nil ->
        {local_state, []}
    end
  end

  defp load_boards_effect(%Context{} = context) do
    user = context.current_user
    boards_mod = domain_module(context, :boards)

    Effect.task(:load_boards, :board_list, fn ->
      boards_mod.board_directory_for(user)
    end)
  end

  defp subscription_effect(op, board, %Context{} = context) do
    user = context.current_user
    board_id = Map.get(board, :id)
    boards_mod = domain_module(context, :boards)

    Effect.task(op, :board_list, fn ->
      case op do
        :subscribe_to_board -> boards_mod.subscribe_user_to_board(user, board_id)
        :unsubscribe_from_board -> boards_mod.unsubscribe_user_from_board(user, board_id)
      end
    end)
  end

  defp normalize_state(%State{} = state), do: state
  defp normalize_state(_state), do: State.new()

  defp directory_status([]), do: :empty
  defp directory_status(_directory), do: :loaded

  defp tree_for_state(%State{board_tree: %BoardTree{} = tree}), do: tree

  defp tree_for_state(%State{directory: directory}) when is_list(directory),
    do: build_tree(directory)

  defp tree_for_state(_state), do: nil

  defp build_tree(directory) when is_list(directory) do
    BoardTree.init(directory: directory, id: "board-directory")
  end

  defp maybe_feedback(%State{feedback: feedback}, theme) when is_binary(feedback) do
    [text(feedback, fg: theme.accent.fg), text("")]
  end

  defp maybe_feedback(_state, _theme), do: []

  defp feedback_row_count(%State{feedback: feedback}) when is_binary(feedback), do: 2
  defp feedback_row_count(_state), do: 0

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
        _entry -> nil
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

  defp row_width(%Context{terminal_size: {cols, _rows}}) when is_integer(cols) and cols > 4,
    do: cols - 4

  defp row_width(_context), do: 80

  defp body_height(%Context{terminal_size: {_cols, rows}}) when is_integer(rows),
    do: max(rows - 4, 0)

  defp body_height(_context), do: 20

  defp render_model(%Context{} = context, %State{} = state) do
    %{
      current_screen: :board_list,
      current_user: context.current_user,
      route_params: context.route_params,
      session_context: context.session_context,
      terminal_size: context.terminal_size,
      screen_state: %{board_list: state}
    }
  end

  defp board_identity(board) when is_map(board) do
    %{
      id: Map.get(board, :id),
      name: Map.get(board, :name),
      slug: Map.get(board, :slug)
    }
  end

  defp domain_module(%Context{domain: domain} = context, key) when is_map(domain) do
    case Map.get(domain, key) do
      module when is_atom(module) and not is_nil(module) ->
        module

      _other ->
        domain_module_from_session_context(context, key)
    end
  end

  defp domain_module(%Context{} = context, key),
    do: domain_module_from_session_context(context, key)

  defp domain_module_from_session_context(%Context{session_context: session_context}, :boards) do
    case Domain.get(session_context || %{}, :boards) do
      {:ok, mod} -> mod
      {:error, :not_configured} -> Foglet.Boards
    end
  end

  defp unwrap_task_result({:ok, {:ok, value}}), do: {:ok, value}
  defp unwrap_task_result({:ok, {:error, reason}}), do: {:error, reason}
  defp unwrap_task_result({:ok, value}), do: {:ok, value}
  defp unwrap_task_result({:error, reason}), do: {:error, reason}
  defp unwrap_task_result(other), do: {:error, other}
end
