defmodule Foglet.TUI.Screens.BoardList.State do
  @moduledoc """
  Screen-local state for the board directory tree.
  """

  alias Foglet.TUI.Widgets.List.BoardTree

  @type t :: %__MODULE__{
          board_tree: BoardTree.t() | nil,
          feedback: String.t() | nil
        }

  defstruct board_tree: nil,
            feedback: nil

  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    %__MODULE__{
      board_tree: Keyword.get(opts, :board_tree),
      feedback: Keyword.get(opts, :feedback)
    }
  end
end
