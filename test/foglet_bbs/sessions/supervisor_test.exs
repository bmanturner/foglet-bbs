defmodule Foglet.Sessions.SupervisorTest do
  use ExUnit.Case, async: false

  alias Foglet.Sessions.Session
  alias Foglet.Sessions.Supervisor, as: Sup

  setup do
    %{user_id: Ecto.UUID.generate()}
  end

  describe "Foglet.Sessions.Supervisor (SSH-05)" do
    test "start_session/1 starts a Session", %{user_id: user_id} do
      assert {:ok, pid} =
               Sup.start_session(
                 user_id: user_id,
                 handle: "alice",
                 role: :user
               )

      on_exit(fn -> if Process.alive?(pid), do: Sup.terminate_session(user_id) end)

      # Registry lookup is a synchronous Registry call — proves the process is
      # alive and registered without resorting to Process.alive?/1 (per CLAUDE.md).
      assert {:ok, ^pid} = Sup.lookup_session(user_id)
    end

    test "start_session/1 replaces existing: old Session receives DOWN", %{user_id: user_id} do
      {:ok, old_pid} =
        Sup.start_session(user_id: user_id, handle: "alice", role: :user)

      ref = Process.monitor(old_pid)

      {:ok, new_pid} =
        Sup.start_session(user_id: user_id, handle: "alice2", role: :user)

      on_exit(fn -> if Process.alive?(new_pid), do: Sup.terminate_session(user_id) end)

      # Old session must be terminated, new one alive.
      assert_receive {:DOWN, ^ref, :process, ^old_pid, _}, 3_000
      assert new_pid != old_pid
      # Registry lookup + get_state below are synchronous calls into new_pid;
      # they would crash if the new session weren't alive, so an explicit
      # Process.alive?/1 assertion is redundant (per CLAUDE.md).
      assert {:ok, ^new_pid} = Sup.lookup_session(user_id)
      assert Session.get_state(user_id).handle == "alice2"
    end

    test "terminate_session/1 stops the running Session", %{user_id: user_id} do
      {:ok, pid} =
        Sup.start_session(user_id: user_id, handle: "alice", role: :user)

      ref = Process.monitor(pid)
      assert :ok = Sup.terminate_session(user_id)
      assert_receive {:DOWN, ^ref, :process, ^pid, _}, 1_000
      # Drain the Registry's mailbox so the unregistration is processed.
      _ = :sys.get_state(Foglet.Sessions.Registry)
      assert {:error, :not_found} = Sup.lookup_session(user_id)
    end

    test "terminate_session/1 returns :not_found for unknown user", %{user_id: user_id} do
      assert {:error, :not_found} = Sup.terminate_session(user_id)
    end

    test "lookup_session/1 returns {:ok, pid} | {:error, :not_found}", %{user_id: user_id} do
      assert {:error, :not_found} = Sup.lookup_session(user_id)

      {:ok, pid} =
        Sup.start_session(user_id: user_id, handle: "alice", role: :user)

      on_exit(fn -> if Process.alive?(pid), do: Sup.terminate_session(user_id) end)

      assert {:ok, ^pid} = Sup.lookup_session(user_id)
    end

    test "start_guest_session/0 starts an anonymous session not in Registry" do
      assert {:ok, pid} = Sup.start_guest_session()
      on_exit(fn -> if Process.alive?(pid), do: DynamicSupervisor.terminate_child(Sup, pid) end)

      # Session.get_state/1 below is a synchronous GenServer call into pid —
      # it would crash if the process weren't alive, so an explicit
      # Process.alive?/1 assertion is redundant (per CLAUDE.md).
      # Guest sessions are not registered under any user_id key.
      state = Session.get_state(pid)
      assert state.user_id == nil
    end

    test "multiple guest sessions can coexist" do
      {:ok, pid1} = Sup.start_guest_session()
      {:ok, pid2} = Sup.start_guest_session()

      on_exit(fn ->
        if Process.alive?(pid1), do: DynamicSupervisor.terminate_child(Sup, pid1)
        if Process.alive?(pid2), do: DynamicSupervisor.terminate_child(Sup, pid2)
      end)

      assert pid1 != pid2
      # Prove both sessions are alive deterministically via synchronous
      # GenServer calls rather than Process.alive?/1 (per CLAUDE.md). Each
      # Session.get_state/1 would crash the test if its target were dead.
      assert Session.get_state(pid1).user_id == nil
      assert Session.get_state(pid2).user_id == nil
    end

    test "promote_guest_session/2 with no existing session promotes the guest", %{
      user_id: user_id
    } do
      {:ok, guest_pid} = Sup.start_guest_session()

      on_exit(fn ->
        if Process.alive?(guest_pid), do: DynamicSupervisor.terminate_child(Sup, guest_pid)
      end)

      user = %Foglet.Accounts.User{id: user_id, handle: "alice", role: :user}
      assert :ok = Sup.promote_guest_session(guest_pid, user)

      # Allow the cast to be processed
      _ = :sys.get_state(guest_pid)

      assert [{^guest_pid, _}] = Registry.lookup(Foglet.Sessions.Registry, user_id)
      state = Session.get_state(guest_pid)
      assert state.user_id == user_id
      assert state.handle == "alice"
      assert state.role == :user
    end

    test "promote_guest_session/2 is a no-op when guest is already the registered session",
         %{user_id: user_id} do
      {:ok, guest_pid} = Sup.start_guest_session()

      on_exit(fn ->
        if Process.alive?(guest_pid), do: DynamicSupervisor.terminate_child(Sup, guest_pid)
      end)

      user = %Foglet.Accounts.User{id: user_id, handle: "alice", role: :user}

      # First promotion registers the guest under user_id
      assert :ok = Sup.promote_guest_session(guest_pid, user)
      _ = :sys.get_state(guest_pid)
      assert [{^guest_pid, _}] = Registry.lookup(Foglet.Sessions.Registry, user_id)

      # Second call with the same guest_pid must be a no-op (idempotent)
      assert :ok = Sup.promote_guest_session(guest_pid, user)
      _ = :sys.get_state(guest_pid)
      assert [{^guest_pid, _}] = Registry.lookup(Foglet.Sessions.Registry, user_id)
    end

    test "promote_guest_session/2 replaces existing session when guest promotes to a user who already has one",
         %{user_id: user_id} do
      # Start an existing authenticated session for user_A
      {:ok, old_pid} =
        Sup.start_session(user_id: user_id, handle: "alice", role: :user)

      old_ref = Process.monitor(old_pid)

      # Start a fresh guest session (simulating a new SSH connection)
      {:ok, guest_pid} = Sup.start_guest_session()

      on_exit(fn ->
        if Process.alive?(guest_pid), do: DynamicSupervisor.terminate_child(Sup, guest_pid)
      end)

      user = %Foglet.Accounts.User{id: user_id, handle: "alice", role: :user}

      # Promoting the guest must replace the old session
      assert :ok = Sup.promote_guest_session(guest_pid, user)

      # Old session must receive :replaced_by_new_session and terminate
      assert_receive {:DOWN, ^old_ref, :process, ^old_pid, :normal}, 3_000

      # Allow the promote cast to be processed
      _ = :sys.get_state(guest_pid)

      # Registry now points to the promoted guest pid
      assert [{^guest_pid, _}] = Registry.lookup(Foglet.Sessions.Registry, user_id)

      state = Session.get_state(guest_pid)
      assert state.user_id == user_id
      assert state.handle == "alice"
      assert state.role == :user
    end

    test "promote_guest_session/3 accepts audit metadata and promotes the guest", %{
      user_id: user_id
    } do
      {:ok, guest_pid} = Sup.start_guest_session()

      on_exit(fn ->
        if Process.alive?(guest_pid), do: DynamicSupervisor.terminate_child(Sup, guest_pid)
      end)

      user = %Foglet.Accounts.User{id: user_id, handle: "alice", role: :user}

      assert :ok =
               Sup.promote_guest_session(guest_pid, user,
                 audit: %{ssh_peer: {{127, 0, 0, 1}, 2222}}
               )

      _ = :sys.get_state(guest_pid)

      assert [{^guest_pid, _}] = Registry.lookup(Foglet.Sessions.Registry, user_id)
      state = Session.get_state(guest_pid)
      assert state.user_id == user_id
      assert state.handle == "alice"
      assert state.role == :user
    end

    test "promote_guest_session/2 force-terminates a session that does not stop gracefully",
         %{user_id: user_id} do
      # Simulate a session that holds the Registry slot but never exits on
      # :replaced_by_new_session. We spawn an unlinked process (so the test
      # process is not killed when the supervisor force-kills the holder), trap
      # exits inside it, and swallow all messages. The Supervisor will time out
      # waiting for a DOWN and fall back to Process.exit(:kill).
      test_pid = self()

      # spawn/1 creates an unlinked process — EXIT from holder_pid will not
      # propagate to the test process even when killed with :kill.
      holder_pid =
        spawn(fn ->
          Process.flag(:trap_exit, true)
          {:ok, _} = Registry.register(Foglet.Sessions.Registry, user_id, nil)
          send(test_pid, :holder_ready)

          # Absorb :replaced_by_new_session and all other messages without exiting.
          # :trap_exit converts EXIT signals to messages, so even :kill as an
          # info msg lands here — but :kill bypasses trap_exit at the OS level.
          loop = fn loop ->
            receive do
              _ -> loop.(loop)
            end
          end

          loop.(loop)
        end)

      assert_receive :holder_ready, 1_000
      holder_ref = Process.monitor(holder_pid)

      {:ok, guest_pid} = Sup.start_guest_session()

      on_exit(fn ->
        if Process.alive?(holder_pid), do: Process.exit(holder_pid, :kill)
        if Process.alive?(guest_pid), do: DynamicSupervisor.terminate_child(Sup, guest_pid)
      end)

      user = %Foglet.Accounts.User{id: user_id, handle: "alice", role: :user}

      # promote_guest_session finds holder_pid in the Registry, sends
      # :replaced_by_new_session, waits @replacement_timeout_ms (2 s), then
      # falls back: terminate_child returns :not_found → Process.exit(:kill).
      # Total wait is ~2 s; give 5 s headroom.
      assert :ok = Sup.promote_guest_session(guest_pid, user)

      # holder_pid was force-killed during the timeout fallback
      assert_receive {:DOWN, ^holder_ref, :process, ^holder_pid, _}, 5_000

      # guest_pid now holds the Registry slot
      _ = :sys.get_state(guest_pid)
      assert [{^guest_pid, _}] = Registry.lookup(Foglet.Sessions.Registry, user_id)

      state = Session.get_state(guest_pid)
      assert state.user_id == user_id
    end

    test "concurrent start_session calls for same user_id leave exactly one alive",
         %{user_id: user_id} do
      results =
        1..5
        |> Task.async_stream(
          fn i ->
            Sup.start_session(user_id: user_id, handle: "alice#{i}", role: :user)
          end,
          timeout: :infinity,
          max_concurrency: 5
        )
        |> Enum.map(fn {:ok, r} -> r end)

      # Each call returns {:ok, pid}.
      assert Enum.all?(results, &match?({:ok, _}, &1))

      # Monitor all returned pids; wait for any extras to settle (those that
      # were replaced by a concurrent call will send a DOWN shortly).
      all_pids = Enum.map(results, fn {:ok, pid} -> pid end) |> Enum.uniq()
      refs = Enum.map(all_pids, fn pid -> {pid, Process.monitor(pid)} end)

      # Drain DOWN messages until only one pid is alive in the Registry.
      Enum.each(refs, fn {pid, ref} ->
        if Process.alive?(pid) do
          # Flush any stale DOWN already in the mailbox.
          receive do
            {:DOWN, ^ref, :process, ^pid, _} -> :ok
          after
            200 ->
              Process.demonitor(ref, [:flush])
          end
        else
          Process.demonitor(ref, [:flush])
        end
      end)

      assert [{_final_pid, _}] = Registry.lookup(Foglet.Sessions.Registry, user_id)

      on_exit(fn ->
        case Sup.lookup_session(user_id) do
          {:ok, _pid} -> Sup.terminate_session(user_id)
          _ -> :ok
        end
      end)
    end
  end
end
