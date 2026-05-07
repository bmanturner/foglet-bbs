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
    * last_action_at (authenticated user input; heartbeat does not update it)
    * tui_pid (set when TUI app spawns and pings back)

  See ARCHITECTURE.md §4 and CONTEXT 03 D-16, D-25.
  """

  use GenServer, restart: :temporary

  require Logger

  alias Foglet.Accounts
  alias Foglet.Sessions.OnlinePresence
  alias Foglet.Sessions.Preferences

  @type t :: %__MODULE__{
          user_id: String.t() | nil,
          handle: String.t() | nil,
          handle_color: String.t() | nil,
          role: atom(),
          terminal_size: {pos_integer(), pos_integer()},
          connected_at: DateTime.t(),
          last_seen_at: DateTime.t(),
          last_action_at: DateTime.t() | nil,
          tui_pid: pid() | nil,
          timezone: String.t(),
          time_format: String.t(),
          theme_id: String.t(),
          theme: Foglet.TUI.Theme.t()
        }

  defstruct [
    :user_id,
    :handle,
    :handle_color,
    :role,
    :terminal_size,
    :connected_at,
    :last_seen_at,
    :last_action_at,
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

  @spec record_user_action(pid() | String.t()) :: :ok
  def record_user_action(target) do
    GenServer.cast(resolve(target), {:user_action, DateTime.utc_now()})
  end

  @spec idle?(t() | map(), DateTime.t()) :: boolean()
  def idle?(%{user_id: user_id, last_action_at: %DateTime{} = last_action_at}, %DateTime{} = now)
      when is_binary(user_id) do
    DateTime.diff(now, last_action_at, :second) >= 180
  end

  def idle?(_session_state, %DateTime{}), do: false

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
    promote_to_user(pid, user, %{})
  end

  @doc """
  Promote a guest session and pass structured `audit` metadata for
  promotion logging (SSH-02 / D-05).

  `audit` is a map. Recognised keys:
    * `:ssh_peer` — peer descriptor captured at channel-up, or `nil` for
      non-SSH callers.
    * `:replacement` — replacement context determined by the supervisor:
      `:none`, `:same_session`, or `{:replaced, old_pid}` (the supervisor
      may also pass a `%{status: :replaced, old_pid: pid}` map equivalent).

  Unknown keys are ignored. Always returns `:ok` (cast).
  """
  @spec promote_to_user(pid(), Foglet.Accounts.User.t(), map()) :: :ok
  def promote_to_user(pid, user, audit) when is_pid(pid) and is_map(audit) do
    GenServer.cast(pid, {:promote_to_user, user, audit})
  end

  defp resolve(pid) when is_pid(pid), do: pid
  defp resolve(user_id) when is_binary(user_id), do: via_tuple(user_id)
  defp resolve({:via, _, _} = via), do: via

  # --- GenServer callbacks ---

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)
    now = DateTime.utc_now()
    preferences = Preferences.from_user(nil)

    state = %__MODULE__{
      user_id: Keyword.get(opts, :user_id),
      handle: Keyword.get(opts, :handle),
      handle_color: Keyword.get(opts, :handle_color),
      role: Keyword.get(opts, :role, :user),
      terminal_size: Keyword.get(opts, :terminal_size, {80, 24}),
      connected_at: now,
      last_seen_at: now,
      last_action_at: initial_last_action_at(Keyword.get(opts, :user_id), now),
      tui_pid: nil,
      timezone: Keyword.get(opts, :timezone, preferences.timezone),
      time_format: Keyword.get(opts, :time_format, preferences.time_format),
      theme_id: Keyword.get(opts, :theme_id, preferences.theme_id),
      theme: Keyword.get(opts, :theme, preferences.theme)
    }

    record_last_seen(state.user_id, now)
    :telemetry.execute([:foglet, :session, :connect], %{count: 1}, %{user_id: state.user_id})
    OnlinePresence.broadcast(:session_connected, %{user_id: state.user_id})

    {:ok, state}
  end

  @impl true
  def handle_call(:get_state, _from, state), do: {:reply, state, state}

  @impl true
  def handle_cast(:heartbeat, state) do
    {:noreply, %{state | last_seen_at: DateTime.utc_now()}}
  end

  def handle_cast({:user_action, timestamp}, %{user_id: user_id} = state)
      when is_binary(user_id) do
    {:noreply, %{state | last_action_at: timestamp}}
  end

  def handle_cast({:user_action, _timestamp}, state), do: {:noreply, state}

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
    handle_cast({:promote_to_user, user, %{}}, state)
  end

  def handle_cast({:promote_to_user, user, audit}, state) when is_map(audit) do
    # Register in the Registry FIRST so the one-session-per-user invariant is
    # enforced before we mutate any identity state. If registration fails the
    # slot is already held by another pid (typically a stale entry that the
    # registry has not yet cleared), and we must NOT merge user identity into
    # this session — doing so would leave a process holding an authenticated
    # identity in memory that is unreachable through the Registry, silently
    # bypassing replacement enforcement (SSH-05 / D-25).
    case Registry.register(Foglet.Sessions.Registry, user.id, nil) do
      {:ok, _} ->
        Logger.info("Session guest promoted",
          event: :guest_promoted,
          session_pid: self(),
          user_id: user.id,
          handle: user.handle,
          ssh_peer: Map.get(audit, :ssh_peer),
          replacement: Map.get(audit, :replacement)
        )

        :telemetry.execute([:foglet, :session, :promote], %{count: 1}, %{outcome: :success})

        now = DateTime.utc_now()
        record_last_seen(user.id, now)

        state =
          state
          |> Map.merge(%{
            user_id: user.id,
            handle: user.handle,
            handle_color: user.handle_color,
            role: user.role,
            last_seen_at: now,
            last_action_at: now
          })
          |> merge_preferences(Preferences.from_user(user))

        OnlinePresence.broadcast(:session_promoted, %{user_id: user.id})

        {:noreply, state}

      {:error, {:already_registered, other_pid}} ->
        # FOG-674: privacy-safe one-session invariant violation log. Internal
        # ids only (user_id, ssh_peer host:port, registered pid) — never the
        # full audit map (carries replacement context not meant for logs) or
        # any auth/key material. Level is `warn`: the `{:stop, …}` below
        # already drives the loud teardown; this line is the
        # invariant-violation marker, not a crash report.
        Logger.warning("Session promote_to_user: registry collision",
          event: :session_registry_collision,
          user_id: user.id,
          ssh_peer: format_ssh_peer(Map.get(audit, :ssh_peer)),
          other_pid: inspect(other_pid)
        )

        :telemetry.execute([:foglet, :session, :promote], %{count: 1}, %{
          outcome: :registry_collision
        })

        # Stop loudly so the SSH channel tears down the orphan rather than
        # leaving a half-promoted session in memory.
        {:stop, {:registry_collision, user.id}, state}
    end
  end

  @impl true
  # FOG-674: orderly stops are intentionally silent — they are not failures
  # and would otherwise spam logs on every disconnect.
  def terminate(:normal, state), do: disconnect_last_seen(state)
  def terminate(:shutdown, state), do: disconnect_last_seen(state)
  def terminate({:shutdown, _}, state), do: disconnect_last_seen(state)

  def terminate(reason, state) do
    disconnect_last_seen(state)

    # FOG-674: log abnormal session exits with privacy-safe context only.
    # `sanitized_reason/1` reduces tagged tuples to their tag atom so embedded
    # payloads (tokens, audit maps, key material) cannot leak through reasons.
    Logger.warning("Session terminating abnormally",
      event: :session_terminated_abnormal,
      session_pid: self(),
      user_id: state.user_id,
      reason: sanitized_reason(reason)
    )

    :ok
  end

  @impl true
  def handle_info(:replaced_by_new_session, state) do
    Logger.info("Session for user_id=#{state.user_id} replaced by new connection (SSH-05 / D-25)")
    OnlinePresence.broadcast(:session_replaced, %{user_id: state.user_id})

    if is_pid(state.tui_pid) and Process.alive?(state.tui_pid) do
      send(state.tui_pid, {:session_replaced, state.user_id})
    end

    {:stop, :normal, state}
  end

  # FOG-674: render the audit ssh_peer as a logger-safe string. Missing
  # entries collapse to the literal "unknown" string per the FOG-674 spec.
  defp format_ssh_peer(nil), do: "unknown"
  defp format_ssh_peer(peer) when is_binary(peer), do: peer
  defp format_ssh_peer(peer), do: inspect(peer)

  # FOG-674: collapse exit reasons to a single safe atom for logging. Tagged
  # tuples (e.g. `{:registry_collision, user_id}`) keep only the tag; orderly
  # stops are short-circuited above before this is reached.
  defp sanitized_reason(reason) when is_atom(reason), do: reason
  defp sanitized_reason(tuple) when is_tuple(tuple) and tuple_size(tuple) > 0, do: elem(tuple, 0)
  defp sanitized_reason(_), do: :unknown

  defp initial_last_action_at(nil, _now), do: nil
  defp initial_last_action_at(user_id, now) when is_binary(user_id), do: now

  defp record_last_seen(nil, _timestamp), do: :ok

  defp record_last_seen(user_id, timestamp) when is_binary(user_id),
    do: Accounts.record_last_seen(user_id, timestamp)

  # Normal EOF/close, TUI/lifecycle quit, replacement, and graceful shutdown all
  # reach Session.terminate/2 and update persisted last_seen_at here. Untrappable
  # :kill / VM / host death cannot run Elixir cleanup; the connect/promotion
  # write remains the honest last-known timestamp for those hard-kill cases.
  defp disconnect_last_seen(state) do
    :telemetry.execute([:foglet, :session, :disconnect], %{count: 1}, %{user_id: state.user_id})
    record_last_seen(state.user_id, DateTime.utc_now())
    OnlinePresence.broadcast(:session_disconnected, %{user_id: state.user_id})
    :ok
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
