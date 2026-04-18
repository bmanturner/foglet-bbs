defmodule Foglet.TUI.Screens.ThreadList do
  @moduledoc "Stub — Plan 04 implements thread list."

  import Raxol.Core.Renderer.View

  def render(_state) do
    panel(
      title: "Thread List",
      border: :single,
      children: [text("(stub — Plan 04 implements thread_list)", color: :green)]
    )
  end

  def handle_key(_key, _state), do: :no_match
end
