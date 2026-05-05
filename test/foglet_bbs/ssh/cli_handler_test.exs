defmodule Foglet.SSH.CLIHandlerTest do
  @moduledoc """
  Unit tests for CLIHandler context-building logic.

  These tests exercise pubkey correlation, context-building paths, real SSH
  channel startup bytes, and deterministic direct callback behavior.
  """

  use FogletBbs.DataCase, async: false

  import ExUnit.CaptureLog

  alias Foglet.SSH.CLIHandler
  alias Foglet.SSH.PubkeyStash
  alias FogletBbs.AccountsFixtures

  defmodule DispatcherUnavailableLifecycle do
    use GenServer

    def start_link(opts \\ []) do
      GenServer.start_link(__MODULE__, opts)
    end

    @impl true
    def init(opts), do: {:ok, opts}

    @impl true
    def handle_call(:get_full_state, _from, state) do
      reason = Keyword.get(state, :reason, :dispatcher_unavailable)
      exit(reason)
    end
  end

  @static_openssh_key FogletBbs.AccountsFixtures.default_ssh_public_key()
  @terminal_takeover "\e[H\e[2J\e[3J\e[?1049h\e[H\e[2J\e[3J"
  @alt_screen_enter "\e[?1049h"
  @alt_screen_leave "\e[?1049l"
  @ssh_timeout 5_000

  describe "real SSH channel startup" do
    test "PTY allocation clears scrollback and enters alternate screen before terminal output" do
      %{conn: conn} = start_test_daemon!()
      channel_id = open_shell!(conn)

      bytes = collect_channel_bytes(conn, channel_id, &String.contains?(&1, @alt_screen_enter))

      assert String.starts_with?(bytes, @terminal_takeover)
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
      # WR-05 (Phase 45): dispatcher pid is resolved once at PTY start and
      # stashed on state, so per-keystroke dispatches are pure casts. Tests
      # that exercise :data directly seed `dispatcher_pid` here rather than
      # relying on a per-event GenServer.call into the Lifecycle.
      state = %CLIHandler{dispatcher_pid: self()}

      assert {:ok, ^state} =
               CLIHandler.handle_ssh_msg({:ssh_cm, make_ref(), {:data, 1, 0, "a"}}, state)

      assert_receive {:"$gen_cast", {:dispatch, event}}
      assert event
    end

    test ":window_change updates returned state and dispatches resize+window events" do
      # IN-01 (Phase 45): Session.set_terminal_size/2 is now driven by
      # Foglet.TUI.App's do_update({:window_change, …}, …) handler in response
      # to the :window event dispatched here, rather than by CLIHandler casting
      # directly. The App is the single owner of the "session knows its size"
      # invariant.
      {:ok, session_pid} = Foglet.Sessions.Supervisor.start_guest_session()
      width = 132
      height = 50

      state = %CLIHandler{
        channel_id: 1,
        dispatcher_pid: self(),
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

      assert_receive {:"$gen_cast", {:dispatch, %{type: :resize} = resize_event}}
      assert resize_event.data == %{width: width, height: height}

      assert_receive {:"$gen_cast", {:dispatch, %{type: :window} = window_event}}
      assert window_event.data == %{width: width, height: height}
    end

    test ":window_change during an active door only resizes the door runner" do
      width = 64
      height = 22

      state = %CLIHandler{
        channel_id: 1,
        dispatcher_pid: self(),
        door_runner_pid: self(),
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
      assert_received {:"$gen_cast", {:resize, {^width, ^height}}}
      refute_received {:"$gen_cast", {:dispatch, _event}}
    end

    test "matching door_exited clears active door after replaying current window size" do
      door_pid = self()
      door_id = "external-echo"

      state = %CLIHandler{
        channel_id: 1,
        dispatcher_pid: self(),
        door_runner_pid: door_pid,
        width: 64,
        height: 22
      }

      assert {:ok, returned_state} =
               CLIHandler.handle_msg({:door_exited, door_pid, door_id, :normal, 0}, state)

      assert returned_state.door_runner_pid == nil
      assert_received {:"$gen_cast", {:dispatch, %{type: :resize} = resize_event}}
      assert resize_event.data == %{width: 64, height: 22}
      assert_received {:"$gen_cast", {:dispatch, %{type: :window} = window_event}}
      assert window_event.data == %{width: 64, height: 22}

      assert_received {:"$gen_cast",
                       {:dispatch,
                        %{
                          type: :foglet_runtime,
                          data: %{message: {:door_exited, ^door_id, :normal, 0}}
                        }}}
    end

    test ":closed stops the guest session and returns a channel stop tuple" do
      reset_cli_counter!()
      {:ok, session_pid} = Foglet.Sessions.Supervisor.start_guest_session()
      ref = Process.monitor(session_pid)

      state = %CLIHandler{channel_id: 7, connection_ref: nil, session_pid: session_pid}

      assert {:stop, 7, returned_state} =
               CLIHandler.handle_ssh_msg({:ssh_cm, make_ref(), {:closed, 7}}, state)

      assert returned_state.channel_id == 7
      assert returned_state.cleanup_done?
      refute returned_state.counter_counted?

      assert_receive {:DOWN, ^ref, :process, ^session_pid, _reason}
    end

    test "matching lifecycle EXIT returns stop without requiring an SSH channel" do
      reset_cli_counter!()
      :ets.update_counter(Foglet.SSH.CLIHandler.Counter, :count, {2, 1})

      lifecycle_pid = self()

      state = %CLIHandler{
        channel_id: nil,
        connection_ref: nil,
        lifecycle_pid: lifecycle_pid,
        counter_counted?: true
      }

      assert {:stop, 0, returned_state} =
               CLIHandler.handle_msg({:EXIT, lifecycle_pid, :boom}, state)

      assert returned_state.cleanup_done?
      refute returned_state.counter_counted?
      assert [{:count, 0}] = :ets.lookup(Foglet.SSH.CLIHandler.Counter, :count)
    end

    test "lifecycle started but dispatcher unavailable fails PTY startup closed and logs" do
      reset_cli_counter!()
      :ets.insert(Foglet.SSH.CLIHandler.Counter, {:count, 1})

      previous_trap_exit = Process.flag(:trap_exit, true)

      {:ok, lifecycle_pid} =
        DispatcherUnavailableLifecycle.start_link(reason: :dispatcher_missing)

      state = %CLIHandler{
        channel_id: 42,
        connection_ref: nil,
        peer: {{127, 0, 0, 1}, 55_555},
        counter_counted?: true
      }

      log =
        try do
          capture_log(fn ->
            assert {:stop, 42, returned_state} =
                     CLIHandler.finish_lifecycle_start_for_test(
                       state,
                       nil,
                       42,
                       true,
                       lifecycle_pid,
                       80,
                       24
                     )

            assert returned_state.lifecycle_pid == lifecycle_pid
            assert returned_state.dispatcher_pid == nil
            assert returned_state.cleanup_done?
            refute returned_state.counter_counted?
            assert_counter!(0)
          end)
        after
          Process.flag(:trap_exit, previous_trap_exit)
        end

      assert log =~ "Dispatcher resolution failed during PTY startup; closing channel"
    end

    test "non-matching lifecycle EXIT is ignored" do
      state = %CLIHandler{channel_id: 1, connection_ref: nil, lifecycle_pid: self()}

      assert {:ok, ^state} =
               CLIHandler.handle_msg({:EXIT, spawn(fn -> :ok end), :boom}, state)
    end
  end

  describe "connection counter balance (SSH-04)" do
    @max_connections 500

    setup do
      reset_cli_counter!()
      reset_site_call_counter!()
      start_supervised!({Foglet.SSH.RateLimiter, clean_period: :timer.minutes(10)})
      :ok
    end

    test "init_counter is idempotent and preserves active count" do
      assert_counter!(0)
      :ets.insert(Foglet.SSH.CLIHandler.Counter, {:count, 42})

      assert :ok = CLIHandler.init_counter()

      assert_counter!(42)
    end

    test "accepted connection increments counter and close decrements exactly once" do
      warm_login_config_cache!()
      peer = {{10, 0, 0, 101}, 65_003}

      assert {:ok, returned_state} =
               CLIHandler.channel_up_for_test(%CLIHandler{}, 1, nil, peer)

      ref = Process.monitor(returned_state.session_pid)

      assert returned_state.counter_counted?
      refute returned_state.cleanup_done?
      assert_counter!(1)
      assert Foglet.SiteCounters.get_call_count() == 1

      assert {:stop, 1, after_close} =
               CLIHandler.handle_ssh_msg({:ssh_cm, make_ref(), {:closed, 1}}, returned_state)

      assert_counter!(0)
      assert Foglet.SiteCounters.get_call_count() == 1
      assert after_close.cleanup_done?
      refute after_close.counter_counted?
      assert_receive {:DOWN, ^ref, :process, _, _reason}

      assert :ok = CLIHandler.terminate(:normal, after_close)
      assert_counter!(0)
    end

    test "accepted public-key member connection increments durable total once" do
      warm_login_config_cache!()

      user =
        AccountsFixtures.user_fixture()
        |> Ecto.Changeset.change(status: :active)
        |> FogletBbs.Repo.update!()

      _key = AccountsFixtures.ssh_key_fixture(user, %{public_key: @static_openssh_key})
      peer = {{10, 0, 0, 102}, 65_004}
      [{public_key, _}] = :ssh_file.decode(@static_openssh_key, :public_key)
      PubkeyStash.put(peer, public_key)

      assert {:ok, returned_state} = CLIHandler.channel_up_for_test(%CLIHandler{}, 1, nil, peer)

      assert returned_state.pubkey_user.id == user.id
      assert_counter!(1)
      assert Foglet.SiteCounters.get_call_count() == 1

      _ = CLIHandler.handle_ssh_msg({:ssh_cm, make_ref(), {:closed, 1}}, returned_state)
      assert_counter!(0)
      assert Foglet.SiteCounters.get_call_count() == 1
    end

    test "guest promotion does not increment durable total a second time" do
      warm_login_config_cache!()
      peer = {{10, 0, 0, 103}, 65_005}

      assert {:ok, returned_state} = CLIHandler.channel_up_for_test(%CLIHandler{}, 1, nil, peer)
      assert Foglet.SiteCounters.get_call_count() == 1

      user =
        AccountsFixtures.user_fixture()
        |> Ecto.Changeset.change(status: :active)
        |> FogletBbs.Repo.update!()

      assert :ok =
               Foglet.Sessions.Supervisor.promote_guest_session(returned_state.session_pid, user)

      assert Foglet.SiteCounters.get_call_count() == 1

      _ = CLIHandler.handle_ssh_msg({:ssh_cm, make_ref(), {:closed, 1}}, returned_state)
      assert_counter!(0)
      assert Foglet.SiteCounters.get_call_count() == 1
    end

    test "session replacement counts only each new successful client connection" do
      warm_login_config_cache!()

      user =
        AccountsFixtures.user_fixture()
        |> Ecto.Changeset.change(status: :active)
        |> FogletBbs.Repo.update!()

      _key = AccountsFixtures.ssh_key_fixture(user, %{public_key: @static_openssh_key})
      [{public_key, _}] = :ssh_file.decode(@static_openssh_key, :public_key)

      first_peer = {{10, 0, 0, 104}, 65_006}
      PubkeyStash.put(first_peer, public_key)

      assert {:ok, first_state} =
               CLIHandler.channel_up_for_test(%CLIHandler{}, 1, nil, first_peer)

      first_ref = Process.monitor(first_state.session_pid)
      assert Foglet.SiteCounters.get_call_count() == 1

      second_peer = {{10, 0, 0, 105}, 65_007}
      PubkeyStash.put(second_peer, public_key)

      assert {:ok, second_state} =
               CLIHandler.channel_up_for_test(%CLIHandler{}, 2, nil, second_peer)

      assert_receive {:DOWN, ^first_ref, :process, _, _reason}
      assert second_state.session_pid != first_state.session_pid
      assert_counter!(2)
      assert Foglet.SiteCounters.get_call_count() == 2

      _ = CLIHandler.handle_ssh_msg({:ssh_cm, make_ref(), {:closed, 1}}, first_state)
      assert_counter!(1)
      assert Foglet.SiteCounters.get_call_count() == 2

      _ = CLIHandler.handle_ssh_msg({:ssh_cm, make_ref(), {:closed, 2}}, second_state)
      assert_counter!(0)
      assert Foglet.SiteCounters.get_call_count() == 2
    end

    test "normal close: :closed on counted state restores counter to 0" do
      {:ok, session_pid} = Foglet.Sessions.Supervisor.start_guest_session()
      ref = Process.monitor(session_pid)
      :ets.insert(Foglet.SSH.CLIHandler.Counter, {:count, 1})
      assert_counter!(1)

      state = %CLIHandler{
        channel_id: 7,
        connection_ref: nil,
        session_pid: session_pid,
        counter_counted?: true
      }

      assert {:stop, 7, returned_state} =
               CLIHandler.handle_ssh_msg({:ssh_cm, make_ref(), {:closed, 7}}, state)

      assert_counter!(0)
      assert returned_state.cleanup_done?
      refute returned_state.counter_counted?

      assert_receive {:DOWN, ^ref, :process, ^session_pid, _reason}
    end

    test "EOF-to-close: EOF leaves counter alone, subsequent :closed decrements once" do
      {:ok, session_pid} = Foglet.Sessions.Supervisor.start_guest_session()
      ref = Process.monitor(session_pid)
      :ets.insert(Foglet.SSH.CLIHandler.Counter, {:count, 1})

      state = %CLIHandler{
        channel_id: 9,
        connection_ref: nil,
        session_pid: session_pid,
        counter_counted?: true
      }

      assert {:ok, after_eof} =
               CLIHandler.handle_ssh_msg({:ssh_cm, make_ref(), {:eof, 9}}, state)

      assert_counter!(1)
      assert after_eof.counter_counted?
      refute after_eof.cleanup_done?

      assert {:stop, 9, after_close} =
               CLIHandler.handle_ssh_msg({:ssh_cm, make_ref(), {:closed, 9}}, after_eof)

      assert_counter!(0)
      assert after_close.cleanup_done?
      refute after_close.counter_counted?

      assert_receive {:DOWN, ^ref, :process, ^session_pid, _reason}
    end

    test "lifecycle EXIT on counted state decrements counter exactly once" do
      :ets.insert(Foglet.SSH.CLIHandler.Counter, {:count, 1})

      lifecycle_pid = self()

      state = %CLIHandler{
        channel_id: nil,
        connection_ref: nil,
        lifecycle_pid: lifecycle_pid,
        counter_counted?: true
      }

      assert {:stop, 0, returned_state} =
               CLIHandler.handle_msg({:EXIT, lifecycle_pid, :boom}, state)

      assert_counter!(0)
      assert returned_state.cleanup_done?
      refute returned_state.counter_counted?
    end

    test "over-limit reject: counter returns to threshold, returned state is uncounted" do
      :ets.insert(Foglet.SSH.CLIHandler.Counter, {:count, @max_connections})

      assert_counter!(@max_connections)

      peer = {{10, 0, 0, 99}, 65_001}

      assert {:ok, returned_state} =
               CLIHandler.channel_up_for_test(%CLIHandler{}, 1, nil, peer)

      assert returned_state.over_limit
      refute returned_state.counter_counted?
      assert returned_state.cleanup_done?
      # Counter must not drift upward past the threshold; check_connection_limit/0
      # compensated its own increment on rejection.
      assert_counter!(@max_connections)
      assert Foglet.SiteCounters.get_call_count() == 0

      # Subsequent cleanup delivery (e.g. terminate) is a no-op for rejected state.
      _ = CLIHandler.handle_ssh_msg({:ssh_cm, make_ref(), {:closed, 1}}, returned_state)
      assert_counter!(@max_connections)
      assert Foglet.SiteCounters.get_call_count() == 0
    end

    test "rate-limit reject: counter unchanged, returned state is uncounted" do
      peer = {{10, 0, 0, 100}, 65_002}

      # Saturate the per-IP rate limit window by exhausting the bucket.
      Enum.each(1..10, fn _ -> Foglet.SSH.RateLimiter.allow?(peer) end)
      refute Foglet.SSH.RateLimiter.allow?(peer)

      starting_count = 3
      :ets.insert(Foglet.SSH.CLIHandler.Counter, {:count, starting_count})

      assert {:ok, returned_state} =
               CLIHandler.channel_up_for_test(%CLIHandler{}, 1, nil, peer)

      assert returned_state.over_limit
      refute returned_state.counter_counted?
      assert returned_state.cleanup_done?
      # check_connection_limit/0 incremented; the rate-limit branch must
      # decrement immediately so the counter returns to the starting value.
      assert_counter!(starting_count)
      assert Foglet.SiteCounters.get_call_count() == 0

      # Idempotent: cleanup delivery on a rejected state must not double-decrement.
      _ = CLIHandler.handle_ssh_msg({:ssh_cm, make_ref(), {:closed, 1}}, returned_state)
      assert_counter!(starting_count)
      assert Foglet.SiteCounters.get_call_count() == 0
    end

    test "crash-during-init: terminate on counted state with no lifecycle/session decrements once" do
      :ets.insert(Foglet.SSH.CLIHandler.Counter, {:count, 1})

      state = %CLIHandler{
        channel_id: nil,
        connection_ref: nil,
        session_pid: nil,
        lifecycle_pid: nil,
        counter_counted?: true
      }

      assert :ok = CLIHandler.terminate(:boom, state)
      assert_counter!(0)
    end

    test "idempotent cleanup: EXIT followed by terminate decrements only once" do
      :ets.insert(Foglet.SSH.CLIHandler.Counter, {:count, 1})

      lifecycle_pid = self()

      state = %CLIHandler{
        channel_id: nil,
        connection_ref: nil,
        lifecycle_pid: lifecycle_pid,
        counter_counted?: true
      }

      assert {:stop, 0, after_exit} =
               CLIHandler.handle_msg({:EXIT, lifecycle_pid, :boom}, state)

      assert_counter!(0)
      assert after_exit.cleanup_done?

      # Subsequent terminate must not double-decrement; cleanup helper short-circuits
      # on cleanup_done? state.
      assert :ok = CLIHandler.terminate(:normal, after_exit)
      assert_counter!(0)
    end

    test "rejected state never asks for later decrement (closed -> terminate stays at start)" do
      starting_count = 7
      :ets.insert(Foglet.SSH.CLIHandler.Counter, {:count, starting_count})

      # Simulate a rejected state shape (matches what over_limit/rate-limit
      # branches return).
      rejected = %CLIHandler{
        channel_id: 1,
        connection_ref: nil,
        over_limit: true,
        cleanup_done?: true,
        counter_counted?: false
      }

      _ = CLIHandler.handle_ssh_msg({:ssh_cm, make_ref(), {:closed, 1}}, rejected)
      assert_counter!(starting_count)

      _ = CLIHandler.terminate(:normal, rejected)
      assert_counter!(starting_count)
    end
  end

  describe "PubkeyStash correlation" do
    setup do
      reset_pubkey_stash!()
      :ok
    end

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

    test "pop_offer preserves the OpenSSH text alongside the decoded key" do
      peer = {{10, 0, 0, 7}, 77_777}
      [{public_key, _}] = :ssh_file.decode(@static_openssh_key, :public_key)

      PubkeyStash.put(peer, public_key)

      assert {:ok, %{public_key: ^public_key, openssh_text: openssh_text}} =
               PubkeyStash.pop_offer(peer)

      assert openssh_text == openssh_text_for(public_key)
      assert PubkeyStash.pop_offer(peer) == :miss
    end

    test "pop(:unknown) always returns :miss" do
      assert PubkeyStash.pop(:unknown) == :miss
    end

    test "sweep removes stale entries past the TTL window" do
      peer = {{10, 0, 0, 3}, 33_333}
      [{public_key, _}] = :ssh_file.decode(@static_openssh_key, :public_key)

      PubkeyStash.put(peer, public_key, 1_000)

      now = 1_000 + :timer.minutes(6)
      assert PubkeyStash.sweep(now, :timer.minutes(5)) == 1
      assert PubkeyStash.pop(peer, now) == :miss
    end

    test "sweep only removes stale entries and leaves fresh entries consumable once" do
      stale_peer = {{10, 0, 0, 4}, 44_444}
      fresh_peer = {{10, 0, 0, 5}, 55_555}
      [{public_key, _}] = :ssh_file.decode(@static_openssh_key, :public_key)

      PubkeyStash.put(stale_peer, public_key, 1_000)
      fresh_inserted_at = 1_000 + :timer.minutes(5)
      PubkeyStash.put(fresh_peer, public_key, fresh_inserted_at)

      now = 1_000 + :timer.minutes(6)
      assert PubkeyStash.sweep(now, :timer.minutes(5)) == 1
      assert PubkeyStash.pop(stale_peer, now) == :miss
      assert {:ok, ^public_key} = PubkeyStash.pop(fresh_peer, now)
      assert PubkeyStash.pop(fresh_peer, now) == :miss
    end

    test "expired entry returns :miss from pop without prior sweep" do
      peer = {{10, 0, 0, 6}, 66_666}
      [{public_key, _}] = :ssh_file.decode(@static_openssh_key, :public_key)

      PubkeyStash.put(peer, public_key, 1_000)

      assert PubkeyStash.pop(peer, 1_000 + :timer.minutes(6)) == :miss
      # Expired entry should have been deleted by the pop, so a follow-up
      # pop with a fresh timestamp must also miss.
      assert PubkeyStash.pop(peer, 1_000 + :timer.minutes(6)) == :miss
    end
  end

  describe "context shape" do
    # These tests verify the structure that CLIHandler.build_context/3 produces
    # by checking that TUI.App.init/1 correctly consumes a Lifecycle-style context.

    test "guest context (no pubkey match) produces login screen" do
      guest_ctx = %{
        session_context: %Foglet.TUI.SessionContext{
          user: nil,
          user_id: nil,
          session_pid: nil,
          pubkey_authenticated: false,
          registration_mode: "open",
          max_post_length: 8192,
          ssh_peer: nil
        },
        terminal_size: {80, 24}
      }

      {:ok, state} = Foglet.TUI.App.init(guest_ctx)
      assert state.current_screen == :login
      assert state.current_user == nil
      assert state.session_pid == nil
    end

    test "authenticated context (pubkey match) produces main_menu screen" do
      user = %Foglet.Accounts.User{
        id: "uid-123",
        handle: "pubkeyuser",
        role: :user,
        confirmed_at: DateTime.utc_now()
      }

      auth_ctx = %{
        session_context: %Foglet.TUI.SessionContext{
          user: user,
          user_id: user.id,
          session_pid: nil,
          pubkey_authenticated: true,
          registration_mode: "open",
          max_post_length: 8192,
          ssh_peer: {{127, 0, 0, 1}, 2222}
        },
        terminal_size: {132, 50}
      }

      {:ok, state} = Foglet.TUI.App.init(auth_ctx)
      assert state.current_screen == :main_menu
      assert state.current_user == user
      assert state.terminal_size == {132, 50}
    end

    test "unmatched offered key is carried into guest SessionContext" do
      reset_cli_counter!()
      reset_pubkey_stash!()
      warm_login_config_cache!()
      start_supervised!({Foglet.SSH.RateLimiter, clean_period: :timer.minutes(10)})

      peer = {{10, 0, 0, 8}, 88_888}
      [{public_key, _}] = :ssh_file.decode(@static_openssh_key, :public_key)
      PubkeyStash.put(peer, public_key)

      assert {:ok, returned_state} = CLIHandler.channel_up_for_test(%CLIHandler{}, 1, nil, peer)

      context = CLIHandler.context_for_test(returned_state, 80, 24)
      session_context = context.session_context

      assert session_context.user == nil
      assert session_context.user_id == nil
      refute session_context.pubkey_authenticated
      assert session_context.offered_ssh_public_key == openssh_text_for(public_key)

      _ = CLIHandler.handle_ssh_msg({:ssh_cm, make_ref(), {:closed, 1}}, returned_state)
    end

    test "password-only guest context leaves offered key blank" do
      reset_cli_counter!()
      reset_pubkey_stash!()
      warm_login_config_cache!()
      start_supervised!({Foglet.SSH.RateLimiter, clean_period: :timer.minutes(10)})

      peer = {{10, 0, 0, 9}, 99_999}

      assert {:ok, returned_state} = CLIHandler.channel_up_for_test(%CLIHandler{}, 1, nil, peer)

      context = CLIHandler.context_for_test(returned_state, 80, 24)

      assert context.session_context.user == nil
      assert context.session_context.offered_ssh_public_key == nil

      _ = CLIHandler.handle_ssh_msg({:ssh_cm, make_ref(), {:closed, 1}}, returned_state)
    end

    test "normalizes OTP connection_info peer transport shape" do
      peer = {{127, 0, 0, 1}, 54_321}

      assert CLIHandler.peer_from_connection_info_for_test(peer: {:tcp, peer}) == peer
      assert CLIHandler.peer_from_connection_info_for_test(peer: {peer, :socket}) == peer
      assert CLIHandler.peer_from_connection_info_for_test(peer: peer) == peer
    end

    test "registered public-key login does not carry offered key into SessionContext" do
      reset_cli_counter!()
      reset_pubkey_stash!()
      warm_login_config_cache!()
      start_supervised!({Foglet.SSH.RateLimiter, clean_period: :timer.minutes(10)})

      user =
        AccountsFixtures.user_fixture()
        |> Ecto.Changeset.change(status: :active)
        |> FogletBbs.Repo.update!()

      _key = AccountsFixtures.ssh_key_fixture(user, %{public_key: @static_openssh_key})
      peer = {{10, 0, 0, 10}, 10_010}
      [{public_key, _}] = :ssh_file.decode(@static_openssh_key, :public_key)
      PubkeyStash.put(peer, public_key)

      assert {:ok, returned_state} = CLIHandler.channel_up_for_test(%CLIHandler{}, 1, nil, peer)

      context = CLIHandler.context_for_test(returned_state, 80, 24)

      assert context.session_context.user.id == user.id
      assert context.session_context.pubkey_authenticated
      assert context.session_context.offered_ssh_public_key == nil

      _ = CLIHandler.handle_ssh_msg({:ssh_cm, make_ref(), {:closed, 1}}, returned_state)
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
    client_key_path = Path.join(dir, "id_ed25519")

    {_, 0} =
      System.cmd("ssh-keygen", ["-t", "ed25519", "-f", key_path, "-N", ""],
        stderr_to_stdout: true
      )

    {_, 0} =
      System.cmd(
        "ssh-keygen",
        ["-t", "ed25519", "-f", client_key_path, "-N", ""],
        stderr_to_stdout: true
      )

    on_exit(fn -> File.rm_rf!(dir) end)
    dir
  end

  defp start_test_daemon! do
    reset_cli_counter!()
    warm_login_config_cache!()
    host_dir = tmp_host_key_dir!()
    start_supervised!({Foglet.SSH.RateLimiter, clean_period: :timer.minutes(10)})

    daemon_opts =
      host_dir
      |> Foglet.SSH.Supervisor.daemon_opts()
      # These channel-lifecycle tests assert PTY/rendering behavior, not SSH
      # transport auth. Keep them on no-auth so they do not depend on client key
      # discovery; SupervisorTest and end-to-end harnesses cover production auth.
      |> Keyword.delete(:auth_methods)
      |> Keyword.put(:no_auth_needed, true)

    daemon_pid =
      start_supervised!({Foglet.SSH.DaemonOwner, port: 0, daemon_opts: daemon_opts})

    %{daemon_ref: daemon_ref} = :sys.get_state(daemon_pid)
    port = daemon_port!(daemon_ref)

    {:ok, conn} =
      :ssh.connect(
        ~c"127.0.0.1",
        port,
        [
          user: ~c"test",
          user_dir: String.to_charlist(host_dir),
          user_interaction: false,
          silently_accept_hosts: true,
          save_accepted_host: false
        ],
        @ssh_timeout
      )

    on_exit(fn -> :ssh.close(conn) end)
    %{conn: conn, daemon_ref: daemon_ref, port: port}
  end

  defp warm_login_config_cache! do
    _ = Foglet.Config.registration_mode()
    _ = Foglet.Config.delivery_mode()
  end

  defp reset_pubkey_stash! do
    if :ets.whereis(PubkeyStash) != :undefined do
      :ets.delete(PubkeyStash)
    end

    PubkeyStash.init()
  end

  defp reset_cli_counter! do
    table = Foglet.SSH.CLIHandler.Counter

    if :ets.whereis(table) != :undefined do
      :ets.delete(table)
    end

    CLIHandler.init_counter()
  end

  defp assert_counter!(expected) do
    assert [{:count, ^expected}] =
             :ets.lookup(Foglet.SSH.CLIHandler.Counter, :count)
  end

  defp reset_site_call_counter! do
    FogletBbs.Repo.delete_all(Foglet.SiteCounters.Counter)
  end

  defp openssh_text_for(public_key) do
    public_key
    |> then(&:ssh_file.encode([{&1, []}], :openssh_key))
    |> to_string()
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
end
