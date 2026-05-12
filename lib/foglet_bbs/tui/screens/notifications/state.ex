defmodule Foglet.TUI.Screens.Notifications.State do
  @moduledoc """
  Screen-local state for the routed notifications inbox.
  """

  @type row :: map()
  @type t :: %__MODULE__{
          rows: [row()],
          selected_index: non_neg_integer(),
          scroll_offset: non_neg_integer(),
          status: :idle | :loading | :loaded | :error | :marking_read | :marking_all_read,
          last_error: String.t() | nil,
          pending_created_ids: %{optional(term()) => true}
        }

  defstruct rows: [],
            selected_index: 0,
            scroll_offset: 0,
            status: :idle,
            last_error: nil,
            pending_created_ids: %{}

  def new, do: %__MODULE__{}

  @spec from_rows(t(), [row()]) :: t()
  def from_rows(%__MODULE__{} = state, rows) when is_list(rows) do
    loaded_ids = row_ids(rows)
    rows = preserve_pending_created_rows(state, rows)
    selected_id = selected_row_id(state)
    selected_index = find_selected_index(rows, selected_id)
    pending_created_ids = Map.drop(state.pending_created_ids, loaded_ids)

    %{
      state
      | rows: rows,
        selected_index: selected_index,
        status: :loaded,
        last_error: nil,
        pending_created_ids: pending_created_ids
    }
    |> clamp_selection()
    |> ensure_selected_visible()
  end

  @spec prepend_or_replace(t(), row()) :: t()
  def prepend_or_replace(%__MODULE__{} = state, %{} = row) do
    row_id = row_id(row)

    rows =
      state.rows
      |> Enum.reject(&(not is_nil(row_id) and row_id(&1) == row_id))
      |> then(&[row | &1])

    pending_created_ids =
      if is_nil(row_id),
        do: state.pending_created_ids,
        else: Map.put(state.pending_created_ids, row_id, true)

    %{
      state
      | rows: rows,
        selected_index: 0,
        last_error: nil,
        pending_created_ids: pending_created_ids
    }
    |> clamp_selection()
    |> ensure_selected_visible()
  end

  @spec set_error(t(), term(), String.t()) :: t()
  def set_error(%__MODULE__{} = state, reason, prefix) do
    %{state | status: :error, last_error: "#{prefix}: #{inspect(reason)}"}
  end

  @spec select_delta(t(), integer(), pos_integer()) :: t()
  def select_delta(%__MODULE__{} = state, delta, window_size) when is_integer(delta) do
    max_index = max(length(state.rows) - 1, 0)
    selected_index = (state.selected_index + delta) |> max(0) |> min(max_index)

    %{state | selected_index: selected_index}
    |> ensure_selected_visible(window_size)
  end

  @spec selected_row(t()) :: row() | nil
  def selected_row(%__MODULE__{rows: rows, selected_index: index}), do: Enum.at(rows, index)

  @spec visible_rows(t(), pos_integer()) :: [{row(), non_neg_integer()}]
  def visible_rows(%__MODULE__{} = state, window_size) do
    state.rows
    |> Enum.with_index()
    |> Enum.drop(state.scroll_offset)
    |> Enum.take(window_size)
  end

  @spec unread_count(t()) :: non_neg_integer()
  def unread_count(%__MODULE__{} = state) do
    Enum.count(state.rows, &is_nil(Map.get(&1, :read_at) || Map.get(&1, "read_at")))
  end

  @spec clamp_selection(t()) :: t()
  def clamp_selection(%__MODULE__{} = state) do
    max_index = max(length(state.rows) - 1, 0)
    %{state | selected_index: state.selected_index |> max(0) |> min(max_index)}
  end

  @spec ensure_selected_visible(t(), pos_integer()) :: t()
  def ensure_selected_visible(state, window_size \\ 10)

  def ensure_selected_visible(%__MODULE__{} = state, window_size) do
    window_size = max(window_size, 1)

    scroll_offset =
      cond do
        state.selected_index < state.scroll_offset ->
          state.selected_index

        state.selected_index >= state.scroll_offset + window_size ->
          state.selected_index - window_size + 1

        true ->
          state.scroll_offset
      end

    max_offset = max(length(state.rows) - window_size, 0)
    %{state | scroll_offset: scroll_offset |> max(0) |> min(max_offset)}
  end

  defp selected_row_id(%__MODULE__{} = state) do
    state
    |> selected_row()
    |> row_id()
  end

  defp find_selected_index(_rows, nil), do: 0

  defp find_selected_index(rows, selected_id) do
    Enum.find_index(rows, &(row_id(&1) == selected_id)) || 0
  end

  defp preserve_pending_created_rows(%__MODULE__{} = state, rows) do
    loaded_ids = row_ids(rows)

    pending_rows =
      state.rows
      |> Enum.filter(fn row ->
        row_id = row_id(row)

        not is_nil(row_id) and Map.has_key?(state.pending_created_ids, row_id) and
          row_id not in loaded_ids and unread?(row)
      end)

    pending_rows ++ rows
  end

  defp row_ids(rows) do
    rows
    |> Enum.map(&row_id/1)
    |> Enum.reject(&is_nil/1)
  end

  defp unread?(%{} = row), do: is_nil(Map.get(row, :read_at) || Map.get(row, "read_at"))

  defp row_id(%{} = row), do: Map.get(row, :id) || Map.get(row, "id")
  defp row_id(_row), do: nil
end
