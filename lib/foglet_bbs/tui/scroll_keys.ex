defmodule Foglet.TUI.ScrollKeys do
  @moduledoc """
  Shared vertical movement convention for scrollable/selectable TUI surfaces.

  Foglet's user-facing command bars advertise arrow keys only so the footer stays
  calm and compact. When a surface is not accepting free text, the same movement
  should also accept `j`/`k` as discoverable-but-unadvertised fallbacks:

    * `↑` / `k` => up / previous (`-1`)
    * `↓` / `j` => down / next (`+1`)

  Text-input and search/filter contexts should not call these helpers for raw
  character events, because typed `j` and `k` must remain input.
  """

  @type direction :: :up | :down

  @doc "Returns the vertical movement direction for arrow or j/k fallback keys."
  @spec vertical_direction(map()) :: direction() | nil
  def vertical_direction(%{key: :up}), do: :up
  def vertical_direction(%{key: :down}), do: :down
  def vertical_direction(%{key: :char, char: "k"}), do: :up
  def vertical_direction(%{key: :char, char: "j"}), do: :down
  def vertical_direction(_event), do: nil

  @doc "Returns -1 for up/previous, +1 for down/next, or nil for non-movement keys."
  @spec vertical_delta(map()) :: -1 | 1 | nil
  def vertical_delta(event) do
    case vertical_direction(event) do
      :up -> -1
      :down -> 1
      nil -> nil
    end
  end

  @doc "Returns true when the event is an unadvertised j/k vertical fallback."
  @spec jk_fallback?(map()) :: boolean()
  def jk_fallback?(%{key: :char, char: char}) when char in ["j", "k"], do: true
  def jk_fallback?(_event), do: false

  @doc "Canonical commandbar label for selectable or scrollable vertical movement."
  @spec commandbar_key() :: String.t()
  def commandbar_key, do: "↑/↓"
end
