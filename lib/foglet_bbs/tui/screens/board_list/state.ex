defmodule Foglet.TUI.Screens.BoardList.State do
  @moduledoc """
  Screen-local state for the board directory tree.
  """

  alias Foglet.TUI.Widgets.Display.Tree

  @type t :: %__MODULE__{
          tree: Tree.t() | nil,
          feedback: String.t() | nil
        }

  defstruct tree: nil,
            feedback: nil

  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    %__MODULE__{
      tree: Keyword.get(opts, :tree),
      feedback: Keyword.get(opts, :feedback)
    }
  end
end
