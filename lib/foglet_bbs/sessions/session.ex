defmodule Foglet.Sessions.Session do
  @moduledoc """
  Per-user Session GenServer. One live Session per user_id, enforced by
  Foglet.Sessions.Registry via-tuple registration.

  Guest sessions (user_id: nil) are anonymous — not registered in the
  Registry. They can be promoted to a full user session via `promote_to_user/2`
  once the TUI login screen authenticates the user.

  State holds session-scoped identity and policy:
    * user_id, handle, role (nil/nil/:user for guest)
    * terminal_size (updated by CLIHandler on :window_change)
    * connected_at / last_seen_at (heartbeats from TUI)
    * tui_pid (set when TUI app spawns and pings back)

  See ARCHITECTURE.md §4 and CONTEXT 03 D-16, D-25.
  """

  use GenServer, restart: :temporary

  require Logger

  alias Foglet.Sessions.Preferences

  @type t :: %__MODULE__{
          user_id: String.t() | nil,
          handle: String.t() | nil,
          role: atom(),
          terminal_size: {pos_integer(), pos_integer()},
          connected_at: DateTime.t(),
          last_seen_at: DateTime.t(),
          tui_pid: pid() | nil,
          timezone: String.t(),
          time_format: String.t(),
          theme_id: String.t(),
          theme: Foglet.TUI.Theme.t()
        }

  defstruct [
    :user_id,
    :handle,
    :role,
    :terminal_size,
    :connected_at,
    :last_seen_at,
    :tui_pid,
    :timezone,
    :time_format,
    :theme_id,
    :theme
  ]

  # --- Public API ---

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    user_id = Keyword.get(opts, :user_id)

    # Guest sessions (user_id: nil) are anonymous — not registered in the
    # Registry (there is no key to register under).
    server_opts =
      if is_binary(user_id) do
        [name: via_tuple(user_id)]
      else
        []
      end

    GenServer.start_link(__MODULE__, opts, server_opts)
  end

  @spec via_tuple(String.t()) :: {:via, Registry, {Foglet.Sessions.Registry, String.t()}}
  def via_tuple(user_id), do: {:via, Registry, {Foglet.Sessions.Registry, user_id}}

  @spec get_state(pid() | {:via, Registry, {Foglet.Sessions.Registry, String.t()}}) :: t()
  def get_state(target) do
    GenServer.call(resolve(target), :get_state)
  end

  @spec heartbeat(pid() | String.t()) :: :ok
  def heartbeat(target) do
    GenServer.cast(resolve(target), :heartbeat)
  end

  @spec set_terminal_size(pid() | String.t(), {pos_integer(), pos_integer()}) :: :ok
  def set_terminal_size(target, {cols, rows} = size) when cols > 0 and rows > 0 do
    GenServer.cast(resolve(target), {:terminal_size, size})
  end

  @spec set_tui_pid(pid() | String.t(), pid()) :: :ok
  def set_tui_pid(target, tui_pid) when is_pid(tui_pid) do
    GenServer.cast(resolve(target), {:tui_pid, tui_pid})
  end

  @spec update_preferences(
          pid() | String.t(),
          Foglet.Accounts.User.t() | Preferences.snapshot()
        ) :: :ok
  def update_preferences(target, user_or_snapshot) do
    GenServer.cast(resolve(target), {:update_preferences, preference_snapshot(user_or_snapshot)})
  end

  @doc """
  Promote a guest session to an authenticated user session.

  Called by `Foglet.TUI.App` after the TUI login screen succeeds.
  Updates user_id, handle, and role in the Session state, then registers
  the process in the Registry under user_id so one-session enforcement
  can apply going forward (if a concurrent session exists, the Supervisor
  replacement protocol handles it separately).
  """
  @spec promote_to_user(pid(), Foglet.Accounts.User.t()) :: :ok
  def promote_to_user(pid, user) when is_pid(pid) do
    GenServer.cast(pid, {:promote_to_user, user})
  end

  defp resolve(pid) when is_pid(pid), do: pid
  defp resolve(user_id) when is_binary(user_id), do: via_tuple(user_id)
  defp resolve({:via, _, _} = via), do: via

  # --- GenServer callbacks ---

  @impl true
  def init(opts) do
    now = DateTime.utc_now()
    preferences = Preferences.from_user(nil)

    state = %__MODULE__{
      user_id: Keyword.get(opts, :user_id),
      handle: Keyword.get(opts, :handle),
      role: Keyword.get(opts, :role, :user),
      terminal_size: Keyword.get(opts, :terminal_size, {80, 24}),
      connected_at: now,
      last_seen_at: now,
      tui_pid: nil,
      timezone: Keyword.get(opts, :timezone, preferences.timezone),
      time_format: Keyword.get(opts, :time_format, preferences.time_format),
      theme_id: Keyword.get(opts, :theme_id, preferences.theme_id),
      theme: Keyword.get(opts, :theme, preferences.theme)
    }

    {:ok, state}
  end

  @impl true
  def handle_call(:get_state, _from, state), do: {:reply, state, state}

  @impl true
  def handle_cast(:heartbeat, state) do
    {:noreply, %{state | last_seen_at: DateTime.utc_now()}}
  end

  def handle_cast({:terminal_size, size}, state) do
    {:noreply, %{state | terminal_size: size}}
  end

  def handle_cast({:tui_pid, pid}, state) do
    {:noreply, %{state | tui_pid: pid}}
  end

  def handle_cast({:update_preferences, preferences}, state) do
    {:noreply, merge_preferences(state, preferences)}
  end

  def handle_cast({:promote_to_user, user}, state) do
    Logger.info("Session guest promoted to user_id=#{user.id} handle=#{user.handle}")

    # Register in the Registry so one-session enforcement applies.
    # The Supervisor's promote_guest_session/2 guarantees the slot is free before
    # casting this message. If registration fails here it is a protocol bug — log
    # it loudly so it surfaces rather than staying silent.
    case Registry.register(Foglet.Sessions.Registry, user.id, nil) do
      {:ok, _} ->
        :ok

      {:error, {:already_registered, other_pid}} ->
        Logger.error(
          "Session promote_to_user: Registry slot for user_id=#{user.id} still held by " <>
            "pid=#{inspect(other_pid)} — protocol violation (promote_guest_session not used?)"
        )
    end

    state =
      state
      |> Map.merge(%{user_id: user.id, handle: user.handle, role: user.role})
      |> merge_preferences(Preferences.from_user(user))

    {:noreply, state}
  end

  @impl true
  def handle_info(:replaced_by_new_session, state) do
    Logger.info("Session for user_id=#{state.user_id} replaced by new connection (SSH-05 / D-25)")

    if is_pid(state.tui_pid) and Process.alive?(state.tui_pid) do
      send(state.tui_pid, {:session_replaced, state.user_id})
    end

    {:stop, :normal, state}
  end

  defp preference_snapshot(%Foglet.Accounts.User{} = user), do: Preferences.from_user(user)

  defp preference_snapshot(%{timezone: _, time_format: _, theme_id: _, theme: _} = snapshot) do
    Map.take(snapshot, [:timezone, :time_format, :theme_id, :theme])
  end

  defp merge_preferences(state, preferences) do
    Map.merge(state, %{
      timezone: preferences.timezone,
      time_format: preferences.time_format,
      theme_id: preferences.theme_id,
      theme: preferences.theme
    })
  end
end
