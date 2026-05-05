defmodule Foglet.Sessions.ActivityPresence do
  @moduledoc """
  Central ephemeral live-activity boundary for public profile presence.

  Entries are authenticated-member-only and tied to the caller process with a
  monitor. Route reducers and app-level navigation update the caller's current
  low-hanging BBS activity; process exit clears it automatically.

  This tracker intentionally does not feed board chat counts. Chat membership
  and the `CHAT (#)` sidebar/count stay owned by `Foglet.Sessions.BoardScreen`.
  """

  use GenServer

  @type board :: map()
  @type activity ::
          :board_list
          | {:browsing_board, board()}
          | {:reading_board, board()}
          | {:chatting_in_board, board()}

  @type entry :: %{user_id: binary(), activity: activity(), pid: pid()}

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @spec track(binary() | nil, activity()) :: :ok
  def track(nil, _activity), do: :ok

  def track(user_id, activity) when is_binary(user_id) do
    GenServer.call(__MODULE__, {:track, user_id, normalize_activity(activity), self()})
  end

  @spec clear(binary() | nil) :: :ok
  def clear(nil), do: :ok

  def clear(user_id) when is_binary(user_id) do
    GenServer.call(__MODULE__, {:clear, user_id, self()})
  end

  @spec get(binary() | nil) :: {:ok, activity()} | :error
  def get(nil), do: :error

  def get(user_id) when is_binary(user_id) do
    GenServer.call(__MODULE__, {:get, user_id})
  end

  @spec list() :: [entry()]
  def list do
    GenServer.call(__MODULE__, :list)
  end

  @impl true
  def init(_opts) do
    {:ok, %{entries: %{}, by_user: %{}}}
  end

  @impl true
  def handle_call({:track, user_id, activity, pid}, _from, state) do
    state =
      state
      |> drop_pid_entry(user_id, pid)
      |> put_entry(user_id, activity, pid)

    {:reply, :ok, state}
  end

  def handle_call({:clear, user_id, pid}, _from, state) do
    {:reply, :ok, drop_pid_entry(state, user_id, pid)}
  end

  def handle_call({:get, user_id}, _from, state) do
    activity =
      state.by_user
      |> Map.get(user_id, MapSet.new())
      |> Enum.map(&Map.fetch!(state.entries, &1))
      |> Enum.map(fn {_user_id, activity, _pid} -> activity end)
      |> Enum.sort_by(&activity_sort_key/1)
      |> List.first()

    {:reply, if(activity, do: {:ok, activity}, else: :error), state}
  end

  def handle_call(:list, _from, state) do
    entries =
      Enum.map(state.entries, fn {_ref, {user_id, activity, pid}} ->
        %{user_id: user_id, activity: activity, pid: pid}
      end)

    {:reply, entries, state}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    {:noreply, drop_ref(state, ref)}
  end

  defp put_entry(state, user_id, activity, pid) do
    ref = Process.monitor(pid)

    %{
      state
      | entries: Map.put(state.entries, ref, {user_id, activity, pid}),
        by_user: Map.update(state.by_user, user_id, MapSet.new([ref]), &MapSet.put(&1, ref))
    }
  end

  defp drop_pid_entry(state, user_id, pid) do
    refs = Map.get(state.by_user, user_id, MapSet.new())

    Enum.reduce(refs, state, fn ref, acc ->
      case Map.fetch(acc.entries, ref) do
        {:ok, {^user_id, _activity, ^pid}} ->
          Process.demonitor(ref, [:flush])
          drop_ref(acc, ref)

        _other ->
          acc
      end
    end)
  end

  defp drop_ref(state, ref) do
    case Map.pop(state.entries, ref) do
      {nil, _entries} ->
        state

      {{user_id, _activity, _pid}, entries} ->
        by_user = remove_ref_from_user(state.by_user, user_id, ref)
        %{state | entries: entries, by_user: by_user}
    end
  end

  defp remove_ref_from_user(by_user, user_id, ref) do
    case Map.get(by_user, user_id) do
      nil ->
        by_user

      refs ->
        refs = MapSet.delete(refs, ref)

        if MapSet.size(refs) == 0 do
          Map.delete(by_user, user_id)
        else
          Map.put(by_user, user_id, refs)
        end
    end
  end

  defp normalize_activity({kind, board})
       when kind in [:browsing_board, :reading_board, :chatting_in_board] and is_map(board),
       do: {kind, board}

  defp normalize_activity(:board_list), do: :board_list

  defp activity_sort_key({:chatting_in_board, board}), do: {0, board_name(board), board_id(board)}
  defp activity_sort_key({:reading_board, board}), do: {1, board_name(board), board_id(board)}
  defp activity_sort_key({:browsing_board, board}), do: {2, board_name(board), board_id(board)}
  defp activity_sort_key(:board_list), do: {3, "", ""}

  defp board_name(board) do
    Map.get(board, :name) || Map.get(board, "name") || Map.get(board, :slug) ||
      Map.get(board, "slug") || "board"
  end

  defp board_id(board), do: Map.get(board, :id) || Map.get(board, "id") || ""
end
