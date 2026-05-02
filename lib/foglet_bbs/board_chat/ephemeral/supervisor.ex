defmodule Foglet.BoardChat.Ephemeral.Supervisor do
  @moduledoc """
  DynamicSupervisor that owns one `Foglet.BoardChat.Ephemeral.Room` per
  ephemeral board on demand.

  Rooms are not started at boot. They are launched the first time a caller
  posts to or reads from a board, and they self-terminate after an idle
  grace period (`Room.@default_idle_grace_ms`). Restart strategy is
  `:transient` so a normal idle shutdown does not respawn the Room.
  """

  use DynamicSupervisor

  alias Foglet.BoardChat.Ephemeral.Room

  def start_link(opts) do
    DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @doc """
  Start the Room for `board_id` if it is not already running, or return the
  existing pid. `room_opts` are forwarded to `Room.start_link/1` and must
  include `:ttl_seconds`.
  """
  @spec ensure_room(binary(), keyword()) :: {:ok, pid()} | {:error, term()}
  def ensure_room(board_id, room_opts) when is_binary(board_id) do
    case Room.whereis(board_id) do
      pid when is_pid(pid) ->
        {:ok, pid}

      nil ->
        spec = %{
          id: {Room, board_id},
          start: {Room, :start_link, [Keyword.put(room_opts, :board_id, board_id)]},
          restart: :transient,
          type: :worker,
          shutdown: 5_000
        }

        case DynamicSupervisor.start_child(__MODULE__, spec) do
          {:ok, pid} -> {:ok, pid}
          {:ok, pid, _info} -> {:ok, pid}
          {:error, {:already_started, pid}} -> {:ok, pid}
          {:error, _} = err -> err
        end
    end
  end

  @doc "Stop the Room for `board_id` if running. Used by tests and admin paths."
  @spec stop_room(binary()) :: :ok
  def stop_room(board_id) when is_binary(board_id) do
    case Room.whereis(board_id) do
      nil ->
        :ok

      pid ->
        _ = DynamicSupervisor.terminate_child(__MODULE__, pid)
        :ok
    end
  end
end
