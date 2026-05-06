defmodule Foglet.TUI.Screens.BoardList.State do
  @moduledoc """
  Screen-local state for the board directory tree.

  Directory rows, `BoardTree` cursor/expansion state, loading status, and
  subscription feedback are local to the BoardList screen reducer.
  """

  alias Foglet.TUI.Widgets.List.BoardTree

  @type t :: %__MODULE__{
          directory: [BoardTree.directory_entry()] | nil,
          board_tree: BoardTree.t() | nil,
          status: :loading | :loaded | :empty | {:error, term()},
          feedback: String.t() | nil,
          last_op: atom() | nil,
          last_error: term() | nil,
          selected_board_id: term() | nil,
          expanded_category_ids: MapSet.t() | nil
        }

  defstruct directory: nil,
            board_tree: nil,
            status: :loading,
            feedback: nil,
            last_op: nil,
            last_error: nil,
            selected_board_id: nil,
            expanded_category_ids: nil

  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    %__MODULE__{
      directory: Keyword.get(opts, :directory),
      board_tree: Keyword.get(opts, :board_tree),
      status: Keyword.get(opts, :status, :loading),
      feedback: Keyword.get(opts, :feedback),
      last_op: Keyword.get(opts, :last_op),
      last_error: Keyword.get(opts, :last_error),
      selected_board_id: Keyword.get(opts, :selected_board_id),
      expanded_category_ids: Keyword.get(opts, :expanded_category_ids)
    }
  end
end
