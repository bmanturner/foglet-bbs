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

    test "includes pwdfun pointing at Foglet.SSH.Supervisor.pwdfun/4" do
      opts = SSHSup.daemon_opts("/tmp/sd")
      assert {:pwdfun, fun} = List.keyfind(opts, :pwdfun, 0)
      assert is_function(fun, 4)
    end

    test "includes key_cb: {Foglet.SSH.KeyCB, [...]}" do
      opts = SSHSup.daemon_opts("/tmp/sd")
      assert {:key_cb, {Foglet.SSH.KeyCB, kcb_opts}} = List.keyfind(opts, :key_cb, 0)
      assert {:system_dir, _} = List.keyfind(kcb_opts, :system_dir, 0)
    end

    test "includes ssh_cli: {Raxol.SSH.CLIHandler, [app_module: Foglet.TUI.App]}" do
      opts = SSHSup.daemon_opts("/tmp/sd")

      assert {:ssh_cli, {Raxol.SSH.CLIHandler, cli_opts}} =
               List.keyfind(opts, :ssh_cli, 0)

      assert {:app_module, Foglet.TUI.App} = List.keyfind(cli_opts, :app_module, 0)
    end
  end

  describe "Foglet.SSH.Supervisor.pwdfun/4 (SSH-02)" do
    import FogletBbs.AccountsFixtures

    setup do
      :ok = Ecto.Adapters.SQL.Sandbox.checkout(FogletBbs.Repo)
      on_exit(fn -> Ecto.Adapters.SQL.Sandbox.checkin(FogletBbs.Repo) end)
      :ok
    end

    test "accepts active user with correct password" do
      password = "correcthorsebatterystaple"
      user = user_fixture(%{password: password})

      result =
        SSHSup.pwdfun(
          String.to_charlist(user.handle),
          String.to_charlist(password),
          {{127, 0, 0, 1}, 22},
          nil
        )

      assert {true, nil} = result
    end

    test "rejects unknown user" do
      result =
        SSHSup.pwdfun(
          ~c"nonexistentuser",
          ~c"whatever",
          {{127, 0, 0, 1}, 22},
          nil
        )

      assert {false, nil} = result
    end

    test ":pubkey form accepts a known non-deleted handle" do
      user = user_fixture()

      result =
        SSHSup.pwdfun(String.to_charlist(user.handle), :pubkey, {{127, 0, 0, 1}, 22}, :s)

      assert {true, :s} = result
    end

    test ":pubkey form rejects an unknown handle" do
      result = SSHSup.pwdfun(~c"ghost", :pubkey, {{127, 0, 0, 1}, 22}, :s)
      assert {false, :s} = result
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
