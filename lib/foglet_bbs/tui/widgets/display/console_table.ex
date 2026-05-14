defmodule Foglet.TUI.Widgets.Display.ConsoleTable do
  @moduledoc """
  Operator-console table facade over `Foglet.TUI.Widgets.Display.Table`.

  Honours:
    * D-03 — exposes an explicit display-level operator table API.
    * D-12 — delegates table behavior to `Display.Table`.
    * D-13 — owns dense defaults for compact operator-console tables.
    * D-14 — supports operator-shaped fixtures, empty states, and selection.
  """

  import Raxol.Core.Renderer.View

  alias Foglet.TUI.Theme
  alias Foglet.TUI.Widgets.Display.Table

  @default_empty_state "No records."
  @default_page_size 10
  @default_width 12

  defstruct [
    :table,
    :columns,
    :rows,
    :empty_state,
    :selectable,
    :sortable,
    :filterable,
    :page_size,
    :width,
    last_action: nil
  ]

  @type t :: %__MODULE__{
          table: Table.t(),
          columns: [map()],
          rows: [map()],
          empty_state: String.t(),
          selectable: boolean(),
          sortable: boolean(),
          filterable: boolean(),
          page_size: pos_integer(),
          width: pos_integer() | nil,
          last_action: Table.action()
        }

  @doc """
  Initializes a dense operator-console table state.
  """
  @spec init(keyword()) :: t()
  def init(opts) when is_list(opts) do
    columns = opts |> Keyword.fetch!(:columns) |> Enum.map(&normalize_column/1)
    rows = Keyword.get(opts, :rows, [])
    empty_state = Keyword.get(opts, :empty_state, @default_empty_state)
    sortable = Keyword.get(opts, :sortable, false)
    filterable = Keyword.get(opts, :filterable, false)
    selectable = Keyword.get(opts, :selectable, false)
    page_size = Keyword.get(opts, :page_size, @default_page_size)
    width = Keyword.get(opts, :width)

    table =
      Table.init(
        columns: columns,
        rows: rows,
        sortable: sortable,
        filterable: filterable,
        page_size: page_size,
        width: width
      )

    %__MODULE__{
      table: table,
      columns: columns,
      rows: rows,
      empty_state: empty_state,
      selectable: selectable,
      sortable: sortable,
      filterable: filterable,
      page_size: page_size,
      width: width,
      last_action: nil
    }
  end

  @spec handle_event(map(), t()) :: {t(), Table.action()}
  def handle_event(%{key: :enter}, %__MODULE__{selectable: false} = state) do
    {%{state | last_action: nil}, nil}
  end

  def handle_event(event, %__MODULE__{} = state) do
    {table, action} = Table.handle_event(event, state.table)
    {%{state | table: table, last_action: action}, action}
  end

  @doc """
  Returns the selected row index owned by the underlying table state.

  Pass a default when a caller needs a concrete fallback for empty tables.
  """
  @spec selected_index(t()) :: non_neg_integer() | nil
  @spec selected_index(t(), term()) :: non_neg_integer() | term()
  def selected_index(%__MODULE__{table: %Table{raxol_state: raxol_state}}, default \\ nil) do
    case Map.get(raxol_state, :selected_row) do
      index when is_integer(index) -> index
      _other -> default
    end
  end

  @doc "Returns the currently selected source row, or nil when no row is selected."
  @spec selected_row(t()) :: map() | nil
  def selected_row(%__MODULE__{rows: rows} = state) do
    case selected_index(state) do
      index when is_integer(index) -> Enum.at(rows, index)
      _other -> nil
    end
  end

  @doc "Sets the selected row index while keeping ownership inside the widget state."
  @spec put_selected_index(t(), non_neg_integer()) :: t()
  def put_selected_index(%__MODULE__{} = state, index) when is_integer(index) and index >= 0 do
    put_in(state.table.raxol_state[:selected_row], index)
  end

  def put_selected_index(%__MODULE__{} = state, _index), do: state

  @doc """
  Rebuilds the table for a new drawable width while preserving selection.

  Screens should use this instead of reaching into nested Raxol state when a
  responsive surface needs to recalculate column widths.
  """
  @spec with_width(t(), pos_integer() | nil) :: t()
  def with_width(%__MODULE__{} = state, width) when is_integer(width) and width > 0 do
    state
    |> rebuild(width)
    |> put_selected_index(selected_index(state))
  end

  def with_width(%__MODULE__{} = state, _width), do: state

  @spec render(t(), keyword()) :: any()
  def render(%__MODULE__{rows: []} = state, opts) do
    %Theme{} = theme = Keyword.fetch!(opts, :theme)
    text(state.empty_state, fg: theme.dim.fg)
  end

  def render(%__MODULE__{} = state, opts) do
    %Theme{} = _theme = Keyword.fetch!(opts, :theme)
    Table.render(state.table, opts)
  end

  defp rebuild(%__MODULE__{} = state, width) do
    init(
      columns: state.columns,
      rows: state.rows,
      empty_state: state.empty_state,
      selectable: state.selectable,
      sortable: state.sortable,
      filterable: state.filterable,
      page_size: state.page_size,
      width: width
    )
  end

  defp normalize_column(column) when is_map(column) do
    column
    |> normalize_column_id()
    |> Map.put_new(:width, @default_width)
  end

  defp normalize_column_id(column) do
    case {Map.get(column, :id), Map.get(column, :key)} do
      {nil, key} when not is_nil(key) -> Map.put(column, :id, key)
      _ -> column
    end
  end
end
