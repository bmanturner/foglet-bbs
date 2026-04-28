defmodule Foglet.TUI.Screens.BoardList.State do
  @moduledoc """
  Screen-local state for the board directory tree.
  """

  alias Foglet.TUI.Widgets.List.BoardTree

  @type t :: %__MODULE__{
          directory: [BoardTree.directory_entry()] | nil,
          board_tree: BoardTree.t() | nil,
          status: :loading | :loaded | :empty | {:error, term()},
          feedback: String.t() | nil,
          last_op: atom() | nil,
          last_error: term() | nil
        }

  defstruct directory: nil,
            board_tree: nil,
            status: :loading,
            feedback: nil,
            last_op: nil,
            last_error: nil

  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    %__MODULE__{
      directory: Keyword.get(opts, :directory),
      board_tree: Keyword.get(opts, :board_tree),
      status: Keyword.get(opts, :status, :loading),
      feedback: Keyword.get(opts, :feedback),
      last_op: Keyword.get(opts, :last_op),
      last_error: Keyword.get(opts, :last_error)
    }
  end
end
