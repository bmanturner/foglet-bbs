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

  alias Foglet.Doors.{Manifest, PTYAdapter}

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
    :pty_adapter,
    :os_pid,
    :context_path,
    :dropfile_paths,
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
    snapshot =
      Map.take(state, [:status, :exit_reason, :exit_status, :os_pid, :last_resize])
      |> Map.put(:pty_backend, pty_backend(state))

    {:reply, snapshot, state}
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

  def handle_cast({:input, data}, %{pty_adapter: %PTYAdapter{} = adapter} = state) do
    case PTYAdapter.input(adapter, data) do
      :ok ->
        :ok

      {:error, reason} ->
        log_privacy_safe(:error, state, :door_input_failed, %{reason_class: reason_class(reason)})
    end

    {:noreply, refresh_idle_timeout(state)}
  end

  def handle_cast({:input, data}, %{port: port} = state) when not is_nil(port) do
    case port_command(port, data) do
      :ok ->
        :ok

      {:error, reason} ->
        log_privacy_safe(:error, state, :door_input_failed, %{reason_class: reason_class(reason)})
    end

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

  def handle_cast({:resize, size}, %{pty_adapter: %PTYAdapter{} = adapter} = state) do
    case PTYAdapter.resize(adapter, size) do
      :ok ->
        :ok

      {:error, reason} ->
        log_privacy_safe(:error, state, :door_resize_failed, %{reason_class: reason_class(reason)})
    end

    notify_owner(state, {:door_resize, self(), state.manifest.id, size})
    {:noreply, %{state | terminal_size: size, last_resize: size}}
  end

  def handle_cast({:resize, size}, state) do
    # Plain-pipe/fallback external doors cannot receive an adapter-level
    # TIOCSWINSZ update. The runner still records the size and notifies the
    # owner for audit/terminal restoration.
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
      {:ok, %PTYAdapter{} = adapter} ->
        notify_owner(state, {:door_started, self(), state.manifest.id})

        {:noreply,
         %{
           state
           | port: adapter.port,
             pty_adapter: adapter,
             os_pid: adapter.os_pid,
             status: :running
         }}

      {:error, reason} ->
        log_door_failure(state, :launch_failed, reason, nil)
        {:stop, {:door_launch_failed, reason}, complete(state, {:error, reason}, nil)}
    end
  end

  def handle_info(:launch, %{manifest: %{runtime: :classic_dropfile}} = state) do
    case prepare_classic_dropfiles(state) do
      {:ok, state} ->
        case open_external_port(state) do
          {:ok, %PTYAdapter{} = adapter} ->
            notify_owner(state, {:door_started, self(), state.manifest.id})

            {:noreply,
             %{
               state
               | port: adapter.port,
                 pty_adapter: adapter,
                 os_pid: adapter.os_pid,
                 status: :running
             }}

          {:error, reason} ->
            log_door_failure(state, :launch_failed, reason, nil)
            {:stop, {:door_launch_failed, reason}, complete(state, {:error, reason}, nil)}
        end

      {:error, reason} ->
        log_door_failure(state, :dropfile_prepare_failed, reason, nil)
        {:stop, {:door_launch_failed, reason}, complete(state, {:error, reason}, nil)}
    end
  end

  def handle_info(:timeout, state) do
    {:stop, :normal, complete(state, :timeout, nil)}
  end

  def handle_info(:idle_timeout, state) do
    {:stop, :normal, complete(state, :idle_timeout, nil)}
  end

  def handle_info({_port, {:data, data}}, %{pty_adapter: %PTYAdapter{} = _adapter} = state) do
    case PTYAdapter.decode_frame(data) do
      {:output, output} ->
        emit(state, output)
        {:noreply, refresh_idle_timeout(state)}

      {:exit, status} ->
        reason = if status == 0, do: :normal, else: :crash
        {:stop, :normal, complete(state, reason, status)}

      {:error, {:bad_exit_frame, reason}} ->
        log_bad_exit_frame(state, data, reason)
        log_door_failure(state, :helper_failed, {:bad_exit_frame, reason}, nil)

        {:stop, {:door_helper_failed, {:bad_exit_frame, reason}},
         complete(state, {:error, {:bad_exit_frame, reason}}, nil)}

      {:error, reason} ->
        log_door_failure(state, :helper_failed, reason, nil)
        {:stop, {:door_helper_failed, reason}, complete(state, {:error, reason}, nil)}

      :ignore ->
        {:noreply, state}
    end
  end

  def handle_info({_port, {:data, data}}, state) do
    emit(state, data)
    {:noreply, refresh_idle_timeout(state)}
  end

  def handle_info(
        {port, {:exit_status, status}},
        %{port: port, pty_adapter: %PTYAdapter{backend: :helper}} = state
      ) do
    {:stop, {:door_helper_exit, status}, complete(state, :crash, status)}
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

  defp emit(%{output: output} = state, data) when is_function(output, 1) do
    _ = output.(data)
    :ok
  rescue
    e ->
      log_privacy_safe(:warning, state, :door_output_callback_failed, %{
        reason_class: reason_class(e)
      })

      :ok
  end

  defp notify_owner(%{owner: owner}, message) when is_pid(owner), do: send(owner, message)
  defp notify_owner(_state, _message), do: :ok

  defp pty_backend(%{pty_adapter: %PTYAdapter{} = adapter}), do: PTYAdapter.backend(adapter)
  defp pty_backend(_state), do: nil

  defp port_command(port, data) do
    true = Port.command(port, data)
    :ok
  rescue
    e -> {:error, e}
  end

  defp log_privacy_safe(level, state, op, details) do
    Logger.log(level, fn ->
      context =
        %{
          door_id: state.manifest.id,
          session_id: Map.get(state.session, :session_id),
          op: op
        }
        |> Map.merge(details)

      "door privacy-safe event #{inspect(context)}"
    end)

    :ok
  end

  defp log_bad_exit_frame(state, <<"X", payload::binary>>, reason) do
    log_privacy_safe(:warning, state, :door_bad_exit_frame, %{
      reason_class: reason_class(reason),
      payload_hex_prefix: hex_prefix(payload)
    })
  end

  defp log_bad_exit_frame(state, _data, reason) do
    log_privacy_safe(:warning, state, :door_bad_exit_frame, %{reason_class: reason_class(reason)})
  end

  defp hex_prefix(payload),
    do: payload |> binary_part(0, min(byte_size(payload), 16)) |> Base.encode16(case: :lower)

  defp reason_class(%module{}), do: inspect(module)
  defp reason_class(reason) when is_atom(reason), do: reason

  defp sanitize_reason(%Jason.DecodeError{}), do: Jason.DecodeError
  defp sanitize_reason(%module{}), do: module

  defp sanitize_reason(tuple) when is_tuple(tuple) do
    tuple
    |> Tuple.to_list()
    |> Enum.map(&sanitize_reason/1)
    |> List.to_tuple()
  end

  defp sanitize_reason(list) when is_list(list), do: Enum.map(list, &sanitize_reason/1)
  defp sanitize_reason(reason), do: reason

  defp log_cleanup_failure(state, op, reason) do
    log_privacy_safe(:warning, state, :door_cleanup_failed, %{
      cleanup_op: op,
      reason_class: reason_class(reason)
    })
  end

  defp log_door_exit(%{manifest: %Manifest{runtime: runtime}} = state, :normal, 0)
       when runtime in [:external_pty, :classic_dropfile],
       do: log_door_event(:info, state, :exited, :normal, 0)

  defp log_door_exit(%{manifest: %Manifest{runtime: runtime}} = state, :disconnect, status)
       when runtime in [:external_pty, :classic_dropfile],
       do: log_door_event(:info, state, :exited, :disconnect, status)

  defp log_door_exit(%{manifest: %Manifest{runtime: runtime}} = state, reason, status)
       when runtime in [:external_pty, :classic_dropfile],
       do: log_door_failure(state, :exited, reason, status)

  defp log_door_exit(_state, _reason, _status), do: :ok

  defp log_door_failure(%{manifest: %Manifest{runtime: runtime}} = state, event, reason, status)
       when runtime in [:external_pty, :classic_dropfile],
       do: log_door_event(:error, state, event, reason, status)

  defp log_door_failure(_state, _event, _reason, _status), do: :ok

  defp log_door_event(level, state, event, reason, status) do
    Logger.log(level, fn ->
      "door runtime event #{inspect(door_log_context(state, event, reason, status))}"
    end)

    :ok
  end

  defp door_log_context(state, event, reason, status) do
    %{
      door_id: state.manifest.id,
      runtime: state.manifest.runtime,
      event: event,
      command: state.manifest.command,
      cwd: state.manifest.working_dir,
      exit_status: status,
      reason: inspect(sanitize_reason(reason)),
      pty_backend: pty_backend(state),
      os_pid: state.os_pid
    }
  end

  defp complete(state, reason, status) do
    log_door_exit(state, reason, status)

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
    _ = cancel_timer(state.timeout_ref, state, :timeout_timer)
    _ = cancel_timer(state.idle_timeout_ref, state, :idle_timeout_timer)
    _ = close_port(state.port, state.os_pid, state.pty_adapter, state)
    _ = remove_dropfiles(state.dropfile_paths, state)
    _ = remove_context_file(state.context_path, state)
    %{state | cleanup_done?: true, port: nil, pty_adapter: nil, dropfile_paths: %{}}
  end

  defp cancel_timer(ref, _state, _op) when is_reference(ref), do: Process.cancel_timer(ref)
  defp cancel_timer(_ref, _state, _op), do: :ok

  defp close_port(nil, _os_pid, _adapter, _state), do: :ok

  defp close_port(port, os_pid, adapter, state) do
    _ = terminate_adapter(adapter, state)
    _ = maybe_term_os_process(os_pid, state)
    _ = close_owned_port(port, state)
    :ok
  end

  defp terminate_adapter(adapter, state) do
    _ = PTYAdapter.terminate(adapter)
    :ok
  rescue
    e ->
      log_cleanup_failure(state, :pty_adapter_terminate, e)
      :ok
  end

  defp close_owned_port(port, state) do
    if Port.info(port) do
      _ = Port.close(port)
    end

    :ok
  rescue
    e ->
      log_cleanup_failure(state, :port_close, e)
      :ok
  end

  defp maybe_term_os_process(pid, state) when is_integer(pid) and pid > 0 do
    _ = System.cmd("kill", ["-TERM", Integer.to_string(pid)], stderr_to_stdout: true)
    :ok
  rescue
    e ->
      log_cleanup_failure(state, :os_process_terminate, e)
      :ok
  end

  defp maybe_term_os_process(_pid, _state), do: :ok

  # sobelow: context paths are generated under System.tmp_dir!/0 with
  # cryptographic random bytes, never from user-controlled input.
  @sobelow_skip ["Traversal.FileModule"]
  defp write_context_file(%Manifest{} = manifest, session, terminal_size) do
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

    write_context_file(body, 3)
  end

  # sobelow: path is generated here under System.tmp_dir!/0 with
  # cryptographic random bytes and written with :exclusive to avoid races.
  @sobelow_skip ["Traversal.FileModule"]
  defp write_context_file(body, attempts) when attempts > 0 do
    nonce = Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)
    path = Path.join(System.tmp_dir!(), "foglet-door-#{nonce}.json")

    case File.write(path, body, [:exclusive]) do
      :ok -> {:ok, path}
      {:error, :eexist} -> write_context_file(body, attempts - 1)
      {:error, reason} -> {:error, {:context_file, reason}}
    end
  end

  defp write_context_file(_body, 0), do: {:error, {:context_file, :eexist}}

  # sobelow: dropfile paths are generated by Foglet.Doors.write_dropfiles/3 from
  # fixed filenames under the validated manifest working directory.
  @sobelow_skip ["Traversal.FileModule"]
  defp remove_dropfiles(paths, state) when is_map(paths) do
    Enum.each(paths, fn {_format, path} ->
      case File.rm(path) do
        :ok -> :ok
        {:error, :enoent} -> :ok
        {:error, reason} -> log_cleanup_failure(state, :dropfile_remove, reason)
      end
    end)

    :ok
  rescue
    e ->
      log_cleanup_failure(state, :dropfile_remove, e)
      :ok
  end

  defp remove_dropfiles(_paths, _state), do: :ok

  defp remove_context_file(nil, _state), do: :ok

  # sobelow: remove only the runner-generated context path described above.
  @sobelow_skip ["Traversal.FileModule"]
  defp remove_context_file(path, state) do
    case File.rm(path) do
      :ok ->
        :ok

      {:error, :enoent} ->
        :ok

      {:error, reason} ->
        log_cleanup_failure(state, :context_file_remove, reason)
        :ok
    end
  rescue
    e ->
      log_cleanup_failure(state, :context_file_remove, e)
      :ok
  end

  defp prepare_classic_dropfiles(state) do
    attrs = %{
      user: state.session,
      session: Map.put(state.session, :terminal_size, state.terminal_size)
    }

    case Foglet.Doors.write_dropfiles(
           state.manifest.dropfile_formats,
           attrs,
           state.manifest.working_dir
         ) do
      {:ok, paths} -> {:ok, %{state | dropfile_paths: paths}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp open_external_port(state) do
    PTYAdapter.open(state.manifest, state.terminal_size, external_env(state))
  end

  defp external_env(state) do
    {cols, rows} = state.terminal_size

    Foglet.Doors.adapter_env(
      state.manifest,
      state.session,
      {cols, rows},
      state.context_path,
      state.dropfile_paths || %{}
    )
    |> Enum.map(fn {key, value} -> {String.to_charlist(key), String.to_charlist(value)} end)
  end
end
