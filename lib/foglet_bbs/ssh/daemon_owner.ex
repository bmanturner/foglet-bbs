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

  # Filenames Erlang's :ssh_file.host_key/2 looks for in the system_dir,
  # one per host-key algorithm. At least one must exist or the daemon
  # will fail at the first incoming connection with an opaque error.
  @host_key_files ~w[
    ssh_host_rsa_key
    ssh_host_dsa_key
    ssh_host_ecdsa_key
    ssh_host_ed25519_key
    ssh_host_ed448_key
  ]

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)

    port = Keyword.fetch!(opts, :port)
    daemon_opts = Keyword.fetch!(opts, :daemon_opts)

    with :ok <- validate_system_dir(daemon_opts),
         {:ok, daemon_ref} <- :ssh.daemon(port, daemon_opts) do
      Logger.info("Foglet SSH daemon started on port #{port}")
      {:ok, %{daemon_ref: daemon_ref, port: port}}
    else
      {:error, {:invalid_system_dir, message}} ->
        Logger.error("Foglet SSH daemon refusing to start: #{message}")
        {:stop, {:ssh_daemon_failed, {:invalid_system_dir, message}}}

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

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp validate_system_dir(daemon_opts) do
    case Keyword.get(daemon_opts, :system_dir) do
      nil ->
        {:error, {:invalid_system_dir, ":system_dir missing from daemon_opts"}}

      sd ->
        dir = to_string(sd)

        cond do
          not File.dir?(dir) ->
            {:error,
             {:invalid_system_dir,
              "host key directory #{inspect(dir)} does not exist or is not readable"}}

          not has_host_key?(dir) ->
            expected = Enum.join(@host_key_files, ", ")
            suggested = Path.join(dir, "ssh_host_ed25519_key")

            {:error,
             {:invalid_system_dir,
              "host key directory #{inspect(dir)} contains no host keys " <>
                "(expected one of: #{expected}). " <>
                "Generate one with: ssh-keygen -t ed25519 -f #{suggested} -N \"\""}}

          true ->
            :ok
        end
    end
  end

  defp has_host_key?(dir) do
    Enum.any?(@host_key_files, fn key -> File.regular?(Path.join(dir, key)) end)
  end
end
