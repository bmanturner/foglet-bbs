defmodule Foglet.TUI.App.RuntimeMessages do
  @moduledoc """
  Routes normalized App runtime messages to the helper that owns each concern.

  `Foglet.TUI.App` remains the Raxol callback boundary, while this module owns
  the message classifier and the reducer clauses for terminal/input, modal,
  routing, session, PubSub, door, clock, notification, and task-result events.
  The concern classifier is intentionally public so tests can lock down the
  known runtime message surface as the callback evolves.
  """

  alias Foglet.TUI.App
  alias Foglet.TUI.App.Door
  alias Foglet.TUI.App.Modal, as: AppModal
  alias Foglet.TUI.App.PubSubRouter
  alias Foglet.TUI.App.Routing
  alias Foglet.TUI.App.ScreenStates
  alias Foglet.TUI.App.SessionAlias
  alias Foglet.TUI.App.Tasks, as: AppTasks
  alias Foglet.TUI.CommandEntry
  alias Foglet.TUI.Guest
  alias Foglet.TUI.SizeGate
  alias Raxol.Core.Runtime.Command

  require PubSubRouter

  @type concern ::
          :clock
          | :door
          | :input
          | :modal
          | :notification
          | :presence
          | :pubsub
          | :routing
          | :session
          | :tasks
          | :terminal
          | :unknown

  @doc "Returns the owning concern for a normalized runtime message."
  @spec concern(term()) :: concern()
  def concern({:window_change, cols, rows})
      when is_integer(cols) and is_integer(rows) and cols > 0 and rows > 0,
      do: :terminal

  def concern({:navigate, screen}) when is_atom(screen), do: :routing
  def concern({:set_user, _user}), do: :session
  def concern(:enter_guest), do: :session
  def concern({:show_modal, modal}) when is_struct(modal, Foglet.TUI.Modal), do: :modal
  def concern(:dismiss_modal), do: :modal
  def concern({:confirm_modal, answer}) when answer in [:yes, :no], do: :modal
  def concern({:key, _key_event}), do: :input
  def concern(msg) when PubSubRouter.is_routable(msg), do: :pubsub
  def concern({:online_presence, _event, _payload}), do: :presence
  def concern({:notification, _user_id, _kind, _payload}), do: :notification
  def concern({:door_exited, _door_id, _reason, _status}), do: :door
  def concern({:door_launch_failed, _door_id, _reason}), do: :door
  def concern(:heartbeat_tick), do: :session
  def concern({:tui_clock, :minute_tick, %DateTime{}}), do: :clock
  def concern(:main_menu_clock_tick), do: :clock
  def concern(:login_menu_scramble_tick), do: :routing
  def concern(:initial_route_enter), do: :routing
  def concern({:session_replaced, _payload}), do: :session
  def concern({:promote_session, _user}), do: :session
  def concern({:command_result, _inner}), do: :tasks
  def concern({:screen_task_result, _key, _op, _result}), do: :tasks
  def concern({:terminate_after_modal, _reason}), do: :modal
  def concern({:task_error, _op, _reason}), do: :tasks
  def concern(_message), do: :unknown

  @doc "Dispatches a normalized runtime message to the owning concern handler."
  @spec handle(term(), App.t()) :: {App.t(), [Command.t()]}
  def handle(message, %App{} = state), do: dispatch(concern(message), message, state)

  defp dispatch(:terminal, message, %App{} = state), do: handle_terminal(message, state)
  defp dispatch(:routing, message, %App{} = state), do: handle_routing(message, state)
  defp dispatch(:session, message, %App{} = state), do: handle_session(message, state)
  defp dispatch(:modal, message, %App{} = state), do: handle_modal(message, state)
  defp dispatch(:input, message, %App{} = state), do: handle_input(message, state)
  defp dispatch(:pubsub, message, %App{} = state), do: PubSubRouter.forward(state, message)
  defp dispatch(:presence, message, %App{} = state), do: handle_presence(message, state)
  defp dispatch(:notification, message, %App{} = state), do: handle_notification(message, state)
  defp dispatch(:door, message, %App{} = state), do: Door.handle(message, state)
  defp dispatch(:clock, message, %App{} = state), do: handle_clock(message, state)
  defp dispatch(:tasks, message, %App{} = state), do: handle_tasks(message, state)
  defp dispatch(:unknown, _message, %App{} = state), do: {state, []}

  defp handle_terminal({:window_change, cols, rows}, %App{} = state) do
    if state.terminal_size == {cols, rows} do
      {state, []}
    else
      if is_pid(state.session_pid) do
        Foglet.Sessions.Session.set_terminal_size(state.session_pid, {cols, rows})
      end

      {%{state | terminal_size: {cols, rows}}, []}
    end
  end

  defp handle_routing({:navigate, screen}, %App{} = state) do
    Foglet.TUI.App.Effects.apply_effect(state, Foglet.TUI.Effect.navigate(screen, %{}))
  end

  defp handle_routing(:login_menu_scramble_tick, %App{} = state) do
    if state.current_screen == :login do
      Routing.route_screen_update(state, :login, :menu_scramble_tick)
    else
      {state, []}
    end
  end

  defp handle_routing(:initial_route_enter, %App{} = state) do
    Routing.route_screen_update(
      state,
      Routing.screen_key(Routing.current_route(state)),
      :on_route_enter
    )
  end

  defp handle_session({:set_user, user}, %App{} = state), do: SessionAlias.set_user(state, user)

  defp handle_session(:enter_guest, %App{} = state) do
    session_context = Guest.enter(state.session_context || %Foglet.TUI.SessionContext{})

    state = %{
      state
      | current_user: nil,
        current_screen: :main_menu,
        route_params: %{},
        session_context: session_context,
        modal: nil
    }

    local_state = Foglet.TUI.Screens.MainMenu.init(Routing.build_context(state))

    state
    |> ScreenStates.put(:main_menu, local_state)
    |> Routing.dispatch_route_entry(:main_menu, %{})
  end

  defp handle_session(:heartbeat_tick, %App{} = state), do: SessionAlias.heartbeat(state)

  defp handle_session({:session_replaced, payload}, %App{} = state),
    do: SessionAlias.session_replaced(state, payload)

  defp handle_session({:promote_session, user}, %App{} = state),
    do: SessionAlias.promote_session(state, user)

  defp handle_modal({:show_modal, modal}, %App{} = state), do: {%{state | modal: modal}, []}
  defp handle_modal(:dismiss_modal, %App{} = state), do: AppModal.dismiss(state)
  defp handle_modal({:confirm_modal, answer}, %App{} = state), do: AppModal.confirm(state, answer)

  defp handle_modal({:terminate_after_modal, _reason}, %App{} = state) do
    modal =
      if state.modal do
        Map.merge(state.modal, %{
          on_confirm: fn s -> {s, [Command.quit()]} end,
          on_cancel: fn s -> {s, [Command.quit()]} end
        })
      else
        %Foglet.TUI.Modal{
          type: :info,
          message: "Session will now close.",
          on_confirm: fn s -> {s, [Command.quit()]} end,
          on_cancel: fn s -> {s, [Command.quit()]} end
        }
      end

    {%{state | modal: modal}, []}
  end

  defp handle_input({:key, key_event}, %App{} = state) do
    :ok = SessionAlias.record_user_action(state)

    cond do
      SizeGate.too_small?(state) ->
        {state, []}

      state.modal != nil ->
        AppModal.handle_key(key_event, state)

      state.command_entry != nil ->
        {entry, effects} = CommandEntry.handle_key(state.command_entry, key_event, state)

        state
        |> Map.put(:command_entry, entry)
        |> Foglet.TUI.App.Effects.apply_effects(effects)

      CommandEntry.open_key?(key_event, state.current_screen) ->
        {%{state | command_entry: CommandEntry.open()}, []}

      true ->
        Routing.route_screen_update(
          state,
          Routing.screen_key(Routing.current_route(state)),
          {:key, key_event}
        )
    end
  end

  defp handle_presence({:online_presence, _event, _payload} = msg, %App{} = state) do
    Routing.route_screen_update(state, Routing.screen_key(Routing.current_route(state)), msg)
  end

  defp handle_notification({:notification, _user_id, kind, payload}, %App{} = state) do
    modal = %Foglet.TUI.Modal{type: :info, message: format_notification(kind, payload)}
    {%{state | modal: modal}, []}
  end

  defp handle_clock({:tui_clock, :minute_tick, %DateTime{} = now}, %App{} = state) do
    session_context = Map.put(state.session_context || %{}, :clock_now, now)
    {%{state | session_context: session_context}, []}
  end

  defp handle_clock(:main_menu_clock_tick, %App{} = state), do: {state, []}

  defp handle_tasks({:command_result, _inner} = msg, %App{} = state) do
    handle(AppTasks.unwrap(msg), state)
  end

  defp handle_tasks({:screen_task_result, _key, _op, _result} = msg, %App{} = state),
    do: AppTasks.handle(msg, state)

  defp handle_tasks({:task_error, _op, _reason} = msg, %App{} = state),
    do: AppTasks.handle(msg, state)

  defp format_notification(:dm, %{body: body}), do: "New message: #{body}"

  defp format_notification(:mention, %{thread_title: title}),
    do: "You were mentioned in: #{title}"

  defp format_notification(kind, _payload), do: "Notification: #{kind}"
end
