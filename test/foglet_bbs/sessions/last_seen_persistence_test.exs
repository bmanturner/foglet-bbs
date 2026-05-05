defmodule Foglet.Sessions.LastSeenPersistenceTest do
  use FogletBbs.DataCase, async: false

  alias Foglet.Accounts
  alias Foglet.Sessions.Session
  alias Foglet.Sessions.Supervisor, as: SessionsSupervisor
  alias FogletBbs.AccountsFixtures
  alias FogletBbs.Repo

  describe "authenticated session last_seen_at persistence" do
    test "authenticated session start records a persisted connect timestamp" do
      user = AccountsFixtures.user_fixture()

      assert {:ok, pid} =
               SessionsSupervisor.start_session(
                 user_id: user.id,
                 handle: user.handle,
                 role: user.role
               )

      _ = :sys.get_state(pid)

      assert %DateTime{} = Repo.reload!(user).last_seen_at
    end

    test "guest session start and stop do not update any user row" do
      user = AccountsFixtures.user_fixture()

      assert {:ok, pid} = SessionsSupervisor.start_guest_session()
      assert :ok = DynamicSupervisor.terminate_child(SessionsSupervisor, pid)

      assert Repo.reload!(user).last_seen_at == nil
    end

    test "promotion records a persisted member timestamp" do
      user = AccountsFixtures.user_fixture()
      assert {:ok, pid} = SessionsSupervisor.start_guest_session()

      assert :ok = SessionsSupervisor.promote_guest_session(pid, user)
      _ = :sys.get_state(pid)

      assert %DateTime{} = Repo.reload!(user).last_seen_at
      assert Session.get_state(pid).user_id == user.id
    end

    test "heartbeat remains in-memory and does not write every tick" do
      user = AccountsFixtures.user_fixture()

      assert {:ok, pid} =
               SessionsSupervisor.start_session(
                 user_id: user.id,
                 handle: user.handle,
                 role: user.role
               )

      persisted_after_connect = Repo.reload!(user).last_seen_at
      state_after_connect = Session.get_state(pid).last_seen_at

      assert :ok = Session.heartbeat(pid)
      _ = :sys.get_state(pid)

      assert DateTime.compare(Session.get_state(pid).last_seen_at, state_after_connect) in [
               :eq,
               :gt
             ]

      assert Repo.reload!(user).last_seen_at == persisted_after_connect
    end

    test "disconnect records a persisted timestamp without regressing a newer value" do
      user = AccountsFixtures.user_fixture()
      future = ~U[2030-01-01 00:00:00.000000Z]

      assert {:ok, pid} =
               SessionsSupervisor.start_session(
                 user_id: user.id,
                 handle: user.handle,
                 role: user.role
               )

      assert :ok = Accounts.record_last_seen(user.id, future)
      ref = Process.monitor(pid)

      assert :ok = SessionsSupervisor.terminate_session(user.id)
      assert_receive {:DOWN, ^ref, :process, ^pid, _reason}, 1_000

      assert Repo.reload!(user).last_seen_at == future
    end

    test "session replacement stops the old session and preserves monotonic last_seen_at" do
      user = AccountsFixtures.user_fixture()
      future = ~U[2030-01-01 00:00:00.000000Z]

      assert {:ok, old_pid} =
               SessionsSupervisor.start_session(
                 user_id: user.id,
                 handle: user.handle,
                 role: user.role
               )

      assert :ok = Accounts.record_last_seen(user.id, future)
      old_ref = Process.monitor(old_pid)

      assert {:ok, new_pid} =
               SessionsSupervisor.start_session(
                 user_id: user.id,
                 handle: user.handle,
                 role: user.role
               )

      assert_receive {:DOWN, ^old_ref, :process, ^old_pid, :normal}, 1_000
      assert new_pid != old_pid
      assert Repo.reload!(user).last_seen_at == future
    end
  end
end
