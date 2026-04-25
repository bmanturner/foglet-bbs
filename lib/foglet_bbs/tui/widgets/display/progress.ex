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
  @default_segments 5
  @filled_char "█"
  @empty_char " "
  @filled_segment "▰"
  @empty_segment "▱"

  @doc """
  Renders a progress bar.

  `progress` — number in `0.0..1.0` (integers coerced to floats;
               out-of-range values clamped)
  `opts`:
    * `:width`           — integer (default `#{@default_width}`)
    * `:segments`        — integer for compact mode (default `#{@default_segments}`)
    * `:mode`            — `:compact` (default) or `:bracket`
    * `:state`           — `:normal | :warning | :error | :complete` override
    * `:label`           — optional string shown above the bar
    * `:show_percentage` — boolean (default `true`)
    * `:theme`           — required `%Foglet.TUI.Theme{}` struct
  """
  @spec render(number(), keyword()) :: any()
  def render(progress, opts) when is_number(progress) and is_list(opts) do
    %Theme{} = theme = Keyword.fetch!(opts, :theme)
    width = Keyword.get(opts, :width, @default_width)
    segments = Keyword.get(opts, :segments, @default_segments)
    mode = Keyword.get(opts, :mode, :compact)
    label = Keyword.get(opts, :label)
    show_pct = Keyword.get(opts, :show_percentage, true)

    raw_progress = to_float(progress)
    progress = clamp(raw_progress, 0.0, 1.0)
    state = Keyword.get(opts, :state, state_for(raw_progress))
    state_slot = slot_for_state(state, theme)

    bar_row = render_bar(progress, mode, width, segments, state_slot, theme)

    pct_row =
      if show_pct do
        pct_str = "#{floor(progress * 100)}%"
        text(pct_str, fg: state_slot.fg)
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

  defp render_bar(progress, :bracket, width, _segments, state_slot, theme) do
    bar_inner_width = max(1, width - 2)
    filled = floor(progress * bar_inner_width)
    empty = bar_inner_width - filled

    row style: %{gap: 0} do
      [
        text("[", fg: theme.border.fg),
        text(String.duplicate(@filled_char, filled), fg: state_slot.fg),
        text(String.duplicate(@empty_char, empty), fg: theme.dim.fg),
        text("]", fg: theme.border.fg)
      ]
    end
  end

  defp render_bar(progress, _compact, _width, segments, state_slot, theme) do
    segments = max(1, segments)
    filled = floor(progress * segments)
    empty = segments - filled

    row style: %{gap: 0} do
      [
        text(String.duplicate(@filled_segment, filled), fg: state_slot.fg),
        text(String.duplicate(@empty_segment, empty), fg: theme.dim.fg)
      ]
    end
  end

  defp state_for(progress) when progress > 1.0, do: :error
  defp state_for(progress) when progress >= 1.0, do: :complete
  defp state_for(progress) when progress >= 0.8, do: :warning
  defp state_for(_progress), do: :normal

  defp slot_for_state(:complete, theme), do: theme.success
  defp slot_for_state(:warning, theme), do: theme.warning
  defp slot_for_state(:error, theme), do: theme.error
  defp slot_for_state(_normal, theme), do: theme.accent

  defp clamp(value, min_val, _max_val) when value < min_val, do: min_val
  defp clamp(value, _min_val, max_val) when value > max_val, do: max_val
  defp clamp(value, _min_val, _max_val), do: value
end
