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
  alias Foglet.TUI.Guest
  alias Foglet.TUI.Layout
  alias Foglet.TUI.Screens.BoardList.State
  alias Foglet.TUI.Screens.Domain
  alias Foglet.TUI.ScrollKeys
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
    local_state = normalize_state(local_state)
    board_tree = build_tree(directory, local_state)

    local_state =
      local_state
      |> Map.merge(%{
        directory: directory,
        board_tree: board_tree,
        status: directory_status(directory),
        last_op: nil,
        last_error: nil
      })
      |> remember_tree_state()

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
      local_state = %{local_state | board_tree: new_tree} |> remember_tree_state()

      case action do
        action when action in [:node_expanded, :node_collapsed] ->
          {local_state, []}

        :node_activated ->
          case BoardTree.focused_board_entry(new_tree) do
            %{board: board} = entry ->
              {local_state,
               [
                 Effect.navigate(:thread_list, %{
                   board: board_identity(board),
                   board_id: Map.get(board, :id),
                   subscribed?: Map.get(entry, :subscribed?, true)
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

    if Guest.guest?(context) do
      {%{local_state | feedback: guest_subscription_feedback(), last_op: nil}, []}
    else
      with %BoardTree{} = tree <- tree_for_state(local_state),
           focused when is_map(focused) <- BoardTree.focused_board_entry(tree) do
        case focused do
          %{archived?: true} ->
            {%{local_state | board_tree: tree, feedback: "That board is archived."}, []}

          %{board: board, subscribed?: false} ->
            local_state = %{
              local_state
              | board_tree: tree,
                feedback: nil,
                last_op: :subscribe_to_board
            }

            {local_state, [subscription_effect(:subscribe_to_board, board, context)]}

          %{subscribed?: true} ->
            {%{local_state | feedback: "Already subscribed."}, []}
        end
      else
        _other ->
          {local_state, []}
      end
    end
  end

  def update({:key, %{key: :char, char: "u"}}, local_state, %Context{} = context) do
    local_state = normalize_state(local_state)

    if Guest.guest?(context) do
      {%{local_state | feedback: guest_subscription_feedback(), last_op: nil}, []}
    else
      with %BoardTree{} = tree <- tree_for_state(local_state),
           focused when is_map(focused) <- BoardTree.focused_board_entry(tree) do
        case focused do
          %{archived?: true} ->
            {%{local_state | board_tree: tree, feedback: "That board is archived."}, []}

          %{required_subscription?: true} ->
            {%{
               local_state
               | board_tree: tree,
                 feedback: "Required subscriptions can't be cancelled."
             }, []}

          %{board: board, subscribed?: true} ->
            local_state = %{
              local_state
              | board_tree: tree,
                feedback: nil,
                last_op: :unsubscribe_from_board
            }

            {local_state, [subscription_effect(:unsubscribe_from_board, board, context)]}

          %{subscribed?: false} ->
            {%{local_state | board_tree: tree}, []}
        end
      else
        _other -> {local_state, []}
      end
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
           | feedback: "Required subscriptions can't be cancelled.",
             last_op: nil,
             last_error: :required_subscription
         }, []}

      {:error, :board_archived} ->
        {%{
           local_state
           | feedback: "This board is archived; you can't subscribe.",
             last_op: nil,
             last_error: :board_archived
         }, []}

      {:error, reason} ->
        {%{
           local_state
           | feedback: "Couldn't change your subscription. Try again in a moment.",
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
      %{breadcrumb_parts: Foglet.AppName.breadcrumb(["Boards"])},
      render_board_content(local_state, context, theme),
      command_groups(context)
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

  defp render_board_content(%State{status: {:error, _reason}} = state, _context, theme) do
    column style: %{gap: 0} do
      maybe_feedback(state, theme) ++
        [text("Couldn't load boards. Press R to retry.", fg: theme.warning.fg)]
    end
  end

  defp render_board_content(%State{} = state, %Context{} = context, theme) do
    directory = state.directory || []
    board_tree = state.board_tree || build_tree(directory)
    width = row_width(context)
    height = body_height(context)
    feedback_rows = feedback_row_count(state)
    archived_note? = archived_present?(directory)
    archived_note_rows = if archived_note?, do: 1, else: 0
    detail? = detail_strip?(height, feedback_rows + archived_note_rows)

    reserved_rows =
      feedback_rows + archived_note_rows +
        if(detail?, do: 1, else: 0)

    visible_height = visible_tree_rows(max(height - reserved_rows, 3))

    tree_panel =
      column style: %{gap: 0} do
        [
          maybe_feedback(state, theme),
          maybe_archived_note(archived_note?, theme),
          BoardTree.render(board_tree,
            theme: theme,
            width: list_width(context),
            visible_height: visible_height
          ),
          if(detail? and not Layout.enhanced?(context.terminal_size),
            do: details_strip(board_tree, directory, theme, width)
          )
        ]
        |> List.flatten()
        |> Enum.reject(&is_nil/1)
      end

    if Layout.enhanced?(context.terminal_size) do
      list_box =
        box style: %{border: :single, padding: 1} do
          tree_panel
        end

      Layout.left_heavy_split(
        list_box,
        selected_board_inspector(board_tree, directory, theme),
        terminal_size: context.terminal_size,
        ratio: {7, 5},
        min_size: 28
      )
    else
      tree_panel
    end
  end

  defp command_groups(%Context{} = context) do
    navigate = %{
      label: "Navigate",
      commands: [
        %{key: ScrollKeys.commandbar_key(), label: "Select", priority: 10},
        %{key: "←/→", label: "Collapse/Expand", priority: 20},
        %{key: "Enter", label: "Open", priority: 5}
      ]
    }

    system = %{
      label: "System",
      commands: [%{key: "Q", label: "Back", priority: 0}]
    }

    if Guest.guest?(context) do
      [navigate, system]
    else
      [
        navigate,
        %{
          label: "Actions",
          commands: [%{key: "s/u", label: "Sub/Unsub", priority: 15}]
        },
        system
      ]
    end
  end

  defp archived_present?(directory) when is_list(directory) do
    Enum.any?(directory, fn %{boards: boards} ->
      Enum.any?(boards, &Map.get(&1, :archived?, false))
    end)
  end

  defp archived_present?(_directory), do: false

  defp maybe_archived_note(true, theme),
    do: text("Archived boards are visible to sysops/mods (read-only).", fg: theme.dim.fg)

  defp maybe_archived_note(false, _theme), do: nil

  defp update_tree(key, local_state) do
    local_state = normalize_state(local_state)

    case tree_for_state(local_state) do
      %BoardTree{} = tree ->
        {new_tree, _action} = BoardTree.handle_event(key, tree)
        {%{local_state | board_tree: new_tree} |> remember_tree_state(), []}

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

  defp tree_for_state(%State{directory: directory} = state) when is_list(directory),
    do: build_tree(directory, state)

  defp tree_for_state(_state), do: nil

  defp build_tree(directory) when is_list(directory) do
    BoardTree.init(directory: directory, id: "board-directory")
  end

  defp build_tree(directory, %State{} = state) when is_list(directory) do
    BoardTree.init(
      directory: directory,
      id: "board-directory",
      selected_board_id: state.selected_board_id,
      expanded_category_ids: state.expanded_category_ids || :all
    )
  end

  defp remember_tree_state(%State{board_tree: %BoardTree{} = tree} = state) do
    selected_board_id = BoardTree.focused_board_id(tree) || state.selected_board_id

    %{
      state
      | selected_board_id: selected_board_id,
        expanded_category_ids: BoardTree.expanded_category_ids(tree)
    }
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

  defp selected_board_inspector(board_tree, directory, theme) do
    entry = BoardTree.focused_entry(board_tree)

    box style: %{border: :single, padding: 1} do
      column style: %{gap: 0} do
        inspector_lines(entry, directory || [], theme)
      end
    end
  end

  defp inspector_lines(%{kind: :board, board: board} = entry, _directory, theme) do
    description =
      board |> Map.get(:description, "No board description yet.") |> normalize_description()

    description = description || "No board description yet."

    [
      text("Selected board", fg: theme.dim.fg, style: [:bold]),
      text(Map.get(board, :name, "Board"), fg: theme.primary.fg, style: [:bold]),
      text(description, fg: theme.unselected.fg),
      text(""),
      inspector_kv("State", subscription_label(entry), theme),
      inspector_kv("Unread", unread_label(entry.unread_count) || "unknown", theme),
      inspector_kv("Posting", posting_label(entry), theme),
      inspector_kv("Latest", age_label(entry.last_post_at), theme),
      text(""),
      text("Enter opens the thread list.", fg: theme.dim.fg),
      text("S/U changes subscription when allowed.", fg: theme.dim.fg)
    ]
  end

  defp inspector_lines(%{kind: :category, category: category}, directory, theme) do
    [
      text("Selected category", fg: theme.dim.fg, style: [:bold]),
      text(Map.get(category, :name, "Category"), fg: theme.primary.fg, style: [:bold]),
      text(detail_text(%{kind: :category, category: category}, directory),
        fg: theme.unselected.fg
      ),
      text(""),
      text("Use ←/→ to collapse or expand.", fg: theme.dim.fg)
    ]
  end

  defp inspector_lines(_entry, _directory, theme),
    do: [text("No board selected.", fg: theme.dim.fg)]

  defp inspector_kv(label, value, theme) do
    text(String.pad_trailing(label, 10) <> value, fg: theme.unselected.fg)
  end

  defp normalize_description(description) when is_binary(description) do
    description
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
    |> case do
      "" -> nil
      value -> value
    end
  end

  defp normalize_description(_description), do: nil

  defp posting_label(%{board: %{archived?: true}}), do: "archived read-only"
  defp posting_label(%{board: %{archived: true}}), do: "archived read-only"
  defp posting_label(%{board: %{postable_by: :mods_only}}), do: "moderators only"
  defp posting_label(%{board: %{postable_by: "mods_only"}}), do: "moderators only"
  defp posting_label(_entry), do: "members can post"

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

    "#{category.name} • #{board_count_label(length(boards))} • #{unread_total} unread total"
  end

  defp detail_text(_entry, _directory), do: ""

  defp board_count_label(1), do: "1 board"
  defp board_count_label(count) when is_integer(count), do: "#{count} boards"

  defp subscription_label(%{required_subscription?: true}), do: "required"
  defp subscription_label(%{subscribed?: true}), do: "subscribed"
  defp subscription_label(_entry), do: "available"

  defp unread_label(nil), do: nil
  defp unread_label(0), do: "all read"
  defp unread_label(count) when is_integer(count), do: "#{count} unread"

  defp age_label(nil), do: "no posts yet"
  defp age_label(%DateTime{} = dt), do: TimeAgo.format(dt) <> " ago"

  defp row_width(%Context{terminal_size: {cols, _rows}}) when is_integer(cols) and cols > 4,
    do: cols - 4

  defp row_width(_context), do: 80

  defp list_width(%Context{terminal_size: size}) do
    if Layout.enhanced?(size), do: 60, else: row_width(%Context{terminal_size: size})
  end

  defp body_height(%Context{terminal_size: {_cols, rows}}) when is_integer(rows),
    do: max(rows - 4, 0)

  defp body_height(_context), do: 20

  defp guest_subscription_feedback,
    do: "Guests can browse boards, but only registered users can subscribe."

  defp render_model(%Context{} = context, %State{} = state) do
    %{
      current_screen: :board_list,
      current_user: context.current_user,
      route_params: context.route_params,
      session_context: context.session_context,
      terminal_size: context.terminal_size,
      unread_count: context.unread_count,
      screen_state: %{board_list: state}
    }
  end

  defp board_identity(board) when is_map(board) do
    %{
      id: Map.get(board, :id),
      name: Map.get(board, :name),
      slug: Map.get(board, :slug),
      archived: Map.get(board, :archived, false),
      readable_by: Map.get(board, :readable_by, :public),
      postable_by: Map.get(board, :postable_by, :members),
      chat_enabled: Map.get(board, :chat_enabled, false),
      chat_storage_mode: Map.get(board, :chat_storage_mode),
      chat_message_ttl_seconds: Map.get(board, :chat_message_ttl_seconds)
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

  # IN-04: thin shim around the shared `Foglet.TUI.Effect.unwrap_task_result/1`.
  defp unwrap_task_result(result), do: Effect.unwrap_task_result(result)
end
