defmodule Foglet.SSH.DaemonOwnerTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias Foglet.SSH.DaemonOwner

  describe "system_dir validation (Concern #2)" do
    test "refuses to start when :system_dir is missing from daemon_opts" do
      log =
        capture_log(fn ->
          assert {:error, {:ssh_daemon_failed, {:invalid_system_dir, msg}}} =
                   start_daemon(daemon_opts: [no_auth_needed: true])

          assert msg =~ ":system_dir missing"
        end)

      assert log =~ "Foglet SSH daemon refusing to start"
    end

    test "refuses to start when :system_dir does not exist" do
      missing_dir =
        Path.join(
          System.tmp_dir!(),
          "foglet_ssh_does_not_exist_#{:erlang.unique_integer([:positive])}"
        )

      refute File.exists?(missing_dir)

      capture_log(fn ->
        assert {:error, {:ssh_daemon_failed, {:invalid_system_dir, msg}}} =
                 start_daemon(daemon_opts: [system_dir: String.to_charlist(missing_dir)])

        assert msg =~ "does not exist or is not readable"
        assert msg =~ missing_dir
      end)
    end

    test "refuses to start when :system_dir exists but contains no host keys" do
      empty_dir = make_tmp_dir!()

      capture_log(fn ->
        assert {:error, {:ssh_daemon_failed, {:invalid_system_dir, msg}}} =
                 start_daemon(daemon_opts: [system_dir: String.to_charlist(empty_dir)])

        # Surfaces the expected filenames *and* a copy-pasteable ssh-keygen recipe.
        assert msg =~ "contains no host keys"
        assert msg =~ "ssh_host_ed25519_key"
        assert msg =~ "ssh-keygen -t ed25519"
      end)
    end
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  # Start the DaemonOwner without linking so an init failure (which is exactly
  # what these tests exercise) does not propagate an EXIT signal that would
  # kill the test process.
  defp start_daemon(opts) do
    port = Keyword.get(opts, :port, 0)
    daemon_opts = Keyword.fetch!(opts, :daemon_opts)

    GenServer.start(DaemonOwner, port: port, daemon_opts: daemon_opts)
  end

  defp make_tmp_dir! do
    dir =
      Path.join(
        System.tmp_dir!(),
        "foglet_ssh_test_#{:erlang.unique_integer([:positive])}"
      )

    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    dir
  end
end
