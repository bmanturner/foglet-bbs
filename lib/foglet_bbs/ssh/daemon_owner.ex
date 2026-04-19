defmodule Foglet.SSH.DaemonOwner do
  @moduledoc """
  GenServer that owns the `:ssh.daemon/2` reference and supervises it.

  ## Why this exists

  Calling `:ssh.daemon/2` inside `Supervisor.init/1` and returning an empty
  children list (the old pattern) means the SSH daemon is owned by OTP's `:ssh`
  application — not by Foglet's supervisor tree. A daemon crash is invisible to
  the supervisor and won't trigger a restart.

  `DaemonOwner` fixes this by:

  1. Calling `:ssh.daemon/2` inside `init/1`, storing the `daemon_ref`.
  2. Trapping exits so any linked process (including the SSH acceptor) that
     dies causes us to receive `{:EXIT, pid, reason}`.
  3. Stopping itself on unexpected exits — which causes `Foglet.SSH.Supervisor`
     to restart the DaemonOwner, which starts a fresh daemon.

  `Foglet.SSH.Supervisor` adds this module as a supervised child with strategy
  `:one_for_one`.
  """

  use GenServer

  require Logger

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)

    port = Keyword.fetch!(opts, :port)
    daemon_opts = Keyword.fetch!(opts, :daemon_opts)

    case :ssh.daemon(port, daemon_opts) do
      {:ok, daemon_ref} ->
        Logger.info("Foglet SSH daemon started on port #{port}")
        {:ok, %{daemon_ref: daemon_ref, port: port}}

      {:error, reason} ->
        Logger.error("Foglet SSH daemon failed to start on port #{port}: #{inspect(reason)}")
        {:stop, {:ssh_daemon_failed, reason}}
    end
  end

  @impl true
  def handle_info({:EXIT, _pid, reason}, state) when reason not in [:normal, :shutdown] do
    Logger.warning(
      "SSH daemon linked process exited (#{inspect(reason)}); restarting via supervisor"
    )

    {:stop, :daemon_down, state}
  end

  @impl true
  def handle_info(_msg, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, %{daemon_ref: ref}) when not is_nil(ref) do
    :ssh.stop_daemon(ref)
    :ok
  end

  def terminate(_reason, _state), do: :ok
end
