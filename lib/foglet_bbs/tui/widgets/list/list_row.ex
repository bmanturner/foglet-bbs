defmodule Foglet.TUI.Widgets.List.ListRow do
  @moduledoc """
  Individual list row renderer for Foglet BBS selection lists (WIDGET-01).

  Renders a single row with a selection marker prefix ("> " or "  ") and
  themed selected/unselected styling. Used by List.SelectionList via the
  row_renderer_fn callback.

  UI-SPEC row contract:
    Selected:   fg: theme.selected.fg, bg: theme.selected.bg, style: [:bold]
    Unselected: fg: theme.unselected.fg
    Marker:     "> " (2 chars) for selected, "  " for unselected
  """

  import Raxol.Core.Renderer.View

  alias Foglet.TUI.Theme

  @doc """
  Renders a single selectable row.

  `label`    — the display string for this row (already formatted by caller)
  `selected` — true if this row is the currently selected item
  `theme`    — the session theme struct
  """
  @spec render(String.t(), boolean(), Theme.t()) :: any()
  def render(label, selected, theme) do
    marker = if selected, do: "> ", else: "  "
    full = "#{marker}#{label}"

    if selected do
      selected_style = Map.get(theme.selected, :style, [:bold])
      text(full, fg: theme.selected.fg, bg: theme.selected.bg, style: selected_style)
    else
      text(full, fg: theme.unselected.fg)
    end
  end
end
