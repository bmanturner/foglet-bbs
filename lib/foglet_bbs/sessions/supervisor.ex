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
  until the guest promotes to an authenticated user via `Session.promote_to_user/2`.
  """
  @spec start_guest_session() :: {:ok, pid()} | {:error, term()}
  def start_guest_session do
    DynamicSupervisor.start_child(__MODULE__, {Foglet.Sessions.Session, [user_id: nil]})
  end

  @spec terminate_session(String.t()) :: :ok | {:error, :not_found}
  def terminate_session(user_id) when is_binary(user_id) do
    case lookup_session(user_id) do
      {:ok, pid} ->
        DynamicSupervisor.terminate_child(__MODULE__, pid)
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
