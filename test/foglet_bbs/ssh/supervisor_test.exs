defmodule Foglet.SSH.SupervisorTest do
  use ExUnit.Case, async: false

  alias Foglet.SSH.Supervisor, as: SSHSup

  describe "Foglet.SSH.Supervisor.daemon_opts/1 (SSH-01)" do
    test "includes system_dir as a charlist" do
      opts = SSHSup.daemon_opts("/tmp/test_sd")
      assert {:system_dir, sd} = List.keyfind(opts, :system_dir, 0)
      assert is_list(sd)
      assert to_string(sd) == "/tmp/test_sd"
    end

    test "includes no_auth_needed: true (Open Question 1 resolution)" do
      opts = SSHSup.daemon_opts("/tmp/sd")
      assert {:no_auth_needed, true} = List.keyfind(opts, :no_auth_needed, 0)
    end

    test "does NOT include pwdfun — TUI is the authentication boundary" do
      opts = SSHSup.daemon_opts("/tmp/sd")
      assert List.keyfind(opts, :pwdfun, 0) == nil
    end

    test "includes key_cb: {Foglet.SSH.KeyCB, [...]}" do
      opts = SSHSup.daemon_opts("/tmp/sd")
      assert {:key_cb, {Foglet.SSH.KeyCB, kcb_opts}} = List.keyfind(opts, :key_cb, 0)
      assert {:system_dir, _} = List.keyfind(kcb_opts, :system_dir, 0)
    end

    test "includes ssh_cli: {Foglet.SSH.CLIHandler, []}" do
      opts = SSHSup.daemon_opts("/tmp/sd")

      assert {:ssh_cli, {Foglet.SSH.CLIHandler, []}} =
               List.keyfind(opts, :ssh_cli, 0)
    end

    test "includes max_sessions: 500" do
      opts = SSHSup.daemon_opts("/tmp/sd")
      assert {:max_sessions, 500} = List.keyfind(opts, :max_sessions, 0)
    end
  end

  describe "application config" do
    test "test env disables start_ssh_daemon" do
      assert Application.get_env(:foglet_bbs, :start_ssh_daemon) == false
    end

    test "default port is 2222" do
      assert Application.get_env(:foglet_bbs, :ssh_port, 2222) == 2222
    end
  end
end
