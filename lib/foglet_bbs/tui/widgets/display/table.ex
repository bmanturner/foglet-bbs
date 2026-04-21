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
  alias Foglet.TUI.Theme
  alias Raxol.UI.Components.Table, as: RaxolTable

  @default_page_size 10

  @type action ::
          {:row_selected, map()}
          | {:sort_changed, atom()}
          | {:filter_changed, String.t()}
          | nil

  defstruct [:raxol_state, :columns, :sortable, :filterable, last_action: nil]

  @type t :: %__MODULE__{
          raxol_state: map(),
          columns: list(map()),
          sortable: boolean(),
          filterable: boolean(),
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
  """
  @spec init(keyword()) :: t()
  def init(opts) when is_list(opts) do
    columns = Keyword.fetch!(opts, :columns) |> Enum.map(&normalize_column/1)
    rows = Keyword.get(opts, :rows, Keyword.get(opts, :data, []))
    sortable = Keyword.get(opts, :sortable, false)
    filterable = Keyword.get(opts, :filterable, false)
    page_size = Keyword.get(opts, :page_size, @default_page_size)

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
    # Initialize selected_row to 0 so down-arrow arithmetic works
    raxol_state = Map.put(raxol_state, :selected_row, 0)

    %__MODULE__{
      raxol_state: raxol_state,
      columns: columns,
      sortable: sortable,
      filterable: filterable,
      last_action: nil
    }
  end

  @spec handle_event(map(), t()) :: {t(), action()}
  def handle_event(event, %__MODULE__{raxol_state: rs} = st) do
    raxol_event = translate_event(event)
    result = RaxolTable.handle_event(raxol_event, rs, %{})

    new_rs =
      case result do
        {:ok, new_state} -> new_state
        {new_state, _cmds} -> new_state
        _ -> rs
      end

    action = derive_action(rs, new_rs, event)
    {%{st | raxol_state: new_rs, last_action: action}, action}
  end

  @spec render(t(), keyword()) :: any()
  def render(%__MODULE__{raxol_state: rs}, opts) do
    %Theme{} = theme = Keyword.fetch!(opts, :theme)
    rs_with_theme = %{rs | theme: build_table_theme(theme)}

    box style: %{border_fg: theme.border.fg, padding: 0} do
      RaxolTable.render(rs_with_theme, %{})
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
end
