defmodule Foglet.TUI.Screens.Login.Menu do
  @moduledoc """
  Per-mode reducer for the `:menu` sub-state of the Login screen.

  Phase 47 plan 05 (D-14): exports `handle_key/2` only — the menu has no
  task-result handlers because no task atoms (`:login`, `:reset_request`,
  `:reset_token`) target the menu sub-state (D-16).

  Operates on the App-state map (the wrapped state passed by
  `Login.reduce_key/2`), so reads/writes go through `LoginState.get/put`.
  """

  alias Foglet.Config
  alias Foglet.TUI.Effect
  alias Foglet.TUI.Guest
  alias Foglet.TUI.Screens.Login.State, as: LoginState

  @spec handle_key(map(), map()) ::
          :no_match | {:update, map(), [Effect.t()]} | {map(), [Effect.t()]}
  def handle_key(%{key: :char, char: c}, state) when c in ["l", "L"],
    do: enter_login_form(state)

  def handle_key(%{key: :char, char: c}, state) when c in ["r", "R"],
    do: maybe_register(state)

  def handle_key(%{key: :char, char: c}, state) when c in ["f", "F"],
    do: maybe_enter_reset_request(state)

  # D-15: [T] Enter reset token is reachable directly from the Login menu so
  # users with an operator-issued raw reset token do not need to walk through
  # the Forgot Password flow first.
  def handle_key(%{key: :char, char: c}, state) when c in ["t", "T"],
    do: enter_reset_consume(state)

  def handle_key(%{key: :char, char: c}, state) when c in ["g", "G"],
    do: maybe_enter_guest(state)

  def handle_key(_key, _state), do: :no_match

  # --- Private ---

  defp enter_login_form(state) do
    {:update, LoginState.put(state, LoginState.login_form()), []}
  end

  defp maybe_register(state) do
    case registration_mode(state) do
      "disabled" ->
        :no_match

      _mode ->
        {:update, state, [Effect.navigate(:register, %{})]}
    end
  end

  # D-01: Forgot Password is unconditionally reachable; the reset request
  # sub-state handles delivery-mode branching at submit time.
  defp maybe_enter_reset_request(state) do
    {:update, LoginState.put(state, LoginState.reset_recovery(:request)), []}
  end

  # D-04, D-15: Enter the unified reset recovery surface from the token pane.
  # Always builds a fresh form so prior fields cannot leak across entries.
  defp enter_reset_consume(state) do
    {:update, LoginState.put(state, LoginState.reset_recovery(:token)), []}
  end

  defp maybe_enter_guest(state) do
    if guest_mode_enabled?(state) do
      {:update, state, [Effect.session(:enter_guest)]}
    else
      :no_match
    end
  end

  defp registration_mode(state) do
    case Map.get(session_ctx(state), :registration_mode) do
      nil -> Config.get("registration_mode", "open")
      mode -> mode
    end
  end

  defp guest_mode_enabled?(state) do
    case Map.get(session_ctx(state), :guest_mode_enabled) do
      nil -> Config.guest_mode_enabled?()
      _value -> Guest.guest_mode_enabled?(session_ctx(state))
    end
  end

  defp session_ctx(state), do: Map.get(state, :session_context) || %{}
end
