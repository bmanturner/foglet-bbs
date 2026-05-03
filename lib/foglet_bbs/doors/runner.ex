defmodule Foglet.Doors.Runner do
  @moduledoc """
  OTP owner for one active door session.

  The runner is the explicit runtime boundary between TUI effects/SSH channel
  events and door execution. It owns:

    * native-door callback execution;
    * external executable `Port` ownership;
    * PTY wrapper command construction;
    * launch context/env file creation and deletion;
    * resize, timeout, disconnect, crash, and normal-exit cleanup.

  Screen reducers should never spawn OS processes directly; they request a door
  launch and the app/SSH interpreter starts a supervised runner here.
  """

  use GenServer, restart: :temporary

  require Logger

  alias Foglet.Doors.Manifest

  Module.register_attribute(__MODULE__, :sobelow_skip, accumulate: true, persist: true)

  @type exit_reason :: :normal | :crash | :timeout | :disconnect | {:error, term()}

  defstruct [
    :manifest,
    :session,
    :terminal_size,
    :output,
    :owner,
    :native_state,
    :port,
    :os_pid,
    :context_path,
    :timeout_ref,
    :idle_timeout_ref,
    :started_at,
    :ended_at,
    :last_resize,
    status: :starting,
    exit_reason: nil,
    exit_status: nil,
    cleanup_done?: false
  ]

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @spec input(pid(), binary()) :: :ok
  def input(pid, data) when is_pid(pid) and is_binary(data) do
    GenServer.cast(pid, {:input, data})
  end

  @spec resize(pid(), {pos_integer(), pos_integer()}) :: :ok
  def resize(pid, {cols, rows} = size) when is_pid(pid) and cols > 0 and rows > 0 do
    GenServer.cast(pid, {:resize, size})
  end

  @spec disconnect(pid()) :: :ok
  def disconnect(pid) when is_pid(pid), do: GenServer.cast(pid, :disconnect)

  @spec stop(pid(), term()) :: :ok
  def stop(pid, reason \\ :normal) when is_pid(pid), do: GenServer.cast(pid, {:stop, reason})

  @spec snapshot(pid()) :: map()
  def snapshot(pid) when is_pid(pid), do: GenServer.call(pid, :snapshot)

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)

    manifest = Keyword.fetch!(opts, :manifest)
    session = Keyword.get(opts, :session, %{})
    terminal_size = Keyword.get(opts, :terminal_size, {80, 24})
    output = Keyword.get(opts, :output, fn _iodata -> :ok end)
    owner = Keyword.get(opts, :owner, self())

    with {:ok, manifest} <- normalize_manifest(manifest),
         {:ok, context_path} <- write_context_file(manifest, session, terminal_size) do
      state = %__MODULE__{
        manifest: manifest,
        session: session,
        terminal_size: terminal_size,
        output: output,
        owner: owner,
        context_path: context_path,
        started_at: DateTime.utc_now(),
        last_resize: terminal_size
      }

      state = arm_timeouts(state)
      send(self(), :launch)
      {:ok, state}
    else
      {:error, reason} -> {:stop, reason}
    end
  end

  @impl true
  def handle_call(:snapshot, _from, state) do
    {:reply, Map.take(state, [:status, :exit_reason, :exit_status, :os_pid, :last_resize]), state}
  end

  @impl true
  def handle_cast({:input, data}, %{manifest: %{runtime: :native_elixir}} = state) do
    module = state.manifest.module

    if function_exported?(module, :handle_input, 2) do
      case module.handle_input(data, state.native_state) do
        {:ok, native_state, output} ->
          emit(state, output)
          {:noreply, %{state | native_state: native_state} |> refresh_idle_timeout()}

        {:stop, reason, native_state, output} ->
          emit(state, output)
          {:stop, :normal, complete(%{state | native_state: native_state}, reason, nil)}
      end
    else
      {:noreply, refresh_idle_timeout(state)}
    end
  rescue
    e ->
      {:stop, {:door_crash, e}, complete(state, :crash, nil)}
  end

  def handle_cast({:input, data}, %{port: port} = state) when not is_nil(port) do
    _ = Port.command(port, data)
    {:noreply, refresh_idle_timeout(state)}
  end

  def handle_cast({:input, _data}, state), do: {:noreply, state}

  def handle_cast({:resize, size}, %{manifest: %{runtime: :native_elixir}} = state) do
    module = state.manifest.module
    state = %{state | terminal_size: size, last_resize: size}

    if function_exported?(module, :handle_resize, 2) do
      case module.handle_resize(size, state.native_state) do
        {:ok, native_state, output} ->
          emit(state, output)
          {:noreply, %{state | native_state: native_state}}
      end
    else
      {:noreply, state}
    end
  rescue
    e ->
      {:stop, {:door_crash, e}, complete(state, :crash, nil)}
  end

  def handle_cast({:resize, size}, state) do
    # External PTY resize support is adapter-dependent. The runner records the
    # new size for audit/handoff and notifies its owner so the SSH interpreter can
    # plug in a concrete PTY backend later without moving ownership into screens.
    notify_owner(state, {:door_resize, self(), state.manifest.id, size})
    {:noreply, %{state | terminal_size: size, last_resize: size}}
  end

  def handle_cast(:disconnect, state) do
    {:stop, :normal, complete(state, :disconnect, nil)}
  end

  def handle_cast({:stop, reason}, state) do
    {:stop, :normal, complete(state, reason, nil)}
  end

  @impl true
  def handle_info(:launch, %{manifest: %{runtime: :native_elixir}} = state) do
    context = launch_context(state)

    case state.manifest.module.init(context) do
      {:ok, native_state, output} ->
        emit(state, output)
        notify_owner(state, {:door_started, self(), state.manifest.id})
        {:noreply, %{state | native_state: native_state, status: :running}}

      {:ok, native_state} ->
        notify_owner(state, {:door_started, self(), state.manifest.id})
        {:noreply, %{state | native_state: native_state, status: :running}}

      {:stop, reason} ->
        {:stop, :normal, complete(state, reason, nil)}
    end
  rescue
    e ->
      {:stop, {:door_crash, e}, complete(state, :crash, nil)}
  end

  def handle_info(:launch, %{manifest: %{runtime: :external_pty}} = state) do
    case open_external_port(state) do
      {:ok, port, os_pid} ->
        notify_owner(state, {:door_started, self(), state.manifest.id})
        {:noreply, %{state | port: port, os_pid: os_pid, status: :running}}

      {:error, reason} ->
        {:stop, {:door_launch_failed, reason}, complete(state, {:error, reason}, nil)}
    end
  end

  def handle_info(:timeout, state) do
    {:stop, :normal, complete(state, :timeout, nil)}
  end

  def handle_info(:idle_timeout, state) do
    {:stop, :normal, complete(state, :idle_timeout, nil)}
  end

  def handle_info({_port, {:data, data}}, state) do
    emit(state, data)
    {:noreply, refresh_idle_timeout(state)}
  end

  def handle_info({port, {:exit_status, status}}, %{port: port} = state) do
    reason = if status == 0, do: :normal, else: :crash
    {:stop, :normal, complete(state, reason, status)}
  end

  def handle_info({:EXIT, port, reason}, %{port: port} = state) do
    {:stop, reason, complete(state, :crash, nil)}
  end

  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, state) do
    _ = cleanup(state)
    :ok
  end

  defp normalize_manifest(%Manifest{} = manifest), do: {:ok, manifest}

  defp normalize_manifest(attrs) do
    case Foglet.Doors.validate_manifest(Map.new(attrs)) do
      {:ok, manifest} -> {:ok, manifest}
      {:error, errors} -> {:error, {:invalid_manifest, errors}}
    end
  end

  defp arm_timeouts(state) do
    timeout_ref = Process.send_after(self(), :timeout, state.manifest.timeout_ms)
    idle_timeout_ref = arm_idle_timeout(state.manifest.idle_timeout_ms)
    %{state | timeout_ref: timeout_ref, idle_timeout_ref: idle_timeout_ref}
  end

  defp refresh_idle_timeout(%{idle_timeout_ref: ref} = state) when is_reference(ref) do
    _ = Process.cancel_timer(ref)
    %{state | idle_timeout_ref: arm_idle_timeout(state.manifest.idle_timeout_ms)}
  end

  defp refresh_idle_timeout(state), do: state

  defp arm_idle_timeout(nil), do: nil

  defp arm_idle_timeout(ms) when is_integer(ms) and ms > 0,
    do: Process.send_after(self(), :idle_timeout, ms)

  defp launch_context(state) do
    %{
      door_id: state.manifest.id,
      session: state.session,
      terminal_size: state.terminal_size,
      send_output: fn data -> emit(state, data) end
    }
  end

  defp emit(%{output: output}, data) when is_function(output, 1) do
    _ = output.(data)
    :ok
  end

  defp notify_owner(%{owner: owner}, message) when is_pid(owner), do: send(owner, message)
  defp notify_owner(_state, _message), do: :ok

  defp complete(state, reason, status) do
    state = %{
      state
      | status: :exited,
        exit_reason: reason,
        exit_status: status,
        ended_at: DateTime.utc_now()
    }

    _ = cleanup(state)
    notify_owner(state, {:door_exited, self(), state.manifest.id, reason, status})
    state
  end

  defp cleanup(%{cleanup_done?: true} = state), do: state

  defp cleanup(state) do
    _ = cancel_timer(state.timeout_ref)
    _ = cancel_timer(state.idle_timeout_ref)
    _ = close_port(state.port, state.os_pid)
    _ = remove_context_file(state.context_path)
    %{state | cleanup_done?: true, port: nil}
  end

  defp cancel_timer(ref) when is_reference(ref), do: Process.cancel_timer(ref)
  defp cancel_timer(_ref), do: :ok

  defp close_port(nil, _os_pid), do: :ok

  defp close_port(port, os_pid) do
    _ = maybe_term_os_process(os_pid)
    _ = Port.close(port)
    :ok
  rescue
    _ -> :ok
  end

  defp os_pid(port) do
    case Port.info(port, :os_pid) do
      {:os_pid, pid} when is_integer(pid) and pid > 0 -> pid
      _other -> nil
    end
  end

  defp maybe_term_os_process(pid) when is_integer(pid) and pid > 0 do
    _ = System.cmd("kill", ["-TERM", Integer.to_string(pid)], stderr_to_stdout: true)
    :ok
  rescue
    _ -> :ok
  end

  defp maybe_term_os_process(_pid), do: :ok

  # sobelow: context paths are generated under System.tmp_dir!/0 with
  # System.unique_integer/1, never from user-controlled input.
  @sobelow_skip ["Traversal.FileModule"]
  defp write_context_file(%Manifest{} = manifest, session, terminal_size) do
    path = Path.join(System.tmp_dir!(), "foglet-door-#{System.unique_integer([:positive])}.json")

    body =
      Jason.encode!(%{
        door_id: manifest.id,
        user_id: Map.get(session, :user_id),
        handle: Map.get(session, :handle),
        role: Map.get(session, :role),
        session_id: Map.get(session, :session_id),
        terminal_width: elem(terminal_size, 0),
        terminal_height: elem(terminal_size, 1)
      })

    case File.write(path, body, [:exclusive]) do
      :ok -> {:ok, path}
      {:error, reason} -> {:error, {:context_file, reason}}
    end
  end

  defp remove_context_file(nil), do: :ok

  # sobelow: remove only the runner-generated context path described above.
  @sobelow_skip ["Traversal.FileModule"]
  defp remove_context_file(path), do: File.rm(path)

  defp open_external_port(state) do
    {executable, args} = external_command(state.manifest)

    opts = [
      :binary,
      :exit_status,
      {:args, args},
      {:env, external_env(state)},
      {:cd, state.manifest.working_dir || File.cwd!()}
    ]

    port = Port.open({:spawn_executable, executable}, opts)
    os_pid = os_pid(port)
    {:ok, port, os_pid}
  rescue
    e -> {:error, e}
  end

  defp external_command(%Manifest{} = manifest) do
    if manifest.pty? do
      case System.find_executable("script") do
        nil -> {manifest.command, manifest.args}
        script -> {script, ["-qfec", shell_join([manifest.command | manifest.args]), "/dev/null"]}
      end
    else
      {manifest.command, manifest.args}
    end
  end

  defp external_env(state) do
    {cols, rows} = state.terminal_size

    Map.merge(state.manifest.env, %{
      "FOGLET_DOOR_ID" => state.manifest.id,
      "FOGLET_USER_ID" => to_env(Map.get(state.session, :user_id)),
      "FOGLET_USERNAME" => to_env(Map.get(state.session, :handle)),
      "FOGLET_SESSION_ID" => to_env(Map.get(state.session, :session_id)),
      "FOGLET_TERMINAL_WIDTH" => Integer.to_string(cols),
      "FOGLET_TERMINAL_HEIGHT" => Integer.to_string(rows),
      "FOGLET_DOOR_CONTEXT" => state.context_path
    })
    |> Enum.map(fn {key, value} -> {String.to_charlist(key), String.to_charlist(value)} end)
  end

  defp to_env(nil), do: ""
  defp to_env(value), do: to_string(value)

  defp shell_join(parts) do
    Enum.map_join(parts, " ", &shell_quote/1)
  end

  defp shell_quote(value) do
    value
    |> to_string()
    |> String.replace("'", "'\\''")
    |> then(&"'#{&1}'")
  end
end
