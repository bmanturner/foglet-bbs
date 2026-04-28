defmodule Foglet.TUI.Screens.MainMenu.State do
  @moduledoc """
  Screen-local state for the authenticated Main Menu.

  MainMenu owns oneliner rows, selection, pending hide targets, and local
  create/hide/load lifecycle errors through `init/1`, `update/3`, and
  `render/2` (Phase 35 D-11/D-13). `Foglet.TUI.App` remains only the
  runtime/effect interpreter; it does not own MainMenu oneliner state.

  Fields:
    * `recent_oneliners` — loaded rows rendered in the home panel.
    * `selected_oneliner_index` — row selected for keyboard navigation/hide.
    * `pending_hide_oneliner_id` — target carried from hide request to submit.
    * `oneliner_status` — load/create/hide lifecycle state.
    * `oneliner_errors` — reducer-visible form and task errors.
  """

  alias Foglet.TUI.Context

  @type errors :: %{optional(atom()) => String.t()}

  @type t :: %__MODULE__{
          recent_oneliners: list(),
          selected_oneliner_index: non_neg_integer(),
          pending_hide_oneliner_id: String.t() | nil,
          oneliner_status: :idle | :loading | :submitting | :hiding | {:error, term()},
          oneliner_errors: errors()
        }

  defstruct recent_oneliners: [],
            selected_oneliner_index: 0,
            pending_hide_oneliner_id: nil,
            oneliner_status: :idle,
            oneliner_errors: %{}

  @doc "Builds the default MainMenu state from screen context."
  @spec new(Context.t() | map() | nil) :: t()
  def new(_context \\ nil), do: %__MODULE__{}

  @doc "Stores loaded oneliner entries and clamps the selected row."
  @spec from_entries(t(), list()) :: t()
  def from_entries(%__MODULE__{} = state, entries) when is_list(entries) do
    %{state | recent_oneliners: entries, oneliner_status: :idle}
    |> clamp_selection()
  end

  @doc "Moves selection by delta while staying inside loaded rows."
  @spec select_delta(t(), integer()) :: t()
  def select_delta(%__MODULE__{} = state, delta) when is_integer(delta) do
    select_index(state, state.selected_oneliner_index + delta)
  end

  @doc "Selects a specific row index, clamped to the loaded row range."
  @spec select_index(t(), integer() | nil) :: t()
  def select_index(%__MODULE__{} = state, index) when is_integer(index) do
    %{state | selected_oneliner_index: clamp(index, state.recent_oneliners)}
  end

  def select_index(%__MODULE__{} = state, _index), do: select_index(state, 0)

  @doc "Stores the oneliner id being hidden by a modal submit."
  @spec set_pending_hide(t(), String.t() | nil) :: t()
  def set_pending_hide(%__MODULE__{} = state, id), do: %{state | pending_hide_oneliner_id: id}

  @doc "Clears pending hide target state."
  @spec clear_pending_hide(t()) :: t()
  def clear_pending_hide(%__MODULE__{} = state), do: %{state | pending_hide_oneliner_id: nil}

  @doc "Stores reducer-visible form or lifecycle errors."
  @spec put_errors(t(), errors()) :: t()
  def put_errors(%__MODULE__{} = state, errors) when is_map(errors) do
    %{state | oneliner_errors: errors, oneliner_status: {:error, errors}}
  end

  @doc "Clears reducer-visible form or lifecycle errors."
  @spec clear_errors(t()) :: t()
  def clear_errors(%__MODULE__{} = state), do: %{state | oneliner_errors: %{}}

  @doc "Clamps the selected row against the current oneliner list."
  @spec clamp_selection(t()) :: t()
  def clamp_selection(%__MODULE__{} = state) do
    %{
      state
      | selected_oneliner_index: clamp(state.selected_oneliner_index, state.recent_oneliners)
    }
  end

  defp clamp(_index, []), do: 0

  defp clamp(index, entries) when is_integer(index) do
    index
    |> max(0)
    |> min(length(entries) - 1)
  end

  defp clamp(_index, entries), do: clamp(0, entries)
end
