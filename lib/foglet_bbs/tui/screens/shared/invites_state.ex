defmodule Foglet.TUI.Screens.Shared.InvitesState do
  @moduledoc """
  Live INVITES state shared by Account, Moderation, and Sysop shells.

  `items: nil` means loading or not-yet-loaded. A list contains status maps
  returned by `Foglet.Accounts.list_invites/1`; the TUI does not query or shape
  invite persistence directly.
  """

  @type invite_status :: map()

  @type t :: %__MODULE__{
          items: nil | [invite_status()],
          selected_index: non_neg_integer(),
          loading?: boolean(),
          last_generated_code: String.t() | nil,
          error: String.t() | nil,
          frame: non_neg_integer()
        }

  defstruct items: nil,
            selected_index: 0,
            loading?: false,
            last_generated_code: nil,
            error: nil,
            frame: 0

  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    items = Keyword.get(opts, :items, nil)
    validate_items!(items)

    %__MODULE__{
      items: items,
      selected_index: Keyword.get(opts, :selected_index, 0) |> normalize_index(items),
      loading?: Keyword.get(opts, :loading?, false),
      last_generated_code: Keyword.get(opts, :last_generated_code),
      error: Keyword.get(opts, :error),
      frame: Keyword.get(opts, :frame, 0)
    }
  end

  @spec loaded(t(), [invite_status()]) :: t()
  def loaded(%__MODULE__{} = state, items) when is_list(items) do
    %__MODULE__{
      state
      | items: items,
        loading?: false,
        error: nil,
        selected_index: normalize_index(state.selected_index, items)
    }
  end

  @spec loading(t()) :: t()
  def loading(%__MODULE__{} = state) do
    %__MODULE__{state | loading?: true, error: nil}
  end

  @spec with_error(t(), String.t()) :: t()
  def with_error(%__MODULE__{} = state, error) when is_binary(error) do
    %__MODULE__{state | loading?: false, error: error}
  end

  @spec with_last_generated(t(), String.t()) :: t()
  def with_last_generated(%__MODULE__{} = state, code) when is_binary(code) do
    %__MODULE__{state | last_generated_code: code}
  end

  @spec select_next(t()) :: t()
  def select_next(%__MODULE__{items: items, selected_index: index} = state) do
    %__MODULE__{state | selected_index: normalize_index(index + 1, items)}
  end

  @spec select_prev(t()) :: t()
  def select_prev(%__MODULE__{items: items, selected_index: index} = state) do
    %__MODULE__{state | selected_index: normalize_index(index - 1, items)}
  end

  defp validate_items!(nil), do: :ok
  defp validate_items!(items) when is_list(items), do: :ok

  defp validate_items!(other) do
    raise ArgumentError,
          "Foglet.TUI.Screens.Shared.InvitesState :items must be a list or nil; got #{inspect(other)}"
  end

  defp normalize_index(_index, nil), do: 0
  defp normalize_index(_index, []), do: 0

  defp normalize_index(index, items) when is_integer(index) and is_list(items) do
    index |> max(0) |> min(length(items) - 1)
  end

  defp normalize_index(_index, _items), do: 0
end
