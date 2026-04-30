defmodule Foglet.TUI.App.Effects do
  @moduledoc """
  App-shell effect interpreter for `%Foglet.TUI.Effect{}` values.

  This module owns generic runtime effect interpretation for `%Foglet.TUI.App{}`
  state while leaving `Foglet.TUI.App` as the Raxol callback integration point.
  Durable domain behavior stays in screen-requested tasks and domain contexts;
  effects only route, schedule, publish, notify, and return runtime commands.
  """

  alias Foglet.TUI.App
  alias Foglet.TUI.App.Modal, as: AppModal
  alias Foglet.TUI.App.Routing
  alias Foglet.TUI.Effect
  alias Raxol.Core.Runtime.Command

  @doc "Interprets one runtime effect against the App shell."
  @spec apply_effect(App.t(), Effect.t()) :: {App.t(), [Command.t()]}
  def apply_effect(%App{} = state, %Effect{
        type: :navigate,
        payload: %{screen: screen, params: params}
      }) do
    params = params || %{}

    state =
      state
      |> Map.put(:current_screen, screen)
      |> Map.put(:route_params, params)
      |> Map.put(:modal, nil)
      |> Routing.init_route_screen_state(screen, params)

    Routing.dispatch_route_entry(state, screen, params)
  end

  def apply_effect(%App{} = state, %Effect{type: :modal, payload: {:open, modal}}) do
    {%{state | modal: modal}, []}
  end

  def apply_effect(%App{} = state, %Effect{type: :modal, payload: :dismiss}) do
    AppModal.dismiss(state)
  end

  def apply_effect(%App{} = state, %Effect{
        type: :modal_submit,
        payload: %{screen_key: screen_key, kind: kind, payload: payload}
      })
      when is_atom(kind) do
    if modal_submit_target?(state, screen_key) do
      Routing.route_screen_update(state, screen_key, {:modal_submit, kind, payload})
    else
      AppModal.submit_error(state)
    end
  end

  def apply_effect(%App{} = state, %Effect{type: :session, payload: {:set_user, user}}) do
    App.update({:set_user, user}, state)
  end

  def apply_effect(%App{} = state, %Effect{
        type: :session,
        payload: {:promote_session, user}
      }) do
    App.update({:promote_session, user}, state)
  end

  def apply_effect(%App{} = state, %Effect{
        type: :session,
        payload: {:set_current_user, user}
      }) do
    {%{state | current_user: user}, []}
  end

  def apply_effect(%App{} = state, %Effect{
        type: :session,
        payload: {:update_preferences, snapshot}
      }) do
    state =
      state
      |> merge_session_preferences(snapshot)
      |> refresh_session_preferences(snapshot)

    {state, []}
  end

  def apply_effect(%App{} = state, %Effect{
        type: :session,
        payload: {:dispatch, message}
      }) do
    App.update(message, state)
  end

  def apply_effect(%App{session_pid: session_pid} = state, %Effect{
        type: :session,
        payload: message
      }) do
    if is_pid(session_pid), do: send(session_pid, message)

    {state, []}
  end

  def apply_effect(%App{} = state, %Effect{
        type: :terminal,
        payload: {:size, {cols, rows}}
      }) do
    App.update({:window_change, cols, rows}, state)
  end

  def apply_effect(%App{} = state, %Effect{
        type: :publish,
        payload: %{topic: topic, message: message}
      }) do
    _ = Phoenix.PubSub.broadcast(FogletBbs.PubSub, topic, message)

    {state, []}
  end

  def apply_effect(%App{} = state, %Effect{type: :quit}) do
    {state, [Command.quit()]}
  end

  def apply_effect(%App{} = state, %Effect{
        type: :task,
        payload: %{op: op, screen_key: screen_key, fun: fun}
      }) do
    task =
      Foglet.TUI.Command.task(op, fn ->
        try do
          {:screen_task_result, screen_key, op, {:ok, fun.()}}
        rescue
          e ->
            reason = Exception.format(:error, e, __STACKTRACE__)
            {:screen_task_result, screen_key, op, {:error, reason}}
        catch
          kind, value ->
            reason = Exception.format(kind, value, __STACKTRACE__)
            {:screen_task_result, screen_key, op, {:error, reason}}
        end
      end)

    {state, [task]}
  end

  @doc "Interprets effects in order, appending produced runtime commands."
  @spec apply_effects(App.t(), [Effect.t()]) :: {App.t(), [Command.t()]}
  def apply_effects(%App{} = state, effects) when is_list(effects) do
    Enum.reduce(effects, {state, []}, fn effect, {acc_state, acc_cmds} ->
      {next_state, cmds} = apply_effect(acc_state, effect)
      {next_state, acc_cmds ++ cmds}
    end)
  end

  defp modal_submit_target?(%App{} = state, screen_key) do
    module = Routing.screen_module_for(state, screen_key)
    Code.ensure_loaded?(module) and function_exported?(module, :update, 3)
  end

  defp merge_session_preferences(state, snapshot) do
    session_context =
      state.session_context
      |> Map.put(:timezone, snapshot.timezone)
      |> Map.put(:time_format, snapshot.time_format)
      |> Map.put(:theme_id, snapshot.theme_id)
      |> Map.put(:theme, snapshot.theme)

    %{state | session_context: session_context}
  end

  defp refresh_session_preferences(%{session_pid: session_pid} = state, snapshot)
       when is_pid(session_pid) do
    Foglet.Sessions.Session.update_preferences(session_pid, snapshot)
    state
  end

  defp refresh_session_preferences(state, _snapshot), do: state
end
