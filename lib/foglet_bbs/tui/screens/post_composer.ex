defmodule Foglet.TUI.Screens.PostComposer do
  @moduledoc "Stub — Plan 04 implements post composer."

  import Raxol.Core.Renderer.View

  def render(_state) do
    panel(
      title: "Post Composer",
      border: :single,
      children: [text("(stub — Plan 04 implements post_composer)", color: :green)]
    )
  end

  def handle_key(_key, _state), do: :no_match
end
