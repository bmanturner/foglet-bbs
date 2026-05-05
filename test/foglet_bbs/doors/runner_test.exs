defmodule Foglet.Doors.RunnerTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  @event_timeout 1_000

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

  defp os_process_alive?(pid) when is_integer(pid) do
    case System.cmd("kill", ["-0", Integer.to_string(pid)], stderr_to_stdout: true) do
      {_, 0} -> true
      {_, _} -> false
    end
  end

  defp os_process_alive?(_pid), do: false
end
