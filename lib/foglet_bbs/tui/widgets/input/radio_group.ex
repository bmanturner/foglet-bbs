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

  Visual contract:
    semantic selected option:   "● {label}", fg: theme.selected.fg
    semantic unselected option: "◇ {label}", fg: theme.unselected.fg
    disabled option:            fg: theme.dim.fg, style: [:dim]
    ASCII compatibility:        "> (o) {label}" / "  ( ) {label}"
    layout:                     column style: %{gap: 0} — no row spacing
  """

  import Raxol.Core.Renderer.View
  alias Foglet.TUI.Theme

  @semantic_on_marker "●"
  @semantic_off_marker "◇"
  @ascii_on_marker "(o)"
  @ascii_off_marker "( )"

  @doc """
  Renders a themed radio group.

  `options`        — list of string labels (one per option)
  `selected_index` — 0-based index of the selected option
  `opts`           — must include `:theme` (`%Foglet.TUI.Theme{}`)

  Options:
    * `:marker_style` — `:semantic` (default) or `:ascii`
    * `:disabled_indices` — list of disabled option indices
  """
  @spec render([String.t()], integer(), keyword()) :: any()
  def render(options, selected_index, opts)
      when is_list(options) and is_integer(selected_index) and is_list(opts) do
    %Theme{} = theme = Keyword.fetch!(opts, :theme)
    marker_style = Keyword.get(opts, :marker_style, :semantic)
    disabled_indices = opts |> Keyword.get(:disabled_indices, []) |> MapSet.new()

    selected_index = clamp_index(selected_index, options)

    rows =
      options
      |> Enum.with_index()
      |> Enum.map(fn {opt, idx} ->
        selected? = idx == selected_index
        disabled? = MapSet.member?(disabled_indices, idx)
        {content, fg, style} = row_contract(opt, selected?, disabled?, marker_style, theme)
        text(content, fg: fg, style: style)
      end)

    column style: %{gap: 0} do
      rows
    end
  end

  # Clamp `selected_index` into the valid option range. Out-of-range indices
  # (negative or >= length) would silently render every row as unselected,
  # leaving the user with no visible selection. Clamping surfaces the bug
  # by highlighting the nearest edge instead of disappearing entirely.
  defp clamp_index(_idx, []), do: -1
  defp clamp_index(idx, _options) when idx < 0, do: 0

  defp clamp_index(idx, options) do
    last = length(options) - 1
    if idx > last, do: last, else: idx
  end

  defp row_contract(label, selected?, disabled?, marker_style, theme) do
    content = row_content(label, selected?, marker_style)

    cond do
      disabled? -> {content, theme.dim.fg, [:dim]}
      selected? -> {content, theme.selected.fg, [:bold]}
      true -> {content, theme.unselected.fg, []}
    end
  end

  defp row_content(label, true, :ascii), do: "> #{@ascii_on_marker} #{label}"
  defp row_content(label, false, :ascii), do: "  #{@ascii_off_marker} #{label}"
  defp row_content(label, true, _semantic), do: "#{@semantic_on_marker} #{label}"
  defp row_content(label, false, _semantic), do: "#{@semantic_off_marker} #{label}"
end
