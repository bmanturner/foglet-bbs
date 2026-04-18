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
  Called from Foglet.Boards context when a board is created, and from
  Application.start/2 (via Foglet.Boards.boot_board_servers/0) at boot.
  """
  def start_board(board_id) do
    spec = {Foglet.Boards.Server, board_id: board_id}
    DynamicSupervisor.start_child(__MODULE__, spec)
  end

  @doc """
  Boot all non-archived boards at application startup.
  Called from FogletBbs.Application.start/2 after the supervision tree is up.
  Full implementation is in Foglet.Boards context (Plan 03).
  This stub is replaced when Plan 03 creates Foglet.Boards.
  """
  def boot_board_servers do
    # Stub: no boards exist yet. Plan 03 implements the real query.
    # When Foglet.Boards context is implemented, Application.start/2
    # calls Foglet.Boards.boot_board_servers/0 (not this stub).
    :ok
  end
end
