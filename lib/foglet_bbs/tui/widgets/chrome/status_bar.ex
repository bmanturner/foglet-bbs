defmodule Foglet.TUI.Widgets.Chrome.StatusBar do
  @moduledoc """
  Themed top-of-screen status bar for Foglet BBS (FRAME-02).

  Renders a full-width row: "Foglet BBS — {title}" on the left,
  "@{handle}" or "guest" on the right. Background and text colors
  come from the theme's status_bar slot (reverse-video bar effect).

  Called by Chrome.ScreenFrame — screens do not call this directly.

  Copywriting contract (UI-SPEC):
    StatusBar left:  "Foglet BBS — {Screen Title}"
    StatusBar right (authed):  "@{handle}"
    StatusBar right (guest):   "guest"
  """

  import Raxol.Core.Renderer.View

  alias Foglet.TUI.Theme

  @doc """
  Renders the status bar.

  `state` — the full app state. Reads `state.current_user.handle` and
             `state.session_context.theme` (falls back to Theme.default()).
  `title` — the page/screen title string (e.g., "Boards", "Login").

  Shape: a `row` with `justify_content: :space_between`. Parent columns
  in ScreenFrame must set `align_items: :stretch` so this row receives
  the full container width; `:space_between` then pushes the handle to
  the right edge. `bg` on each `text` (when the theme sets one) paints
  behind the visible characters only — the gap between stays the
  terminal default.
  """
  @spec render(map(), String.t()) :: any()
  def render(state, title) do
    theme = (Map.get(state, :session_context) || %{}) |> Map.get(:theme) || Theme.default()
    handle = state.current_user && state.current_user.handle
    right = if handle, do: "@#{handle}", else: "guest"

    fg = Map.get(theme.status_bar, :fg)
    bg = Map.get(theme.status_bar, :bg)

    # Kept `justify_content: :space_between` over `spacer()` per 08-06 audit —
    # spacer/1 is fixed-size (vendor/raxol/lib/raxol/view/components.ex:164),
    # cannot reproduce the flex-grow push-to-opposite-ends behavior without
    # caller-computed widths.
    row style: %{justify_content: :space_between} do
      [
        text(" Foglet BBS — #{title}", fg: fg, bg: bg),
        text("#{right} ", fg: fg, bg: bg)
      ]
    end
  end
end
