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

  alias Foglet.TUI.TextWidth
  alias Foglet.TUI.Theme

  @doc """
  Renders the key bar.

  `theme` — a `%Foglet.TUI.Theme{}` struct (passed from ScreenFrame).
  `keys`  — list of `{key_label, description}` pairs,
             e.g. `[{"j/k", "Navigate"}, {"Enter", "Select"}]`.
  """
  @spec render(Theme.t(), [{String.t(), String.t()}], keyword()) :: any()
  def render(theme, keys, opts \\ []) when is_list(keys) do
    accent_style = Map.get(theme.accent, :style, [])

    keys = fit_keys(keys, Keyword.get(opts, :width))

    labels =
      Enum.flat_map(keys, fn {k, d} ->
        [
          text("[#{k}] ", fg: theme.accent.fg, style: accent_style),
          text(d, fg: theme.dim.fg)
        ]
      end)

    row style: %{gap: 0, justify_content: :center} do
      labels
    end
  end

  defp fit_keys(keys, nil) do
    Enum.map(keys, fn {key, description} -> {to_string(key), to_string(description) <> "  "} end)
  end

  defp fit_keys(keys, width) when is_integer(width) do
    hints =
      Enum.map(keys, fn {key, description} ->
        %{key: to_string(key), description: to_string(description) <> "  "}
      end)

    key_width =
      Enum.reduce(hints, 0, fn hint, width ->
        width + TextWidth.display_width("[#{hint.key}] ")
      end)

    desc_budget = max(width - key_width, 0)

    hints
    |> Enum.reduce({[], desc_budget}, fn hint, {acc, remaining} ->
      desc_width = TextWidth.display_width(hint.description)

      description =
        cond do
          remaining <= 0 -> ""
          desc_width <= remaining -> hint.description
          true -> TextWidth.truncate(hint.description, remaining)
        end

      remaining = max(remaining - TextWidth.display_width(description), 0)
      {acc ++ [{hint.key, description}], remaining}
    end)
    |> elem(0)
    |> fit_key_labels(width)
  end

  defp fit_keys(keys, _width), do: keys

  defp fit_key_labels(keys, width) do
    {fit, _used} =
      Enum.reduce_while(keys, {[], 0}, fn {key, description}, {acc, used} ->
        hint_width = TextWidth.display_width("[#{key}] " <> description)

        if used + hint_width <= width do
          {:cont, {acc ++ [{key, description}], used + hint_width}}
        else
          {:halt, {acc, used}}
        end
      end)

    fit
  end
end
