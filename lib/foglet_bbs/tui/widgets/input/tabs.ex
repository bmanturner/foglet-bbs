defmodule Foglet.TUI.Widgets.Input.Tabs do
  @moduledoc """
  Themed tab-bar widget (D-02, D-13, D-14).

  Stateless facade over `Raxol.UI.Components.Input.Tabs`. Supports
  Left/Right navigation, Home/End, and digit shortcuts 1–9.

  **Pitfall 6 (RESEARCH.md):** Digit shortcuts 1–9 are consumed
  unconditionally by the underlying Raxol component. D-15 places
  key-event routing with the parent screen — when a screen needs
  digit input for another purpose (e.g., port numbers), it must
  filter the event BEFORE forwarding to `handle_event/2`. The
  wrapper does not second-guess caller filtering.

  Honours:
    * D-07/D-09 — theme-routed colors only
    * D-13     — `theme:` keyword arg
    * D-14     — `init/1` + `handle_event/2` + `render/2` (no process)

  ## Contract

    * `init(opts)` — keyword list; options:
        * `:tabs`   list of string labels or `%{label: String.t()}` maps (required)
        * `:active` initial active index (default `0`)
    * `handle_event(event, state)` — `{new_state, action | nil}`
    * `render(state, theme: theme)` — view element tree

  ## Actions returned from `handle_event/2`
    {:tab_changed, new_index} — Left/Right/Home/End/1–9 caused index change
    nil                        — key consumed but index unchanged
  """

  import Raxol.Core.Renderer.View

  alias Foglet.TUI.Theme
  alias Raxol.UI.Components.Input.Tabs, as: RaxolTabs

  @default_active_indicator "▌"

  @type action :: {:tab_changed, non_neg_integer()} | nil

  defstruct [:raxol_state, last_action: nil]

  @type t :: %__MODULE__{raxol_state: map(), last_action: action()}

  @doc """
  Pure constructor.

  Options:
    * `:tabs`   — list of tab entries (required). Each entry may be a string
                  label, an atom (converted via `Atom.to_string/1`), or a
                  `%{label: String.t()}` map. Any other shape raises
                  `ArgumentError` with a helpful message.
    * `:active` — initial active index (default `0`)
  """
  @spec init(keyword()) :: t()
  def init(opts) when is_list(opts) do
    raw_tabs = Keyword.fetch!(opts, :tabs)
    normalized_tabs = Enum.map(raw_tabs, &normalize_tab/1)

    raxol_opts = [
      tabs: normalized_tabs,
      active_index: Keyword.get(opts, :active, 0),
      active_indicator: @default_active_indicator
    ]

    {:ok, raxol_state} = RaxolTabs.init(raxol_opts)
    %__MODULE__{raxol_state: raxol_state, last_action: nil}
  end

  @spec handle_event(map(), t()) :: {t(), action()}
  def handle_event(event, %__MODULE__{raxol_state: rs} = st) do
    raxol_event = %Raxol.Core.Events.Event{type: :key, data: event}
    {new_rs, _cmds} = RaxolTabs.handle_event(raxol_event, rs, %{})
    action = derive_action(rs, new_rs)
    {%{st | raxol_state: new_rs, last_action: action}, action}
  end

  @spec render(t(), keyword()) :: any()
  def render(%__MODULE__{raxol_state: rs}, opts) do
    %Theme{} = theme = Keyword.fetch!(opts, :theme)

    rs_with_theme = %{rs | theme: build_tabs_theme(theme)}

    box style: %{border_fg: theme.border.fg, padding: 0} do
      RaxolTabs.render(rs_with_theme, %{})
    end
  end

  # --- private ---

  defp normalize_tab(label) when is_binary(label), do: %{label: label}

  defp normalize_tab(label) when is_atom(label) and not is_nil(label),
    do: %{label: Atom.to_string(label)}

  defp normalize_tab(%{label: _} = tab), do: tab

  defp normalize_tab(other) do
    raise ArgumentError,
          "Foglet.TUI.Widgets.Input.Tabs :tabs entry must be a string, atom, " <>
            "or %{label: _}; got #{inspect(other)}"
  end

  defp derive_action(before_rs, after_rs) do
    before_idx = Map.get(before_rs, :active_index, 0)
    after_idx = Map.get(after_rs, :active_index, 0)

    if before_idx != after_idx, do: {:tab_changed, after_idx}, else: nil
  end

  defp build_tabs_theme(%Theme{} = t) do
    %{
      tab: %{fg: t.unselected.fg},
      active_tab: %{fg: t.selected.fg, style: [:bold]},
      border: %{fg: t.border.fg}
    }
  end
end
