defmodule Foglet.TUI.Widgets.Input.Tabs do
  @moduledoc """
  Themed tab-bar widget (D-02, D-13, D-14).

  Stateful facade over `Raxol.UI.Components.Input.Tabs` event handling.
  Rendering is Foglet-owned so the default tab strip shape stays stable:

      ▌ Profile   Prefs   SSH Keys   Invites

  Supports Left/Right navigation, Home/End, and digit shortcuts 1–9.

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

  alias Foglet.TUI.Presentation
  alias Foglet.TUI.TextWidth
  alias Foglet.TUI.Theme
  alias Raxol.UI.Components.Input.Tabs, as: RaxolTabs

  @default_active_indicator "▌"
  @tab_gap "   "

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

    active_index =
      opts
      |> Keyword.get(:active, 0)
      |> clamp_active_index(normalized_tabs)

    raxol_opts = [
      tabs: normalized_tabs,
      active_index: active_index,
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
    width = Keyword.get(opts, :width)

    mappings = Presentation.theme_mappings().tabs

    row style: %{gap: 0} do
      rs
      |> Map.get(:tabs, [])
      |> Enum.with_index()
      |> clamp_tab_labels(Map.get(rs, :active_index, 0), width)
      |> Enum.map(&render_tab(&1, Map.get(rs, :active_index, 0), theme, mappings))
      |> Enum.intersperse([text(@tab_gap, fg: Map.fetch!(theme, mappings.border).fg)])
      |> List.flatten()
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

  # Clamp `:active` into the valid tab range. An out-of-range index would
  # render every tab as unselected because `render_tab/4` only marks
  # `idx == active_index`, leaving the screen with no visible active tab
  # until a navigation event corrects state. Clamping mirrors the defensive
  # behavior already used by `Foglet.TUI.Widgets.Input.RadioGroup` (WR-02).
  defp clamp_active_index(_idx, []), do: 0
  defp clamp_active_index(idx, _tabs) when idx < 0, do: 0
  defp clamp_active_index(idx, tabs), do: min(idx, length(tabs) - 1)

  defp derive_action(before_rs, after_rs) do
    before_idx = Map.get(before_rs, :active_index, 0)
    after_idx = Map.get(after_rs, :active_index, 0)

    if before_idx != after_idx, do: {:tab_changed, after_idx}, else: nil
  end

  defp clamp_tab_labels(indexed_tabs, _active_index, nil), do: indexed_tabs

  defp clamp_tab_labels(_indexed_tabs, _active_index, width)
       when not is_integer(width) or width <= 0,
       do: []

  defp clamp_tab_labels(indexed_tabs, active_index, width) do
    indexed_tabs
    |> Enum.map(fn {tab, idx} ->
      label = tab |> Map.fetch!(:label) |> to_string()
      min_width = if idx == active_index, do: 1, else: 0
      %{tab: %{tab | label: label}, idx: idx, min_width: min_width}
    end)
    |> shrink_to_width(active_index, width)
    |> Enum.map(fn %{tab: tab, idx: idx} -> {tab, idx} end)
  end

  defp shrink_to_width(entries, active_index, width) do
    if rendered_width(entries, active_index) <= width do
      entries
    else
      entries
      |> shrink_inactive_labels(active_index, width)
      |> shrink_active_label(active_index, width)
    end
  end

  defp shrink_inactive_labels(entries, active_index, width) do
    shrunk =
      Enum.reduce_while(entries, entries, fn %{idx: idx}, acc ->
        if rendered_width(acc, active_index) <= width do
          {:halt, acc}
        else
          {:cont, shrink_entry(acc, idx, 0)}
        end
      end)

    if rendered_width(shrunk, active_index) <= width or shrunk == entries do
      shrunk
    else
      shrink_inactive_labels(shrunk, active_index, width)
    end
  end

  defp shrink_active_label(entries, active_index, width) do
    if rendered_width(entries, active_index) <= width do
      entries
    else
      shrunk = shrink_entry(entries, active_index, 1)

      if rendered_width(shrunk, active_index) <= width or shrunk == entries do
        shrunk
      else
        shrink_active_label(shrunk, active_index, width)
      end
    end
  end

  defp shrink_entry(entries, idx, min_width) do
    Enum.map(entries, fn
      %{idx: ^idx, tab: tab} = entry ->
        label = Map.fetch!(tab, :label)
        current_width = TextWidth.display_width(label)
        target_width = max(current_width - 1, min_width)
        %{entry | tab: %{tab | label: TextWidth.truncate(label, target_width)}}

      entry ->
        entry
    end)
  end

  defp rendered_width(entries, active_index) do
    label_widths =
      Enum.map(entries, fn %{tab: %{label: label}, idx: idx} ->
        label_width = TextWidth.display_width(label)

        if idx == active_index do
          TextWidth.display_width(@default_active_indicator <> " ") + label_width
        else
          label_width
        end
      end)

    Enum.sum(label_widths) + gap_width(entries)
  end

  defp gap_width(entries) do
    max(length(entries) - 1, 0) * TextWidth.display_width(@tab_gap)
  end

  defp render_tab({tab, idx}, active_index, theme, mappings) do
    label = Map.fetch!(tab, :label)

    if idx == active_index do
      [
        text(@default_active_indicator <> " ", fg: Map.fetch!(theme, mappings.indicator).fg),
        text(label, fg: Map.fetch!(theme, mappings.selected).fg, style: [:bold])
      ]
    else
      [text(label, fg: Map.fetch!(theme, mappings.unselected).fg)]
    end
  end
end
