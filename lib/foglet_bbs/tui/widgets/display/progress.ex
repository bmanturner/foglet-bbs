defmodule Foglet.TUI.Widgets.Display.Progress do
  @moduledoc """
  Themed animated progress bar (D-02, D-13, D-16).

  Stateless — caller passes current progress (0.0..1.0) on every render.
  Renders the bar directly using Raxol DSL primitives to guarantee full
  theme-slot routing (D-07/D-09) without delegating to
  `Raxol.UI.Components.Display.Progress`.

  **Pitfall 8 (RESEARCH.md):** `Raxol.UI.Components.Display.Progress` has
  hardcoded `:green`/`:black`/`:white` defaults in `extract_colors/1` when
  the `:theme` prop is missing or improperly routed. This wrapper bypasses
  that component's render entirely and emits DSL `text/2` elements directly,
  so those atoms can never leak.

  Honours:
    * D-07/D-09 — theme-routed colors only
    * D-13     — `theme:` keyword arg
    * D-16     — no state struct (purely stateless)
  """

  import Raxol.Core.Renderer.View
  alias Foglet.TUI.Theme

  @default_width 40
  @filled_char "█"
  @empty_char " "

  @doc """
  Renders a progress bar.

  `progress` — number in `0.0..1.0` (integers coerced to floats;
               out-of-range values clamped)
  `opts`:
    * `:width`           — integer (default `#{@default_width}`)
    * `:label`           — optional string shown above the bar
    * `:show_percentage` — boolean (default `true`)
    * `:theme`           — required `%Foglet.TUI.Theme{}` struct
  """
  @spec render(number(), keyword()) :: any()
  def render(progress, opts) when is_number(progress) and is_list(opts) do
    %Theme{} = theme = Keyword.fetch!(opts, :theme)
    width = Keyword.get(opts, :width, @default_width)
    label = Keyword.get(opts, :label)
    show_pct = Keyword.get(opts, :show_percentage, true)

    progress = progress |> to_float() |> clamp(0.0, 1.0)
    bar_inner_width = max(1, width - 2)
    filled = floor(progress * bar_inner_width)
    empty = bar_inner_width - filled

    filled_color = if progress >= 1.0, do: theme.success.fg, else: theme.accent.fg
    filled_str = String.duplicate(@filled_char, filled)
    empty_str = String.duplicate(@empty_char, empty)

    bar_row =
      row style: %{gap: 0} do
        [
          text("[", fg: theme.border.fg),
          text(filled_str, fg: filled_color),
          text(empty_str, fg: theme.dim.fg),
          text("]", fg: theme.border.fg)
        ]
      end

    pct_row =
      if show_pct do
        pct_str = "#{floor(progress * 100)}%"
        text(pct_str, fg: theme.primary.fg)
      else
        nil
      end

    label_row =
      if label do
        text(label, fg: theme.primary.fg)
      else
        nil
      end

    rows = Enum.reject([label_row, bar_row, pct_row], &is_nil/1)

    column style: %{gap: 0} do
      rows
    end
  end

  # --- private ---

  defp to_float(n) when is_integer(n), do: n * 1.0
  defp to_float(n) when is_float(n), do: n

  defp clamp(value, min_val, _max_val) when value < min_val, do: min_val
  defp clamp(value, _min_val, max_val) when value > max_val, do: max_val
  defp clamp(value, _min_val, _max_val), do: value
end
