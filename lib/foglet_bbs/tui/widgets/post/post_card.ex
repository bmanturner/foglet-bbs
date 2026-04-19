defmodule Foglet.TUI.Widgets.Post.PostCard do
  @moduledoc """
  Post display card for Foglet BBS (WIDGET-01).

  STUB — Phase 1 defines the module and type contract only.
  Phase 2 implements render/3 with the full post card layout.

  Phase 2 contract:
    render(post, width, theme) :: Raxol view element

  Where:
    post  — a Foglet.Posts.Post struct with :body, :inserted_at, :user preloaded
    width — terminal column count
    theme — %Foglet.TUI.Theme{} for styled output
  """

  @doc """
  Stub render — raises until Phase 2 implements this.
  """
  @spec render(map(), pos_integer(), Foglet.TUI.Theme.t()) :: any()
  def render(_post, _width, _theme) do
    raise "Foglet.TUI.Widgets.Post.PostCard.render/3 not yet implemented — Phase 2 deliverable"
  end
end
