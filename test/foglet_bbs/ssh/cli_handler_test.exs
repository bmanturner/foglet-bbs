defmodule Foglet.SSH.CLIHandlerTest do
  @moduledoc """
  Unit tests for CLIHandler context-building logic.

  These tests exercise pubkey correlation, context-building paths, real SSH
  channel startup bytes, and deterministic direct callback behavior.
  """

  use FogletBbs.DataCase, async: false

  import FogletBbs.AccountsFixtures

  alias Foglet.Accounts
  alias Foglet.SSH.CLIHandler
  alias Foglet.SSH.PubkeyStash

  @static_openssh_key FogletBbs.AccountsFixtures.default_ssh_public_key()
  @alt_screen_enter "\e[?1049h"
  @alt_screen_leave "\e[?1049l"
  @ssh_timeout 5_000

  describe "real SSH channel startup" do
    test "PTY allocation and shell startup emit alternate-screen ENTER" do
      %{conn: conn} = start_test_daemon!()
      channel_id = open_shell!(conn)

      bytes = collect_channel_bytes(conn, channel_id, &String.contains?(&1, @alt_screen_enter))

      assert bytes =~ @alt_screen_enter
    end

    test "initial terminal output is CRLF-normalized" do
      %{conn: conn} = start_test_daemon!()
      channel_id = open_shell!(conn)

      bytes = collect_channel_bytes(conn, channel_id, &String.contains?(&1, "\r\n"))

      assert bytes =~ "\r\n"
      refute bytes =~ ~r/(?<!\r)\n/
    end

    test "EOF emits alternate-screen LEAVE before teardown" do
      %{conn: conn} = start_test_daemon!()
      channel_id = open_shell!(conn)

      _ = collect_channel_bytes(conn, channel_id, &String.contains?(&1, @alt_screen_enter))
      :ok = :ssh_connection.send_eof(conn, channel_id)

      bytes = collect_channel_bytes(conn, channel_id, &String.contains?(&1, @alt_screen_leave))

      assert bytes =~ @alt_screen_leave
    end
  end

  describe "direct SSH callbacks" do
    test ":data parses SSH bytes and dispatches input events" do
      lifecycle_pid = start_fake_lifecycle!(self())

      state = %CLIHandler{lifecycle_pid: lifecycle_pid}

      assert {:ok, ^state} =
               CLIHandler.handle_ssh_msg({:ssh_cm, make_ref(), {:data, 1, 0, "a"}}, state)

      assert_receive {:"$gen_cast", {:dispatch, event}}
      assert event
    end

    test ":window_change updates returned state, dispatches resize, and updates session size" do
      {:ok, session_pid} = Foglet.Sessions.Supervisor.start_guest_session()
      lifecycle_pid = start_fake_lifecycle!(self())
      width = 132
      height = 50

      state = %CLIHandler{
        channel_id: 1,
        lifecycle_pid: lifecycle_pid,
        session_pid: session_pid,
        width: 80,
        height: 24
      }

      assert {:ok, returned_state} =
               CLIHandler.handle_ssh_msg(
                 {:ssh_cm, make_ref(), {:window_change, 1, width, height, 0, 0}},
                 state
               )

      assert returned_state.width == width
      assert returned_state.height == height

      assert_receive {:"$gen_cast", {:dispatch, event}}
      assert event.type == :resize
      assert event.data == %{width: width, height: height}

      _ = :sys.get_state(session_pid)
      assert Foglet.Sessions.Session.get_state(session_pid).terminal_size == {width, height}
    end

    test ":closed stops the guest session and returns a channel stop tuple" do
      reset_cli_counter!()
      {:ok, session_pid} = Foglet.Sessions.Supervisor.start_guest_session()
      ref = Process.monitor(session_pid)

      state = %CLIHandler{channel_id: 7, connection_ref: nil, session_pid: session_pid}

      assert {:stop, 7, ^state} =
               CLIHandler.handle_ssh_msg({:ssh_cm, make_ref(), {:closed, 7}}, state)

      assert_receive {:DOWN, ^ref, :process, ^session_pid, _reason}
    end

    test "matching lifecycle EXIT returns stop without requiring an SSH channel" do
      reset_cli_counter!()
      :ets.update_counter(Foglet.SSH.CLIHandler.Counter, :count, {2, 1})

      lifecycle_pid = self()
      state = %CLIHandler{channel_id: nil, connection_ref: nil, lifecycle_pid: lifecycle_pid}

      assert {:stop, 0, ^state} =
               CLIHandler.handle_msg({:EXIT, lifecycle_pid, :boom}, state)

      assert [{:count, 0}] = :ets.lookup(Foglet.SSH.CLIHandler.Counter, :count)
    end

    test "non-matching lifecycle EXIT is ignored" do
      state = %CLIHandler{channel_id: 1, connection_ref: nil, lifecycle_pid: self()}

      assert {:ok, ^state} =
               CLIHandler.handle_msg({:EXIT, spawn(fn -> :ok end), :boom}, state)
    end
  end

  describe "PubkeyStash correlation" do
    test "pop returns :miss when no key was stashed for that peer" do
      peer = {{10, 0, 0, 1}, 11_111}
      assert PubkeyStash.pop(peer) == :miss
    end

    test "pop returns {:ok, key} after put and removes the entry" do
      peer = {{10, 0, 0, 2}, 22_222}
      [{public_key, _}] = :ssh_file.decode(@static_openssh_key, :public_key)

      PubkeyStash.put(peer, public_key)

      assert {:ok, ^public_key} = PubkeyStash.pop(peer)
      # Second pop should be a miss (entry deleted)
      assert PubkeyStash.pop(peer) == :miss
    end

    test "pop(:unknown) always returns :miss" do
      assert PubkeyStash.pop(:unknown) == :miss
    end
  end

  describe "pubkey → user resolution (context-building logic)" do
    # These tests verify the CLIHandler's pubkey resolution path by calling
    # the domain functions the CLIHandler calls internally. We don't invoke
    # CLIHandler callbacks directly (they require live SSH infrastructure).

    test "pubkey matching a registered user returns that user" do
      user = user_fixture()

      {:ok, _ssh_key} =
        Accounts.register_ssh_key(user, %{label: "laptop", public_key: @static_openssh_key})

      assert {:ok, found_user} = Accounts.get_user_by_public_key(@static_openssh_key)
      assert found_user.id == user.id
      assert found_user.handle == user.handle
    end

    test "pubkey NOT registered returns {:error, :not_found}" do
      assert {:error, :not_found} = Accounts.get_user_by_public_key(@static_openssh_key)
    end

    test "pubkey for a deleted user returns {:error, :not_found}" do
      user = user_fixture()

      {:ok, _} =
        Accounts.register_ssh_key(user, %{label: "test", public_key: @static_openssh_key})

      {:ok, _} = Accounts.delete_user(user)

      assert {:error, :not_found} = Accounts.get_user_by_public_key(@static_openssh_key)
    end
  end

  describe "context shape" do
    # These tests verify the structure that CLIHandler.build_context/3 produces
    # by checking that TUI.App.init/1 correctly consumes a Lifecycle-style context.

    test "guest context (no pubkey match) produces login screen" do
      guest_ctx = %{
        session_context: %{
          user: nil,
          user_id: nil,
          session_pid: nil,
          pubkey_authenticated: false,
          registration_mode: "open",
          max_post_length: 8192
        },
        terminal_size: {80, 24}
      }

      {:ok, state} = Foglet.TUI.App.init(guest_ctx)
      assert state.current_screen == :login
      assert state.current_user == nil
      assert state.session_pid == nil
    end

    test "authenticated context (pubkey match) produces main_menu screen" do
      user = %Foglet.Accounts.User{id: "uid-123", handle: "pubkeyuser", role: :user}

      auth_ctx = %{
        session_context: %{
          user: user,
          user_id: user.id,
          session_pid: nil,
          pubkey_authenticated: true,
          registration_mode: "open",
          max_post_length: 8192
        },
        terminal_size: {132, 50}
      }

      {:ok, state} = Foglet.TUI.App.init(auth_ctx)
      assert state.current_screen == :main_menu
      assert state.current_user == user
      assert state.terminal_size == {132, 50}
    end
  end

  defp tmp_host_key_dir! do
    dir =
      Path.join(
        System.tmp_dir!(),
        "foglet_ssh_cli_handler_#{System.unique_integer([:positive, :monotonic])}"
      )

    File.mkdir_p!(dir)
    key_path = Path.join(dir, "ssh_host_ed25519_key")

    {_, 0} =
      System.cmd("ssh-keygen", ["-t", "ed25519", "-f", key_path, "-N", ""],
        stderr_to_stdout: true
      )

    on_exit(fn -> File.rm_rf!(dir) end)
    dir
  end

  defp start_test_daemon! do
    reset_cli_counter!()
    host_dir = tmp_host_key_dir!()
    start_supervised!({Foglet.SSH.RateLimiter, clean_period: :timer.minutes(10)})

    daemon_pid =
      start_supervised!(
        {Foglet.SSH.DaemonOwner,
         port: 0, daemon_opts: Foglet.SSH.Supervisor.daemon_opts(host_dir)}
      )

    %{daemon_ref: daemon_ref} = :sys.get_state(daemon_pid)
    port = daemon_port!(daemon_ref)

    {:ok, conn} =
      :ssh.connect(
        ~c"127.0.0.1",
        port,
        [
          user: ~c"test",
          user_interaction: false,
          silently_accept_hosts: true,
          save_accepted_host: false
        ],
        @ssh_timeout
      )

    on_exit(fn -> :ssh.close(conn) end)
    %{conn: conn, daemon_ref: daemon_ref, port: port}
  end

  defp reset_cli_counter! do
    table = Foglet.SSH.CLIHandler.Counter

    if :ets.whereis(table) != :undefined do
      :ets.delete(table)
    end

    CLIHandler.init_counter()
  end

  defp daemon_port!(daemon_ref) do
    daemon_info =
      case :ssh.daemon_info(daemon_ref) do
        {:ok, info} -> info
        info when is_list(info) -> info
      end

    {:port, port} = List.keyfind(daemon_info, :port, 0)
    port
  end

  defp open_shell!(conn) do
    {:ok, channel_id} = :ssh_connection.session_channel(conn, @ssh_timeout)

    assert :success =
             :ssh_connection.ptty_alloc(
               conn,
               channel_id,
               [term: ~c"xterm-256color", width: 80, height: 24, pty_opts: []],
               @ssh_timeout
             )

    assert :ok = :ssh_connection.shell(conn, channel_id)
    channel_id
  end

  defp collect_channel_bytes(conn, channel_id, predicate, timeout_ms \\ @ssh_timeout) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    do_collect_channel_bytes(conn, channel_id, predicate, deadline, "")
  end

  defp do_collect_channel_bytes(conn, channel_id, predicate, deadline, acc) do
    if predicate.(acc) do
      acc
    else
      remaining = max(deadline - System.monotonic_time(:millisecond), 0)

      receive do
        {:ssh_cm, ^conn, {:data, ^channel_id, 0, data}} ->
          do_collect_channel_bytes(conn, channel_id, predicate, deadline, acc <> to_string(data))

        {:ssh_cm, ^conn, {:eof, ^channel_id}} ->
          acc

        {:ssh_cm, ^conn, {:closed, ^channel_id}} ->
          acc
      after
        remaining ->
          flunk("timed out waiting for SSH channel bytes; collected=#{inspect(acc)}")
      end
    end
  end

  defp start_fake_lifecycle!(dispatcher_pid) do
    start_supervised!({Task, fn -> fake_lifecycle_loop(dispatcher_pid) end})
  end

  defp fake_lifecycle_loop(dispatcher_pid) do
    receive do
      {:"$gen_call", from, :get_full_state} ->
        GenServer.reply(from, %{dispatcher_pid: dispatcher_pid})
        fake_lifecycle_loop(dispatcher_pid)

      _other ->
        fake_lifecycle_loop(dispatcher_pid)
    end
  end
end
