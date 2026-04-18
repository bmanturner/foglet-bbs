defmodule Foglet.TUI.Screens.MainMenu do
  @moduledoc "Stub — Plan 04 implements main menu."

  import Raxol.Core.Renderer.View

  def render(_state) do
    panel(
      title: "Main Menu",
      border: :single,
      children: [text("(stub — Plan 04 implements main_menu)", color: :green)]
    )
  end

  def handle_key(_key, _state), do: :no_match
end
