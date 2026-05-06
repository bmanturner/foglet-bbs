defmodule Foglet.TUI.SizeGate do
  @moduledoc """
  Terminal size gate for Foglet BBS (FRAME-03, Phase 5).

  When the terminal is below the minimum size, `App.view/1` short-circuits
  to `SizeGate.render/1` instead of rendering the normal screen. This is a
  pure render-time branch — `state.current_screen`, `state.screen_state`,
  composer drafts, and selected indices are preserved across resize.

  Threshold (D-02, D-13): 64×22 strict inequality. Below this, chrome
  (outer border 2×2 + padding 2×2 + StatusBar 1 row + divider 1 row +
  KeyBar 1 row) leaves no usable content area. The gate message quotes
  the same number so users know exactly what size makes the gate go away.

  See `05-CONTEXT.md` D-01..D-13 for the full decision trail.
  """

  import Raxol.Core.Renderer.View

  alias Foglet.AppName
  alias Foglet.TUI.Theme

  @min_cols 64
  @min_rows 22

  @doc "Returns the code-level minimum columns. 64."
  @spec min_cols() :: 64
  def min_cols, do: @min_cols

  @doc "Returns the code-level minimum rows. 22."
  @spec min_rows() :: 22
  def min_rows, do: @min_rows

  @doc """
  Returns true when the terminal is below the minimum size (D-02, D-13).

  Strict inequality: 64×22 passes through, 63×22 or 64×21 are gated.
  Falsy terminal_size (missing key, nil) is treated as "not gated" —
  safer to render normally than to lock users out on state corruption.
  """
  @spec too_small?(map()) :: boolean()
  def too_small?(%{terminal_size: {cols, rows}})
      when is_integer(cols) and is_integer(rows) do
    cols < @min_cols or rows < @min_rows
  end

  def too_small?(_state), do: false

  @doc """
  Renders the centered four-line "terminal too small" message.

  Copy:
    Terminal too small.
    Foglet BBS requires at least 64×22.
    Your terminal is currently: {cols}×{rows}.
    Please resize.

  Color comes from `theme.dim.fg` (D-07), falling back to `Theme.default()`
  when `session_context.theme` is absent (same pattern as StatusBar and
  ScreenFrame).
  """
  @spec render(map()) :: any()
  def render(state) do
    theme = Theme.from_state(state)

    fg = Map.get(theme.dim, :fg)

    # Defensive fallback: `App.view/1` only calls `render/1` after
    # `too_small?/1` has returned true, which itself requires a
    # well-formed `{cols, rows}` tuple. The `_ -> "unknown"` branch is
    # unreachable in production; we keep it so unit tests can invoke
    # `render/1` directly with a bare `%{}` state without crashing.
    # Use a sentinel string rather than "0×0" so a stray screenshot of
    # this output cannot be misread as a real terminal-size detection bug.
    size_text =
      case Map.get(state, :terminal_size) do
        {c, r} when is_integer(c) and is_integer(r) -> "#{c}×#{r}"
        _ -> "unknown"
      end

    # Raxol's Flex.column reads top-level :align/:justify (not nested CSS-style
    # :align_items/:justify_content under :style — those are silently dropped,
    # leaving the gate text rendered at the top-left and effectively invisible
    # in the chrome-less gate path). Match the working modal-overlay pattern in
    # App.render_modal_overlay/2.
    column justify: :center, align: :center do
      [
        column align: :center do
          [
            text("Terminal too small.", fg: fg),
            text(
              "#{AppName.name()} requires at least #{@min_cols}×#{@min_rows}.",
              fg: fg
            ),
            text("Your terminal is currently: #{size_text}.", fg: fg),
            text("Please resize.", fg: fg)
          ]
        end
      ]
    end
  end
end
