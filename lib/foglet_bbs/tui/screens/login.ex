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

  Sub-states (Phase 47 plan 05 D-14: each sub-state owned by its sibling
  per-mode reducer module under `lib/foglet_bbs/tui/screens/login/`):
    * `:menu`          — `Login.Menu` (handle_key only — no task atom targets it)
    * `:login_form`    — `Login.LoginForm` (handle_key + handle_task_result for `:login`)
    * `:reset_request` — `Login.ResetRequest` (handle_key + handle_task_result for `:reset_request`)
    * `:reset_consume` — `Login.ResetConsume` (handle_key + handle_task_result for `:reset_token`)

  State shape is owned by `Foglet.TUI.Screens.Login.State`. D-13: the
  `:sub`-keyed map shape is preserved; this screen does NOT use a
  tagged-union struct.

  Top-level dispatch (D-15): `reduce_key/2` is a four-way `case
  LoginState.sub(state)` with one-line delegates per branch. Task-result
  clauses (D-16) route by **task atom** (`:login`, `:reset_request`,
  `:reset_token`), NOT by current `:sub`. This preserves today's behavior
  where a delayed reset-request result arriving after the user navigated
  back to `:menu` still sets `state.message`.
  """

  @behaviour Foglet.TUI.Screen

  alias Foglet.TUI.{Context, Effect}

  alias Foglet.TUI.Screens.Login.{
    LoginForm,
    Menu,
    MenuScramble,
    Render,
    ResetConsume,
    ResetRecovery,
    ResetRequest
  }

  alias Foglet.TUI.Screens.Login.State, as: LoginState
  alias Foglet.TUI.Screens.Shared.AppStateBridge

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

  def update({:task_result, :reset_request, result}, local_state, %Context{} = ctx),
    do: ResetRequest.handle_task_result(result, local_state, ctx)

  def update({:task_result, :reset_token, result}, local_state, %Context{} = ctx),
    do: ResetConsume.handle_task_result(result, local_state, ctx)

  def update(:menu_scramble_tick, local_state, %Context{} = context) do
    local_state
    |> app_state_from_local(context)
    |> update_menu_scramble()
    |> local_result(local_state)
  end

  def update(_message, local_state, %Context{}), do: {local_state, []}

  @impl true
  @spec subscriptions(map(), Context.t()) :: %{
          topics: [String.t()],
          intervals: [MenuScramble.interval_subscription()]
        }
  def subscriptions(local_state, %Context{}) do
    %{topics: [], intervals: MenuScramble.subscriptions(local_state)}
  end

  # --- Top-level dispatch (D-15) ---

  defp reduce_key(state, key) do
    case LoginState.sub(state) do
      :login_form -> LoginForm.handle_key(key, state)
      :reset_recovery -> ResetRecovery.handle_key(key, state)
      :reset_request -> ResetRequest.handle_key(key, state)
      :reset_consume -> ResetConsume.handle_key(key, state)
      _ -> Menu.handle_key(key, state)
    end
  end

  defp update_menu_scramble(state) do
    login_ss = LoginState.get(state)
    next = MenuScramble.tick(login_ss)
    {:update, LoginState.put(state, next), []}
  end

  # --- App-state wrap/unwrap glue ---

  # WR-04: shared bridge — see Foglet.TUI.Screens.Shared.AppStateBridge.
  defp app_state_from_local(local_state, %Context{} = context) do
    AppStateBridge.from_context(local_state, context, :login, &LoginState.default/0)
  end

  defp local_result(:no_match, local_state), do: {local_state, []}

  defp local_result({:update, state, effects}, _local_state) do
    {LoginState.get(state), effects}
  end
end
