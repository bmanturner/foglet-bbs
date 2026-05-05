defmodule Foglet.TUI.App.SessionAlias do
  @moduledoc """
  App-shell user/session aliasing helpers.

  Owns the `:set_user`, `:promote_session`, and `:session_replaced`
  do_update clauses (extracted from `Foglet.TUI.App` per Phase 47 D-20).
  Public callback boundary on `Foglet.TUI.App` is unchanged — `App` keeps
  thin one-line delegating `do_update` clauses.
  """

  alias Foglet.Sessions.Preferences
  alias Foglet.TUI.App
  alias Foglet.TUI.App.Effects
  alias Raxol.Core.Runtime.Command

  @spec set_user(App.t(), Foglet.Accounts.User.t()) :: {App.t(), [Command.t()]}
  def set_user(%App{} = state, user), do: promote_session(state, user)

  # TUI login screen authenticated a user — promote the guest session.
  # Routes through the Supervisor so one-session-per-user (SSH-05 / D-25) is
  # enforced: any pre-existing session for this user is replaced before this
  # guest pid registers under the user_id key.
  #
  # IN-05: missing-session_pid policy. When `state.session_pid` is not a pid
  # we still update `current_user`/`session_context` and emit
  # navigate(:main_menu). This is intentional: production wires the pid
  # before set_user fires (SSH-04), so the no-pid case is reachable only in
  # tests that build %App{} without an SSH layer. Refusing to promote in
  # that case would force every test to fabricate a pid; today no test
  # exercises the half-state behaviour and the consequences below are
  # tolerable for test fixtures.
  #
  # Consequences when session_pid is missing:
  #   * Sessions GenServer has no row for this user → presence/heartbeat
  #     telemetry is silently lost.
  #   * SSH-05 (one-session-per-user) cannot be enforced — a parallel SSH
  #     login for the same user will not see this "session" and will not
  #     replace it.
  #   * `Sessions.Session.heartbeat/1` calls below also no-op.
  @spec promote_session(App.t(), Foglet.Accounts.User.t()) :: {App.t(), [Command.t()]}
  def promote_session(%App{} = state, user) do
    if is_pid(state.session_pid) do
      Foglet.Sessions.Supervisor.promote_guest_session(state.session_pid, user,
        audit: %{ssh_peer: Map.get(state.session_context, :ssh_peer)}
      )
    else
      require Logger

      Logger.warning(
        "[TUI.App] promote_session without session_pid; user=#{inspect(user.handle)} — " <>
          "session telemetry will be missing and SSH-05 (one-session-per-user) " <>
          "cannot be enforced for this connection"
      )
    end

    preferences = Preferences.from_user(user)

    # Keep session_context in lockstep with current_user so screens that read
    # session_context.user (rather than current_user) see the authenticated
    # identity and preference snapshot. :pubkey_authenticated stays as-is —
    # TUI-driven login is password-based by definition, so promoting here does
    # NOT make the session pubkey-authenticated.
    updated_context =
      state.session_context
      |> Map.put(:user, user)
      |> Map.put(:user_id, user.id)
      |> Map.put(:timezone, preferences.timezone)
      |> Map.put(:time_format, preferences.time_format)
      |> Map.put(:theme_id, preferences.theme_id)
      |> Map.put(:theme, preferences.theme)

    Effects.apply_effect(
      %{state | current_user: user, session_context: updated_context},
      Foglet.TUI.Effect.navigate(:main_menu, %{})
    )
  end

  # Record a real authenticated user action. This is intentionally separate
  # from heartbeat/liveness so idle can age while the connection stays alive.
  @spec record_user_action(App.t()) :: :ok
  def record_user_action(%App{current_user: %{id: user_id}, session_pid: session_pid})
      when is_binary(user_id) and is_pid(session_pid) do
    Foglet.Sessions.Session.record_user_action(session_pid)
  end

  def record_user_action(%App{}), do: :ok

  # Heartbeat — keep last_seen_at alive in the Session GenServer.
  @spec heartbeat(App.t()) :: {App.t(), [Command.t()]}
  def heartbeat(%App{} = state) do
    if is_pid(state.session_pid), do: Foglet.Sessions.Session.heartbeat(state.session_pid)
    {state, []}
  end

  # A new SSH connection for the same user replaced this session.
  # Show a notice modal and defer the quit until the user dismisses it
  # (mirrors `:terminate_after_modal` so the user actually sees the message
  # rather than getting torn down on the next tick).
  @spec session_replaced(App.t(), term()) :: {App.t(), [Command.t()]}
  def session_replaced(%App{} = state, _payload) do
    modal = %Foglet.TUI.Modal{
      type: :warning,
      message: "Your session was replaced by a new connection. Goodbye.",
      on_confirm: fn s -> {s, [Command.quit()]} end,
      on_cancel: fn s -> {s, [Command.quit()]} end
    }

    {%{state | modal: modal}, []}
  end
end
