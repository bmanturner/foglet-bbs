defmodule Foglet.Doors.PTYAdapter do
  @moduledoc """
  Boundary for the Foglet-owned external door PTY helper protocol.

  `Foglet.Doors.Runner` owns the door session lifecycle. This module owns the
  helper executable path, framed protocol, resize/input controls, and the
  explicit degraded `script(1)` fallback used only when the helper is absent.
  """

  import Bitwise

  require Logger

  alias Foglet.Doors.Manifest

  @type backend :: :helper | :script_fallback | :plain
  @type t :: %__MODULE__{port: port(), os_pid: non_neg_integer() | nil, backend: backend()}

  defstruct [:port, :os_pid, :backend]

  @spec open(Manifest.t(), {pos_integer(), pos_integer()}, [{charlist(), charlist()}]) ::
          {:ok, t()} | {:error, term()}
  def open(%Manifest{pty?: true} = manifest, terminal_size, env) do
    case helper_path() do
      {:ok, helper} -> open_helper(helper, manifest, terminal_size, env)
      :unavailable -> open_script_fallback(manifest, env)
    end
  end

  def open(%Manifest{} = manifest, _terminal_size, env), do: open_plain(manifest, env)

  @spec input(t(), binary()) :: :ok | {:error, Exception.t()}
  def input(%__MODULE__{backend: :helper, port: port}, data),
    do: command(port, <<"D", data::binary>>)

  def input(%__MODULE__{port: port}, data), do: command(port, data)

  @spec resize(t(), {pos_integer(), pos_integer()}) :: :ok | {:error, Exception.t()}
  def resize(%__MODULE__{backend: :helper, port: port} = adapter, {cols, rows}) do
    case command(port, "R" <> Jason.encode!(%{cols: cols, rows: rows})) do
      :ok ->
        :ok

      {:error, reason} = error ->
        log_adapter_write_failure(adapter, :pty_adapter_resize_failed, reason)
        error
    end
  end

  def resize(_adapter, _size), do: :ok

  @spec terminate(t() | nil) :: :ok
  def terminate(%__MODULE__{backend: :helper, port: port}) do
    _ = Port.command(port, "T")
    :ok
  rescue
    _ -> :ok
  end

  def terminate(_adapter), do: :ok

  @spec decode_frame(binary()) ::
          {:output, binary()} | {:exit, integer() | nil} | {:error, term()} | :ignore
  def decode_frame(<<"O", data::binary>>), do: {:output, data}

  def decode_frame(<<"X", payload::binary>>) do
    case Jason.decode(payload) do
      {:ok, %{"status" => status}} when is_integer(status) ->
        {:exit, status}

      {:ok, %{"status" => nil, "signal" => signal}} when is_integer(signal) ->
        {:exit, 128 + signal}

      {:ok, _payload} ->
        {:exit, nil}

      {:error, reason} ->
        {:error, {:bad_exit_frame, reason}}
    end
  end

  def decode_frame(<<"E", payload::binary>>) do
    case Jason.decode(payload) do
      {:ok, payload} -> {:error, {:helper, payload}}
      {:error, reason} -> {:error, {:helper, {:bad_error_frame, reason}}}
    end
  end

  def decode_frame(_data), do: :ignore

  def backend(%__MODULE__{backend: backend}), do: backend

  defp command(port, data) do
    true = Port.command(port, data)
    :ok
  rescue
    e -> {:error, e}
  end

  defp log_adapter_write_failure(adapter, op, reason) do
    Logger.warning(fn ->
      "door PTY adapter event #{inspect(%{op: op, backend: adapter.backend, reason_class: reason_class(reason)})}"
    end)
  end

  defp reason_class(%module{}), do: inspect(module)

  defp open_helper(helper, manifest, {cols, rows}, env) do
    args = ["--cols", Integer.to_string(cols), "--rows", Integer.to_string(rows)]

    args =
      args ++ working_dir_args(manifest.working_dir) ++ ["--", manifest.command | manifest.args]

    opts = [
      :binary,
      :exit_status,
      {:packet, 4},
      {:args, args},
      {:env, env},
      {:cd, manifest.working_dir || File.cwd!()}
    ]

    port = Port.open({:spawn_executable, helper}, opts)
    {:ok, %__MODULE__{port: port, os_pid: os_pid(port), backend: :helper}}
  rescue
    e -> {:error, e}
  end

  defp open_plain(manifest, env) do
    opts = [
      :binary,
      :exit_status,
      {:args, manifest.args},
      {:env, env},
      {:cd, manifest.working_dir || File.cwd!()}
    ]

    port = Port.open({:spawn_executable, manifest.command}, opts)
    {:ok, %__MODULE__{port: port, os_pid: os_pid(port), backend: :plain}}
  rescue
    e -> {:error, e}
  end

  defp open_script_fallback(manifest, env) do
    case System.find_executable("script") do
      nil ->
        open_plain(manifest, env)

      script ->
        args = ["-qfec", shell_join([manifest.command | manifest.args]), "/dev/null"]

        opts = [
          :binary,
          :exit_status,
          {:args, args},
          {:env, env},
          {:cd, manifest.working_dir || File.cwd!()}
        ]

        port = Port.open({:spawn_executable, script}, opts)
        {:ok, %__MODULE__{port: port, os_pid: os_pid(port), backend: :script_fallback}}
    end
  rescue
    e -> {:error, e}
  end

  defp helper_path do
    path =
      Application.get_env(:foglet_bbs, :door_pty_helper_path) ||
        default_helper_path()

    if File.regular?(path) and executable?(path), do: {:ok, path}, else: :unavailable
  end

  defp default_helper_path do
    case :code.priv_dir(:foglet_bbs) do
      path when is_list(path) ->
        Path.join(List.to_string(path), "doors/pty/foglet_pty_adapter.py")

      {:error, _reason} ->
        Path.expand("priv/doors/pty/foglet_pty_adapter.py")
    end
  end

  defp executable?(path) do
    case File.stat(path) do
      {:ok, %{mode: mode}} -> (mode &&& 0o111) != 0
      _ -> false
    end
  end

  defp working_dir_args(nil), do: []
  defp working_dir_args(path), do: ["--cwd", path]

  defp os_pid(port) do
    case Port.info(port, :os_pid) do
      {:os_pid, pid} when is_integer(pid) and pid > 0 -> pid
      _other -> nil
    end
  end

  defp shell_join(parts), do: Enum.map_join(parts, " ", &shell_quote/1)

  defp shell_quote(value) do
    value
    |> to_string()
    |> String.replace("'", "'\\''")
    |> then(&"'#{&1}'")
  end
end
