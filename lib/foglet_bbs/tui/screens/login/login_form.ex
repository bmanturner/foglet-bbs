defmodule Foglet.TUI.Screens.Login.LoginForm do
  @moduledoc """
  Per-mode reducer for the `:login_form` sub-state of the Login screen.

  Phase 47 plan 05 (D-14, D-16): exports `handle_key/2` and
  `handle_task_result/3` for the `:login` task atom.

  D-13: state remains a `:sub`-keyed map; `Map.merge(login_ss, %{...})`
  writes are preserved verbatim from the pre-refactor `login.ex`.
  """

  require Logger

  alias Foglet.Accounts
  alias Foglet.Accounts.{Auth, Verification}
  alias Foglet.TUI.{Context, Effect}
  alias Foglet.TUI.Screens.Login.State, as: LoginState
  alias Foglet.TUI.Screens.Shared.{AppStateBridge, FocusInput}
  alias Foglet.TUI.Widgets.Input.TextInput

  @typep login_result ::
           {:ok, Foglet.Accounts.User.t(), :main_menu}
           | {:ok, Foglet.Accounts.User.t(), :verify,
              :attempted | :changeset_error | :delivery_failed | :unavailable}
           | {:error, :invalid_credentials | :pending | :rejected | :suspended}

  @spec handle_key(map(), map()) ::
          :no_match | {:update, map(), [Effect.t()]} | {map(), [Effect.t()]}
  def handle_key(key, state) do
    login_ss = LoginState.get(state)

    if Map.get(login_ss, :submitting?, false) do
      {:update, state, []}
    else
      handle_unlocked_form_key(key, state)
    end
  end

  @doc """
  Handles `:login` task results (D-16).

  Operates on `local_state` directly. Internally wraps into the App-state
  shell so existing `handle_login_result/2` (which uses `LoginState.put`)
  keeps working unchanged.
  """
  @spec handle_task_result(term(), map(), Context.t()) :: {map(), [Effect.t()]}
  def handle_task_result({:ok, result}, local_state, %Context{} = ctx) do
    local_state
    |> app_state_from_local(ctx)
    |> handle_login_result(result)
    |> local_result(local_state)
  end

  # WR-01: Reserve `{:error, :invalid_credentials}` for the explicit auth
  # failure shape returned by `authenticate_login/5`. A `{:error, _reason}`
  # arriving here means the task itself failed (network, GenServer crash,
  # WithClauseError surfaced from WR-02's catch-all, Ecto pool timeout) —
  # log it as an operator fault signal and surface an "unavailable" modal
  # rather than silently miscategorizing the bug as bad credentials.
  def handle_task_result({:error, reason}, local_state, %Context{} = ctx) do
    Logger.error("[Login] login task crashed: #{inspect(reason)}")

    modal = %Foglet.TUI.Modal{
      type: :error,
      message: "Login is temporarily unavailable. Please try again."
    }

    local_state
    |> app_state_from_local(ctx)
    |> login_error_modal_unavailable(modal)
    |> local_result(local_state)
  end

  defp login_error_modal_unavailable(state, modal) do
    {unlock_login_form(state), [Effect.open_modal(modal)]}
  end

  # --- Key handlers ---

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

  defp focused_input(state) do
    FocusInput.get_focused(LoginState.get(state), &LoginState.input_key/1, :handle)
  end

  defp update_focused_input(state, new_input) do
    login_ss = LoginState.get(state)

    new_login_ss =
      FocusInput.update_focused(login_ss, new_input, &LoginState.input_key/1, :handle)

    LoginState.put(state, new_login_ss)
  end

  # --- Login submission + result handling ---

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

      # WR-02: surface unanticipated auth-error tuples (e.g. a future
      # `{:error, :rate_limited}` or `{:error, :unavailable}`) instead of
      # raising `WithClauseError` and getting silently masked as
      # "invalid credentials" by the task-result handler above.
      {:error, other} ->
        Logger.error("[Login] unexpected auth error: #{inspect(other)}")
        {:error, :invalid_credentials}

      # WR-02: same defensive treatment for unanticipated user statuses.
      # `Foglet.Accounts.User.status` is an atom and could in principle
      # take values outside the known set (e.g. test fixtures or a future
      # state); raise a logged breadcrumb and fall back to the generic
      # invalid-credentials path rather than crashing.
      other ->
        Logger.error("[Login] unexpected user status: #{inspect(other)}")
        {:error, :invalid_credentials}
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

  # --- App-state wrap/unwrap (Phase 47 plan 05 D-14 + WR-04 shared module) ---

  defp app_state_from_local(local_state, %Context{} = context) do
    AppStateBridge.from_context(local_state, context, :login, &LoginState.default/0)
  end

  defp local_result({state, effects}, _local_state) when is_list(effects) do
    {LoginState.get(state), effects}
  end

  # --- Domain-module resolution (duplicated from Login per Phase 47 plan 05 D-14) ---

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
