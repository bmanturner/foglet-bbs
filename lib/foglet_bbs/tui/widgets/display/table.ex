defmodule Foglet.TUI.Widgets.Display.Table do
  @moduledoc """
  Themed sortable / filterable / selectable table widget (D-02, D-13, D-14).

  Stateful facade over `Raxol.UI.Components.Table`. Supports sort (key
  cycles asc/desc/none), filter (type-to-search), and row selection via
  keyboard.

  Honours:
    * D-07/D-09 — theme-routed colors only
    * D-13     — `theme:` keyword arg
    * D-14     — `init/1` + `handle_event/2` + `render/2`

  ## Theme-map shape routed into the Raxol component (D-07)

      %{
        box: %{border_fg: theme.border.fg},
        header: %{fg: theme.title.fg, style: [:bold]},
        row: %{fg: theme.primary.fg},
        selected_row: %{fg: theme.selected.fg, bg: theme.selected.bg}
      }

  ## Column spec shape

      %{id: atom(), label: String.t(), width: integer() | :auto}

  ## Actions returned from `handle_event/2`

      {:row_selected, row}          — Enter on a focused row
      {:sort_changed, column_key}   — sort-cycle key pressed on a sortable column
      {:filter_changed, term}       — filter input changed (searchable tables)
      nil                           — navigation key, no semantic action
  """

  import Raxol.Core.Renderer.View
  alias Foglet.TUI.TextWidth
  alias Foglet.TUI.Theme
  alias Raxol.UI.Components.Table, as: RaxolTable

  @default_page_size 10
  @min_column_width 3

  @type action ::
          {:row_selected, map()}
          | {:sort_changed, atom()}
          | {:filter_changed, String.t()}
          | nil

  defstruct [:raxol_state, :columns, :sortable, :filterable, :available_width, last_action: nil]

  @type t :: %__MODULE__{
          raxol_state: map(),
          columns: list(map()),
          sortable: boolean(),
          filterable: boolean(),
          available_width: pos_integer() | nil,
          last_action: action()
        }

  @doc """
  Pure constructor.

  Options:
    * `:columns`    — list of column specs (required). Each: `%{id: atom(), label: String.t(), width: integer() | :auto}`
    * `:rows`       — list of row maps keyed by column `:id` (alias for `:data`)
    * `:sortable`   — boolean, default `false`
    * `:filterable` — boolean, default `false`
    * `:page_size`  — integer, default `#{@default_page_size}`
    * `:width`      — drawable content width available inside the caller container
  """
  @spec init(keyword()) :: t()
  def init(opts) when is_list(opts) do
    available_width = Keyword.get(opts, :width)

    columns =
      opts
      |> Keyword.fetch!(:columns)
      |> Enum.map(&normalize_column/1)
      |> resolve_columns(available_width)

    rows = Keyword.get(opts, :rows, Keyword.get(opts, :data, []))
    sortable = Keyword.get(opts, :sortable, false)
    filterable = Keyword.get(opts, :filterable, false)
    page_size = Keyword.get(opts, :page_size, @default_page_size)
    rows = normalize_rows(rows, columns, available_width)

    raxol_props = %{
      id: :foglet_table,
      columns: columns,
      data: rows,
      options: %{
        sortable: sortable,
        searchable: filterable,
        paginate: false,
        page_size: page_size
      }
    }

    {:ok, raxol_state} = RaxolTable.init(raxol_props)
    # Initialize selected_row to 0 only when there is at least one row;
    # otherwise leave it nil so the renderer doesn't paint a phantom
    # selection bar over an empty table (WR-05).
    initial_selected = if rows == [], do: nil, else: 0
    raxol_state = Map.put(raxol_state, :selected_row, initial_selected)

    %__MODULE__{
      raxol_state: raxol_state,
      columns: columns,
      sortable: sortable,
      filterable: filterable,
      available_width: available_width,
      last_action: nil
    }
  end

  @spec handle_event(map(), t()) :: {t(), action()}
  def handle_event(event, %__MODULE__{raxol_state: rs} = st) do
    if Map.get(rs, :data, []) == [] do
      # WR-05: empty tables have selected_row = nil; forwarding nav keys into
      # Raxol's table would crash on `nil + 1` arithmetic. Short-circuit and
      # return the state unchanged with no semantic action.
      {%{st | last_action: nil}, nil}
    else
      raxol_event = translate_event(event)
      {:ok, new_rs} = RaxolTable.handle_event(raxol_event, rs, %{})

      action = derive_action(rs, new_rs, event)
      {%{st | raxol_state: new_rs, last_action: action}, action}
    end
  end

  @spec render(t(), keyword()) :: any()
  def render(%__MODULE__{raxol_state: rs, available_width: available_width}, opts) do
    %Theme{} = theme = Keyword.fetch!(opts, :theme)
    rs_with_theme = %{rs | theme: build_table_theme(theme)}

    box style: %{border_fg: theme.border.fg, padding: 0} do
      RaxolTable.render(rs_with_theme, %{available_width: available_width})
    end
  end

  # --- private ---

  # Translate Foglet key events to Raxol.UI.Components.Table event tuples
  defp translate_event(%{key: :down}), do: {:key, {:arrow_down, nil}}
  defp translate_event(%{key: :up}), do: {:key, {:arrow_up, nil}}
  defp translate_event(%{key: :left}), do: {:key, {:arrow_left, nil}}
  defp translate_event(%{key: :right}), do: {:key, {:arrow_right, nil}}
  defp translate_event(%{key: :enter}), do: {:key, {:enter, nil}}
  defp translate_event(%{key: :escape}), do: {:key, {:escape, nil}}
  defp translate_event(%{key: :page_up}), do: {:key, {:page_up, nil}}
  defp translate_event(%{key: :page_down}), do: {:key, {:page_down, nil}}
  defp translate_event(%{key: :home}), do: {:key, {:home, nil}}
  defp translate_event(%{key: :end}), do: {:key, {:end, nil}}

  defp translate_event(%{key: :char, char: c}), do: {:key, {:char, c}}

  defp translate_event(_), do: {:key, {:unknown, nil}}

  defp derive_action(_before_rs, after_rs, %{key: :enter}) do
    row = Map.get(after_rs, :selected_row)

    if is_integer(row) do
      data = Map.get(after_rs, :data, [])
      selected = Enum.at(data, row)
      if selected, do: {:row_selected, selected}, else: nil
    else
      nil
    end
  end

  defp derive_action(before_rs, after_rs, _event) do
    cond do
      Map.get(before_rs, :sort_by) != Map.get(after_rs, :sort_by) ->
        {:sort_changed, Map.get(after_rs, :sort_by)}

      Map.get(before_rs, :filter_term) != Map.get(after_rs, :filter_term) ->
        {:filter_changed, Map.get(after_rs, :filter_term)}

      true ->
        nil
    end
  end

  defp build_table_theme(%Theme{} = t) do
    %{
      box: %{border_fg: t.border.fg},
      header: %{fg: t.title.fg, style: [:bold]},
      row: %{fg: t.primary.fg},
      selected_row: %{fg: t.selected.fg, bg: t.selected.bg}
    }
  end

  # Ensure each column has the required :id, :align, :width, and :format fields that Raxol
  # accesses directly. Callers may pass either :id or :key for the column identifier; both
  # forms are normalised so Raxol's create_cells/7 (which reads column.id) finds the field.
  defp normalize_column(col) when is_map(col) do
    col
    |> then(fn c ->
      # Accept :key as an alias for :id (plan spec uses %{key: :name, label: "Name"})
      case {Map.get(c, :id), Map.get(c, :key)} do
        {nil, key} when not is_nil(key) -> Map.put(c, :id, key)
        _ -> c
      end
    end)
    |> Map.put_new(:align, :left)
    |> Map.put_new(:width, 20)
    |> Map.put_new(:format, nil)
  end

  defp resolve_columns(columns, width) when is_integer(width) and width > 0 do
    column_count = length(columns)
    data_budget = max(width - column_count, column_count * @min_column_width)
    widths = resolve_widths(columns, data_budget)

    columns
    |> Enum.zip(widths)
    |> Enum.map(fn {column, width} ->
      column
      |> Map.put(:width, width)
      |> Map.update!(:label, &format_header(&1, width))
      |> wrap_formatter(width)
    end)
  end

  defp resolve_columns(columns, _width), do: columns

  defp resolve_widths(columns, data_budget) do
    fixed_width = fixed_width(columns)

    if fixed_width > data_budget do
      compact_widths(columns, data_budget)
    else
      distribute_flexible_widths(columns, data_budget - fixed_width)
    end
  end

  defp fixed_width(columns) do
    Enum.reduce(columns, 0, fn
      %{width: width}, total when is_integer(width) -> total + max(width, @min_column_width)
      _column, total -> total
    end)
  end

  defp compact_widths(columns, data_budget) do
    column_count = length(columns)
    base = div(data_budget, column_count)
    extra = rem(data_budget, column_count)

    columns
    |> Enum.with_index()
    |> Enum.map(fn {_column, index} ->
      max(base + if(index < extra, do: 1, else: 0), @min_column_width)
    end)
  end

  defp distribute_flexible_widths(columns, remaining_width) do
    flexible = Enum.reject(columns, &integer_width?/1)
    flexible_count = length(flexible)
    ratio_total = Enum.reduce(flexible, 0, &(&2 + ratio_weight(&1)))
    minimum_flexible = flexible_count * @min_column_width
    flexible_extra = max(remaining_width - minimum_flexible, 0)

    columns
    |> Enum.map(fn
      %{width: width} when is_integer(width) ->
        max(width, @min_column_width)

      column ->
        @min_column_width + div(flexible_extra * ratio_weight(column), max(ratio_total, 1))
    end)
    |> distribute_remainder(remaining_width + fixed_width(columns))
  end

  defp distribute_remainder(widths, data_budget) do
    remainder = data_budget - Enum.sum(widths)

    widths
    |> Enum.with_index()
    |> Enum.map(fn {width, index} ->
      width + if(index < remainder, do: 1, else: 0)
    end)
  end

  defp integer_width?(%{width: width}), do: is_integer(width)

  defp ratio_weight(%{width: {:ratio, weight}}) when is_integer(weight) and weight > 0, do: weight
  defp ratio_weight(_column), do: 1

  defp wrap_formatter(%{format: nil} = column, _width), do: column

  defp wrap_formatter(%{format: formatter} = column, width) when is_function(formatter, 1) do
    Map.put(column, :format, fn value ->
      value
      |> formatter.()
      |> TextWidth.truncate(width)
    end)
  end

  defp format_header(label, width) do
    label
    |> TextWidth.truncate(width)
    |> TextWidth.pad_trailing(width)
    |> Kernel.<>(" ")
  end

  defp normalize_rows(rows, _columns, width) when not is_integer(width) or width <= 0, do: rows

  defp normalize_rows(rows, columns, _width) do
    Enum.map(rows, fn row ->
      Enum.reduce(columns, row, fn
        %{id: id, width: width, format: nil}, acc ->
          Map.update(acc, id, "", &TextWidth.truncate(to_string(&1), width))

        _column, acc ->
          acc
      end)
    end)
  end
end
