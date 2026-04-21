defmodule Foglet.TUI.Widgets.Input.RadioGroup do
  @moduledoc """
  Themed radio-group widget (D-02, D-13, D-16).

  Stateless — caller passes `selected_index`. No `Raxol.UI.Components.Input.RadioGroup`
  module exists (verified in vendor/raxol/lib/raxol/playground/demos/radio_group_demo.ex —
  even Raxol's own demo composes radio groups from `text/2`). We mirror
  that pattern with our marker + theme slot convention.

  Honours:
    * D-07/D-09 — colors come from theme slots only
    * D-13     — `theme:` keyword arg
    * D-16     — no state struct (purely stateless)

  UI-SPEC contract:
    selected option:  "> (o) {label}", fg: theme.selected.fg
    unselected opts:  "  ( ) {label}", fg: theme.unselected.fg
    layout:           column style: %{gap: 0} — no row spacing
  """

  import Raxol.Core.Renderer.View
  alias Foglet.TUI.Theme

  @on_marker "(o)"
  @off_marker "( )"

  @doc """
  Renders a themed radio group.

  `options`        — list of string labels (one per option)
  `selected_index` — 0-based index of the selected option
  `opts`           — must include `:theme` (`%Foglet.TUI.Theme{}`)
  """
  @spec render([String.t()], non_neg_integer(), keyword()) :: any()
  def render(options, selected_index, opts)
      when is_list(options) and is_integer(selected_index) and is_list(opts) do
    %Theme{} = theme = Keyword.fetch!(opts, :theme)

    rows =
      options
      |> Enum.with_index()
      |> Enum.map(fn {opt, idx} ->
        selected? = idx == selected_index
        mark = if selected?, do: @on_marker, else: @off_marker
        prefix = if selected?, do: "> ", else: "  "
        fg = if selected?, do: theme.selected.fg, else: theme.unselected.fg
        text("#{prefix}#{mark} #{opt}", fg: fg)
      end)

    column style: %{gap: 0} do
      rows
    end
  end
end
