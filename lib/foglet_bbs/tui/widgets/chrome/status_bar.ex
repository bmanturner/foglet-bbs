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
  """
  @spec render(map(), String.t()) :: any()
  def render(state, title) do
    theme = (Map.get(state, :session_context) || %{}) |> Map.get(:theme) || Theme.default()
    handle = state.current_user && state.current_user.handle
    right = if handle, do: "@#{handle}", else: "guest"

    row style: %{gap: 1} do
      [
        text("Foglet BBS — #{title}", fg: theme.status_bar.fg),
        text("| #{right}", fg: theme.status_bar.fg)
      ]
    end
  end
end
