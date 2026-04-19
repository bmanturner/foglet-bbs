defmodule Foglet.TUI.Widgets.StatusBar do
  @moduledoc """
  Top-of-screen status bar showing handle and current location.
  Used across all BBS screens; Plan 04 wires it into main_menu and below.
  """

  import Raxol.Core.Renderer.View

  @spec render(%{handle: String.t() | nil, location: String.t()}) :: any()
  def render(%{handle: handle, location: location}) do
    left = if handle, do: "@#{handle}", else: "guest"

    row style: %{gap: 1} do
      [
        text("Foglet BBS — #{location}", fg: :green),
        text("| #{left}", style: [:dim])
      ]
    end
  end
end
