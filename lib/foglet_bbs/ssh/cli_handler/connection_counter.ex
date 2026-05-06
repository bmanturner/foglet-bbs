defmodule Foglet.SSH.CLIHandler.ConnectionCounter do
  @moduledoc """
  VM-local active SSH connection accounting for `Foglet.SSH.CLIHandler`.

  The counter table is runtime-only ETS state initialized by the SSH supervisor.
  Accepted channel-up paths own exactly one later decrement; rejected paths
  compensate their own admission increment before returning.
  """

  @counter_table Foglet.SSH.CLIHandler.Counter

  @doc """
  Initializes the ETS table without resetting an existing active count.
  """
  def init do
    case :ets.info(@counter_table) do
      :undefined -> create_table()
      _info -> ensure_row()
    end

    :ok
  end

  @doc """
  Attempts to reserve one active connection slot.

  Returns `:ok` when the slot is owned by the caller. Returns `:over_limit`
  after immediately compensating the admission increment when the configured
  limit would be exceeded.
  """
  def check_in(max_connections) when is_integer(max_connections) and max_connections > 0 do
    new_count = :ets.update_counter(@counter_table, :count, {2, 1})

    if new_count > max_connections do
      _ = decrement()
      :over_limit
    else
      :ok
    end
  end

  @doc """
  Releases one active connection slot without allowing the count below zero.
  """
  def decrement do
    :ets.update_counter(@counter_table, :count, {2, -1, 0, 0})
  end

  @doc false
  def table, do: @counter_table

  defp create_table do
    _ = :ets.new(@counter_table, [:named_table, :public, :set])
    ensure_row()
  rescue
    ArgumentError -> ensure_row()
  end

  defp ensure_row do
    _ = :ets.insert_new(@counter_table, {:count, 0})
    :ok
  end
end
