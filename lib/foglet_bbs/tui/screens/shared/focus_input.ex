defmodule Foglet.TUI.Screens.Shared.FocusInput do
  @moduledoc """
  Helpers for screens that maintain a focused field and a map of
  TextInput-like widgets keyed by field name.

  Each caller provides a `mapper` function `field_atom -> map_key` to
  translate the focused field into the storage key for its widget.
  """

  @doc """
  Returns the currently focused input widget from `screen_state`.

  `mapper` translates the focused field atom to the storage key in `screen_state`.
  `default_field` is used when `:focused_field` is not set.
  """
  @spec get_focused(map(), (atom() -> atom()), atom()) :: any()
  def get_focused(screen_state, mapper, default_field) do
    focused = Map.get(screen_state, :focused_field, default_field)
    Map.get(screen_state, mapper.(focused))
  end

  @doc """
  Returns an updated `screen_state` with the currently focused input
  widget replaced by `new_input`.

  `mapper` translates the focused field atom to the storage key in `screen_state`.
  `default_field` is used when `:focused_field` is not set.
  """
  @spec update_focused(map(), any(), (atom() -> atom()), atom()) :: map()
  def update_focused(screen_state, new_input, mapper, default_field) do
    focused = Map.get(screen_state, :focused_field, default_field)
    Map.put(screen_state, mapper.(focused), new_input)
  end
end
