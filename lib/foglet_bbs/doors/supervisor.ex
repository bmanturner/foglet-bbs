defmodule Foglet.Doors.Supervisor do
  @moduledoc """
  Dynamic supervisor for one door runner per active SSH/TUI handoff.

  Runners are `:temporary`: a normal door exit, crash, timeout, or disconnect is
  a session event, not a process that OTP should restart behind the user's back.
  """

  use DynamicSupervisor

  @spec start_link(term()) :: Supervisor.on_start()
  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @spec start_runner(keyword()) :: DynamicSupervisor.on_start_child()
  def start_runner(opts) when is_list(opts) do
    DynamicSupervisor.start_child(__MODULE__, {Foglet.Doors.Runner, opts})
  end

  @spec stop_runner(pid(), term()) :: :ok
  def stop_runner(pid, reason \\ :normal) when is_pid(pid) do
    Foglet.Doors.Runner.stop(pid, reason)
  end
end
