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

    test "requires publickey auth so clients offer keys for reconnect auto-login" do
      opts = SSHSup.daemon_opts("/tmp/sd")

      assert {:auth_methods, ~c"publickey"} = List.keyfind(opts, :auth_methods, 0)
      assert List.keyfind(opts, :no_auth_needed, 0) == nil
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

    test "socket_options sets backlog and reuseaddr for high-concurrency accept queues" do
      opts = SSHSup.daemon_opts("/tmp/sd")
      assert {:socket_options, sock_opts} = List.keyfind(opts, :socket_options, 0)
      assert Keyword.get(sock_opts, :backlog) >= 1024
      assert Keyword.get(sock_opts, :reuseaddr) == true
    end

    test "preferred_algorithms is an explicit allowlist — no modify_algorithms present" do
      opts = SSHSup.daemon_opts("/tmp/sd")
      # preferred_algorithms replaces the default list entirely; a separate
      # modify_algorithms rm: would be redundant and potentially confusing.
      assert List.keyfind(opts, :modify_algorithms, 0) == nil
      assert {:preferred_algorithms, _} = List.keyfind(opts, :preferred_algorithms, 0)
    end

    test "preferred_algorithms KEX: Curve25519 is first, no legacy DHE" do
      opts = SSHSup.daemon_opts("/tmp/sd")
      assert {:preferred_algorithms, prefs} = List.keyfind(opts, :preferred_algorithms, 0)
      kex = Keyword.get(prefs, :kex, [])

      assert hd(kex) in [:"curve25519-sha256", :"curve25519-sha256@libssh.org"]
      refute :"diffie-hellman-group1-sha1" in kex
      refute :"diffie-hellman-group14-sha1" in kex
      refute :"diffie-hellman-group-exchange-sha1" in kex
    end

    test "preferred_algorithms public_key: ssh-ed25519 first, no deprecated types" do
      opts = SSHSup.daemon_opts("/tmp/sd")
      assert {:preferred_algorithms, prefs} = List.keyfind(opts, :preferred_algorithms, 0)
      pk = Keyword.get(prefs, :public_key, [])

      assert hd(pk) == :"ssh-ed25519"
      refute :"ssh-rsa" in pk
      refute :"ssh-dss" in pk
    end

    test "preferred_algorithms cipher: AEAD first, no CBC or 3DES" do
      opts = SSHSup.daemon_opts("/tmp/sd")
      assert {:preferred_algorithms, prefs} = List.keyfind(opts, :preferred_algorithms, 0)
      ciphers = Keyword.get(prefs, :cipher, [])

      assert hd(ciphers) in [:"aes256-gcm@openssh.com", :"chacha20-poly1305@openssh.com"]
      refute :"3des-cbc" in ciphers
      refute :"aes128-cbc" in ciphers
      refute :"aes256-cbc" in ciphers
    end

    test "preferred_algorithms mac: ETM variants first, no SHA-1 or MD5" do
      opts = SSHSup.daemon_opts("/tmp/sd")
      assert {:preferred_algorithms, prefs} = List.keyfind(opts, :preferred_algorithms, 0)
      macs = Keyword.get(prefs, :mac, [])

      assert hd(macs) in [
               :"hmac-sha2-256-etm@openssh.com",
               :"hmac-sha2-512-etm@openssh.com"
             ]

      refute :"hmac-sha1" in macs
      refute :"hmac-md5" in macs
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
