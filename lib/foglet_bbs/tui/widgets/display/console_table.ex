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

  defstruct [:table, :columns, :rows, :empty_state, :selectable, last_action: nil]

  @type t :: %__MODULE__{
          table: Table.t(),
          columns: [map()],
          rows: [map()],
          empty_state: String.t(),
          selectable: boolean(),
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

    table =
      Table.init(
        columns: columns,
        rows: rows,
        sortable: sortable,
        filterable: filterable,
        page_size: page_size
      )

    %__MODULE__{
      table: table,
      columns: columns,
      rows: rows,
      empty_state: empty_state,
      selectable: selectable,
      last_action: nil
    }
  end

  @spec handle_event(map(), t()) :: {t(), Table.action()}
  def handle_event(event, %__MODULE__{} = state) do
    {table, action} = Table.handle_event(event, state.table)
    {%{state | table: table, last_action: action}, action}
  end

  @spec render(t(), keyword()) :: any()
  def render(%__MODULE__{rows: []} = state, opts) do
    %Theme{} = theme = Keyword.fetch!(opts, :theme)
    text(state.empty_state, fg: theme.dim.fg)
  end

  def render(%__MODULE__{} = state, opts) do
    %Theme{} = _theme = Keyword.fetch!(opts, :theme)
    Table.render(state.table, opts)
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
