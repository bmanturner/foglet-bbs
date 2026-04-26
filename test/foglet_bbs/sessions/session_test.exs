defmodule Foglet.Sessions.SessionTest do
  use ExUnit.Case, async: false

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

    test "heartbeat advances last_seen_at", %{user_id: user_id} do
      {:ok, _pid} =
        start_supervised({Session, [user_id: user_id, handle: "alice", role: :user]})

      initial = Session.get_state(user_id).last_seen_at
      # Ensure a measurable time delta.
      :ok = Session.heartbeat(user_id)
      _ = :sys.get_state(Session.via_tuple(user_id))

      later = Session.get_state(user_id).last_seen_at
      assert DateTime.compare(later, initial) in [:eq, :gt]
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
