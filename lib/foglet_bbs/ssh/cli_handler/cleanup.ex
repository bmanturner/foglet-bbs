defmodule Foglet.SSH.CLIHandler.Cleanup do
  @moduledoc """
  Idempotent SSH channel cleanup for `Foglet.SSH.CLIHandler` state.

  Cleanup order is intentionally centralized here because EOF, closed-channel,
  lifecycle EXIT, dispatcher-start failure, and terminate callbacks all need the
  same failure-path guarantees:

  1. untrack/disconnect door runner,
  2. restore terminal cursor / leave alternate screen while the channel may still be writable,
  3. stop the Raxol lifecycle,
  4. terminate the Foglet session,
  5. optionally close the SSH channel,
  6. decrement the active connection counter exactly once.
  """

  alias Foglet.Sessions
  alias Foglet.SSH.CLIHandler.ConnectionCounter

  @doc """
  Runs idempotent cleanup for a Foglet.SSH.CLIHandler state struct.
  """
  def cleanup(%Foglet.SSH.CLIHandler{cleanup_done?: true} = state, _opts), do: state

  def cleanup(%Foglet.SSH.CLIHandler{} = state, opts) do
    Foglet.Sessions.DoorPresence.untrack_runner(state.door_runner_pid)
    stop_door_runner(state.door_runner_pid)
    send_alt_screen_leave(state)
    stop_lifecycle(state.lifecycle_pid)
    _ = stop_session(state.session_pid)

    if Keyword.get(opts, :close_channel, false) do
      maybe_close_channel(state)
    end

    _ =
      if state.counter_counted? do
        _ = ConnectionCounter.decrement()
      end

    %Foglet.SSH.CLIHandler{
      state
      | cleanup_done?: true,
        counter_counted?: false,
        door_runner_pid: nil,
        active_door_manifest: nil
    }
  end

  @doc """
  Takes over the terminal before first render.
  """
  def send_alt_screen_enter(%{connection_ref: ref, channel_id: ch})
      when not is_nil(ref) and not is_nil(ch) do
    _ = :ssh_connection.send(ref, ch, "\e[?25l\e[H\e[2J\e[3J\e[?1049h\e[?25l\e[H\e[2J\e[3J")
    :ok
  rescue
    _ -> :ok
  end

  def send_alt_screen_enter(_state), do: :ok

  @doc """
  Restores the primary terminal buffer if the channel is still writable.
  """
  def send_alt_screen_leave(%{connection_ref: ref, channel_id: ch})
      when not is_nil(ref) and not is_nil(ch) do
    _ = :ssh_connection.send(ref, ch, "\e[?25h\e[?1049l\e[?25h")
    :ok
  rescue
    _ -> :ok
  end

  def send_alt_screen_leave(_state), do: :ok

  defp stop_lifecycle(nil), do: :ok

  defp stop_lifecycle(pid) do
    if Process.alive?(pid), do: Raxol.Core.Runtime.Lifecycle.stop(pid)
  rescue
    _ -> :ok
  end

  defp stop_door_runner(nil), do: :ok

  defp stop_door_runner(pid) when is_pid(pid) do
    if Process.alive?(pid), do: Foglet.Doors.Runner.disconnect(pid)
  rescue
    _ -> :ok
  end

  defp stop_session(nil), do: :ok

  defp stop_session(pid) do
    if Process.alive?(pid) do
      DynamicSupervisor.terminate_child(Sessions.Supervisor, pid)
    end
  rescue
    _ -> :ok
  end

  defp maybe_close_channel(%{connection_ref: ref, channel_id: ch})
       when not is_nil(ref) and not is_nil(ch) do
    :ssh_connection.close(ref, ch)
  rescue
    _ -> :ok
  end

  defp maybe_close_channel(_state), do: :ok
end
