defmodule Foglet.TUI.Screens.Login do
  @moduledoc """
  Login-or-register entry screen (SSH-04, D-22).

  Respects runtime config:
    * registration_mode == "disabled" → hides [R] Register (D-06)
    * any other value → shows all three options

  Login owns menu, form, reset request, reset-token consumption, and
  login/reset task outcomes through `init/1`, `update/3`, and `render/2`
  (Phase 35 D-11/D-13). App stores the reducer state and interprets emitted
  runtime effects; it does not own Login local flow.

  Sub-states:
    * :menu          — showing [L]/[R]/[F]/[T] menu as allowed by config
    * :login_form    — collecting handle+password
    * :reset_request — collecting handle/email for reset delivery
    * :reset_consume — collecting raw reset token + new password (Plan 31-03)

  State shape is owned by `Foglet.TUI.Screens.Login.State`.

  ## Config snapshotting (D-07)

  Registration mode is read by reducer helpers or from session context before
  render. Sibling render modules consume only already-loaded state/context.

  TextInput structs are created lazily in enter_login_form/1 each time the
  user presses L — this keeps per-session memory footprint small.
  """

  @behaviour Foglet.TUI.Screen

  alias Foglet.{Accounts, Config}
  alias Foglet.Accounts.{Auth, Verification}
  alias Foglet.TUI.{Context, Effect}
  alias Foglet.TUI.Screens.Login.Render
  alias Foglet.TUI.Screens.Login.State, as: LoginState
  alias Foglet.TUI.Screens.Shared.FocusInput
  alias Foglet.TUI.Widgets.Input.TextInput

  # WR-001: email-shape validation is delegated to
  # `Foglet.Accounts.Verification.email_shape?/1` so the screen and the
  # boundary cannot drift. Local validation still happens before the
  # boundary call so malformed inputs never invoke
  # `Verification.request_password_reset_delivery/1` (D-02).

  @reset_email_dispatched_message "If an active account matches, reset instructions will be sent by email. To enter a reset token already in hand, return to the Login menu (Esc) and press [T] Enter reset token."
  @reset_invalid_email_message "Please enter an email address (for example: name@example.test)."
  @reset_no_email_intro "Email delivery is disabled on this Foglet. Contact a sysop or operator over SSH to request a reset token, then return to the Login menu (Esc) and press [T] Enter reset token to set a new password."
  @reset_no_email_no_sysops_fallback "No sysop contact email is published on this Foglet. Reach an operator through your invite or community channel."

  # D-10: Generic, non-leaking copy for any token-validation failure.
  # Identical for invalid, malformed, expired, and already-used tokens so the
  # screen never reveals which failure mode occurred.
  @reset_consume_invalid_or_expired_message "That reset token did not work. Ask the sysop for a new one."
  @reset_consume_password_mismatch_message "Passwords do not match. Re-enter the new password."
  # Generic copy for any password-changeset validation failure on the new
  # password. Honest enough to be actionable, but does not echo specific
  # validation reasons that could differ across users.
  @reset_consume_password_invalid_message "Your new password is not acceptable. Choose a different password and try again."

  @impl true
  @spec init(Context.t()) :: map()
  def init(%Context{}), do: LoginState.default()

  @impl true
  @spec render(map(), Context.t()) :: any()
  def render(local_state, %Context{} = context), do: Render.render(local_state, context)

  @impl true
  @spec update(term(), map(), Context.t()) :: {map(), [Effect.t()]}
  def update({:key, %{key: :char, char: c, ctrl: true}}, local_state, %Context{})
      when c in ["c", "C"],
      do: {local_state, [Effect.quit()]}

  def update({:key, key}, local_state, %Context{} = context) do
    local_state
    |> app_state_from_local(context)
    |> reduce_key(key)
    |> local_result(local_state)
  end

  def update({:task_result, :login, {:ok, result}}, local_state, %Context{} = context) do
    local_state
    |> app_state_from_local(context)
    |> handle_login_result(result)
    |> local_result(local_state)
  end

  def update({:task_result, :login, {:error, _reason}}, local_state, %Context{} = context) do
    local_state
    |> app_state_from_local(context)
    |> handle_login_result({:error, :invalid_credentials})
    |> local_result(local_state)
  end

  def update({:task_result, :reset_request, {:ok, result}}, local_state, context),
    do: update({:task_result, :reset_request, result}, local_state, context)

  def update({:task_result, :reset_request, :email_dispatched}, local_state, %Context{}) do
    {Map.merge(
       local_state,
       %{
         error: nil,
         message: @reset_email_dispatched_message,
         message_category: :email_dispatched
       }
     ), []}
  end

  def update(
        {:task_result, :reset_request, {:no_email_operator_assisted, sysops}},
        local_state,
        %Context{}
      ) do
    {Map.merge(
       local_state,
       %{
         error: nil,
         message: no_email_operator_message(sysops),
         message_category: :no_email_operator_assisted
       }
     ), []}
  end

  def update({:task_result, :reset_request, {:error, _reason}}, local_state, %Context{}) do
    {Map.merge(local_state, %{error: @reset_invalid_email_message, message: nil}), []}
  end

  def update({:task_result, :reset_token, {:ok, {:ok, _user}}}, _local_state, %Context{}) do
    {LoginState.default(), []}
  end

  def update(
        {:task_result, :reset_token, {:ok, {:error, :invalid_or_expired}}},
        local_state,
        %Context{}
      ) do
    {Map.put(local_state, :error, @reset_consume_invalid_or_expired_message), []}
  end

  def update(
        {:task_result, :reset_token, {:ok, {:error, %Ecto.Changeset{}}}},
        local_state,
        %Context{}
      ) do
    {Map.put(local_state, :error, @reset_consume_password_invalid_message), []}
  end

  def update({:task_result, :reset_token, {:error, _reason}}, local_state, %Context{}) do
    {Map.put(local_state, :error, @reset_consume_invalid_or_expired_message), []}
  end

  def update(_message, local_state, %Context{}), do: {local_state, []}

  # Route all keys through sub-state so form input gets every character.
  defp reduce_key(state, key) do
    case LoginState.sub(state) do
      :login_form -> handle_form_key(key, state)
      :reset_request -> handle_reset_key(key, state)
      :reset_consume -> handle_reset_consume_key(key, state)
      _ -> handle_menu_key(key, state)
    end
  end

  defp handle_menu_key(%{key: :char, char: c}, state) when c in ["l", "L"],
    do: enter_login_form(state)

  defp handle_menu_key(%{key: :char, char: c}, state) when c in ["r", "R"],
    do: maybe_register(state)

  defp handle_menu_key(%{key: :char, char: c}, state) when c in ["f", "F"],
    do: maybe_enter_reset_request(state)

  # D-15: [T] Enter reset token is reachable directly from the Login menu so
  # users with an operator-issued raw reset token do not need to walk through
  # the Forgot Password flow first.
  defp handle_menu_key(%{key: :char, char: c}, state) when c in ["t", "T"],
    do: enter_reset_consume(state)

  defp handle_menu_key(_key, _state), do: :no_match

  # --- Private ---

  @typep login_result ::
           {:ok, Foglet.Accounts.User.t(), :main_menu}
           | {:ok, Foglet.Accounts.User.t(), :verify,
              :attempted | :changeset_error | :delivery_failed | :unavailable}
           | {:error, :invalid_credentials | :pending | :rejected | :suspended}

  @spec handle_login_result(map(), login_result()) :: {map(), [Effect.t()]}
  defp handle_login_result(state, {:ok, user, :main_menu}) do
    {LoginState.put(state, LoginState.default()), [Effect.session({:promote_session, user})]}
  end

  defp handle_login_result(state, {:ok, user, :verify, :attempted}) do
    complete_verify_login(state, user)
  end

  defp handle_login_result(state, {:ok, _user, :verify, :unavailable}) do
    login_error_modal(
      state,
      "Email verification is unavailable because email delivery is disabled."
    )
  end

  defp handle_login_result(state, {:ok, _user, :verify, :delivery_failed}) do
    login_error_modal(
      state,
      "Verification instructions could not be sent. Please try again later."
    )
  end

  defp handle_login_result(state, {:ok, _user, :verify, :changeset_error}) do
    login_error_modal(state, "Could not prepare verification instructions. Please try again.")
  end

  defp handle_login_result(state, {:error, :invalid_credentials}) do
    login_ss = LoginState.get(state)
    new_password_input = TextInput.init(mask_char: "*")

    new_login_ss =
      Map.merge(login_ss, %{
        error: "Invalid credentials.",
        password_input: new_password_input,
        submitting?: false
      })

    {LoginState.put(state, new_login_ss), []}
  end

  defp handle_login_result(state, {:error, :pending}) do
    login_error_modal(state, "Your account is pending sysop approval.", clear?: true)
  end

  defp handle_login_result(state, {:error, :rejected}) do
    login_error_modal(state, "Your registration was rejected. Contact the sysop.", clear?: true)
  end

  defp handle_login_result(state, {:error, :suspended}) do
    login_error_modal(state, "Your account is suspended. Contact the sysop.", clear?: true)
  end

  # Key routing pattern (D-06): Screen intercepts Tab/Enter/Escape, delegates to TextInput.
  # This pattern is inherited by Phase 2 (Register) and Phase 7 (NewThread).

  defp handle_form_key(key, state) do
    login_ss = LoginState.get(state)

    if Map.get(login_ss, :submitting?, false) do
      {:update, state, []}
    else
      handle_unlocked_form_key(key, state)
    end
  end

  # Tab cycles focus between :handle and :password
  defp handle_unlocked_form_key(%{key: :tab}, state) do
    login_ss = LoginState.get(state)
    new_login_ss = LoginState.toggle_focus(login_ss)
    {:update, LoginState.put(state, new_login_ss), []}
  end

  # Enter: submit if focused on password; advance focus if on handle
  defp handle_unlocked_form_key(%{key: :enter}, state) do
    login_ss = LoginState.get(state)

    if login_ss.focused_field == :password do
      submit_login(state)
    else
      new_login_ss = %{login_ss | focused_field: :password}
      {:update, LoginState.put(state, new_login_ss), []}
    end
  end

  # Escape: return to menu sub, clear form state
  defp handle_unlocked_form_key(%{key: :escape}, state) do
    {:update, LoginState.put(state, LoginState.default()), []}
  end

  # Everything else — delegate to focused TextInput
  defp handle_unlocked_form_key(event, state) do
    {new_input, _action} = TextInput.handle_event(event, focused_input(state))
    {:update, update_focused_input(state, new_input), []}
  end

  defp handle_reset_key(%{key: :enter}, state), do: submit_reset_request(state)

  defp handle_reset_key(%{key: :escape}, state) do
    {:update, LoginState.put(state, LoginState.default()), []}
  end

  # D-15 / CR-001: token-consume entry remains reachable from the Login menu
  # ([T] on `:menu`). The reset_request screen does *not* intercept bare `t`/`T`
  # because the identifier field is a free-text email input — any address
  # containing `t` or `T` (e.g. `taylor@example.com`, `bfturner@foglet.io`)
  # would otherwise have its keystrokes hijacked, jumping the screen into
  # `:reset_consume` and discarding the partially-typed identifier. Users on
  # the Forgot Password screen reach token entry via Esc → menu → [T].

  defp handle_reset_key(event, state) do
    login_ss = LoginState.get(state)
    {new_input, _action} = TextInput.handle_event(event, login_ss.identifier_input)
    {:update, LoginState.put(state, %{login_ss | identifier_input: new_input}), []}
  end

  # Reset-consume key handling (Plan 31-03 / D-04, D-06, D-07).
  #
  # Tab and :backtab cycle focus through the three fields in fixed order.
  # Enter submits the form. Escape returns to the menu and clears all
  # field state. Everything else is forwarded to the focused TextInput.

  defp handle_reset_consume_key(%{key: :tab}, state) do
    login_ss = LoginState.get(state)
    next_focus = LoginState.next_reset_consume_focus(login_ss.focused_field)
    {:update, LoginState.put(state, %{login_ss | focused_field: next_focus}), []}
  end

  defp handle_reset_consume_key(%{key: :backtab}, state) do
    login_ss = LoginState.get(state)
    prev_focus = LoginState.prev_reset_consume_focus(login_ss.focused_field)
    {:update, LoginState.put(state, %{login_ss | focused_field: prev_focus}), []}
  end

  # Some terminals send Shift+Tab as `:shift_tab` rather than `:backtab`;
  # accept both for symmetry with other Foglet forms.
  defp handle_reset_consume_key(%{key: :shift_tab}, state),
    do: handle_reset_consume_key(%{key: :backtab}, state)

  defp handle_reset_consume_key(%{key: :enter}, state), do: submit_reset_consume(state)

  defp handle_reset_consume_key(%{key: :escape}, state) do
    # D-07: Escape clears token/password fields and returns to the menu.
    {:update, LoginState.put(state, LoginState.default()), []}
  end

  defp handle_reset_consume_key(event, state) do
    {new_input, _action} = TextInput.handle_event(event, focused_input(state))
    {:update, update_focused_input(state, new_input), []}
  end

  defp focused_input(state) do
    FocusInput.get_focused(LoginState.get(state), &LoginState.input_key/1, :handle)
  end

  defp update_focused_input(state, new_input) do
    login_ss = LoginState.get(state)

    new_login_ss =
      FocusInput.update_focused(login_ss, new_input, &LoginState.input_key/1, :handle)

    LoginState.put(state, new_login_ss)
  end

  defp registration_mode(state) do
    case Map.get(session_ctx(state), :registration_mode) do
      nil -> Config.get("registration_mode", "open")
      mode -> mode
    end
  end

  defp session_ctx(state), do: Map.get(state, :session_context) || %{}

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
    {:update, LoginState.put(state, LoginState.reset_request()), []}
  end

  # D-04, D-15: Enter the reset-consume sub-state from any prior sub-state.
  # Always builds a fresh form so prior fields cannot leak across entries.
  defp enter_reset_consume(state) do
    {:update, LoginState.put(state, LoginState.reset_consume()), []}
  end

  defp submit_reset_request(state) do
    login_ss = LoginState.get(state)
    identifier = login_ss.identifier_input.raxol_state.value
    trimmed = String.trim(identifier)

    if email_shape?(trimmed) do
      dispatch_reset_request(state, login_ss, trimmed)
    else
      # D-02: malformed local input never invokes Accounts reset delivery.
      new_login_ss = %{
        login_ss
        | error: @reset_invalid_email_message,
          message: nil,
          message_category: :invalid_email
      }

      {:update, LoginState.put(state, new_login_ss), []}
    end
  end

  defp email_shape?(value), do: Verification.email_shape?(value)

  # Valid email shape — branch on delivery mode at the boundary level.
  # In email mode the same generic outward message_category is set whether or
  # not the email belongs to an active user (D-03). In no-email mode we present
  # operator-assisted copy with active sysop emails (D-14, AUTH-03).
  defp dispatch_reset_request(state, login_ss, email) do
    verification_mod = domain_module(state, :verification)
    submitting_state = LoginState.put(state, %{login_ss | error: nil, message: nil})

    effect =
      Effect.task(:reset_request, :login, fn ->
        case Foglet.Config.delivery_mode() do
          "email" ->
            # Discard return value: the boundary is generic by contract.
            _ = verification_mod.request_password_reset_delivery(email)
            :email_dispatched

          "no_email" ->
            {:no_email_operator_assisted, verification_mod.active_sysop_contact_emails()}
        end
      end)

    {:update, submitting_state, [effect]}
  end

  defp no_email_operator_message(sysops) do
    sysop_line =
      case sysops do
        [] -> @reset_no_email_no_sysops_fallback
        emails -> "Sysop contacts: " <> Enum.join(emails, ", ") <> "."
      end

    @reset_no_email_intro <> "\n\n" <> sysop_line
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
        Effect.task(:reset_token, :login, fn ->
          verification_mod.consume_reset_token(raw_token, %{password: new_password})
        end)

      {:update, submitting_state, [effect]}
    end
  end

  defp submit_login(state) do
    login_ss = LoginState.get(state)
    handle_value = login_ss.handle_input.raxol_state.value
    password_value = login_ss.password_input.raxol_state.value
    accounts_mod = domain_module(state, :accounts)
    auth_mod = domain_module(state, :auth)
    verification_mod = domain_module(state, :verification)
    submitting_ss = Map.merge(login_ss, %{error: nil, submitting?: true})
    submitting_state = LoginState.put(state, submitting_ss)

    effect =
      Effect.task(:login, :login, fn ->
        authenticate_login(
          accounts_mod,
          auth_mod,
          verification_mod,
          handle_value,
          password_value
        )
      end)

    {:update, submitting_state, [effect]}
  end

  defp authenticate_login(accounts_mod, auth_mod, verification_mod, handle_value, password_value) do
    # with chain (D-08): authenticate first, then dispatch on user status.
    # post_login_screen/1 returns :verify | :main_menu directly (no {:ok, _} wrapper).
    # Status check is inside the success branch — pending/suspended users authenticate
    # successfully but must not reach the main flow.
    with {:ok, user} <- auth_mod.authenticate_by_password(handle_value, password_value),
         :active <- user.status do
      screen = accounts_mod.post_login_screen(user)
      login_success_result(verification_mod, user, screen)
    else
      {:error, :invalid_credentials} ->
        {:error, :invalid_credentials}

      status when status in [:pending, :rejected, :suspended] ->
        {:error, status}
    end
  end

  defp login_success_result(_verification_mod, user, :main_menu), do: {:ok, user, :main_menu}

  defp login_success_result(verification_mod, user, :verify) do
    case verification_mod.deliver_verification_code(user) do
      {:ok, :attempted} -> {:ok, user, :verify, :attempted}
      {:error, :unavailable} -> {:ok, user, :verify, :unavailable}
      {:error, :delivery_failed} -> {:ok, user, :verify, :delivery_failed}
      {:error, %Ecto.Changeset{}} -> {:ok, user, :verify, :changeset_error}
    end
  end

  defp complete_verify_login(state, user) do
    {
      LoginState.put(state, LoginState.default()),
      [Effect.session({:set_current_user, user}), Effect.navigate(:verify, %{})]
    }
  end

  defp login_error_modal(state, message, opts \\ []) do
    modal = %Foglet.TUI.Modal{type: :error, message: message}

    if Keyword.get(opts, :clear?, false) do
      {LoginState.put(state, LoginState.default()), [Effect.open_modal(modal)]}
    else
      {unlock_login_form(state), [Effect.open_modal(modal)]}
    end
  end

  defp unlock_login_form(state) do
    login_ss = LoginState.get(state)

    if Map.get(login_ss, :sub) == :login_form do
      LoginState.put(state, Map.put(login_ss, :submitting?, false))
    else
      state
    end
  end

  defp app_state_from_local(local_state, %Context{} = context) do
    %{
      current_screen: :login,
      current_user: context.current_user,
      session_context: context.session_context,
      session_pid: context.session_pid,
      terminal_size: context.terminal_size,
      route_params: context.route_params,
      domain: context.domain,
      screen_state: %{login: local_state || LoginState.default()}
    }
  end

  defp local_result(:no_match, local_state), do: {local_state, []}

  defp local_result({:update, state, effects}, _local_state) do
    {LoginState.get(state), effects}
  end

  defp local_result({state, effects}, _local_state) when is_list(effects) do
    {LoginState.get(state), effects}
  end

  defp domain_module(state, key) do
    domain = Map.get(state, :domain) || %{}

    case Map.get(domain, key) do
      mod when is_atom(mod) and not is_nil(mod) -> mod
      _other -> default_domain_module(key)
    end
  end

  defp default_domain_module(:accounts), do: Accounts
  defp default_domain_module(:auth), do: Auth
  defp default_domain_module(:verification), do: Verification
end
