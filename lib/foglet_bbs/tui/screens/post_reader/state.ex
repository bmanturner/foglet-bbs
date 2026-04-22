defmodule Foglet.TUI.Screens.PostReader.State do
  @moduledoc """
  Screen-local state for `Foglet.TUI.Screens.PostReader`.

  The app stores this struct at `state.screen_state[:post_reader]`.
  """

  alias Raxol.UI.Components.Display.Viewport

  @type t :: %__MODULE__{
          selected_post_index: non_neg_integer(),
          viewport: map(),
          render_cache: map()
        }

  defstruct selected_post_index: 0,
            viewport: nil,
            render_cache: %{}

  @doc """
  Builds a fresh PostReader screen state struct.
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    %__MODULE__{
      selected_post_index: Keyword.get(opts, :selected_post_index, 0),
      viewport: Keyword.get(opts, :viewport) || default_viewport(),
      render_cache: Keyword.get(opts, :render_cache) || %{}
    }
  end

  defp default_viewport do
    {:ok, viewport} =
      Viewport.init(%{
        id: "post_reader_vp",
        children: [],
        visible_height: 10,
        scroll_top: 0,
        show_scrollbar: false
      })

    viewport
  end
end
