defmodule Foglet.Sessions.SessionTest do
  use FogletBbs.DataCase, async: false

  import ExUnit.CaptureLog

  alias Foglet.Accounts.User
  alias Foglet.Sessions.Preferences
  alias Foglet.Sessions.Session
  alias Foglet.TUI.Theme

  setup do
    # Registry and DynamicSupervisor are started by the application —
    # but each test creates its own user_id to avoid clashes.
    user_id = Ecto.UUID.generate()
    %{user_id: user_id}
  end

  describe "Foglet.Sessions.Preferences.from_user/1" do
    test "builds a snapshot from persisted user preferences" do
      user =
        %User{preferences: %{"time_format" => "24h"}, theme: "amber"}
        |> Map.put(:timezone, "America/Chicago")

      snapshot = Preferences.from_user(user)

      assert snapshot.timezone == "America/Chicago"
      assert snapshot.time_format == "24h"
      assert snapshot.theme_id == "amber"
      assert snapshot.theme == Theme.resolve(:amber)
    end

    test "falls back to default preferences when values are missing" do
      assert Preferences.from_user(nil) == %{
               timezone: "Etc/UTC",
               time_format: "12h",
               theme_id: "gray",
               theme: Theme.default()
             }

      snapshot = Preferences.from_user(%User{preferences: nil, theme: nil})

      assert snapshot.timezone == "Etc/UTC"
      assert snapshot.time_format == "12h"
      assert snapshot.theme_id == "gray"
      assert snapshot.theme == Theme.default()
    end
  end

  describe "Foglet.Sessions.Session (SSH-05)" do
    test "start_link registers in Foglet.Sessions.Registry for authenticated user", %{
      user_id: user_id
    } do
      {:ok, pid} =
        start_supervised(
          {Session, [user_id: user_id, handle: "alice", role: :user, terminal_size: {80, 24}]}
        )

      assert [{^pid, _}] = Registry.lookup(Foglet.Sessions.Registry, user_id)
    end

    test "second start_link for same user_id returns :already_started", %{user_id: user_id} do
      {:ok, pid1} =
        start_supervised(
          {Session, [user_id: user_id, handle: "alice", role: :user]},
          id: :first
        )

      result = Session.start_link(user_id: user_id, handle: "alice2", role: :user)

      assert {:error, {:already_started, ^pid1}} = result
    end

    test "state holds user_id, handle, role, default terminal_size", %{user_id: user_id} do
      {:ok, _pid} =
        start_supervised({Session, [user_id: user_id, handle: "alice", role: :mod]})

      state = Session.get_state(user_id)
      assert state.user_id == user_id
      assert state.handle == "alice"
      assert state.role == :mod
      assert state.terminal_size == {80, 24}
      assert %DateTime{} = state.connected_at
      assert state.timezone == "Etc/UTC"
      assert state.time_format == "12h"
      assert state.theme_id == "gray"
      assert state.theme == Theme.default()
    end

    test ":replaced_by_new_session terminates cleanly", %{user_id: user_id} do
      {:ok, pid} =
        start_supervised({Session, [user_id: user_id, handle: "alice", role: :user]})

      ref = Process.monitor(pid)
      send(pid, :replaced_by_new_session)

      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 1_000
    end

    test "heartbeat advances last_seen_at without resetting last_action_at", %{user_id: user_id} do
      {:ok, _pid} =
        start_supervised({Session, [user_id: user_id, handle: "alice", role: :user]})

      initial = Session.get_state(user_id)

      # Ensure a measurable time delta.
      :ok = Session.heartbeat(user_id)
      _ = :sys.get_state(Session.via_tuple(user_id))

      later = Session.get_state(user_id)
      assert DateTime.compare(later.last_seen_at, initial.last_seen_at) in [:eq, :gt]
      assert later.last_action_at == initial.last_action_at
    end

    test "record_user_action advances last_action_at without touching last_seen_at", %{
      user_id: user_id
    } do
      {:ok, _pid} =
        start_supervised({Session, [user_id: user_id, handle: "alice", role: :user]})

      old_action_at = ~U[2026-05-05 12:00:00Z]

      :sys.replace_state(Session.via_tuple(user_id), fn state ->
        %{state | last_action_at: old_action_at}
      end)

      before_action = Session.get_state(user_id)
      :ok = Session.record_user_action(user_id)
      _ = :sys.get_state(Session.via_tuple(user_id))

      after_action = Session.get_state(user_id)
      assert DateTime.compare(after_action.last_action_at, old_action_at) == :gt
      assert after_action.last_seen_at == before_action.last_seen_at
    end

    test "idle threshold is three minutes and requires an authenticated user", %{user_id: user_id} do
      now = ~U[2026-05-05 12:03:00Z]

      refute Session.idle?(
               %{user_id: user_id, last_action_at: ~U[2026-05-05 12:00:01Z]},
               now
             )

      assert Session.idle?(
               %{user_id: user_id, last_action_at: ~U[2026-05-05 12:00:00Z]},
               now
             )

      refute Session.idle?(%{user_id: nil, last_action_at: ~U[2026-05-05 12:00:00Z]}, now)
      refute Session.idle?(%{user_id: user_id, last_action_at: nil}, now)
    end

    test "guest record_user_action leaves last_action_at unset" do
      {:ok, pid} = start_supervised({Session, [user_id: nil]})

      :ok = Session.record_user_action(pid)
      _ = :sys.get_state(pid)

      assert Session.get_state(pid).last_action_at == nil
    end

    test "terminal_size cast updates state", %{user_id: user_id} do
      {:ok, _pid} =
        start_supervised({Session, [user_id: user_id, handle: "alice", role: :user]})

      :ok = Session.set_terminal_size(user_id, {132, 50})
      _ = :sys.get_state(Session.via_tuple(user_id))

      assert Session.get_state(user_id).terminal_size == {132, 50}
    end
  end

  describe "guest sessions (user_id: nil)" do
    test "start_link with user_id: nil does NOT register in Registry" do
      {:ok, pid} = start_supervised({Session, [user_id: nil]})
      # :sys.get_state/1 proves liveness without Process.alive?/1 (per AGENTS.md).
      _ = :sys.get_state(pid)
      # No user_id key to look up — Registry should have no entry for nil
      assert Registry.lookup(Foglet.Sessions.Registry, nil) == []
    end

    test "guest session state has nil user_id and handle" do
      {:ok, pid} = start_supervised({Session, [user_id: nil]})
      state = Session.get_state(pid)
      assert state.user_id == nil
      assert state.handle == nil
    end
  end

  describe "promote_to_user/2" do
    test "updates user_id, handle, role, and preferences in state", %{user_id: user_id} do
      {:ok, pid} = start_supervised({Session, [user_id: nil]})

      user =
        %Foglet.Accounts.User{
          id: user_id,
          handle: "promoted",
          role: :user,
          preferences: %{"time_format" => "24h"},
          theme: "amber"
        }
        |> Map.put(:timezone, "America/Chicago")

      :ok = Session.promote_to_user(pid, user)
      _ = :sys.get_state(pid)

      state = Session.get_state(pid)
      assert state.user_id == user_id
      assert state.handle == "promoted"
      assert state.role == :user
      assert state.timezone == "America/Chicago"
      assert state.time_format == "24h"
      assert state.theme_id == "amber"
      assert state.theme == Theme.resolve(:amber)
    end

    test "registers the promoted session in the Registry", %{user_id: user_id} do
      {:ok, pid} = start_supervised({Session, [user_id: nil]})

      user = %Foglet.Accounts.User{id: user_id, handle: "promoted", role: :user}
      :ok = Session.promote_to_user(pid, user)
      # Allow the cast to be processed
      _ = :sys.get_state(pid)

      assert [{^pid, _}] = Registry.lookup(Foglet.Sessions.Registry, user_id)
    end

    test "registry collision logs a privacy-safe warning and stops the second session",
         %{user_id: user_id} do
      # First session owns the registry slot for user_id.
      {:ok, owner_pid} =
        start_supervised(
          {Session, [user_id: user_id, handle: "owner", role: :user]},
          id: :owner
        )

      # Second guest session attempts to promote to the same user_id and must
      # lose. Spawn outside the supervisor so the {:registry_collision, _}
      # stop reason doesn't crash the test process.
      Process.flag(:trap_exit, true)
      {:ok, guest_pid} = Session.start_link(user_id: nil)
      ref = Process.monitor(guest_pid)

      user = %Foglet.Accounts.User{id: user_id, handle: "intruder", role: :user}
      ssh_peer = {{127, 0, 0, 1}, 4242}
      bogus_secret = "ULTRA_SECRET_TOKEN_DO_NOT_LEAK"

      log =
        capture_log([level: :warning], fn ->
          :ok =
            Session.promote_to_user(guest_pid, user, %{
              ssh_peer: ssh_peer,
              # Pretend the audit map carries something sensitive — the
              # FOG-674 warning line must NOT echo it.
              session_secret: bogus_secret
            })

          assert_receive {:DOWN, ^ref, :process, ^guest_pid, {:registry_collision, ^user_id}},
                         1_000
        end)

      collision_line =
        log
        |> String.split("\n")
        |> Enum.find(&String.contains?(&1, "registry collision"))

      assert is_binary(collision_line), "expected a `registry collision` warning line in: #{log}"
      assert collision_line =~ "user_id=#{user_id}"
      assert collision_line =~ "ssh_peer="
      assert collision_line =~ "other_pid="
      assert collision_line =~ inspect(owner_pid)
      refute collision_line =~ bogus_secret
      refute collision_line =~ "session_secret"

      # Owner session is undisturbed and still registered.
      assert [{^owner_pid, _}] = Registry.lookup(Foglet.Sessions.Registry, user_id)
    end

    test "registry collision falls back to ssh_peer=unknown when audit lacks the key",
         %{user_id: user_id} do
      {:ok, _owner_pid} =
        start_supervised(
          {Session, [user_id: user_id, handle: "owner", role: :user]},
          id: :owner
        )

      Process.flag(:trap_exit, true)
      {:ok, guest_pid} = Session.start_link(user_id: nil)
      ref = Process.monitor(guest_pid)

      user = %Foglet.Accounts.User{id: user_id, handle: "intruder", role: :user}

      log =
        capture_log(fn ->
          :ok = Session.promote_to_user(guest_pid, user, %{})
          assert_receive {:DOWN, ^ref, :process, ^guest_pid, _}, 1_000
        end)

      assert log =~ "ssh_peer=unknown"
    end

    test "promote_to_user/3 accepts audit metadata and reaches the same user state",
         %{user_id: user_id} do
      {:ok, pid} = start_supervised({Session, [user_id: nil]})

      user = %Foglet.Accounts.User{id: user_id, handle: "promoted", role: :user}

      :ok =
        Session.promote_to_user(pid, user, %{
          ssh_peer: {{127, 0, 0, 1}, 2222},
          replacement: :none
        })

      _ = :sys.get_state(pid)

      state = Session.get_state(pid)
      assert state.user_id == user_id
      assert state.handle == "promoted"
      assert state.role == :user
      assert [{^pid, _}] = Registry.lookup(Foglet.Sessions.Registry, user_id)
    end
  end

  describe "update_preferences/2" do
    test "updates only preference snapshot fields for a user struct", %{user_id: user_id} do
      {:ok, _pid} =
        start_supervised({Session, [user_id: user_id, handle: "alice", role: :mod]})

      user =
        %User{preferences: %{"time_format" => "24h"}, theme: "amber"}
        |> Map.put(:timezone, "America/Chicago")

      :ok = Session.update_preferences(user_id, user)
      _ = :sys.get_state(Session.via_tuple(user_id))

      state = Session.get_state(user_id)
      assert state.user_id == user_id
      assert state.handle == "alice"
      assert state.role == :mod
      assert state.timezone == "America/Chicago"
      assert state.time_format == "24h"
      assert state.theme_id == "amber"
      assert state.theme == Theme.resolve(:amber)
    end

    test "updates preference snapshot fields from an existing snapshot" do
      {:ok, pid} = start_supervised({Session, [user_id: nil]})

      snapshot = %{
        timezone: "America/Chicago",
        time_format: "24h",
        theme_id: "amber",
        theme: Theme.resolve(:amber)
      }

      :ok = Session.update_preferences(pid, snapshot)
      _ = :sys.get_state(pid)

      state = Session.get_state(pid)
      assert state.user_id == nil
      assert state.timezone == "America/Chicago"
      assert state.time_format == "24h"
      assert state.theme_id == "amber"
      assert state.theme == Theme.resolve(:amber)
    end
  end
end
