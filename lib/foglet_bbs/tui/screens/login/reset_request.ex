defmodule Foglet.TUI.Screens.Login.ResetRequest do
  @moduledoc """
  Per-mode reducer for the `:reset_request` sub-state of the Login screen.

  Phase 47 plan 05 (D-14, D-16): exports `handle_key/2` and
  `handle_task_result/3` for the `:reset_request` task atom.

  D-16: task-result handlers route by **task atom**, not by current
  `:sub`. A delayed reset-request result arriving after the user
  navigated back to `:menu` still updates `state.message`.

  D-13: state remains a `:sub`-keyed map; `Map.merge(local_state, %{...})`
  writes are preserved verbatim from the pre-refactor `login.ex`.
  """

  alias Foglet.Accounts.Verification
  alias Foglet.TUI.{Context, Effect}
  alias Foglet.TUI.Screens.Login.State, as: LoginState
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

  @spec handle_key(map(), map()) ::
          :no_match | {:update, map(), [Effect.t()]} | {map(), [Effect.t()]}
  def handle_key(%{key: :enter}, state), do: submit_reset_request(state)

  def handle_key(%{key: :escape}, state) do
    {:update, LoginState.put(state, LoginState.default()), []}
  end

  # D-15 / CR-001: token-consume entry remains reachable from the Login menu
  # ([T] on `:menu`). The reset_request screen does *not* intercept bare `t`/`T`
  # because the identifier field is a free-text email input — any address
  # containing `t` or `T` (e.g. `taylor@example.com`, `bfturner@foglet.io`)
  # would otherwise have its keystrokes hijacked, jumping the screen into
  # `:reset_consume` and discarding the partially-typed identifier. Users on
  # the Forgot Password screen reach token entry via Esc → menu → [T].
  def handle_key(event, state) do
    login_ss = LoginState.get(state)
    {new_input, _action} = TextInput.handle_event(event, login_ss.identifier_input)
    {:update, LoginState.put(state, %{login_ss | identifier_input: new_input}), []}
  end

  @doc """
  Handles `:reset_request` task results (D-16).

  Operates on `local_state` directly — these task results are routed by
  task atom (D-16), so they may arrive on any current `:sub` (e.g., after
  the user navigated back to `:menu`). The behavior matches the
  pre-refactor flow: `Map.merge(local_state, %{...})` writes set
  `error`/`message`/`message_category` regardless of the current sub.
  """
  @spec handle_task_result(term(), map(), Context.t()) :: {map(), [Effect.t()]}
  def handle_task_result({:ok, result}, local_state, ctx),
    do: handle_task_result(result, local_state, ctx)

  def handle_task_result(:email_dispatched, local_state, %Context{}) do
    {Map.merge(
       local_state,
       %{
         error: nil,
         message: @reset_email_dispatched_message,
         message_category: :email_dispatched
       }
     ), []}
  end

  def handle_task_result({:no_email_operator_assisted, sysops}, local_state, %Context{}) do
    {Map.merge(
       local_state,
       %{
         error: nil,
         message: no_email_operator_message(sysops),
         message_category: :no_email_operator_assisted
       }
     ), []}
  end

  def handle_task_result({:error, _reason}, local_state, %Context{}) do
    {Map.merge(local_state, %{error: @reset_invalid_email_message, message: nil}), []}
  end

  # --- Private ---

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
