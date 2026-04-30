defmodule Foglet.TUI.App.SessionAlias do
  @moduledoc """
  App-shell user/session aliasing helpers.

  Owns the `:set_user`, `:promote_session`, and `:session_replaced`
  do_update clauses (extracted from `Foglet.TUI.App` per Phase 47 D-20).
  Public callback boundary on `Foglet.TUI.App` is unchanged — `App` keeps
  thin one-line delegating `do_update` clauses.
  """

  alias Foglet.TUI.App
  alias Foglet.TUI.App.Effects
  alias Raxol.Core.Runtime.Command

  @spec set_user(App.t(), Foglet.Accounts.User.t()) :: {App.t(), [Command.t()]}
  def set_user(%App{} = state, user), do: promote_session(state, user)

  # TUI login screen authenticated a user — promote the guest session.
  # Routes through the Supervisor so one-session-per-user (SSH-05 / D-25) is
  # enforced: any pre-existing session for this user is replaced before this
  # guest pid registers under the user_id key.
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
          "Session telemetry will be missing"
      )
    end

    # Keep session_context in lockstep with current_user so screens that read
    # session_context.user (rather than current_user) see the authenticated
    # identity. :pubkey_authenticated stays as-is — TUI-driven login is
    # password-based by definition, so promoting here does NOT make the
    # session pubkey-authenticated.
    updated_context =
      state.session_context
      |> Map.put(:user, user)
      |> Map.put(:user_id, user.id)

    Effects.apply_effect(
      %{state | current_user: user, session_context: updated_context},
      Foglet.TUI.Effect.navigate(:main_menu, %{})
    )
  end

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
