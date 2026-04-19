defmodule Foglet.Sessions.Supervisor do
  @moduledoc """
  DynamicSupervisor for Foglet.Sessions.Session processes.

  Enforces one-session-per-user via Foglet.Sessions.Registry. When a new
  session is requested for a user that already has one, the old session
  is notified with :replaced_by_new_session and stopped before the new one
  starts (SSH-05 / D-25).

  Handles the Registry via-tuple race (Pitfall 4): if `start_child` races
  with an existing session, `{:error, {:already_started, old_pid}}` is
  caught and turned into the replacement flow.
  """

  use DynamicSupervisor

  require Logger

  @registry Foglet.Sessions.Registry
  @replacement_timeout_ms 2_000

  def start_link(opts) do
    DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @doc """
  Start (or replace) a Session for the given authenticated user.

  opts: user_id (required binary), handle, role, terminal_size

  If a session for user_id already exists it is replaced: the old session
  receives `:replaced_by_new_session`, waits for it to stop, then starts a
  fresh one.
  """
  @spec start_session(keyword()) :: {:ok, pid()} | {:error, term()}
  def start_session(opts) do
    _user_id = Keyword.fetch!(opts, :user_id)

    case DynamicSupervisor.start_child(__MODULE__, {Foglet.Sessions.Session, opts}) do
      {:ok, pid} ->
        {:ok, pid}

      {:error, {:already_started, old_pid}} ->
        replace(old_pid, opts)

      # Registry collision from a race: the Registry via-tuple found an existing
      # registration even before start_child returned.
      {:error, {:already_registered, old_pid}} ->
        replace(old_pid, opts)

      {:error, _reason} = err ->
        err
    end
  end

  @doc """
  Start an anonymous guest session (user_id: nil).

  Guest sessions are not registered in `Foglet.Sessions.Registry` — there is no
  user_id key to register under. One-session-per-user enforcement does not apply
  until the guest promotes to an authenticated user via `promote_guest_session/2`.
  """
  @spec start_guest_session() :: {:ok, pid()} | {:error, term()}
  def start_guest_session do
    DynamicSupervisor.start_child(__MODULE__, {Foglet.Sessions.Session, [user_id: nil]})
  end

  @doc """
  Promote a guest session to an authenticated user session, enforcing SSH-05 / D-25.

  Looks up any existing session for `user.id`:
    * If none exists: promotes `guest_pid` in-place (no replacement needed).
    * If the existing pid IS `guest_pid`: no-op (idempotent — already this user).
    * If a different session owns the slot: replaces it (send `:replaced_by_new_session`,
      wait for `:DOWN` or force-terminate after `@replacement_timeout_ms`), then promotes.

  Always returns `:ok` — the underlying promote and replace paths both return
  `:ok` (promote is a cast, replace sync-waits then casts).
  """
  @spec promote_guest_session(pid(), Foglet.Accounts.User.t()) :: :ok
  def promote_guest_session(guest_pid, user) when is_pid(guest_pid) do
    case Registry.lookup(@registry, user.id) do
      [] ->
        # No existing session — simple promote.
        Foglet.Sessions.Session.promote_to_user(guest_pid, user)

      [{^guest_pid, _}] ->
        # Already registered as this user — idempotent no-op.
        :ok

      [{old_pid, _}] ->
        # Different session holds the slot — replace it, then promote.
        replace_then_promote(old_pid, guest_pid, user)
    end
  end

  @spec terminate_session(String.t()) :: :ok | {:error, :not_found}
  def terminate_session(user_id) when is_binary(user_id) do
    case lookup_session(user_id) do
      {:ok, pid} ->
        _ = DynamicSupervisor.terminate_child(__MODULE__, pid)
        :ok

      {:error, :not_found} = err ->
        err
    end
  end

  @spec lookup_session(String.t()) :: {:ok, pid()} | {:error, :not_found}
  def lookup_session(user_id) when is_binary(user_id) do
    case Registry.lookup(@registry, user_id) do
      [{pid, _}] -> {:ok, pid}
      [] -> {:error, :not_found}
    end
  end

  # --- Private ---

  defp replace_then_promote(old_pid, guest_pid, user) do
    ref = Process.monitor(old_pid)
    send(old_pid, :replaced_by_new_session)

    receive do
      {:DOWN, ^ref, :process, ^old_pid, _reason} ->
        Foglet.Sessions.Session.promote_to_user(guest_pid, user)
    after
      @replacement_timeout_ms ->
        Process.demonitor(ref, [:flush])

        # Try graceful DynamicSupervisor termination first; fall back to a
        # direct exit signal if old_pid is not a supervised child (e.g. in
        # tests or after a partial crash/restart).
        case DynamicSupervisor.terminate_child(__MODULE__, old_pid) do
          :ok ->
            :ok

          {:error, reason} ->
            Logger.warning(
              "Session replace_then_promote: terminate_child failed (#{inspect(reason)}), " <>
                "sending EXIT to #{inspect(old_pid)}"
            )

            Process.exit(old_pid, :kill)
        end

        Foglet.Sessions.Session.promote_to_user(guest_pid, user)
    end
  end

  defp replace(old_pid, opts) do
    ref = Process.monitor(old_pid)

    # Notify first so the old Session can do graceful TUI cleanup, then stop.
    send(old_pid, :replaced_by_new_session)

    receive do
      {:DOWN, ^ref, :process, ^old_pid, _reason} ->
        start_or_adopt(opts)
    after
      @replacement_timeout_ms ->
        Process.demonitor(ref, [:flush])
        # Forcefully terminate if the old Session didn't stop in time.
        :ok = DynamicSupervisor.terminate_child(__MODULE__, old_pid)
        start_or_adopt(opts)
    end
  end

  # Attempt to start a new child; if a concurrent replacement already started
  # one for the same user_id, adopt that pid as a successful result.
  defp start_or_adopt(opts) do
    case DynamicSupervisor.start_child(__MODULE__, {Foglet.Sessions.Session, opts}) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      {:error, _} = err -> err
    end
  end
end
