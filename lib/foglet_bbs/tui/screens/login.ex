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

  Sub-states (Phase 47 plan 05 in progress — D-14):
    * :menu          — extracted to `Login.Menu`
    * :login_form    — extracted to `Login.LoginForm`
    * :reset_request — collecting handle/email for reset delivery (still local pending Task 2)
    * :reset_consume — collecting raw reset token + new password (still local pending Task 2)

  State shape is owned by `Foglet.TUI.Screens.Login.State` and remains a
  `:sub`-keyed map per D-13 (no tagged-union struct conversion).
  """

  @behaviour Foglet.TUI.Screen

  alias Foglet.Accounts
  alias Foglet.Accounts.{Auth, Verification}
  alias Foglet.TUI.{Context, Effect}
  alias Foglet.TUI.Screens.Login.{LoginForm, Menu, Render}
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
  @reset_consume_invalid_or_expired_message "That reset token did not work. Ask the sysop for a new one."
  @reset_consume_password_mismatch_message "Passwords do not match. Re-enter the new password."
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

  def update({:task_result, :login, result}, local_state, %Context{} = ctx),
    do: LoginForm.handle_task_result(result, local_state, ctx)

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
      :login_form -> LoginForm.handle_key(key, state)
      :reset_request -> handle_reset_key(key, state)
      :reset_consume -> handle_reset_consume_key(key, state)
      _ -> Menu.handle_key(key, state)
    end
  end

  # --- Reset-request key handling (still local pending Task 2) ---

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

  # --- Reset-consume key handling (still local pending Task 2) ---
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

  defp handle_reset_consume_key(%{key: :shift_tab}, state),
    do: handle_reset_consume_key(%{key: :backtab}, state)

  defp handle_reset_consume_key(%{key: :enter}, state), do: submit_reset_consume(state)

  defp handle_reset_consume_key(%{key: :escape}, state) do
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

  defp dispatch_reset_request(state, login_ss, email) do
    verification_mod = domain_module(state, :verification)
    submitting_state = LoginState.put(state, %{login_ss | error: nil, message: nil})

    effect =
      Effect.task(:reset_request, :login, fn ->
        case Foglet.Config.delivery_mode() do
          "email" ->
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

  defp submit_reset_consume(state) do
    login_ss = LoginState.get(state)
    raw_token = login_ss.token_input.raxol_state.value
    new_password = login_ss.password_input.raxol_state.value
    confirmation = login_ss.password_confirmation_input.raxol_state.value

    if new_password != confirmation do
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

  # --- App-state wrap/unwrap glue ---

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
