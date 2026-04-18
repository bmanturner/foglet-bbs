defmodule Foglet.TUI.Screens.BoardList do
  @moduledoc "Stub — Plan 04 implements board list."

  import Raxol.Core.Renderer.View

  def render(_state) do
    panel(
      title: "Board List",
      border: :single,
      children: [text("(stub — Plan 04 implements board_list)", color: :green)]
    )
  end

  def handle_key(_key, _state), do: :no_match
end
