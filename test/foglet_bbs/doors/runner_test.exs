defmodule Foglet.Doors.RunnerTest do
  use ExUnit.Case, async: false

  alias Foglet.Doors
  alias Foglet.Doors.Runner
  alias Foglet.Doors.Supervisor, as: DoorSupervisor

  defmodule CrashingDoor do
    @behaviour Foglet.Doors.Door

    @impl true
    def init(_context), do: raise("boom")
  end

  describe "native Elixir door runtime" do
    test "starts under the door supervisor, emits output, propagates resize, and exits normally" do
      {:ok, manifest} =
        manifest(%{
          id: "native-echo",
          display_name: "Native Echo",
          description: "demo",
          runtime: :native_elixir,
          module: Foglet.Doors.Demo.NativeEcho,
          timeout_ms: 5_000
        })

      {:ok, pid} =
        DoorSupervisor.start_runner(
          manifest: manifest,
          session: %{handle: "alice", user_id: "u1", session_id: "s1"},
          terminal_size: {100, 30},
          output: output_to(self()),
          owner: self()
        )

      assert_receive {:door_started, ^pid, "native-echo"}
      assert_receive {:door_output, output}
      assert IO.iodata_to_binary(output) =~ "Native Echo ready for alice (100x30)"

      Runner.resize(pid, {120, 40})
      assert_receive {:door_output, resize_output}
      assert IO.iodata_to_binary(resize_output) =~ "resized 120x40"
      assert %{last_resize: {120, 40}, status: :running} = Runner.snapshot(pid)

      ref = Process.monitor(pid)
      Runner.input(pid, "/quit\n")
      assert_receive {:door_output, quit_output}
      assert IO.iodata_to_binary(quit_output) =~ "Leaving Native Echo."
      assert_receive {:door_exited, ^pid, "native-echo", :normal, nil}
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}
    end

    test "built-in Native Hello remains attached until user exit input" do
      {:ok, manifest} =
        manifest(%{
          id: "native-hello",
          display_name: "Native Hello",
          description: "demo",
          runtime: :native_elixir,
          module: Foglet.Doors.Demo.NativeHello,
          timeout_ms: 5_000
        })

      {:ok, pid} =
        DoorSupervisor.start_runner(
          manifest: manifest,
          session: %{handle: "alice", user_id: "u1", session_id: "s1"},
          terminal_size: {100, 30},
          output: output_to(self()),
          owner: self()
        )

      assert_receive {:door_started, ^pid, "native-hello"}
      assert_receive {:door_output, output}
      assert IO.iodata_to_binary(output) =~ "Native Hello welcomes alice (100x30)"
      assert %{status: :running} = Runner.snapshot(pid)

      ref = Process.monitor(pid)
      Runner.input(pid, "hello\n")
      assert_receive {:door_output, echo_output}
      assert IO.iodata_to_binary(echo_output) =~ "native> hello"

      Runner.input(pid, "/quit\n")
      assert_receive {:door_output, quit_output}
      assert IO.iodata_to_binary(quit_output) =~ "Leaving Native Hello."
      assert_receive {:door_exited, ^pid, "native-hello", :normal, nil}
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}
    end

    test "native callback crash is reported as a crash exit" do
      {:ok, manifest} =
        manifest(%{
          id: "native-crash",
          display_name: "Native Crash",
          runtime: :native_elixir,
          module: __MODULE__.CrashingDoor,
          timeout_ms: 5_000
        })

      {:ok, pid} =
        DoorSupervisor.start_runner(manifest: manifest, output: output_to(self()), owner: self())

      ref = Process.monitor(pid)

      assert_receive {:door_exited, ^pid, "native-crash", :crash, nil}
      assert_receive {:DOWN, ^ref, :process, ^pid, {:door_crash, %RuntimeError{message: "boom"}}}
    end
  end

  describe "external door runtime" do
    test "launches a non-Elixir executable with minimal Foglet metadata env/context and exits normally" do
      {:ok, manifest} =
        manifest(%{
          id: "external-env",
          display_name: "External Env",
          runtime: :external_pty,
          command: external_demo_path(),
          working_dir: Path.expand("priv/doors/demo"),
          args: [],
          timeout_ms: 5_000,
          pty?: true
        })

      {:ok, pid} =
        DoorSupervisor.start_runner(
          manifest: manifest,
          session: %{handle: "alice", user_id: "u1", session_id: "s1"},
          terminal_size: {132, 40},
          output: output_to(self()),
          owner: self()
        )

      ref = Process.monitor(pid)
      assert_receive {:door_started, ^pid, "external-env"}
      assert_receive {:door_output, output}
      assert IO.iodata_to_binary(output) =~ "external-env:alice:132"
      assert %{status: :running} = Runner.snapshot(pid)

      Runner.input(pid, "hello\n")
      assert_receive {:door_output, echo_output}

      echo_output =
        echo_output
        |> IO.iodata_to_binary()
        |> then(fn output ->
          if output =~ "external> hello" do
            output
          else
            assert_receive {:door_output, more_echo_output}
            output <> IO.iodata_to_binary(more_echo_output)
          end
        end)

      assert echo_output =~ "external> hello"

      Runner.input(pid, "/quit\n")
      assert_receive {:door_output, quit_output}

      quit_output =
        quit_output
        |> IO.iodata_to_binary()
        |> then(fn output ->
          if output =~ "Leaving External Echo." do
            output
          else
            assert_receive {:door_output, more_quit_output}
            output <> IO.iodata_to_binary(more_quit_output)
          end
        end)

      assert quit_output =~ "Leaving External Echo."
      assert_receive {:door_exited, ^pid, "external-env", :normal, 0}
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}
    end

    test "external non-zero exit is reported as crash" do
      {:ok, manifest} =
        manifest(%{
          id: "external-crash",
          display_name: "External Crash",
          runtime: :external_pty,
          command: "/bin/sh",
          working_dir: "/tmp",
          args: ["-c", "exit 42"],
          timeout_ms: 5_000,
          pty?: false
        })

      {:ok, pid} =
        DoorSupervisor.start_runner(manifest: manifest, output: output_to(self()), owner: self())

      ref = Process.monitor(pid)

      assert_receive {:door_started, ^pid, "external-crash"}
      assert_receive {:door_exited, ^pid, "external-crash", :crash, 42}
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}
    end

    test "timeout terminates the external OS process and removes context file" do
      {:ok, manifest} =
        manifest(%{
          id: "external-timeout",
          display_name: "External Timeout",
          runtime: :external_pty,
          command: "/bin/sleep",
          working_dir: "/tmp",
          args: ["30"],
          timeout_ms: 100,
          pty?: false
        })

      {:ok, pid} =
        DoorSupervisor.start_runner(manifest: manifest, output: output_to(self()), owner: self())

      assert_receive {:door_started, ^pid, "external-timeout"}
      %{os_pid: os_pid} = Runner.snapshot(pid)
      ref = Process.monitor(pid)

      assert_receive {:door_exited, ^pid, "external-timeout", :timeout, nil}, 1_000
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}
      refute os_process_alive?(os_pid)
    end

    test "disconnect cleans up the external process tree owner" do
      {:ok, manifest} =
        manifest(%{
          id: "external-disconnect",
          display_name: "External Disconnect",
          runtime: :external_pty,
          command: "/bin/sleep",
          working_dir: "/tmp",
          args: ["30"],
          timeout_ms: 5_000,
          pty?: false
        })

      {:ok, pid} =
        DoorSupervisor.start_runner(manifest: manifest, output: output_to(self()), owner: self())

      assert_receive {:door_started, ^pid, "external-disconnect"}
      %{os_pid: os_pid} = Runner.snapshot(pid)
      ref = Process.monitor(pid)

      Runner.disconnect(pid)

      assert_receive {:door_exited, ^pid, "external-disconnect", :disconnect, nil}
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}
      refute os_process_alive?(os_pid)
    end

    test "resize is recorded and forwarded to the runtime owner for adapter-specific PTY handling" do
      {:ok, manifest} =
        manifest(%{
          id: "external-resize",
          display_name: "External Resize",
          runtime: :external_pty,
          command: "/bin/sleep",
          working_dir: "/tmp",
          args: ["30"],
          timeout_ms: 5_000,
          pty?: false
        })

      {:ok, pid} =
        DoorSupervisor.start_runner(manifest: manifest, output: output_to(self()), owner: self())

      assert_receive {:door_started, ^pid, "external-resize"}

      Runner.resize(pid, {90, 20})
      assert_receive {:door_resize, ^pid, "external-resize", {90, 20}}
      assert %{last_resize: {90, 20}} = Runner.snapshot(pid)

      Runner.disconnect(pid)
      assert_receive {:door_exited, ^pid, "external-resize", :disconnect, nil}
    end
  end

  defp manifest(attrs) do
    attrs =
      Map.merge(
        %{
          slug: Map.fetch!(attrs, :id),
          description: Map.get(attrs, :description, "runner test door"),
          visibility: :members,
          auth_scope: :site
        },
        attrs
      )

    Doors.validate_manifest(attrs)
  end

  defp output_to(test_pid), do: fn data -> send(test_pid, {:door_output, data}) end

  defp external_demo_path, do: Path.expand("priv/doors/demo/external_echo.sh")

  defp os_process_alive?(pid) when is_integer(pid) do
    case System.cmd("kill", ["-0", Integer.to_string(pid)], stderr_to_stdout: true) do
      {_, 0} -> true
      {_, _} -> false
    end
  end

  defp os_process_alive?(_pid), do: false
end
