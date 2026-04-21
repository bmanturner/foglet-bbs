defmodule Foglet.TUI.Widgets.Progress.Spinner do
  @moduledoc """
  Themed indeterminate spinner (D-02, D-13, D-16).

  Stateless — caller passes the current frame index. Wraps
  `Raxol.UI.Components.Progress.Spinner.spinner/3`, which returns
  a plain string glyph; this module wraps that glyph in a themed
  `text/2` with `theme.accent.fg`.

  **Outlier note:** Unlike other stateless widgets, we do NOT call
  a Raxol component's `init/1` + `render/2`. `spinner/3` is a pure
  utility that maps (type, frame, opts) → glyph string. The glyph
  is then emitted as a single themed `text/2` element.

  Honours:
    * D-07/D-09 — theme-routed colors only (via `theme.accent.fg`)
    * D-13     — `theme:` keyword arg
    * D-16     — no state struct (purely stateless; frame index passed in)

  ## Style atoms

      :dots | :line | :circle | :arrow | :bounce |
      :pulse | :wave | :dots3 | :square | :flip
  """

  import Raxol.Core.Renderer.View
  alias Foglet.TUI.Theme
  alias Raxol.UI.Components.Progress.Spinner, as: RaxolSpinner

  @default_style :line
  @default_frame_duration_ms 100

  @type style ::
          :dots
          | :line
          | :circle
          | :arrow
          | :bounce
          | :pulse
          | :wave
          | :dots3
          | :square
          | :flip

  @doc """
  Renders a spinner at the given frame index.

  `frame` — non-negative integer (wraps around the style's frame set)
  `opts`:
    * `:style` — one of `#{inspect([:dots, :line, :circle, :arrow, :bounce, :pulse, :wave, :dots3, :square, :flip])}` (default `#{inspect(@default_style)}`)
    * `:theme` — required `%Foglet.TUI.Theme{}` struct
  """
  @spec render(non_neg_integer(), keyword()) :: any()
  def render(frame, opts) when is_integer(frame) and frame >= 0 and is_list(opts) do
    %Theme{} = theme = Keyword.fetch!(opts, :theme)
    style = Keyword.get(opts, :style, @default_style)
    accent_style = Map.get(theme.accent, :style, [])

    # RaxolSpinner.spinner/3 signature: spinner(message, frame, opts)
    # The :type key selects the spinner style (not :style)
    glyph = RaxolSpinner.spinner(nil, frame, type: style)

    text(glyph, fg: theme.accent.fg, style: accent_style)
  end

  @doc "Recommended frame duration in ms (for caller-driven animation)."
  @spec frame_duration_ms() :: pos_integer()
  def frame_duration_ms, do: @default_frame_duration_ms
end
