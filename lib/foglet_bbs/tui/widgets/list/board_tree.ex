defmodule Foglet.TUI.Widgets.List.BoardTree do
  @moduledoc """
  Themed board-directory tree (BOARDS-01..04). Stateful facade.

  Owns a `Foglet.TUI.Widgets.Display.Tree` for cursor and expanded
  state, walks `Raxol.UI.Components.Display.Tree.visible_nodes/1`
  itself, and dispatches each visible node to either an inline themed
  category renderer (`▾`/`▸` + name, truncated with `…` at narrow
  widths) or the RichRow list renderer for board rows.

  Per 21-CONTEXT.md (revised 2026-04-25):

    * D-01 — public surface is `init/1`, `handle_event/2`, `render/2`,
      `focused_board_entry/1` (D-13).
    * D-02 — `RichRow :state_cluster` carries the read-state cell
      (`:unread` when `unread_count >= 1`, absent otherwise) AND the
      subscription cell (one of `:locked` / `%{key: :subscribed_board,
      glyph: "✓", slot: :info}` / `%{key: :available_board, glyph:
      "+", slot: :dim}`). `RichRow :title` carries the indented board
      name ONLY (no glyph prefix).
    * D-04 — board row layout: indent (in title) + cluster (read +
      subscription cells) + name (in title) + composite trailing
      metadata (`"N unread  AGE"` / `"all read  AGE"` / `"AGE"` only).
    * D-06 — age is `Foglet.TimeAgo.format/1` short form for non-nil
      DateTime; `"—"` (U+2014) for nil. Branch BEFORE calling TimeAgo
      (it returns `"?"` for nil — see 21-RESEARCH.md Pitfall 3).
    * D-07 — category rows render only `"{▾|▸} {category.name}"`,
      truncated with `…` at narrow widths.
    * D-10b — subscription glyphs route through theme slots via
      RichRow's existing cluster-cell `:slot` field. No separate
      styling layer.
    * D-13 — `focused_board_entry/1 :: t() -> board_entry() | nil`
      encapsulates the cursor → entry lookup so `BoardList` does not
      pattern-match on internal `Display.Tree.t()` shape. `focused_entry/1`
      exposes the same encapsulation for board/category detail rendering.

  ## Terminal-rendering caveat (21-RESEARCH.md Pitfall 1)

  The `⚿` (U+26BF Squared Key) glyph has Unicode East_Asian_Width
  property "Ambiguous." On East-Asian-locale terminals (CJK fonts,
  ambiguous=wide), it renders as 2 cells. On Western terminals it
  renders as 1 cell. Raxol's width measurement
  (`Foglet.TUI.TextWidth.display_width/1`) treats it as 1 cell; that is
  the layout-truth source.
  """

  import Raxol.Core.Renderer.View

  alias Foglet.TimeAgo
  alias Foglet.TUI.TextWidth
  alias Foglet.TUI.Theme
  alias Foglet.TUI.Widgets.Display.Tree
  alias Foglet.TUI.Widgets.List.RichRow
  alias Raxol.UI.Components.Display.Tree, as: RaxolTree

  @category_glyph_expanded "▾"
  @category_glyph_collapsed "▸"
  @glyph_subscribed "✓"
  @glyph_available "+"
  @glyph_no_age "—"
  @archived_suffix " [archived]"
  @indent_per_depth 2
  @default_width 80

  @type directory_entry :: %{
          required(:category) => map(),
          required(:boards) => [board_entry()]
        }

  @type board_entry :: %{
          required(:board) => map(),
          required(:subscribed?) => boolean(),
          required(:required_subscription?) => boolean(),
          required(:unread_count) => non_neg_integer() | nil,
          required(:last_post_at) => DateTime.t() | nil,
          optional(:archived?) => boolean()
        }

  @typep state_cluster_cell ::
           :unread | subscription_cluster_cell()

  @typep subscription_cluster_cell ::
           :locked
           | %{
               required(:key) => :available_board | :subscribed_board,
               required(:glyph) => String.t(),
               required(:slot) => :dim | :info
             }

  defstruct [:tree, :directory, last_action: nil]

  @type t :: %__MODULE__{
          tree: Tree.t(),
          directory: [directory_entry()],
          last_action: Tree.action() | nil
        }

  @doc """
  Build a `BoardTree` from a directory list.

  Required keys:

    * `:directory` — list of category/boards maps from
      `Foglet.Boards.board_directory_for/1`.

  Optional keys:

    * `:id` — string id for the underlying `Display.Tree`. Defaults to
      a unique generated id.
  """
  @spec init(keyword()) :: t()
  def init(opts) when is_list(opts) do
    directory = Keyword.fetch!(opts, :directory)
    id = Keyword.get(opts, :id, "board-tree-#{:erlang.unique_integer([:positive])}")

    nodes = directory_to_nodes(directory)
    tree = Tree.init(id: id, nodes: nodes)

    expanded =
      nodes
      |> Enum.map(& &1.id)
      |> MapSet.new()

    tree = put_in(tree.raxol_state.expanded, expanded)

    # FOG-105: park the initial cursor on the first board (leaf) so the
    # selection marker is visible on first entry and Enter on the first
    # frame opens that board deterministically. Raxol's default lands the
    # cursor on the first category, which renders without a `▌` marker
    # and binds Enter to expand/collapse rather than open.
    tree =
      case first_board_id(nodes) do
        nil -> tree
        board_id -> put_in(tree.raxol_state.cursor, board_id)
      end

    %__MODULE__{tree: tree, directory: directory, last_action: nil}
  end

  @spec first_board_id([Tree.tree_node()]) :: term() | nil
  defp first_board_id(nodes) do
    Enum.find_value(nodes, fn
      %{children: [first | _]} -> first.id
      _ -> nil
    end)
  end

  @doc "Forward an input event to the underlying tree and surface its action."
  @spec handle_event(map(), t()) :: {t(), Tree.action()}
  def handle_event(event, %__MODULE__{tree: t} = st) do
    {new_t, action} = Tree.handle_event(event, t)
    {%{st | tree: new_t, last_action: action}, action}
  end

  @doc """
  Render the tree.

  Required keyword:

    * `:theme` — `%Foglet.TUI.Theme{}` slot snapshot.

  Optional keyword:

    * `:width` — display width budget (default `#{@default_width}`).
    * `:visible_height` — maximum visible rows to render, or `:all`
      for the full tree.
  """
  @spec render(t(), keyword()) :: any()
  def render(%__MODULE__{tree: %Tree{raxol_state: rs}}, opts) do
    %Theme{} = theme = Keyword.fetch!(opts, :theme)
    width = Keyword.get(opts, :width, @default_width)
    visible_height = Keyword.get(opts, :visible_height, :all)
    cursor = Map.get(rs, :cursor)
    expanded = Map.get(rs, :expanded, MapSet.new())
    visible = rs |> RaxolTree.visible_nodes() |> visible_window(cursor, visible_height)

    rows =
      Enum.map(visible, fn {node, depth} ->
        case Map.get(node, :data) do
          %{kind: :category, category: cat} = data ->
            render_category(
              cat,
              depth,
              expanded,
              node.id == cursor,
              theme,
              width,
              Map.get(data, :archived?, false) || Map.get(cat, :archived, false)
            )

          %{kind: :board} = data ->
            render_board(data, depth, node.id == cursor, theme, width)
        end
      end)

    column style: %{gap: 0} do
      rows
    end
  end

  @doc """
  Returns the focused board entry map (with `:kind` stripped) when the
  cursor is on a board node; `nil` when the cursor is on a category or
  out of range.

  `BoardList` consumes this API instead of pattern-matching on the
  internal `Display.Tree.t()` shape (CONTEXT D-13).
  """
  @spec focused_board_entry(t()) :: board_entry() | nil
  def focused_board_entry(%__MODULE__{tree: %Tree{raxol_state: %{cursor: cursor, nodes: nodes}}}) do
    case focused_data(nodes, cursor) do
      %{kind: :board} = data -> Map.delete(data, :kind)
      _ -> nil
    end
  end

  @doc """
  Returns the focused category or board entry data.

  The returned map includes `:kind` so callers can render category and
  board details without depending on the underlying `Display.Tree` state.
  """
  @spec focused_entry(t()) ::
          %{required(:kind) => :category, required(:category) => map()}
          | %{
              required(:kind) => :board,
              required(:board) => map(),
              required(:subscribed?) => boolean(),
              required(:required_subscription?) => boolean(),
              required(:unread_count) => non_neg_integer() | nil,
              required(:last_post_at) => DateTime.t() | nil
            }
          | nil
  def focused_entry(%__MODULE__{tree: %Tree{raxol_state: %{cursor: cursor, nodes: nodes}}}) do
    focused_data(nodes, cursor)
  end

  @spec focused_data([Tree.tree_node()] | nil, term() | nil) :: map() | nil
  defp focused_data(nodes, cursor) do
    case find_node(nodes, cursor) do
      %{data: data} when is_map(data) -> data
      _ -> nil
    end
  end

  @spec find_node([Tree.tree_node()] | nil, term() | nil) :: Tree.tree_node() | nil
  defp find_node(_nodes, nil), do: nil

  defp find_node(nodes, id) when is_list(nodes) do
    Enum.find_value(nodes, fn
      %{id: ^id} = node ->
        node

      %{children: children} ->
        find_node(children, id)

      _ ->
        nil
    end)
  end

  defp find_node(_, _), do: nil

  @spec visible_window(
          [{Tree.tree_node(), non_neg_integer()}],
          term() | nil,
          :all | pos_integer() | term()
        ) ::
          [{Tree.tree_node(), non_neg_integer()}]
  defp visible_window(visible, _cursor, :all), do: visible
  defp visible_window(visible, _cursor, height) when not is_integer(height), do: visible
  defp visible_window(_visible, _cursor, height) when height <= 0, do: []

  defp visible_window(visible, cursor, height) do
    cursor_index =
      Enum.find_index(visible, fn {node, _depth} ->
        node.id == cursor
      end) || 0

    start = cursor_index |> min(length(visible) - height) |> max(0)

    Enum.slice(visible, start, height)
  end

  @spec render_category(
          map(),
          non_neg_integer(),
          MapSet.t(),
          boolean(),
          Theme.t(),
          pos_integer(),
          boolean()
        ) :: any()
  defp render_category(cat, depth, expanded, selected?, theme, width, archived?) do
    indent = TextWidth.pad_trailing("", depth * @indent_per_depth)

    glyph =
      if MapSet.member?(expanded, {:category, cat.id}),
        do: @category_glyph_expanded,
        else: @category_glyph_collapsed

    name = if archived?, do: cat.name <> @archived_suffix, else: cat.name
    full_label = "#{indent}#{glyph} #{name}"
    label = TextWidth.truncate(full_label, max(width, 2))

    cond do
      selected? ->
        text(label,
          fg: theme.selected.fg,
          bg: theme.selected.bg,
          style: Map.get(theme.selected, :style, [:bold])
        )

      archived? ->
        text(label, fg: theme.dim.fg)

      true ->
        style = Map.get(theme.primary, :style, [])

        if style == [] do
          text(label, fg: theme.primary.fg, style: [:bold])
        else
          text(label, fg: theme.primary.fg, style: Enum.uniq(style ++ [:bold]))
        end
    end
  end

  @spec render_board(
          board_entry() | map(),
          non_neg_integer(),
          boolean(),
          Theme.t(),
          pos_integer()
        ) ::
          any()
  defp render_board(data, depth, selected?, theme, width) do
    %{
      board: board,
      subscribed?: subscribed?,
      required_subscription?: required?,
      unread_count: unread,
      last_post_at: last_post_at
    } = data

    archived? = Map.get(data, :archived?, false) || Map.get(board, :archived, false)

    RichRow.render(
      title: compose_title(depth, board.name, archived?),
      metadata: compose_metadata(unread, last_post_at, archived?),
      state_cluster: build_state_cluster(unread, subscribed?, required?, archived?),
      selected: selected?,
      theme: theme,
      width: width,
      emphasis: row_emphasis(unread, archived?)
    )
  end

  @spec row_emphasis(non_neg_integer() | nil, boolean()) :: :dim | :bold | nil
  defp row_emphasis(_unread, true), do: :dim
  defp row_emphasis(unread, false), do: if(unread_present?(unread), do: :bold)

  @spec build_state_cluster(non_neg_integer() | nil, boolean(), boolean(), boolean()) :: [
          state_cluster_cell()
        ]
  defp build_state_cluster(_unread, _subscribed?, _required?, true), do: [:locked]

  defp build_state_cluster(unread, subscribed?, required?, false) do
    read_cells = if unread_present?(unread), do: [:unread], else: []
    sub_cell = subscription_cluster_cell(subscribed?, required?)
    read_cells ++ [sub_cell]
  end

  @spec unread_present?(non_neg_integer() | nil) :: boolean()
  defp unread_present?(unread) when is_integer(unread) and unread >= 1, do: true
  defp unread_present?(_), do: false

  @spec subscription_cluster_cell(boolean(), boolean()) :: subscription_cluster_cell()
  defp subscription_cluster_cell(_subscribed?, true), do: :locked

  defp subscription_cluster_cell(true, false),
    do: %{key: :subscribed_board, glyph: @glyph_subscribed, slot: :info}

  defp subscription_cluster_cell(false, false),
    do: %{key: :available_board, glyph: @glyph_available, slot: :dim}

  @spec compose_title(non_neg_integer(), String.t(), boolean()) :: String.t()
  defp compose_title(depth, name, archived?) do
    indent = TextWidth.pad_trailing("", depth * @indent_per_depth)
    suffix = if archived?, do: @archived_suffix, else: ""
    indent <> name <> suffix
  end

  @spec compose_metadata(non_neg_integer() | nil, DateTime.t() | nil, boolean()) :: String.t()
  defp compose_metadata(_unread, last_post_at, true), do: format_age(last_post_at)
  defp compose_metadata(nil, last_post_at, false), do: format_age(last_post_at)

  defp compose_metadata(0, last_post_at, false),
    do: "all read  " <> format_age(last_post_at)

  defp compose_metadata(n, last_post_at, false) when is_integer(n) and n >= 1,
    do: "#{n} unread  " <> format_age(last_post_at)

  @spec format_age(DateTime.t() | nil) :: String.t()
  defp format_age(nil), do: @glyph_no_age
  defp format_age(%DateTime{} = dt), do: TimeAgo.format(dt)

  @spec directory_to_nodes([directory_entry()]) :: [Tree.tree_node()]
  defp directory_to_nodes(directory) do
    Enum.map(directory, fn %{category: cat, boards: boards} ->
      cat_archived? =
        Map.get(cat, :archived, false) or
          (boards != [] and Enum.all?(boards, &Map.get(&1, :archived?, false)))

      %{
        id: {:category, cat.id},
        label: cat.name,
        children: Enum.map(boards, &board_to_node/1),
        data: %{kind: :category, category: cat, archived?: cat_archived?}
      }
    end)
  end

  @spec board_to_node(board_entry()) :: Tree.tree_node()
  defp board_to_node(%{board: board} = entry) do
    %{
      id: {:board, board.id},
      label: board.name,
      children: [],
      data: Map.put(entry, :kind, :board)
    }
  end
end
