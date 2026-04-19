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

      assert Process.alive?(pid)
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
      assert Process.alive?(new_pid)
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

      assert Process.alive?(pid)
      # Guest sessions are not registered under any user_id key
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
      assert Process.alive?(pid1)
      assert Process.alive?(pid2)
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
