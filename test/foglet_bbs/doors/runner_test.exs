defmodule Foglet.Doors.RunnerTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  @event_timeout 1_000
  @former_demo_timeout_ms 5_000

  alias Foglet.Doors
  alias Foglet.Doors.PTYAdapter
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

    test "built-in Native Hello survives beyond the former five-second demo timeout" do
      {:ok, manifest} =
        manifest(%{
          id: "native-hello",
          display_name: "Native Hello",
          description: "demo",
          runtime: :native_elixir,
          module: Foglet.Doors.Demo.NativeHello,
          timeout_ms: @former_demo_timeout_ms + 2_000
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

      refute_receive {:door_exited, ^pid, "native-hello", :timeout, nil},
                     @former_demo_timeout_ms + 100

      assert %{status: :running} = Runner.snapshot(pid)

      ref = Process.monitor(pid)
      Runner.input(pid, "/quit\n")
      assert_receive {:door_output, quit_output}
      assert IO.iodata_to_binary(quit_output) =~ "Leaving Native Hello."
      assert_receive {:door_exited, ^pid, "native-hello", :normal, nil}
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}
    end

    test "absolute timeout stops a native door even when idle timeout is disabled" do
      {:ok, manifest} =
        manifest(%{
          id: "native-timeout",
          display_name: "Native Timeout",
          runtime: :native_elixir,
          module: Foglet.Doors.Demo.NativeHello,
          timeout_ms: 100,
          idle_timeout_ms: nil
        })

      {:ok, pid} =
        DoorSupervisor.start_runner(manifest: manifest, output: output_to(self()), owner: self())

      assert_receive {:door_started, ^pid, "native-timeout"}
      ref = Process.monitor(pid)
      assert_receive {:door_exited, ^pid, "native-timeout", :timeout, nil}, @event_timeout
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, @event_timeout
    end

    test "idle timeout refreshes on native input and expires separately from absolute timeout" do
      {:ok, manifest} =
        manifest(%{
          id: "native-idle-timeout",
          display_name: "Native Idle Timeout",
          runtime: :native_elixir,
          module: Foglet.Doors.Demo.NativeHello,
          timeout_ms: 5_000,
          idle_timeout_ms: 200
        })

      {:ok, pid} =
        DoorSupervisor.start_runner(manifest: manifest, output: output_to(self()), owner: self())

      assert_receive {:door_started, ^pid, "native-idle-timeout"}
      assert_receive {:door_output, _output}

      Runner.input(pid, "still here\n")
      assert_receive {:door_output, echo_output}, @event_timeout
      assert IO.iodata_to_binary(echo_output) =~ "native> still here"
      refute_receive {:door_exited, ^pid, "native-idle-timeout", :idle_timeout, nil}, 100

      ref = Process.monitor(pid)

      assert_receive {:door_exited, ^pid, "native-idle-timeout", :idle_timeout, nil},
                     @event_timeout

      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, @event_timeout
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
      assert_door_output_contains("external-env:alice:132")
      assert %{status: :running, pty_backend: :helper} = Runner.snapshot(pid)

      # SSH clients send Enter as carriage return. The helper must preserve the
      # child PTY's default CR->NL translation so shell/readline-style doors see
      # a complete line.
      Runner.input(pid, "hello\r")
      assert_door_output_contains("external> hello")

      Runner.input(pid, "/quit\r")
      assert_door_output_contains("Leaving External Echo.")

      assert_receive {:door_exited, ^pid, "external-env", :normal, 0}, @event_timeout
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, @event_timeout
    end

    test "external helper-backed demo stays alive beyond former five-second cutoff while awaiting input" do
      {:ok, manifest} =
        manifest(%{
          id: "external-echo-survival",
          display_name: "External Echo Survival",
          runtime: :external_pty,
          command: external_demo_path(),
          working_dir: Path.expand("priv/doors/demo"),
          args: [],
          timeout_ms: @former_demo_timeout_ms + 2_000,
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

      assert_receive {:door_started, ^pid, "external-echo-survival"}
      assert_door_output_contains("external-echo-survival:alice:132")
      assert %{status: :running, pty_backend: :helper} = Runner.snapshot(pid)

      refute_receive {:door_exited, ^pid, "external-echo-survival", :timeout, nil},
                     @former_demo_timeout_ms + 100

      assert %{status: :running} = Runner.snapshot(pid)

      ref = Process.monitor(pid)
      Runner.input(pid, "/quit\r")
      assert_door_output_contains("Leaving External Echo.")
      assert_receive {:door_exited, ^pid, "external-echo-survival", :normal, 0}, @event_timeout
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, @event_timeout
    end

    test "idle timeout refreshes on external helper output and input before expiring" do
      {:ok, manifest} =
        manifest(%{
          id: "external-idle-timeout",
          display_name: "External Idle Timeout",
          runtime: :external_pty,
          command: external_demo_path(),
          working_dir: Path.expand("priv/doors/demo"),
          args: [],
          timeout_ms: 5_000,
          idle_timeout_ms: 500,
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

      assert_receive {:door_started, ^pid, "external-idle-timeout"}
      assert_door_output_contains("external-idle-timeout:alice:132")

      Runner.input(pid, "ping\r")
      assert_door_output_contains("external> ping")
      refute_receive {:door_exited, ^pid, "external-idle-timeout", :idle_timeout, nil}, 100

      ref = Process.monitor(pid)

      assert_receive {:door_exited, ^pid, "external-idle-timeout", :idle_timeout, nil},
                     @event_timeout

      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, @event_timeout
    end

    test "operator stop cleans up the external process tree owner" do
      {:ok, manifest} =
        manifest(%{
          id: "external-operator-stop",
          display_name: "External Operator Stop",
          runtime: :external_pty,
          command: "/bin/sleep",
          working_dir: "/tmp",
          args: ["30"],
          timeout_ms: 5_000,
          pty?: false
        })

      {:ok, pid} =
        DoorSupervisor.start_runner(manifest: manifest, output: output_to(self()), owner: self())

      assert_receive {:door_started, ^pid, "external-operator-stop"}
      %{os_pid: os_pid} = Runner.snapshot(pid)
      ref = Process.monitor(pid)

      Runner.stop(pid, :operator_stop)

      assert_receive {:door_exited, ^pid, "external-operator-stop", :operator_stop, nil}
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}
      refute os_process_alive?(os_pid)
    end

    test "launches the Python context example and returns cleanly" do
      {:ok, manifest} =
        manifest(%{
          id: "python-context",
          display_name: "Python Context",
          runtime: :external_pty,
          command: python_context_demo_path(),
          working_dir: Path.expand("priv/doors/demo"),
          args: [],
          timeout_ms: 5_000,
          pty?: true
        })

      {:ok, pid} =
        DoorSupervisor.start_runner(
          manifest: manifest,
          session: %{handle: "alice", user_id: "u1", session_id: "s1"},
          terminal_size: {90, 25},
          output: output_to(self()),
          owner: self()
        )

      ref = Process.monitor(pid)
      assert_receive {:door_started, ^pid, "python-context"}
      assert_door_output_contains("python-context-demo:alice:90x25")

      Runner.input(pid, "/quit\n")
      assert_door_output_contains("Leaving Python Context Demo.")
      assert_receive {:door_exited, ^pid, "python-context", :normal, 0}, @event_timeout
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, @event_timeout
    end

    test "classic dropfile runtime writes requested dropfiles in an isolated cwd and cleans metadata" do
      working_dir = Path.expand("priv/doors/demo")

      original_dropfiles = %{
        "CHAIN.TXT" => "pre-existing chain",
        "DOOR.SYS" => "pre-existing door",
        "DORINFO.DEF" => "pre-existing dorinfo"
      }

      Enum.each(original_dropfiles, fn {filename, body} ->
        File.write!(Path.join(working_dir, filename), body)
      end)

      on_exit(fn ->
        Enum.each(Map.keys(original_dropfiles), &File.rm(Path.join(working_dir, &1)))
      end)

      {:ok, manifest} =
        manifest(%{
          id: "classic-demo",
          display_name: "Classic Demo",
          runtime: :classic_dropfile,
          command: classic_dropfile_demo_path(),
          working_dir: working_dir,
          dropfile_formats: [:chain_txt, :door_sys, :dorinfo_def],
          args: [],
          timeout_ms: 5_000,
          pty?: true
        })

      {:ok, pid} =
        DoorSupervisor.start_runner(
          manifest: manifest,
          session: %{
            handle: "alice",
            real_name: "Alice Liddell",
            user_id: "u1",
            role: :user,
            session_id: "s1"
          },
          terminal_size: {100, 30},
          output: output_to(self()),
          owner: self()
        )

      ref = Process.monitor(pid)
      assert_receive {:door_started, ^pid, "classic-demo"}
      assert_door_output_contains("classic-dropfile-demo:DOOR.SYS:alice")

      assert %{
               dropfile_working_dir: dropfile_working_dir,
               dropfile_paths: %{door_sys: door_sys_path}
             } = Runner.snapshot(pid)

      assert dropfile_working_dir != working_dir
      assert Path.dirname(door_sys_path) == dropfile_working_dir
      assert File.exists?(door_sys_path)

      Enum.each(original_dropfiles, fn {filename, body} ->
        assert File.read!(Path.join(working_dir, filename)) == body
      end)

      Runner.input(pid, "/quit\n")
      assert_door_output_contains("Leaving Classic Dropfile Demo.")
      assert_receive {:door_exited, ^pid, "classic-demo", :normal, 0}, @event_timeout
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, @event_timeout

      refute File.exists?(dropfile_working_dir)

      Enum.each(original_dropfiles, fn {filename, body} ->
        assert File.read!(Path.join(working_dir, filename)) == body
      end)
    end

    test "concurrent classic runners use separate dropfile directories and independent cleanup" do
      working_dir = Path.expand("priv/doors/demo")

      {:ok, manifest} =
        manifest(%{
          id: "classic-concurrent",
          display_name: "Classic Concurrent",
          runtime: :classic_dropfile,
          command: "/bin/sleep",
          working_dir: working_dir,
          dropfile_formats: [:chain_txt, :door_sys, :dorinfo_def],
          args: ["30"],
          timeout_ms: 5_000,
          pty?: false
        })

      {:ok, alice_pid} =
        DoorSupervisor.start_runner(
          manifest: manifest,
          session: %{handle: "alice", user_id: "u1", role: :user, session_id: "session-alice"},
          terminal_size: {100, 30},
          output: output_to(self()),
          owner: self()
        )

      {:ok, bob_pid} =
        DoorSupervisor.start_runner(
          manifest: manifest,
          session: %{handle: "bob", user_id: "u2", role: :mod, session_id: "session-bob"},
          terminal_size: {90, 25},
          output: output_to(self()),
          owner: self()
        )

      assert_receive {:door_started, ^alice_pid, "classic-concurrent"}
      assert_receive {:door_started, ^bob_pid, "classic-concurrent"}

      %{dropfile_working_dir: alice_dir, dropfile_paths: alice_paths} = Runner.snapshot(alice_pid)
      %{dropfile_working_dir: bob_dir, dropfile_paths: bob_paths} = Runner.snapshot(bob_pid)

      assert alice_dir != bob_dir
      assert Path.dirname(alice_paths.door_sys) == alice_dir
      assert Path.dirname(bob_paths.door_sys) == bob_dir
      assert File.exists?(alice_paths.door_sys)
      assert File.exists?(bob_paths.door_sys)

      alice_ref = Process.monitor(alice_pid)
      bob_ref = Process.monitor(bob_pid)

      Runner.disconnect(alice_pid)
      assert_receive {:door_exited, ^alice_pid, "classic-concurrent", :disconnect, nil}
      assert_receive {:DOWN, ^alice_ref, :process, ^alice_pid, :normal}

      refute File.exists?(alice_dir)
      assert File.exists?(bob_paths.door_sys)
      assert File.read!(bob_paths.door_sys) =~ "session-bob"
      refute File.read!(bob_paths.door_sys) =~ "session-alice"

      Runner.disconnect(bob_pid)
      assert_receive {:door_exited, ^bob_pid, "classic-concurrent", :disconnect, nil}
      assert_receive {:DOWN, ^bob_ref, :process, ^bob_pid, :normal}
      refute File.exists?(bob_dir)
    end

    test "helper-backed PTY hides inherited env while keeping Foglet and manifest env" do
      previous_secret = System.get_env("FOGLET_TEST_INHERITED_SECRET")
      System.put_env("FOGLET_TEST_INHERITED_SECRET", "do-not-leak")

      on_exit(fn ->
        restore_env("FOGLET_TEST_INHERITED_SECRET", previous_secret)
      end)

      {:ok, manifest} =
        manifest(%{
          id: "external-env-sanitized-helper",
          display_name: "External Env Sanitized Helper",
          runtime: :external_pty,
          command: "/bin/sh",
          working_dir: System.tmp_dir!(),
          args: ["-c", env_probe_command()],
          env: %{"FOGLET_TEST_MANIFEST_VALUE" => "manifest-ok"},
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
      assert_receive {:door_started, ^pid, "external-env-sanitized-helper"}
      assert %{pty_backend: :helper} = Runner.snapshot(pid)
      assert_door_output_contains("env-probe:absent:alice:manifest-ok:present")

      assert_receive {:door_exited, ^pid, "external-env-sanitized-helper", :normal, 0},
                     @event_timeout

      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, @event_timeout
    end

    test "plain and script fallback launches hide inherited env while keeping Foglet env" do
      previous_secret = System.get_env("FOGLET_TEST_INHERITED_SECRET")
      previous_helper = Application.get_env(:foglet_bbs, :door_pty_helper_path)
      System.put_env("FOGLET_TEST_INHERITED_SECRET", "do-not-leak")
      Application.put_env(:foglet_bbs, :door_pty_helper_path, "/tmp/foglet-missing-pty-helper")

      on_exit(fn ->
        restore_env("FOGLET_TEST_INHERITED_SECRET", previous_secret)
        restore_helper_path(previous_helper)
      end)

      for {door_id, pty?} <- [
            {"external-env-sanitized-plain", false},
            {"external-env-sanitized-fallback", true}
          ] do
        {:ok, manifest} =
          manifest(%{
            id: door_id,
            display_name: door_id,
            runtime: :external_pty,
            command: "/bin/sh",
            working_dir: System.tmp_dir!(),
            args: ["-c", env_probe_command()],
            env: %{
              "FOGLET_TEST_MANIFEST_VALUE" => "manifest-ok"
            },
            timeout_ms: 5_000,
            pty?: pty?
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
        assert_receive {:door_started, ^pid, ^door_id}
        assert_door_output_contains("env-probe:absent:alice:manifest-ok:present")
        assert_receive {:door_exited, ^pid, ^door_id, :normal, 0}, @event_timeout
        assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, @event_timeout
      end
    end

    test "external non-zero exit is reported as crash with actionable launch context in logs" do
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

      log =
        capture_log(fn ->
          {:ok, pid} =
            DoorSupervisor.start_runner(
              manifest: manifest,
              output: output_to(self()),
              owner: self()
            )

          ref = Process.monitor(pid)

          assert_receive {:door_started, ^pid, "external-crash"}
          assert_receive {:door_exited, ^pid, "external-crash", :crash, 42}
          assert_receive {:DOWN, ^ref, :process, ^pid, :normal}
        end)

      assert log =~ "door runtime event"
      assert log =~ "external-crash"
      assert log =~ "runtime: :external_pty"
      assert log =~ "command: \"/bin/sh\""
      assert log =~ "cwd: \"/tmp\""
      assert log =~ "exit_status: 42"
      refute log =~ "DATABASE_URL"
    end

    test "external launch failure exits runner cleanly and logs redacted launch context" do
      missing_command = Path.join(System.tmp_dir!(), "foglet-missing-door-command")

      {:ok, manifest} =
        manifest(%{
          id: "external-missing",
          display_name: "External Missing",
          runtime: :external_pty,
          command: missing_command,
          working_dir: System.tmp_dir!(),
          args: [],
          timeout_ms: 5_000,
          pty?: false
        })

      log =
        capture_log(fn ->
          {:ok, pid} =
            DoorSupervisor.start_runner(
              manifest: manifest,
              output: output_to(self()),
              owner: self()
            )

          ref = Process.monitor(pid)

          assert_receive {:door_exited, ^pid, "external-missing", {:error, _reason}, nil}
          assert_receive {:DOWN, ^ref, :process, ^pid, {:door_launch_failed, _reason}}
        end)

      assert log =~ "door runtime event"
      assert log =~ "event: :launch_failed"
      assert log =~ "external-missing"
      assert log =~ missing_command
      assert log =~ "runtime: :external_pty"
      refute log =~ "DATABASE_URL"
    end

    test "sandbox-required door fails closed when helper is unavailable" do
      previous = Application.get_env(:foglet_bbs, :door_pty_helper_path)
      Application.put_env(:foglet_bbs, :door_pty_helper_path, "/tmp/foglet-missing-pty-helper")

      on_exit(fn ->
        if previous do
          Application.put_env(:foglet_bbs, :door_pty_helper_path, previous)
        else
          Application.delete_env(:foglet_bbs, :door_pty_helper_path)
        end
      end)

      {:ok, manifest} =
        manifest(%{
          id: "external-sandbox-missing-helper",
          display_name: "External Sandbox Missing Helper",
          runtime: :external_pty,
          command: "/usr/bin/env",
          working_dir: "/tmp",
          args: [],
          timeout_ms: 5_000,
          pty?: true,
          sandbox: same_user_sandbox()
        })

      {:ok, pid} =
        DoorSupervisor.start_runner(manifest: manifest, output: output_to(self()), owner: self())

      ref = Process.monitor(pid)

      assert_receive {:door_exited, ^pid, "external-sandbox-missing-helper",
                      {:error, {:sandbox_unavailable, :pty_helper_missing}}, nil}

      assert_receive {:DOWN, ^ref, :process, ^pid,
                      {:door_launch_failed, {:sandbox_unavailable, :pty_helper_missing}}}
    end

    test "sandbox-required launch fails closed when configured user is unavailable" do
      {:ok, manifest} =
        manifest(%{
          id: "external-sandbox-missing-user",
          display_name: "External Sandbox Missing User",
          runtime: :external_pty,
          command: "/usr/bin/env",
          working_dir: "/tmp",
          args: [],
          timeout_ms: 5_000,
          pty?: true,
          sandbox: %{mode: :restricted_user_process_group, user: "foglet-missing-door-user"}
        })

      {:ok, pid} =
        DoorSupervisor.start_runner(manifest: manifest, output: output_to(self()), owner: self())

      ref = Process.monitor(pid)

      assert_receive {:door_exited, ^pid, "external-sandbox-missing-user",
                      {:error, {:helper, %{"reason" => "sandbox_user_not_found"}}}, nil}

      assert_receive {:DOWN, ^ref, :process, ^pid,
                      {:door_helper_failed, {:helper, %{"reason" => "sandbox_user_not_found"}}}}
    end

    test "helper sandbox reports group setup failure and does not execute door command" do
      previous = Application.get_env(:foglet_bbs, :door_pty_helper_path)

      marker =
        Path.join(
          System.tmp_dir!(),
          "foglet-sandbox-executed-#{System.unique_integer([:positive])}"
        )

      helper = forced_group_failure_helper()
      Application.put_env(:foglet_bbs, :door_pty_helper_path, helper)

      on_exit(fn ->
        File.rm(marker)
        File.rm(helper)
        restore_helper_path(previous)
      end)

      {:ok, manifest} =
        manifest(%{
          id: "external-sandbox-group-failure",
          display_name: "External Sandbox Group Failure",
          runtime: :external_pty,
          command: "/bin/sh",
          working_dir: "/tmp",
          args: ["-c", "echo EXECUTED > #{marker}"],
          timeout_ms: 5_000,
          pty?: true,
          sandbox: same_user_sandbox()
        })

      {:ok, pid} =
        DoorSupervisor.start_runner(manifest: manifest, output: output_to(self()), owner: self())

      ref = Process.monitor(pid)
      assert_receive {:door_started, ^pid, "external-sandbox-group-failure"}

      assert_receive {:door_exited, ^pid, "external-sandbox-group-failure",
                      {:error, {:helper, %{"reason" => "sandbox_group_setup_failed"}}}, nil},
                     @event_timeout

      assert_receive {:DOWN, ^ref, :process, ^pid,
                      {:door_helper_failed,
                       {:helper, %{"reason" => "sandbox_group_setup_failed"}}}},
                     @event_timeout

      refute File.exists?(marker)
    end

    test "helper sandbox passes only minimal Foglet env and no app secrets" do
      previous_secret = System.get_env("SECRET_KEY_BASE")
      previous_paperclip = System.get_env("PAPERCLIP_API_KEY")
      System.put_env("SECRET_KEY_BASE", "door-secret-key-base")
      System.put_env("PAPERCLIP_API_KEY", "door-paperclip-secret")

      on_exit(fn ->
        restore_env("SECRET_KEY_BASE", previous_secret)
        restore_env("PAPERCLIP_API_KEY", previous_paperclip)
      end)

      {:ok, manifest} =
        manifest(%{
          id: "external-env-sandbox",
          display_name: "External Env Sandbox",
          runtime: :external_pty,
          command: "/usr/bin/env",
          working_dir: "/tmp",
          args: [],
          timeout_ms: 5_000,
          pty?: true,
          sandbox: same_user_sandbox()
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
      assert_receive {:door_started, ^pid, "external-env-sandbox"}
      output = assert_door_output_contains("FOGLET_USERNAME=alice")
      assert_receive {:door_exited, ^pid, "external-env-sandbox", :normal, 0}, @event_timeout
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, @event_timeout

      refute output =~ "SECRET_KEY_BASE"
      refute output =~ "door-secret-key-base"
      refute output =~ "PAPERCLIP_API_KEY"
      refute output =~ "door-paperclip-secret"
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

    test "sandboxed helper cleans up child and grandchild process group on timeout, crash, and disconnect" do
      for {id, trigger, expected_reason, expected_status} <- [
            {"external-tree-timeout", :timeout, :timeout, nil},
            {"external-tree-crash", :crash, :crash, 42},
            {"external-tree-disconnect", :disconnect, :disconnect, nil}
          ] do
        pidfile = Path.join(System.tmp_dir!(), "#{id}-#{System.unique_integer([:positive])}.pid")

        command =
          case trigger do
            :crash ->
              "(sh -c 'trap \"exit 0\" TERM; while :; do sleep 1; done' & echo $! > #{pidfile}; exit 42)"

            _other ->
              "sh -c 'trap \"exit 0\" TERM; while :; do sleep 1; done' & echo $! > #{pidfile}; wait"
          end

        {:ok, manifest} =
          manifest(%{
            id: id,
            display_name: id,
            runtime: :external_pty,
            command: "/bin/sh",
            working_dir: "/tmp",
            args: ["-c", command],
            timeout_ms: if(trigger == :timeout, do: 100, else: 5_000),
            pty?: true,
            sandbox: same_user_sandbox()
          })

        {:ok, runner_pid} =
          DoorSupervisor.start_runner(
            manifest: manifest,
            output: output_to(self()),
            owner: self()
          )

        assert_receive {:door_started, ^runner_pid, ^id}
        child_pid = wait_for_pidfile(pidfile)
        ref = Process.monitor(runner_pid)

        if trigger == :disconnect, do: Runner.disconnect(runner_pid)

        assert_receive {:door_exited, ^runner_pid, ^id, ^expected_reason, ^expected_status}, 1_500
        assert_receive {:DOWN, ^ref, :process, ^runner_pid, _reason}, 1_500
        refute eventually_os_process_alive?(child_pid)
        File.rm(pidfile)
      end
    end

    test "helper exit cleanup is bounded when a grandchild keeps writing to the PTY" do
      id = "external-tree-exit-writer"
      pidfile = Path.join(System.tmp_dir!(), "#{id}-#{System.unique_integer([:positive])}.pid")

      command = """
      printf 'final-before-exit\n'
      sh -c 'trap \"exit 0\" TERM; while :; do printf \"writer-chunk-0123456789\\n\"; done' &
      echo $! > #{pidfile}
      exit 0
      """

      {:ok, manifest} =
        manifest(%{
          id: id,
          display_name: id,
          runtime: :external_pty,
          command: "/bin/sh",
          working_dir: "/tmp",
          args: ["-c", command],
          timeout_ms: 5_000,
          pty?: true,
          sandbox: same_user_sandbox()
        })

      {:ok, runner_pid} =
        DoorSupervisor.start_runner(
          manifest: manifest,
          output: output_to(self()),
          owner: self()
        )

      assert_receive {:door_started, ^runner_pid, ^id}
      writer_pid = wait_for_pidfile(pidfile)
      ref = Process.monitor(runner_pid)

      assert_door_output_contains("final-before-exit")
      assert_receive {:door_exited, ^runner_pid, ^id, :normal, 0}, 1_000
      assert_receive {:DOWN, ^ref, :process, ^runner_pid, :normal}, 1_000
      refute eventually_os_process_alive?(writer_pid)
      File.rm(pidfile)
    end

    test "helper-backed PTY propagates resize to a full-screen child" do
      {:ok, manifest} =
        manifest(%{
          id: "external-resize",
          display_name: "External Resize",
          runtime: :external_pty,
          command: fullscreen_probe_path(),
          working_dir: Path.expand("priv/doors/demo"),
          args: [],
          timeout_ms: 5_000,
          pty?: true
        })

      {:ok, pid} =
        DoorSupervisor.start_runner(manifest: manifest, output: output_to(self()), owner: self())

      assert_receive {:door_started, ^pid, "external-resize"}
      assert_door_output_contains("fullscreen-probe:80x24")
      assert %{pty_backend: :helper} = Runner.snapshot(pid)

      Runner.resize(pid, {90, 20})
      assert_receive {:door_resize, ^pid, "external-resize", {90, 20}}
      assert %{last_resize: {90, 20}} = Runner.snapshot(pid)
      assert_door_output_contains("resize:90x20")

      ref = Process.monitor(pid)
      Runner.input(pid, "/quit\n")
      assert_door_output_contains("leaving-fullscreen")
      assert_receive {:door_exited, ^pid, "external-resize", :normal, 0}, @event_timeout
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, @event_timeout
    end

    test "missing helper degrades to script fallback for PTY manifests" do
      previous = Application.get_env(:foglet_bbs, :door_pty_helper_path)
      Application.put_env(:foglet_bbs, :door_pty_helper_path, "/tmp/foglet-missing-pty-helper")

      on_exit(fn ->
        if previous do
          Application.put_env(:foglet_bbs, :door_pty_helper_path, previous)
        else
          Application.delete_env(:foglet_bbs, :door_pty_helper_path)
        end
      end)

      {:ok, manifest} =
        manifest(%{
          id: "external-fallback",
          display_name: "External Fallback",
          runtime: :external_pty,
          command: external_demo_path(),
          working_dir: Path.expand("priv/doors/demo"),
          args: [],
          timeout_ms: 5_000,
          pty?: true
        })

      {:ok, pid} =
        DoorSupervisor.start_runner(manifest: manifest, output: output_to(self()), owner: self())

      assert_receive {:door_started, ^pid, "external-fallback"}
      assert %{pty_backend: backend} = Runner.snapshot(pid)
      assert backend in [:script_fallback, :plain]

      ref = Process.monitor(pid)
      Runner.input(pid, "/quit\n")
      assert_receive {:door_exited, ^pid, "external-fallback", :normal, 0}, @event_timeout
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, @event_timeout
    end

    test "helper crash is reported without leaking the runner" do
      previous = Application.get_env(:foglet_bbs, :door_pty_helper_path)
      Application.put_env(:foglet_bbs, :door_pty_helper_path, "/bin/false")

      on_exit(fn ->
        if previous do
          Application.put_env(:foglet_bbs, :door_pty_helper_path, previous)
        else
          Application.delete_env(:foglet_bbs, :door_pty_helper_path)
        end
      end)

      {:ok, manifest} =
        manifest(%{
          id: "external-helper-crash",
          display_name: "External Helper Crash",
          runtime: :external_pty,
          command: external_demo_path(),
          working_dir: Path.expand("priv/doors/demo"),
          args: [],
          timeout_ms: 5_000,
          pty?: true
        })

      {:ok, pid} =
        DoorSupervisor.start_runner(manifest: manifest, output: output_to(self()), owner: self())

      ref = Process.monitor(pid)
      assert_receive {:door_started, ^pid, "external-helper-crash"}
      assert_receive {:door_exited, ^pid, "external-helper-crash", :crash, 1}, @event_timeout
      assert_receive {:DOWN, ^ref, :process, ^pid, {:door_helper_exit, 1}}, @event_timeout
    end

    test "input write failures are logged without input bytes" do
      port = closed_port()

      state =
        runner_state("external-input-log", port: port, session: %{session_id: "session-123"})

      log =
        capture_log(fn ->
          assert {:noreply, _state} = Runner.handle_cast({:input, "secret typed text"}, state)
        end)

      assert log =~ "door privacy-safe event"
      assert log =~ "op: :door_input_failed"
      assert log =~ "door_id: \"external-input-log\""
      assert log =~ "session_id: \"session-123\""
      assert log =~ "reason_class:"
      refute log =~ "secret typed text"
    end

    test "cleanup failures are logged without payload data" do
      state =
        runner_state("external-cleanup-log",
          context_path: System.tmp_dir!(),
          session: %{session_id: "session-456"}
        )

      log =
        capture_log(fn ->
          assert :ok = Runner.terminate(:normal, state)
        end)

      assert log =~ "door privacy-safe event"
      assert log =~ "op: :door_cleanup_failed"
      assert log =~ "cleanup_op: :context_file_remove"
      assert log =~ "door_id: \"external-cleanup-log\""
      assert log =~ "session_id: \"session-456\""
    end

    test "malformed helper exit frames log only a short hex prefix" do
      payload = "not-json secret-payload"
      data = "X" <> payload
      state = runner_state("external-bad-frame", pty_adapter: %PTYAdapter{backend: :helper})

      log =
        capture_log(fn ->
          assert {:stop, {:door_helper_failed, {:bad_exit_frame, _reason}}, _state} =
                   Runner.handle_info({nil, {:data, data}}, state)
        end)

      assert log =~ "op: :door_bad_exit_frame"
      assert log =~ "payload_hex_prefix: \"6e6f742d6a736f6e207365637265742d\""
      refute log =~ payload
      refute log =~ "secret-payload"
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

  defp runner_state(id, opts) do
    {:ok, manifest} =
      manifest(%{
        id: id,
        display_name: id,
        runtime: :external_pty,
        command: "/bin/true",
        working_dir: "/tmp",
        args: [],
        timeout_ms: 5_000,
        pty?: false
      })

    struct!(
      Runner,
      Keyword.merge(
        [
          manifest: manifest,
          session: %{},
          terminal_size: {80, 24},
          output: output_to(self()),
          owner: self()
        ],
        opts
      )
    )
  end

  defp closed_port do
    port = Port.open({:spawn_executable, "/bin/cat"}, [:binary])
    Port.close(port)
    port
  end

  defp output_to(test_pid), do: fn data -> send(test_pid, {:door_output, data}) end

  defp assert_door_output_contains(expected, timeout \\ @event_timeout) do
    assert_receive {:door_output, output}, timeout
    output = IO.iodata_to_binary(output)

    if output =~ expected do
      output
    else
      output <> assert_door_output_contains(expected, timeout)
    end
  end

  defp external_demo_path, do: Path.expand("priv/doors/demo/external_echo.sh")
  defp python_context_demo_path, do: Path.expand("priv/doors/demo/python_context_demo.py")
  defp classic_dropfile_demo_path, do: Path.expand("priv/doors/demo/classic_dropfile_demo.py")
  defp fullscreen_probe_path, do: Path.expand("priv/doors/demo/fullscreen_probe.py")

  defp same_user_sandbox do
    %{
      mode: :restricted_user_process_group,
      user: current_username(),
      process_tree: :process_group
    }
  end

  defp current_username do
    case System.cmd("id", ["-un"], stderr_to_stdout: true) do
      {username, 0} -> String.trim(username)
      _other -> System.get_env("USER") || "nobody"
    end
  end

  defp env_probe_command do
    """
    if [ -z "${FOGLET_TEST_INHERITED_SECRET+x}" ]; then inherited=absent; else inherited=present; fi
    if [ -n "${PATH}" ]; then path_status=present; else path_status=missing; fi
    if [ -n "${FOGLET_TEST_PROBE_PATH}" ]; then
      printf 'env-probe:%s:%s:%s:%s\n' "$inherited" "$FOGLET_USERNAME" "$FOGLET_TEST_MANIFEST_VALUE" "$path_status" > "$FOGLET_TEST_PROBE_PATH"
    else
      printf 'env-probe:%s:%s:%s:%s\n' "$inherited" "$FOGLET_USERNAME" "$FOGLET_TEST_MANIFEST_VALUE" "$path_status"
    fi
    sleep 0.1
    """
  end

  defp forced_group_failure_helper do
    path =
      Path.join(
        System.tmp_dir!(),
        "foglet-pty-force-group-failure-#{System.unique_integer([:positive])}.py"
      )

    helper_path = Path.expand("priv/doors/pty/foglet_pty_adapter.py")

    File.write!(path, """
    #!/usr/bin/env python3
    import os
    import runpy

    os.geteuid = lambda: 0
    os.getegid = lambda: 0

    def fail_initgroups(user, gid):
        raise OSError("forced initgroups failure")

    def fail_setgroups(groups):
        raise OSError("forced setgroups failure")

    os.initgroups = fail_initgroups
    os.setgroups = fail_setgroups
    os.setgid = lambda gid: None
    os.setuid = lambda uid: None

    runpy.run_path(#{inspect(helper_path)}, run_name="__main__")
    """)

    File.chmod!(path, 0o700)
    path
  end

  defp restore_env(name, nil), do: System.delete_env(name)
  defp restore_env(name, value), do: System.put_env(name, value)

  defp wait_for_pidfile(path, attempts \\ 50)

  defp wait_for_pidfile(path, attempts) when attempts > 0 do
    case File.read(path) do
      {:ok, contents} ->
        contents |> String.trim() |> String.to_integer()

      {:error, _reason} ->
        receive do
        after
          20 -> wait_for_pidfile(path, attempts - 1)
        end
    end
  end

  defp wait_for_pidfile(path, 0), do: flunk("pidfile was not written: #{path}")

  defp eventually_os_process_alive?(pid, attempts \\ 20)

  defp eventually_os_process_alive?(pid, attempts) when attempts > 0 do
    if os_process_alive?(pid) do
      receive do
      after
        50 -> eventually_os_process_alive?(pid, attempts - 1)
      end
    else
      false
    end
  end

  defp eventually_os_process_alive?(pid, 0), do: os_process_alive?(pid)

  defp restore_helper_path(nil), do: Application.delete_env(:foglet_bbs, :door_pty_helper_path)

  defp restore_helper_path(path),
    do: Application.put_env(:foglet_bbs, :door_pty_helper_path, path)

  defp os_process_alive?(pid) when is_integer(pid) do
    case System.cmd("kill", ["-0", Integer.to_string(pid)], stderr_to_stdout: true) do
      {_, 0} -> true
      {_, _} -> false
    end
  end

  defp os_process_alive?(_pid), do: false
end
