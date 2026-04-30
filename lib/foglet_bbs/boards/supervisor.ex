defmodule Foglet.Boards.Supervisor do
  @moduledoc """
  DynamicSupervisor that manages one `Foglet.Boards.Server` per active board.

  Board servers are started at application boot (after the supervision tree
  is up) and whenever a new board is created. Each server is registered via
  `Foglet.BoardRegistry` by board_id.

  Per D-04 (CONTEXT.md): all non-archived boards are started at boot.
  """

  use DynamicSupervisor

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    # Children are NOT started here — boot_board_servers/0 in Application.start/2
    # calls start_child/1 after the tree is fully started.
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @doc """
  Start a Board Server for the given board_id.

  Called from `Foglet.Boards` context when a board is created, and at boot
  from `FogletBbs.Application.start/2` via `Foglet.Boards.boot_board_servers/0`
  (the canonical implementation lives in `lib/foglet_bbs/boards.ex`).
  """
  def start_board(board_id) do
    spec = {Foglet.Boards.Server, board_id: board_id}
    DynamicSupervisor.start_child(__MODULE__, spec)
  end
end
