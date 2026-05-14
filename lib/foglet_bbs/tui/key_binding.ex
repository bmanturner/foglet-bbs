defmodule Foglet.TUI.KeyBinding do
  @moduledoc """
  Canonical key binding predicates for non-text-entry TUI surfaces.

  This module wraps `Foglet.TUI.ScrollKeys` so existing movement conventions
  stay centralized:

    * `↑` / `k` => previous/up
    * `↓` / `j` => next/down

  Text-input, composer-body, and search/filter contexts must not call the
  character-key movement helpers for raw `j`/`k` events. In those contexts,
  characters remain typed input unless the focused widget explicitly consumes
  them as commands.

  Modifier-bearing character keys are not treated as plain movement, submit,
  cancel, or help bindings. Full-screen composers may opt into the documented
  terminal fallback with `cancel?(event, composer?: true)`, which accepts
  `Ctrl+C` as the same action as `Esc`.
  """

  alias Foglet.TUI.ScrollKeys

  @doc "Returns true for canonical up/previous movement."
  @spec scroll_up?(map()) :: boolean()
  def scroll_up?(event), do: plain_event?(event) and ScrollKeys.vertical_direction(event) == :up

  @doc "Returns true for canonical down/next movement."
  @spec scroll_down?(map()) :: boolean()
  def scroll_down?(event),
    do: plain_event?(event) and ScrollKeys.vertical_direction(event) == :down

  @doc "Returns -1, +1, or nil for canonical vertical movement."
  @spec vertical_delta(map()) :: -1 | 1 | nil
  def vertical_delta(event) do
    cond do
      scroll_up?(event) -> -1
      scroll_down?(event) -> 1
      true -> nil
    end
  end

  @doc "Returns true for PageUp key shapes."
  @spec page_up?(map()) :: boolean()
  def page_up?(event), do: plain_key?(event, [:page_up, :pageup])

  @doc "Returns true for PageDown key shapes."
  @spec page_down?(map()) :: boolean()
  def page_down?(event), do: plain_key?(event, [:page_down, :pagedown])

  @doc "Returns true for Home."
  @spec home?(map()) :: boolean()
  def home?(event), do: plain_key?(event, [:home])

  @doc "Returns true for End."
  @spec end?(map()) :: boolean()
  def end?(event), do: plain_key?(event, [:end])

  @doc "Returns true for unmodified Enter."
  @spec submit?(map()) :: boolean()
  def submit?(event), do: plain_key?(event, [:enter])

  @doc """
  Returns true for cancel.

  `Esc` is always cancel. `Ctrl+C` is accepted only when `composer?: true` is
  passed for full-screen composers that document the terminal fallback.
  """
  @spec cancel?(map(), keyword()) :: boolean()
  def cancel?(event, opts \\ [])

  def cancel?(%{key: :escape} = event, _opts), do: plain_event?(event)

  def cancel?(%{key: :char, char: "c", ctrl: true} = event, opts),
    do: Keyword.get(opts, :composer?, false) and no_non_control_modifiers?(event)

  def cancel?(_event, _opts), do: false

  @doc "Returns true for Help."
  @spec help?(map()) :: boolean()
  def help?(%{key: :char, char: "?"} = event), do: plain_event?(event)
  def help?(event), do: plain_key?(event, [:f1, :help])

  @doc "Canonical commandbar label for selectable or scrollable vertical movement."
  @spec commandbar_key() :: String.t()
  def commandbar_key, do: ScrollKeys.commandbar_key()

  defp plain_key?(%{key: key} = event, keys) when is_list(keys),
    do: key in keys and plain_event?(event)

  defp plain_key?(_event, _keys), do: false

  defp plain_event?(event) when is_map(event) do
    Enum.all?(
      [:ctrl, :control, :alt, :meta, :shift],
      &(Map.get(event, &1, false) in [false, nil])
    )
  end

  defp plain_event?(_event), do: false

  defp no_non_control_modifiers?(event) do
    Enum.all?([:alt, :meta, :shift], &(Map.get(event, &1, false) in [false, nil]))
  end
end
