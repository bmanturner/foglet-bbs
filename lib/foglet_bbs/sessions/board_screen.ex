defmodule Foglet.Sessions.BoardScreen do
  @moduledoc """
  Tracks which users are currently viewing a board screen, regardless of
  which tab (`:threads` or `:chat`) they have focused.

  Presence is keyed by `{board_id, user_id, tab}` so a user can only have
  one active tab per board at a time. `count/1` returns the number of unique
  `user_id`s for a board (the value rendered as `CHAT (#)` in the TUI),
  independent of how many tabs they have open.

  ## Lifecycle

  Entries are tied to the caller pid via `Process.monitor/1`. When that pid
  goes down (TUI dispatcher exit, SSH channel close, supervisor replacement),
  the matching entries are dropped automatically. This piggy-backs on the
  existing session/process lifetime — there is no separate heartbeat or
  timeout to manage.

  ## Broadcasts

  Every join, tab change, and leave broadcasts a `{:board_screen, event,
  payload}` message on the board's screen topic
  (`Foglet.PubSub.board_screen_topic/1`). Consumers (the C5/C6 TUI views)
  subscribe to that topic and re-render presence when notified.

  Events:

    * `{:board_screen, :join, %{board_id, user_id, tab}}`
    * `{:board_screen, :tab_changed, %{board_id, user_id, tab}}`
    * `{:board_screen, :leave, %{board_id, user_id}}`

  Joins and tab changes from a user already present do not emit a duplicate
  `:join`; tab-only changes emit `:tab_changed`. Leaves only fire when a
  user has no remaining entries on that board.
  """

  use GenServer

  require Logger

  @valid_tabs [:threads, :chat]

  # --- Public API ---

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Track that `user_id` is on the board screen for `board_id` viewing `tab`.

  Tied to the caller pid; the entry is auto-evicted when that pid exits.
  """
  @spec track(binary(), binary() | nil, :threads | :chat) :: :ok
  def track(_board_id, nil, tab) when tab in @valid_tabs, do: :ok

  def track(board_id, user_id, tab) when tab in @valid_tabs do
    GenServer.call(__MODULE__, {:track, board_id, user_id, tab, self()})
  end

  @doc """
  Update the tab for the caller's existing presence entry. If no entry
  exists for the caller, this is equivalent to `track/3`.
  """
  @spec update_tab(binary(), binary() | nil, :threads | :chat) :: :ok
  def update_tab(_board_id, nil, tab) when tab in @valid_tabs, do: :ok

  def update_tab(board_id, user_id, tab) when tab in @valid_tabs do
    GenServer.call(__MODULE__, {:update_tab, board_id, user_id, tab, self()})
  end

  @doc """
  Remove all of the caller's presence entries for `board_id` / `user_id`.
  """
  @spec untrack(binary(), binary() | nil) :: :ok
  def untrack(_board_id, nil), do: :ok

  def untrack(board_id, user_id) do
    GenServer.call(__MODULE__, {:untrack, board_id, user_id, self()})
  end

  @doc """
  Number of unique `user_id`s currently present on the board screen and
  therefore visible in the board chat roster/count.
  """
  @spec chat_count(binary()) :: non_neg_integer()
  def chat_count(board_id) do
    GenServer.call(__MODULE__, {:chat_count, board_id})
  end

  @doc """
  Number of unique `user_id`s currently present on `board_id`.
  """
  @spec count(binary()) :: non_neg_integer()
  def count(board_id) do
    GenServer.call(__MODULE__, {:count, board_id})
  end

  @doc """
  List of `%{user_id: binary, tab: :threads | :chat}` entries currently
  present on `board_id`. If a user has multiple tabs open from distinct
  processes, all entries are returned.
  """
  @spec list(binary()) :: [%{user_id: binary(), tab: :threads | :chat}]
  def list(board_id) do
    GenServer.call(__MODULE__, {:list, board_id})
  end

  # --- GenServer ---

  @impl true
  def init(_opts) do
    # entries: %{ref => {board_id, user_id, tab, pid}}
    # by_board: %{board_id => MapSet.t(ref)}
    {:ok, %{entries: %{}, by_board: %{}}}
  end

  @impl true
  def handle_call({:track, board_id, user_id, tab, pid}, _from, state) do
    {state, was_present?} = put_entry(state, board_id, user_id, tab, pid)

    broadcast(
      board_id,
      if(was_present?, do: :tab_changed, else: :join),
      %{board_id: board_id, user_id: user_id, tab: tab}
    )

    {:reply, :ok, state}
  end

  def handle_call({:update_tab, board_id, user_id, tab, pid}, _from, state) do
    {state, was_present?} = put_entry(state, board_id, user_id, tab, pid)

    broadcast(
      board_id,
      if(was_present?, do: :tab_changed, else: :join),
      %{board_id: board_id, user_id: user_id, tab: tab}
    )

    {:reply, :ok, state}
  end

  def handle_call({:untrack, board_id, user_id, pid}, _from, state) do
    {state, removed_user?} = drop_caller_entries(state, board_id, user_id, pid)

    if removed_user? do
      broadcast(board_id, :leave, %{board_id: board_id, user_id: user_id})
    end

    {:reply, :ok, state}
  end

  def handle_call({:count, board_id}, _from, state) do
    refs = Map.get(state.by_board, board_id, MapSet.new())

    count =
      refs
      |> Enum.map(fn ref -> elem(Map.fetch!(state.entries, ref), 1) end)
      |> MapSet.new()
      |> MapSet.size()

    {:reply, count, state}
  end

  def handle_call({:chat_count, board_id}, _from, state) do
    refs = Map.get(state.by_board, board_id, MapSet.new())

    count =
      refs
      |> Enum.map(fn ref -> elem(Map.fetch!(state.entries, ref), 1) end)
      |> MapSet.new()
      |> MapSet.size()

    {:reply, count, state}
  end

  def handle_call({:list, board_id}, _from, state) do
    refs = Map.get(state.by_board, board_id, MapSet.new())

    entries =
      Enum.map(refs, fn ref ->
        {_board_id, user_id, tab, _pid} = Map.fetch!(state.entries, ref)
        %{user_id: user_id, tab: tab}
      end)

    {:reply, entries, state}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _reason}, state) do
    case Map.pop(state.entries, ref) do
      {nil, _entries} ->
        {:noreply, state}

      {{board_id, user_id, _tab, _pid}, entries} ->
        by_board = remove_ref_from_board(state.by_board, board_id, ref)
        state = %{state | entries: entries, by_board: by_board}

        unless user_still_present?(state, board_id, user_id) do
          broadcast(board_id, :leave, %{board_id: board_id, user_id: user_id})
        end

        {:noreply, state}
    end
  end

  # --- Private helpers ---

  defp put_entry(state, board_id, user_id, tab, pid) do
    was_present? = user_still_present?(state, board_id, user_id)

    # Replace any existing entry for the same {board_id, user_id, pid} so a
    # caller flipping tabs does not stack multiple monitor refs.
    state = drop_pid_entry(state, board_id, user_id, pid)

    ref = Process.monitor(pid)
    entries = Map.put(state.entries, ref, {board_id, user_id, tab, pid})

    by_board =
      Map.update(state.by_board, board_id, MapSet.new([ref]), &MapSet.put(&1, ref))

    {%{state | entries: entries, by_board: by_board}, was_present?}
  end

  defp drop_pid_entry(state, board_id, user_id, pid) do
    refs = Map.get(state.by_board, board_id, MapSet.new())

    Enum.reduce(refs, state, fn ref, acc ->
      case Map.fetch(acc.entries, ref) do
        {:ok, {^board_id, ^user_id, _tab, ^pid}} ->
          Process.demonitor(ref, [:flush])
          entries = Map.delete(acc.entries, ref)
          by_board = remove_ref_from_board(acc.by_board, board_id, ref)
          %{acc | entries: entries, by_board: by_board}

        _ ->
          acc
      end
    end)
  end

  defp drop_caller_entries(state, board_id, user_id, pid) do
    was_present? = user_still_present?(state, board_id, user_id)
    state = drop_pid_entry(state, board_id, user_id, pid)
    now_present? = user_still_present?(state, board_id, user_id)
    {state, was_present? and not now_present?}
  end

  defp remove_ref_from_board(by_board, board_id, ref) do
    case Map.get(by_board, board_id) do
      nil ->
        by_board

      set ->
        set = MapSet.delete(set, ref)

        if MapSet.size(set) == 0 do
          Map.delete(by_board, board_id)
        else
          Map.put(by_board, board_id, set)
        end
    end
  end

  defp user_still_present?(state, board_id, user_id) do
    refs = Map.get(state.by_board, board_id, MapSet.new())

    Enum.any?(refs, fn ref ->
      case Map.fetch(state.entries, ref) do
        {:ok, {^board_id, ^user_id, _tab, _pid}} -> true
        _ -> false
      end
    end)
  end

  defp broadcast(board_id, event, payload) do
    _ =
      Phoenix.PubSub.broadcast(
        FogletBbs.PubSub,
        Foglet.PubSub.board_screen_topic(board_id),
        {:board_screen, event, payload}
      )

    :ok
  end
end
