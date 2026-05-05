defmodule Foglet.SSH.CLIHandlerDoorPresenceTest do
  use FogletBbs.DataCase, async: false

  alias Foglet.Doors.Manifest
  alias Foglet.Sessions.{DoorPresence, Session, Supervisor}
  alias Foglet.SSH.CLIHandler
  alias FogletBbs.AccountsFixtures

  setup do
    user = AccountsFixtures.user_fixture()
    {:ok, guest_session} = Supervisor.start_guest_session()
    runner = spawn_waiter()

    on_exit(fn ->
      DoorPresence.untrack_runner(runner)
      stop_runner(runner)
      stop_session(guest_session)
    end)

    %{user: user, guest_session: guest_session, runner: runner}
  end

  test "tracks door presence for password-promoted TUI sessions", %{
    user: user,
    guest_session: session,
    runner: runner
  } do
    Supervisor.promote_guest_session(session, user)
    assert %Session{user_id: user_id} = Session.get_state(session)
    assert user_id == user.id

    state = %CLIHandler{
      session_pid: session,
      door_runner_pid: runner,
      active_door_manifest: manifest("lord")
    }

    assert {:ok, ^state} = CLIHandler.handle_msg({:door_started, runner, "lord"}, state)

    assert {:ok, %{id: "lord", name: "Legend of the Red Dragon"}} = DoorPresence.get(user.id)
  end

  test "still ignores guest sessions with no authenticated user", %{
    user: user,
    guest_session: session,
    runner: runner
  } do
    assert %Session{user_id: nil} = Session.get_state(session)

    state = %CLIHandler{
      session_pid: session,
      door_runner_pid: runner,
      active_door_manifest: manifest("lord")
    }

    assert {:ok, ^state} = CLIHandler.handle_msg({:door_started, runner, "lord"}, state)

    assert DoorPresence.get(user.id) == :error
  end

  defp manifest(id) do
    %Manifest{
      id: id,
      slug: id,
      display_name: "Legend of the Red Dragon",
      description: "door",
      runtime: :native_elixir,
      visibility: :members,
      auth_scope: :site,
      timeout_ms: 1_000
    }
  end

  defp spawn_waiter do
    spawn_link(fn ->
      receive do
        :stop -> :ok
      end
    end)
  end

  defp stop_runner(pid) when is_pid(pid) do
    if Process.alive?(pid) do
      ref = Process.monitor(pid)
      send(pid, :stop)

      receive do
        {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
      after
        1_000 -> :ok
      end
    end
  end

  defp stop_session(pid) when is_pid(pid) do
    if Process.alive?(pid), do: DynamicSupervisor.terminate_child(Supervisor, pid)
  end
end
