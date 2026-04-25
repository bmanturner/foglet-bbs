defmodule Foglet.TUI.Widgets.Workspace.Inspector do
  @moduledoc """
  Wide-terminal selected-row detail panel for operator-console workspaces.

  Honours:
    * D-04 — lives under the Workspace widget bucket.
    * D-15 — collapses as optional enhancement below wide-terminal widths.
    * D-16 — renders caller-provided details and action descriptors only.
    * D-17 — supports board, user, invite, and no-selection fixture shapes.
  """

  import Raxol.Core.Renderer.View

  alias Foglet.TUI.Theme
  alias Foglet.TUI.Widgets.Display.KvGrid

  @default_min_width 100
  @default_width 80
  @detail_margin 4

  @doc """
  Renders selected item details and caller-provided action descriptors.
  """
  @spec render(map() | nil, keyword()) :: any()
  def render(selection, opts) when is_list(opts) do
    %Theme{} = theme = Keyword.fetch!(opts, :theme)
    width = Keyword.get(opts, :width, @default_width)
    min_width = Keyword.get(opts, :min_width, @default_min_width)

    if width < min_width do
      []
    else
      render_wide(selection, theme, width, opts)
    end
  end

  defp render_wide(nil, %Theme{} = theme, _width, _opts) do
    text("No selection", fg: theme.dim.fg)
  end

  defp render_wide(selection, %Theme{} = theme, width, opts) do
    title = Keyword.get(opts, :title, Map.get(selection, :title, "Details"))
    details = Keyword.get(opts, :details, Map.get(selection, :details, []))
    actions = Keyword.get(opts, :actions, Map.get(selection, :actions, []))
    detail_width = max(width - @detail_margin, 0)

    [
      text(title, fg: theme.title.fg, style: theme.title[:style]),
      text("\n"),
      KvGrid.render(details, theme: theme, width: detail_width),
      actions_block(actions, theme)
    ]
  end

  defp actions_block([], _theme), do: []

  defp actions_block(actions, %Theme{} = theme) do
    [
      text("\n"),
      actions
      |> Enum.map(&action_text(&1, theme))
      |> Enum.intersperse(text("  ", fg: theme.dim.fg))
    ]
  end

  defp action_text(action, %Theme{} = theme) do
    key = Map.get(action, :key)
    label = Map.get(action, :label, "")
    slot = action_slot(Map.get(action, :role))
    style = Map.fetch!(theme, slot)
    content = if key in [nil, ""], do: label, else: "#{key} #{label}"

    text(content, text_opts(style))
  end

  defp action_slot(:destructive), do: :error
  defp action_slot(:inactive), do: :dim
  defp action_slot(:primary), do: :primary
  defp action_slot(_role), do: :accent

  defp text_opts(style) do
    []
    |> maybe_put(:fg, Map.get(style, :fg))
    |> maybe_put(:bg, Map.get(style, :bg))
    |> maybe_put(:style, Map.get(style, :style))
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)
end
