defmodule Foglet.TUI.Screens.Account.SSHKeysState do
  @moduledoc """
  Screen-local state for the Account SSH KEYS tab.

  This state is pure UI state. Persistence, ownership, and validation remain
  inside `Foglet.Accounts`.
  """

  @type focus :: :label | :public_key
  @type mode :: :list | :add

  @type t :: %__MODULE__{
          items: [map()] | nil,
          selected_index: non_neg_integer(),
          form: %{label: String.t(), public_key: String.t()},
          focus: focus(),
          mode: mode(),
          errors: map(),
          status_message: String.t() | nil
        }

  defstruct items: nil,
            selected_index: 0,
            form: %{label: "", public_key: ""},
            focus: :label,
            mode: :list,
            errors: %{},
            status_message: nil

  @spec new() :: t()
  def new, do: %__MODULE__{}

  @spec loaded(t(), [map()]) :: t()
  def loaded(%__MODULE__{} = state, items) when is_list(items) do
    %{state | items: items, selected_index: clamp_index(state.selected_index, items), errors: %{}}
  end

  @spec with_error(t(), String.t() | map()) :: t()
  def with_error(%__MODULE__{} = state, error) when is_binary(error) do
    %{state | errors: %{general: error}, status_message: nil}
  end

  def with_error(%__MODULE__{} = state, errors) when is_map(errors) do
    %{state | errors: errors, status_message: nil}
  end

  @spec with_status(t(), String.t()) :: t()
  def with_status(%__MODULE__{} = state, message) when is_binary(message) do
    %{state | status_message: message, errors: %{}}
  end

  @spec start_add(t()) :: t()
  def start_add(%__MODULE__{} = state) do
    %{
      state
      | mode: :add,
        form: %{label: "", public_key: ""},
        focus: :label,
        errors: %{},
        status_message: nil
    }
  end

  @spec cancel_add(t()) :: t()
  def cancel_add(%__MODULE__{} = state) do
    %{state | mode: :list, form: %{label: "", public_key: ""}, focus: :label, errors: %{}}
  end

  @spec toggle_focus(t()) :: t()
  def toggle_focus(%__MODULE__{focus: :label} = state), do: %{state | focus: :public_key}
  def toggle_focus(%__MODULE__{} = state), do: %{state | focus: :label}

  @spec put_focused_value(t(), String.t()) :: t()
  def put_focused_value(%__MODULE__{} = state, value) when is_binary(value) do
    put_in(state.form[state.focus], value)
  end

  @spec append_focused(t(), String.t()) :: t()
  def append_focused(%__MODULE__{} = state, char) when is_binary(char) do
    current = Map.get(state.form, state.focus, "")
    put_focused_value(state, current <> char)
  end

  @spec backspace_focused(t()) :: t()
  def backspace_focused(%__MODULE__{} = state) do
    current = Map.get(state.form, state.focus, "")
    put_focused_value(state, String.slice(current, 0, max(String.length(current) - 1, 0)))
  end

  @spec select_next(t()) :: t()
  def select_next(%__MODULE__{items: items} = state) when is_list(items) do
    %{state | selected_index: clamp_index(state.selected_index + 1, items)}
  end

  def select_next(%__MODULE__{} = state), do: state

  @spec select_prev(t()) :: t()
  def select_prev(%__MODULE__{items: items} = state) when is_list(items) do
    %{state | selected_index: clamp_index(state.selected_index - 1, items)}
  end

  def select_prev(%__MODULE__{} = state), do: state

  defp clamp_index(_index, []), do: 0

  defp clamp_index(index, items) when is_integer(index) do
    index |> max(0) |> min(length(items) - 1)
  end

  defp clamp_index(_index, _items), do: 0
end
