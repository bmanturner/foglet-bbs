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

      %{
        id: atom(),
        label: String.t(),
        width: integer() | :auto,
        grow: non_neg_integer(),
        priority: integer(),
        demand: :content | :header | :minimum | integer()
      }

  ## Actions returned from `handle_event/2`

      {:row_selected, row}          — Enter on a focused row
      {:sort_changed, column_key}   — sort-cycle key pressed on a sortable column
      {:filter_changed, term}       — filter input changed (searchable tables)
      nil                           — navigation key, no semantic action
  """

  import Raxol.Core.Renderer.View
  alias Foglet.TUI.KeyBinding
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
    * `:columns`    — list of column specs (required). Each: `%{id: atom(), label: String.t(), width: integer() | :auto, grow: non_neg_integer(), priority: integer(), demand: :content | :header | :minimum | integer()}`
    * `:rows`       — list of row maps keyed by column `:id` (alias for `:data`)
    * `:sortable`   — boolean, default `false`
    * `:filterable` — boolean, default `false`
    * `:page_size`  — integer, default `#{@default_page_size}`
    * `:width`      — drawable content width available inside the caller container
  """
  @spec init(keyword()) :: t()
  def init(opts) when is_list(opts) do
    available_width = Keyword.get(opts, :width)
    rows = Keyword.get(opts, :rows, Keyword.get(opts, :data, []))

    columns =
      opts
      |> Keyword.fetch!(:columns)
      |> Enum.map(&normalize_column/1)
      |> resolve_columns(available_width, rows)

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
      navigation_event = normalize_navigation_event(event, st)
      raxol_event = translate_event(navigation_event, st)
      {:ok, new_rs} = RaxolTable.handle_event(raxol_event, rs, %{})

      action = derive_action(rs, new_rs, navigation_event)
      {%{st | raxol_state: new_rs, last_action: action}, action}
    end
  end

  @spec render(t(), keyword()) :: any()
  def render(%__MODULE__{raxol_state: rs, available_width: available_width}, opts) do
    %Theme{} = theme = Keyword.fetch!(opts, :theme)
    available_height = Keyword.get(opts, :height)
    rs_with_theme = prepare_render_state(rs, theme)

    box style: %{border_fg: theme.border.fg, padding: 0} do
      RaxolTable.render(rs_with_theme, %{
        available_width: available_width,
        available_height: available_height
      })
    end
  end

  # --- private ---

  # Translate unadvertised j/k fallbacks to vertical arrows only when the table
  # is not accepting typed filter/search characters. Filterable tables keep j/k
  # as text input so search terms remain typeable.
  defp normalize_navigation_event(%{key: :char, char: _} = event, %__MODULE__{filterable: true}),
    do: event

  defp normalize_navigation_event(%{key: :char, char: "j"}, %__MODULE__{}), do: %{key: :down}
  defp normalize_navigation_event(%{key: :char, char: "k"}, %__MODULE__{}), do: %{key: :up}
  defp normalize_navigation_event(event, %__MODULE__{}), do: event

  # Translate Foglet key events to Raxol.UI.Components.Table event tuples.
  # Searchable tables are text-input surfaces, so raw j/k chars must remain
  # filter characters instead of going through the global movement fallback.
  defp translate_event(%{key: :char} = event, %__MODULE__{filterable: true}),
    do: translate_non_vertical_event(event)

  defp translate_event(event, %__MODULE__{}) do
    case KeyBinding.vertical_delta(event) do
      1 -> {:key, {:arrow_down, nil}}
      -1 -> {:key, {:arrow_up, nil}}
      nil -> translate_non_vertical_event(event)
    end
  end

  defp translate_non_vertical_event(%{key: :left}), do: {:key, {:arrow_left, nil}}
  defp translate_non_vertical_event(%{key: :right}), do: {:key, {:arrow_right, nil}}
  defp translate_non_vertical_event(%{key: :enter}), do: {:key, {:enter, nil}}
  defp translate_non_vertical_event(%{key: :escape}), do: {:key, {:escape, nil}}
  defp translate_non_vertical_event(%{key: :page_up}), do: {:key, {:page_up, nil}}
  defp translate_non_vertical_event(%{key: :page_down}), do: {:key, {:page_down, nil}}
  defp translate_non_vertical_event(%{key: :home}), do: {:key, {:home, nil}}
  defp translate_non_vertical_event(%{key: :end}), do: {:key, {:end, nil}}

  defp translate_non_vertical_event(%{key: :char, char: c}), do: {:key, {:char, c}}

  defp translate_non_vertical_event(_), do: {:key, {:unknown, nil}}

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

  defp prepare_render_state(rs, %Theme{} = theme) do
    # Raxol renders sortable headers as buttons. Buttons paint with their own
    # horizontal chrome/padding, which shifts header text away from the row cell
    # starts even when the column widths are correct. Keep sorting state/data in
    # the Raxol state, but render headers as plain text so headers and rows both
    # follow the same width + separator contract.
    rs
    |> Map.put(:theme, build_table_theme(theme))
    |> Map.update!(:options, &Map.put(&1, :sortable, false))
  end

  defp build_table_theme(%Theme{} = t) do
    %{
      box: %{border_fg: t.border.fg},
      header: %{fg: t.title.fg, style: [:bold]},
      row: %{fg: t.primary.fg},
      selected_row: %{fg: t.selected.fg, bg: t.selected.bg}
    }
  end

  # Ensure each column has the required :id, :align, :width, :grow, and :format fields that Raxol
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
    |> Map.put_new(:grow, 0)
    |> Map.put_new(:priority, 0)
    |> Map.put_new(:demand, :content)
    |> Map.put_new(:format, nil)
  end

  defp resolve_columns(columns, width, rows) when is_integer(width) and width > 0 do
    column_count = length(columns)
    data_budget = max(width - column_count, column_count * @min_column_width)
    widths = resolve_widths(columns, rows, data_budget)

    columns
    |> Enum.zip(widths)
    |> Enum.map(fn {column, width} ->
      column
      |> Map.put(:width, width)
      |> Map.update!(:label, &format_header(&1, width))
      |> wrap_formatter(width)
    end)
  end

  defp resolve_columns(columns, _width, _rows), do: columns

  defp resolve_widths(columns, rows, data_budget) do
    minimums = Enum.map(columns, &minimum_width/1)
    demands = Enum.map(columns, &demand_width(&1, rows))
    minimum_total = Enum.sum(minimums)
    demand_total = Enum.sum(demands)

    cond do
      minimum_total > data_budget ->
        compact_widths(columns, minimums, data_budget)

      demand_total <= data_budget ->
        distribute_flexible_widths(columns, demands, data_budget - demand_total)

      true ->
        allocate_priority_widths(columns, minimums, demands, data_budget - minimum_total)
    end
  end

  defp compact_widths(columns, minimums, data_budget) do
    excess = Enum.sum(minimums) - data_budget
    sacrifice_width(minimums, columns, excess)
  end

  defp allocate_priority_widths(columns, widths, demands, remaining_width) do
    needs =
      Enum.zip(widths, demands)
      |> Enum.map(fn {width, demand} -> max(demand - width, 0) end)

    satisfy_demands(widths, columns, needs, remaining_width)
  end

  defp distribute_flexible_widths(columns, widths, remaining_width) do
    growth_weights = Enum.map(columns, &grow_weight/1)

    active_weights =
      if Enum.sum(growth_weights) > 0, do: growth_weights, else: Enum.map(widths, fn _ -> 1 end)

    weight_total = Enum.sum(active_weights)

    additions =
      Enum.map(active_weights, fn weight ->
        div(remaining_width * weight, weight_total)
      end)

    remainder = remaining_width - Enum.sum(additions)
    priority_indexes = remainder_priority(active_weights)

    widths
    |> Enum.zip(additions)
    |> Enum.map(fn {width, addition} -> width + addition end)
    |> distribute_weighted_remainder(remainder, priority_indexes)
  end

  defp distribute_weighted_remainder(widths, remainder, _priority_indexes) when remainder <= 0,
    do: widths

  defp distribute_weighted_remainder(widths, remainder, priority_indexes) do
    remainder_indexes = Enum.take(Stream.cycle(priority_indexes), remainder)

    widths
    |> Enum.with_index()
    |> Enum.map(fn {width, index} ->
      width + Enum.count(remainder_indexes, &(&1 == index))
    end)
  end

  defp sacrifice_width(widths, _columns, excess) when excess <= 0, do: widths

  defp sacrifice_width(widths, columns, excess) do
    indexes = sacrifice_priority(columns, widths)

    case Enum.find(indexes, fn index -> Enum.at(widths, index) > @min_column_width end) do
      nil ->
        widths

      index ->
        widths
        |> List.update_at(index, &(&1 - 1))
        |> sacrifice_width(columns, excess - 1)
    end
  end

  defp satisfy_demands(widths, _columns, _needs, remaining_width) when remaining_width <= 0,
    do: widths

  defp satisfy_demands(widths, columns, needs, remaining_width) do
    indexes = fulfillment_priority(columns, needs)

    case Enum.find(indexes, fn index -> Enum.at(needs, index) > 0 end) do
      nil ->
        widths

      index ->
        widths = List.update_at(widths, index, &(&1 + 1))
        needs = List.update_at(needs, index, &max(&1 - 1, 0))
        satisfy_demands(widths, columns, needs, remaining_width - 1)
    end
  end

  defp minimum_width(%{width: width}) when is_integer(width), do: max(width, @min_column_width)
  defp minimum_width(_column), do: @min_column_width

  defp demand_width(column, rows) do
    minimum = minimum_width(column)
    header = TextWidth.display_width(Map.get(column, :label, ""))
    content = max_content_width(rows, column)

    case Map.get(column, :demand, :content) do
      :minimum -> minimum
      :header -> max(header, minimum)
      :content -> max(max(header, content), minimum)
      value when is_integer(value) -> max(value, minimum)
      _ -> max(max(header, content), minimum)
    end
  end

  defp max_content_width(rows, %{id: id, format: formatter}) when is_function(formatter, 1) do
    rows
    |> Enum.map(fn row ->
      row
      |> Map.get(id, "")
      |> formatter.()
      |> to_string()
      |> TextWidth.display_width()
    end)
    |> Enum.max(fn -> 0 end)
  end

  defp max_content_width(rows, %{id: id}) do
    rows
    |> Enum.map(fn row ->
      row
      |> Map.get(id, "")
      |> to_string()
      |> TextWidth.display_width()
    end)
    |> Enum.max(fn -> 0 end)
  end

  defp grow_weight(%{grow: grow}) when is_integer(grow) and grow > 0, do: grow

  defp grow_weight(%{width: {:ratio, weight}}) when is_integer(weight) and weight > 0,
    do: weight

  defp grow_weight(%{width: :auto}), do: 1
  defp grow_weight(_column), do: 0

  defp remainder_priority(weights) do
    weights
    |> Enum.with_index()
    |> Enum.sort_by(fn {weight, index} -> {-weight, index} end)
    |> Enum.map(fn {_weight, index} -> index end)
  end

  defp sacrifice_priority(columns, widths) do
    columns
    |> Enum.with_index()
    |> Enum.sort_by(fn {column, index} ->
      {column_priority(column), -Enum.at(widths, index), index}
    end)
    |> Enum.map(fn {_column, index} -> index end)
  end

  defp fulfillment_priority(columns, needs) do
    columns
    |> Enum.with_index()
    |> Enum.sort_by(fn {column, index} ->
      {-column_priority(column), -Enum.at(needs, index), -grow_weight(column), index}
    end)
    |> Enum.map(fn {_column, index} -> index end)
  end

  defp column_priority(%{priority: priority}) when is_integer(priority), do: priority
  defp column_priority(_column), do: 0

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
