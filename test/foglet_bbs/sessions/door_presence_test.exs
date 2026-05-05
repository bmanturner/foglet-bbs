defmodule Foglet.Sessions.DoorPresenceTest do
  use ExUnit.Case, async: true

  alias Foglet.Doors.Manifest
  alias Foglet.Sessions.DoorPresence

  setup do
    server = {:global, {:door_presence_test, Ecto.UUID.generate()}}
    start_supervised!({DoorPresence, name: server})

    %{server: server, user_id: "user-" <> Ecto.UUID.generate()}
  end

  test "tracks a user's active door with a public display name", %{
    server: server,
    user_id: user_id
  } do
    runner = spawn_waiter()
    owner = self()

    assert :ok = DoorPresence.track(server, user_id, manifest("lord"), owner, runner)

    assert {:ok, %{id: "lord", name: "Legend of the Red Dragon"}} =
             DoorPresence.get(server, user_id)

    assert [%{user_id: ^user_id, runner_pid: ^runner, owner_pid: ^owner}] =
             DoorPresence.list(server)

    stop_process(runner)
  end

  test "ignores guest/nil users", %{server: server} do
    runner = spawn_waiter()

    assert :ok = DoorPresence.track(server, nil, manifest("lord"), self(), runner)

    assert DoorPresence.list(server) == []
    assert DoorPresence.get(server, nil) == :error

    stop_process(runner)
  end

  test "untrack_runner removes presence on normal door exit", %{server: server, user_id: user_id} do
    runner = spawn_waiter()
    :ok = DoorPresence.track(server, user_id, manifest("lord"), self(), runner)

    assert :ok = DoorPresence.untrack_runner(server, runner)

    assert DoorPresence.get(server, user_id) == :error
    assert DoorPresence.list(server) == []

    stop_process(runner)
  end

  test "owner crash removes presence without sleeps", %{server: server, user_id: user_id} do
    runner = spawn_waiter()
    owner = spawn_tracker(server, user_id, manifest("trade-wars"), runner)

    assert {:ok, %{id: "trade-wars", name: "Trade Wars 2002"}} = DoorPresence.get(server, user_id)

    stop_process(owner)

    assert eventually(fn -> DoorPresence.get(server, user_id) == :error end)
    assert DoorPresence.list(server) == []

    stop_process(runner)
  end

  test "runner crash removes presence without sleeps", %{server: server, user_id: user_id} do
    runner = spawn_tracker_runner()
    :ok = DoorPresence.track(server, user_id, manifest("lord"), self(), runner)

    assert {:ok, %{id: "lord"}} = DoorPresence.get(server, user_id)

    stop_process(runner)

    assert eventually(fn -> DoorPresence.get(server, user_id) == :error end)
    assert DoorPresence.list(server) == []
  end

  defp manifest(id) do
    %Manifest{
      id: id,
      slug: id,
      display_name: display_name(id),
      description: "door",
      runtime: :native_elixir,
      visibility: :members,
      auth_scope: :site,
      timeout_ms: 1_000
    }
  end

  defp display_name("lord"), do: "Legend of the Red Dragon"
  defp display_name("trade-wars"), do: "Trade Wars 2002"
  defp display_name(id), do: id

  defp spawn_waiter do
    spawn_link(fn ->
      receive do
        :stop -> :ok
      end
    end)
  end

  defp spawn_tracker(server, user_id, manifest, runner) do
    parent = self()

    pid =
      spawn_link(fn ->
        :ok = DoorPresence.track(server, user_id, manifest, self(), runner)
        send(parent, {:tracked, self()})

        receive do
          :stop -> :ok
        end
      end)

    assert_receive {:tracked, ^pid}, 1_000
    pid
  end

  defp spawn_tracker_runner do
    spawn_link(fn ->
      receive do
        :stop -> :ok
      end
    end)
  end

  defp stop_process(pid) when is_pid(pid) do
    ref = Process.monitor(pid)
    send(pid, :stop)

    assert_receive {:DOWN, ^ref, :process, ^pid, _reason}, 1_000
  end

  defp eventually(fun, attempts \\ 20)

  defp eventually(fun, attempts) when attempts > 0 do
    if fun.() do
      true
    else
      receive do
      after
        10 -> eventually(fun, attempts - 1)
      end
    end
  end

  defp eventually(_fun, 0), do: false
end
