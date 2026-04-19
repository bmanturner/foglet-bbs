defmodule Foglet.TUI.Widgets.Post.MarkdownBody do
  @moduledoc """
  Markdown-to-terminal body renderer for Foglet BBS (WIDGET-01).

  STUB — Phase 1 defines the module and type contract only.
  Phase 2 implements render/3 with MDEx + newline-grouping fix.

  Phase 2 contract:
    render(markdown_text, width, theme) :: Raxol view element

  Where:
    markdown_text — raw markdown string from post.body
    width         — terminal column count for line wrapping
    theme         — %Foglet.TUI.Theme{} for styled output
  """

  @doc """
  Stub render — raises until Phase 2 implements this.
  Phase 2 will replace this body with MDEx + ANSI rendering logic.
  """
  @spec render(String.t(), pos_integer(), Foglet.TUI.Theme.t()) :: any()
  def render(_markdown_text, _width, _theme) do
    # Phase 2 implements this. Stub prevents compile errors on Phase 2 PLAN imports.
    raise "Foglet.TUI.Widgets.Post.MarkdownBody.render/3 not yet implemented — Phase 2 deliverable"
  end
end
