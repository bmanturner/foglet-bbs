defmodule Foglet.Sessions.DoorPresence do
  @moduledoc """
  Tracks authenticated users currently running a door game.

  Entries are ephemeral runtime presence tied to both the owning SSH channel
  process and the door runner process via monitors. Normal door exit removes
  the entry explicitly; owner or runner crashes remove it automatically. Guests
  (`nil` user ids) are ignored so public profile presence never exposes guest
  activity.
  """

  use GenServer

  alias Foglet.Doors.Manifest
  alias Foglet.Sessions.OnlinePresence

  @type door :: %{id: binary(), name: binary()}
  @type entry :: %{
          user_id: binary(),
          door: door(),
          owner_pid: pid(),
          runner_pid: pid()
        }

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Track `user_id` as playing `door` under the caller and `runner_pid` lifetimes.

  The public API uses the application singleton. Tests can pass a custom server
  name as the first argument to avoid shared state.
  """
  @spec track(binary() | nil, Manifest.t() | map(), pid()) :: :ok
  def track(user_id, door, runner_pid), do: track(__MODULE__, user_id, door, self(), runner_pid)

  @spec track(GenServer.server(), binary() | nil, Manifest.t() | map(), pid(), pid()) :: :ok
  def track(_server, nil, _door, _owner_pid, _runner_pid), do: :ok

  def track(server, user_id, door, owner_pid, runner_pid)
      when is_binary(user_id) and is_pid(owner_pid) and is_pid(runner_pid) do
    GenServer.call(server, {:track, user_id, door_summary(door), owner_pid, runner_pid})
  end

  @doc "Remove the caller's door-presence entry for `user_id`."
  @spec untrack(binary() | nil) :: :ok
  def untrack(user_id), do: untrack(__MODULE__, user_id, self())

  @spec untrack(GenServer.server(), binary() | nil, pid()) :: :ok
  def untrack(_server, nil, _owner_pid), do: :ok

  def untrack(server, user_id, owner_pid) when is_binary(user_id) and is_pid(owner_pid) do
    GenServer.call(server, {:untrack_owner, user_id, owner_pid})
  end

  @doc "Remove a door-presence entry by its runner pid."
  @spec untrack_runner(pid() | nil) :: :ok
  def untrack_runner(runner_pid), do: untrack_runner(__MODULE__, runner_pid)

  @spec untrack_runner(GenServer.server(), pid() | nil) :: :ok
  def untrack_runner(_server, nil), do: :ok

  def untrack_runner(server, runner_pid) when is_pid(runner_pid) do
    GenServer.call(server, {:untrack_runner, runner_pid})
  end

  @doc "Return the highest-priority active door for `user_id`, if any."
  @spec get(binary() | nil) :: {:ok, door()} | :error
  def get(user_id), do: get(__MODULE__, user_id)

  @spec get(GenServer.server(), binary() | nil) :: {:ok, door()} | :error
  def get(_server, nil), do: :error

  def get(server, user_id) when is_binary(user_id) do
    GenServer.call(server, {:get, user_id})
  end

  @doc false
  @spec list(GenServer.server()) :: [entry()]
  def list(server \\ __MODULE__), do: GenServer.call(server, :list)

  @impl true
  def init(_opts), do: {:ok, %{entries: %{}, by_user: %{}}}

  @impl true
  def handle_call({:track, user_id, door, owner_pid, runner_pid}, _from, state) do
    state =
      state
      |> drop_user_owner(user_id, owner_pid)
      |> put_entry(user_id, door, owner_pid, runner_pid)

    broadcast_activity_changed(user_id)

    {:reply, :ok, state}
  end

  def handle_call({:untrack_owner, user_id, owner_pid}, _from, state) do
    state = drop_user_owner(state, user_id, owner_pid)
    broadcast_activity_changed(user_id)

    {:reply, :ok, state}
  end

  def handle_call({:untrack_runner, runner_pid}, _from, state) do
    {state, user_id} = drop_runner_with_user(state, runner_pid)
    broadcast_activity_changed(user_id)

    {:reply, :ok, state}
  end

  def handle_call({:get, user_id}, _from, state) do
    reply =
      state.by_user
      |> Map.get(user_id, MapSet.new())
      |> Enum.map(&Map.fetch!(state.entries, &1))
      |> Enum.sort_by(&entry_sort_key/1)
      |> List.first()
      |> case do
        nil -> :error
        entry -> {:ok, entry.door}
      end

    {:reply, reply, state}
  end

  def handle_call(:list, _from, state) do
    entries =
      state.entries
      |> Map.values()
      |> Enum.uniq_by(& &1.owner_ref)
      |> Enum.map(&public_entry/1)

    {:reply, entries, state}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    {state, user_id} = drop_ref_with_user(state, ref)
    broadcast_activity_changed(user_id)

    {:noreply, state}
  end

  defp put_entry(state, user_id, door, owner_pid, runner_pid) do
    owner_ref = Process.monitor(owner_pid)
    runner_ref = Process.monitor(runner_pid)

    entry = %{
      user_id: user_id,
      door: door,
      owner_pid: owner_pid,
      runner_pid: runner_pid,
      owner_ref: owner_ref,
      runner_ref: runner_ref,
      inserted_at: System.monotonic_time()
    }

    entries = state.entries |> Map.put(owner_ref, entry) |> Map.put(runner_ref, entry)

    by_user =
      Map.update(state.by_user, user_id, MapSet.new([owner_ref]), &MapSet.put(&1, owner_ref))

    %{state | entries: entries, by_user: by_user}
  end

  defp drop_user_owner(state, user_id, owner_pid) do
    state.by_user
    |> Map.get(user_id, MapSet.new())
    |> Enum.find_value(state, fn ref ->
      case Map.fetch(state.entries, ref) do
        {:ok, %{owner_pid: ^owner_pid} = entry} -> drop_entry(state, entry)
        _ -> false
      end
    end)
  end

  defp drop_runner_with_user(state, runner_pid) do
    Enum.find_value(state.entries, state, fn
      {_ref, %{runner_pid: ^runner_pid} = entry} -> {drop_entry(state, entry), entry.user_id}
      _ -> false
    end)
    |> case do
      {state, user_id} -> {state, user_id}
      state -> {state, nil}
    end
  end

  defp drop_ref_with_user(state, ref) do
    case Map.fetch(state.entries, ref) do
      {:ok, entry} -> {drop_entry(state, entry), entry.user_id}
      :error -> {state, nil}
    end
  end

  defp broadcast_activity_changed(user_id) when is_binary(user_id) do
    OnlinePresence.broadcast(:activity_changed, %{source: :door_presence, user_id: user_id})
  end

  defp broadcast_activity_changed(_user_id), do: :ok

  defp drop_entry(state, entry) do
    Process.demonitor(entry.owner_ref, [:flush])
    Process.demonitor(entry.runner_ref, [:flush])

    entries =
      state.entries
      |> Map.delete(entry.owner_ref)
      |> Map.delete(entry.runner_ref)

    by_user =
      state.by_user
      |> Map.update(entry.user_id, MapSet.new(), &MapSet.delete(&1, entry.owner_ref))
      |> prune_empty_user(entry.user_id)

    %{state | entries: entries, by_user: by_user}
  end

  defp prune_empty_user(by_user, user_id) do
    case Map.get(by_user, user_id) do
      set when is_struct(set, MapSet) ->
        if MapSet.size(set) == 0, do: Map.delete(by_user, user_id), else: by_user

      _ ->
        by_user
    end
  end

  defp public_entry(entry) do
    %{
      user_id: entry.user_id,
      door: entry.door,
      owner_pid: entry.owner_pid,
      runner_pid: entry.runner_pid
    }
  end

  defp entry_sort_key(entry), do: {entry.door.name, entry.door.id, entry.inserted_at}

  defp door_summary(%Manifest{id: id, display_name: name}), do: normalize_door(id, name)

  defp door_summary(%{id: id, display_name: name}), do: normalize_door(id, name)
  defp door_summary(%{id: id, name: name}), do: normalize_door(id, name)
  defp door_summary(%{"id" => id, "display_name" => name}), do: normalize_door(id, name)
  defp door_summary(%{"id" => id, "name" => name}), do: normalize_door(id, name)
  defp door_summary(other), do: normalize_door(to_string(other), to_string(other))

  defp normalize_door(id, name) do
    id = id |> to_string() |> String.trim()
    name = name |> to_string() |> String.trim()

    %{
      id: if(id == "", do: "door", else: id),
      name: if(name == "", do: id_or_default(id), else: name)
    }
  end

  defp id_or_default(""), do: "Door"
  defp id_or_default(id), do: id
end
