defmodule Foglet.TUI.Screens.Login.ResetConsume do
  @moduledoc """
  Per-mode reducer for the `:reset_consume` sub-state of the Login screen.

  Phase 47 plan 05 (D-14, D-16): exports `handle_key/2` and
  `handle_task_result/3` for the `:reset_token` task atom.

  Reset-consume key handling (Plan 31-03 / D-04, D-06, D-07):
    * Tab / `:backtab` cycle focus through the three fields in fixed order.
    * Enter submits the form.
    * Escape returns to the menu and clears all field state.
    * Everything else is forwarded to the focused TextInput.

  D-13: state remains a `:sub`-keyed map.
  """

  alias Foglet.Accounts.Verification
  alias Foglet.TUI.{Context, Effect, Input, KeyBinding}
  alias Foglet.TUI.Screens.Login.State, as: LoginState
  alias Foglet.TUI.Screens.Shared.FocusInput
  alias Foglet.TUI.Widgets.Input.TextInput

  # D-10: Generic, non-leaking copy for any token-validation failure.
  # Identical for invalid, malformed, expired, and already-used tokens so the
  # screen never reveals which failure mode occurred.
  @reset_consume_invalid_or_expired_message "That reset token did not work. Ask the sysop for a new one."
  @reset_consume_password_mismatch_message "Those two passwords don't match. Re-type the new one."
  # Generic copy for any password-changeset validation failure on the new
  # password. Honest enough to be actionable, but does not echo specific
  # validation reasons that could differ across users.
  @reset_consume_password_invalid_message "That password isn't allowed. Pick a different one."

  @spec handle_key(map(), map()) ::
          :no_match | {:update, map(), [Effect.t()]} | {map(), [Effect.t()]}
  def handle_key(event, state) do
    cond do
      Input.backward_tab?(event) ->
        move_focus(state, :previous)

      Input.forward_tab?(event) ->
        move_focus(state, :next)

      KeyBinding.submit?(event) ->
        submit_reset_consume(state)

      KeyBinding.cancel?(event) ->
        {:update, LoginState.put(state, LoginState.default()), []}

      true ->
        handle_input_key(event, state)
    end
  end

  defp move_focus(state, :next) do
    login_ss = LoginState.get(state)
    next_focus = LoginState.next_reset_consume_focus(login_ss.focused_field)
    {:update, LoginState.put(state, %{login_ss | focused_field: next_focus}), []}
  end

  defp move_focus(state, :previous) do
    login_ss = LoginState.get(state)
    prev_focus = LoginState.prev_reset_consume_focus(login_ss.focused_field)
    {:update, LoginState.put(state, %{login_ss | focused_field: prev_focus}), []}
  end

  defp handle_input_key(event, state) do
    {new_input, _action} = TextInput.handle_event(event, focused_input(state))
    {:update, update_focused_input(state, new_input), []}
  end

  @doc """
  Handles `:reset_token` task results (D-16).

  Operates on `local_state` directly. Routed by task atom — same task may
  arrive after the user navigated to a different sub-state.
  """
  @spec handle_task_result(term(), map(), Context.t()) :: {map(), [Effect.t()]}
  def handle_task_result({:ok, {:ok, _user}}, _local_state, %Context{}) do
    {LoginState.default(), []}
  end

  def handle_task_result({:ok, {:error, :invalid_or_expired}}, local_state, %Context{}) do
    {Map.put(local_state, :error, @reset_consume_invalid_or_expired_message), []}
  end

  def handle_task_result({:ok, {:error, %Ecto.Changeset{}}}, local_state, %Context{}) do
    {Map.put(local_state, :error, @reset_consume_password_invalid_message), []}
  end

  def handle_task_result({:error, _reason}, local_state, %Context{}) do
    {Map.put(local_state, :error, @reset_consume_invalid_or_expired_message), []}
  end

  # --- Private: focus and submission ---

  # The third arg (`:handle`) is the default focused field used when
  # `:focused_field` is missing from the screen state — see Login state
  # invariants for the rationale.
  defp focused_input(state) do
    FocusInput.get_focused(LoginState.get(state), &LoginState.input_key/1, :handle)
  end

  defp update_focused_input(state, new_input) do
    login_ss = LoginState.get(state)

    new_login_ss =
      FocusInput.update_focused(login_ss, new_input, &LoginState.input_key/1, :handle)

    LoginState.put(state, new_login_ss)
  end

  # Reset-consume submission (Plan 31-03 / D-07, D-08, D-09, D-10).
  #
  # 1. Compare new password to confirmation locally; on mismatch set inline
  #    error and bail without calling Accounts. Token is *not* consumed.
  # 2. Otherwise call Verification.consume_reset_token/2 which atomically
  #    verifies, claims the token row, updates the password, and deletes
  #    other outstanding reset tokens for the user.
  # 3. On success return to the logged-out Login menu and clear all field
  #    state (D-07). On any token failure render the generic invalid/expired
  #    copy (D-10). On password-changeset failure render generic password
  #    failure copy (still token-consumed-once because consume runs in a
  #    transaction; if the password update fails the consume rolls back).
  defp submit_reset_consume(state) do
    login_ss = LoginState.get(state)
    raw_token = login_ss.token_input.raxol_state.value
    new_password = login_ss.password_input.raxol_state.value
    confirmation = login_ss.password_confirmation_input.raxol_state.value

    if new_password != confirmation do
      # D-07/D-10 mismatch: keep state, surface a generic mismatch error,
      # and do *not* call into Accounts. Token row is preserved so the user
      # can correct their password and try again.
      new_login_ss = %{login_ss | error: @reset_consume_password_mismatch_message}
      {:update, LoginState.put(state, new_login_ss), []}
    else
      verification_mod = domain_module(state, :verification)
      submitting_state = LoginState.put(state, %{login_ss | error: nil})

      effect =
        Effect.task(:reset_token, fn ->
          verification_mod.consume_reset_token(raw_token, %{password: new_password})
        end)

      {:update, submitting_state, [effect]}
    end
  end

  # --- Domain-module resolution (duplicated from Login per Phase 47 plan 05 D-14) ---

  defp domain_module(state, key) do
    domain = Map.get(state, :domain) || %{}

    case Map.get(domain, key) do
      mod when is_atom(mod) and not is_nil(mod) -> mod
      _other -> default_domain_module(key)
    end
  end

  defp default_domain_module(:verification), do: Verification
end
