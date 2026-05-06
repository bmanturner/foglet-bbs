defmodule Foglet.TUI.Screens.OnlineNow.State do
  @moduledoc """
  Screen-local state for the routed Online Now view.

  Modal-vs-screen choice: Online Now is a routed screen because the app has a
  single `state.modal` slot, no modal stack, and no generic selectable,
  scrollable list modal. A routed screen keeps selection/scroll state local and
  can open the existing public profile modal without awkward modal replacement
  semantics.
  """

  @type row :: map()
  @type t :: %__MODULE__{
          rows: [row()],
          selected_index: non_neg_integer(),
          scroll_offset: non_neg_integer(),
          status: :idle | :loading | :loaded | :error,
          last_error: String.t() | nil
        }

  defstruct rows: [], selected_index: 0, scroll_offset: 0, status: :idle, last_error: nil

  def new, do: %__MODULE__{}

  @spec from_rows(t(), [row()]) :: t()
  def from_rows(%__MODULE__{} = state, rows) when is_list(rows) do
    %{state | rows: rows, status: :loaded, last_error: nil}
    |> clamp_selection()
    |> ensure_selected_visible()
  end

  @spec set_error(t(), term()) :: t()
  def set_error(%__MODULE__{} = state, reason) do
    %{state | status: :error, last_error: "Unable to load online users: #{inspect(reason)}"}
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
end
