defmodule Foglet.TUI.Screens.PostReader do
  @moduledoc "Stub — Plan 04 implements post reader."

  import Raxol.Core.Renderer.View

  def render(_state) do
    panel(
      title: "Post Reader",
      border: :single,
      children: [text("(stub — Plan 04 implements post_reader)", color: :green)]
    )
  end

  def handle_key(_key, _state), do: :no_match
end
