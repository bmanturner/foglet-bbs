defmodule Foglet.TUI.Widgets.Chrome.KeyBar do
  @moduledoc """
  Themed bottom-of-screen key hint bar for Foglet BBS.

  Renders a single row of "[KEY] Description" hints. Colors come from
  the theme's accent slot (key bracket) and dim slot (description).

  Called by Chrome.ScreenFrame — screens do not call this directly.

  UI-SPEC contract:
    Key bracket: fg: theme.accent.fg, style: [:bold]
    Description: fg: theme.dim.fg
    Format: "[{KEY}] {Description}" per hint, gap: 2 between hints
  """

  import Raxol.Core.Renderer.View

  alias Foglet.TUI.Theme

  @doc """
  Renders the key bar.

  `theme` — a `%Foglet.TUI.Theme{}` struct (passed from ScreenFrame).
  `keys`  — list of `{key_label, description}` pairs,
             e.g. `[{"j/k", "Navigate"}, {"Enter", "Select"}]`.
  """
  @spec render(Theme.t(), [{String.t(), String.t()}]) :: any()
  def render(theme, keys) when is_list(keys) do
    accent_style = Map.get(theme.accent, :style, [])

    labels =
      Enum.flat_map(keys, fn {k, d} ->
        [
          text("[#{k}] ", fg: theme.accent.fg, style: accent_style),
          text("#{d}  ", fg: theme.dim.fg)
        ]
      end)

    row style: %{gap: 0} do
      labels
    end
  end
end
