defmodule Foglet.TUI.Screens.ThreadList.State do
  @moduledoc """
  Screen-local state for the selected board's thread directory.

  ThreadList owns selected board identity, loaded rows, loading status, and
  selected index through the Phase 34 `init/1`, `update/3`, and `render/2`
  contract.
  """

  alias Foglet.Threads.ThreadEntry
  alias Foglet.TUI.Context

  @type status :: :loading | :loaded | :empty | {:error, term()}

  @type t :: %__MODULE__{
          board: map() | nil,
          board_id: String.t() | nil,
          threads: [ThreadEntry.t() | map()] | nil,
          selected_index: non_neg_integer(),
          select_thread_id: String.t() | nil,
          status: status(),
          last_op: atom() | nil,
          last_error: term() | nil
        }

  defstruct board: nil,
            board_id: nil,
            threads: nil,
            selected_index: 0,
            select_thread_id: nil,
            status: :loading,
            last_op: nil,
            last_error: nil

  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    %__MODULE__{
      board: Keyword.get(opts, :board),
      board_id: Keyword.get(opts, :board_id),
      threads: Keyword.get(opts, :threads),
      selected_index: Keyword.get(opts, :selected_index, 0),
      select_thread_id: Keyword.get(opts, :select_thread_id),
      status: Keyword.get(opts, :status, :loading),
      last_op: Keyword.get(opts, :last_op),
      last_error: Keyword.get(opts, :last_error)
    }
  end

  @spec from_context(Context.t()) :: t()
  def from_context(%Context{} = context) do
    params = context.route_params || %{}
    board = Map.get(params, :board) || Map.get(params, "board")

    explicit_board_id = Map.get(params, :board_id) || Map.get(params, "board_id")
    select_thread_id = Map.get(params, :select_thread_id) || Map.get(params, "select_thread_id")

    new(
      board: board,
      board_id: explicit_board_id || board_id_from_board(board),
      select_thread_id: select_thread_id
    )
  end

  defp board_id_from_board(%{} = board), do: Map.get(board, :id) || Map.get(board, "id")
  defp board_id_from_board(_board), do: nil
end
