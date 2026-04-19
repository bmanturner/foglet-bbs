defmodule Foglet.TUI.Widgets.KeyBar do
  @moduledoc """
  Bottom-of-screen key-shortcut bar (D-19). Accepts a list of
  {key_label, description} pairs and renders them in a single row.
  """

  import Raxol.Core.Renderer.View

  @spec render(keys :: [{String.t(), String.t()}]) :: any()
  def render(keys) when is_list(keys) do
    formatted =
      Enum.map_join(keys, "  ", fn {k, d} -> "[#{k}] #{d}" end)

    box(
      children: [
        text(formatted, style: [:dim])
      ]
    )
  end
end
