defmodule Foglet.TUI.App.Effects do
  @moduledoc """
  App-shell effect interpreter for `%Foglet.TUI.Effect{}` values.

  This module owns generic runtime effect interpretation for `%Foglet.TUI.App{}`
  state while leaving `Foglet.TUI.App` as the Raxol callback integration point.
  Durable domain behavior stays in screen-requested tasks and domain contexts;
  effects only route, schedule, publish, notify, and return runtime commands.
  """

  require Logger

  alias Foglet.Sessions.ActivityPresence
  alias Foglet.TUI.App
  alias Foglet.TUI.App.Modal, as: AppModal
  alias Foglet.TUI.App.Routing
  alias Foglet.TUI.Effect
  alias Foglet.TUI.Guest
  alias Raxol.Core.Runtime.Command

  @doc "Interprets one runtime effect against the App shell."
  @spec apply_effect(App.t(), Effect.t()) :: {App.t(), [Command.t()]}
  def apply_effect(%App{} = state, %Effect{
        type: :navigate,
        payload: %{screen: screen, params: params}
      }) do
    params = params || %{}

    if guest_route_denied?(state, screen, params) do
      {%{state | modal: Guest.denial_modal(denial_kind_for_screen(screen))}, []}
    else
      navigate(state, screen, params)
    end
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
        payload: :enter_guest
      }) do
    App.update(:enter_guest, state)
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
    case pubsub_module().broadcast(FogletBbs.PubSub, topic, message) do
      :ok ->
        :ok

      {:error, reason} ->
        # Privacy-safe (FOG-675): log only the broadcast topic plus a
        # low-cardinality kind atom derived from the payload's tag. The raw
        # `message` (which may carry chat content, screen state, or
        # session-specific values) is never written to logs.
        Logger.warning(
          "TUI.App.Effects publish broadcast failed: topic=#{inspect(topic)} " <>
            "message_kind=#{inspect(publish_message_kind(message))} reason=#{inspect(reason)}"
        )
    end

    {state, []}
  end

  def apply_effect(%App{} = state, %Effect{
        type: :door,
        payload: %{action: :launch, manifest: manifest} = payload
      }) do
    if Guest.guest?(state) do
      {%{state | modal: Guest.denial_modal(:door)}, []}
    else
      launch_door(state, manifest, payload)
    end
  end

  def apply_effect(%App{} = state, %Effect{type: :quit}) do
    {state, [Command.quit()]}
  end

  def apply_effect(%App{} = state, %Effect{
        type: :task,
        payload: %{op: op, screen_key: screen_key, fun: fun}
      }) do
    user_id = current_user_id(state)

    task =
      Foglet.TUI.Command.task(op, fn ->
        try do
          {:screen_task_result, screen_key, op, {:ok, fun.()}}
        rescue
          e ->
            log_task_failure(screen_key, op, :exception, e, user_id)
            {:screen_task_result, screen_key, op, {:error, {:task_failed, :exception}}}
        catch
          kind, value ->
            log_task_failure(screen_key, op, kind, value, user_id)

            {:screen_task_result, screen_key, op,
             {:error, {:task_failed, safe_failure_kind(kind)}}}
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

  defp log_task_failure(screen_key, op, failure_kind, reason, user_id) do
    Logger.error(
      [
        "tui_screen_task_failed",
        "screen=#{safe_value(screen_key)}",
        "operation=#{safe_value(op)}",
        "failure_kind=#{safe_value(safe_failure_kind(failure_kind))}",
        "reason_class=#{safe_value(reason_class(reason))}",
        "user_id=#{safe_value(user_id)}",
        test_email_delivery_mode_fragment(op)
      ]
      |> Enum.reject(&(&1 in [nil, ""]))
      |> Enum.join(" ")
    )
  end

  defp reason_class(%module{}) when is_atom(module), do: module
  defp reason_class(value) when is_atom(value), do: value
  defp reason_class(value) when is_tuple(value) and tuple_size(value) > 0, do: elem(value, 0)
  defp reason_class(value) when is_binary(value), do: :binary
  defp reason_class(value) when is_integer(value), do: :integer
  defp reason_class(_value), do: :unknown

  defp safe_failure_kind(:error), do: :exception
  defp safe_failure_kind(kind) when kind in [:exception, :throw, :exit], do: kind
  defp safe_failure_kind(kind) when is_atom(kind), do: kind
  defp safe_failure_kind(_kind), do: :unknown

  defp current_user_id(%App{current_user: %{id: id}}), do: id
  defp current_user_id(_state), do: nil

  defp test_email_delivery_mode_fragment(:sysop_send_test_email),
    do: "delivery_mode=#{safe_value(Foglet.Config.delivery_mode())}"

  defp test_email_delivery_mode_fragment(_op), do: nil

  defp safe_value(nil), do: "nil"
  defp safe_value(value) when is_atom(value), do: Atom.to_string(value)
  defp safe_value(value) when is_binary(value), do: value
  defp safe_value(value), do: inspect(value)

  # Low-cardinality kind atom for failure logs. Never returns the raw payload.
  defp publish_message_kind(message) when is_tuple(message) and tuple_size(message) > 0 do
    case elem(message, 0) do
      tag when is_atom(tag) -> tag
      _ -> :unknown
    end
  end

  defp publish_message_kind(message) when is_atom(message), do: message
  defp publish_message_kind(_message), do: :unknown

  # Test seam (FOG-675): swappable via Application env so a stub broadcast
  # implementation can return `{:error, _}` and exercise the warning path.
  defp pubsub_module do
    Application.get_env(:foglet_bbs, :pubsub_module, Phoenix.PubSub)
  end

  defp navigate(%App{} = state, screen, params) do
    state =
      state
      |> Map.put(:current_screen, screen)
      |> Map.put(:route_params, params)
      |> Map.put(:modal, nil)
      |> Routing.init_route_screen_state(screen, params)

    track_route_activity(state, screen, params)
    Routing.dispatch_route_entry(state, screen, params)
  end

  defp track_route_activity(%App{} = state, screen, params) do
    user_id = state.current_user && state.current_user.id

    case route_activity(screen, params) do
      {:track, activity} -> ActivityPresence.track(user_id, activity)
      :clear -> ActivityPresence.clear(user_id)
    end
  end

  defp route_activity(:board_list, _params), do: {:track, :board_list}

  defp route_activity(:thread_list, params) do
    case board_from_params(params) do
      nil -> :clear
      board -> {:track, {:browsing_board, board}}
    end
  end

  defp route_activity(:post_reader, params) do
    case board_from_params(params) do
      nil -> :clear
      board -> {:track, {:reading_board, board}}
    end
  end

  defp route_activity(:post_composer, params) do
    case {Map.get(params, :origin) || Map.get(params, "origin"), board_from_params(params)} do
      {origin, board} when origin in [:post_reader, "post_reader"] and is_map(board) ->
        {:track, {:reading_board, board}}

      _other ->
        :clear
    end
  end

  defp route_activity(screen, _params) when screen in [:main_menu, :account, :door_list],
    do: :clear

  defp route_activity(_screen, _params), do: :clear

  defp board_from_params(params) do
    case Map.get(params, :board) || Map.get(params, "board") do
      board when is_map(board) -> board
      _other -> board_from_id(params)
    end
  end

  defp board_from_id(params) do
    case Map.get(params, :board_id) || Map.get(params, "board_id") do
      board_id when is_binary(board_id) -> %{id: board_id}
      _other -> nil
    end
  end

  defp modal_submit_target?(%App{} = state, screen_key) do
    module = Routing.screen_module_for(state, screen_key)
    Code.ensure_loaded?(module) and function_exported?(module, :update, 3)
  end

  defp guest_route_denied?(%App{} = state, screen, params) do
    Guest.guest?(state) and
      (screen in [:new_thread, :post_composer, :account, :moderation, :sysop] or
         private_board_route_params?(screen, params))
  end

  defp private_board_route_params?(screen, params)
       when screen in [:thread_list, :post_reader] and is_map(params) do
    params
    |> known_content_param_maps()
    |> Enum.any?(&members_only_board_reference?/1)
  end

  defp private_board_route_params?(_screen, _params), do: false

  defp known_content_param_maps(params) do
    [
      params,
      Map.get(params, :board),
      Map.get(params, "board"),
      Map.get(params, :thread),
      Map.get(params, "thread"),
      Map.get(params, :post),
      Map.get(params, "post")
    ]
    |> Enum.filter(&is_map/1)
  end

  defp members_only_board_reference?(%{readable_by: :members}), do: true
  defp members_only_board_reference?(%{"readable_by" => "members"}), do: true
  defp members_only_board_reference?(%{"readable_by" => :members}), do: true

  defp members_only_board_reference?(%{} = map) do
    [Map.get(map, :board), Map.get(map, "board")]
    |> Enum.filter(&is_map/1)
    |> Enum.any?(&members_only_board_reference?/1)
  end

  defp denial_kind_for_screen(:door_list), do: :door
  defp denial_kind_for_screen(:account), do: :account
  defp denial_kind_for_screen(:thread_list), do: :board
  defp denial_kind_for_screen(:post_reader), do: :board
  defp denial_kind_for_screen(_screen), do: :post

  defp launch_door(%App{} = state, manifest, payload) do
    session = %{
      user_id: state.current_user && state.current_user.id,
      handle: state.current_user && state.current_user.handle,
      role: state.current_user && state.current_user.role,
      session_id: session_identifier(state.session_pid)
    }

    output = Map.get(payload, :output) || fn _iodata -> :ok end

    case door_handler_pid(state) do
      pid when is_pid(pid) ->
        Process.send_after(
          pid,
          {:foglet_launch_door, manifest, session, state.terminal_size},
          100
        )

        {state, []}

      _other ->
        start_detached_runner(state, manifest, session, output)
    end
  end

  defp start_detached_runner(state, manifest, session, output) do
    case Foglet.Doors.Supervisor.start_runner(
           manifest: manifest,
           session: session,
           terminal_size: state.terminal_size,
           output: output,
           owner: nil
         ) do
      {:ok, _pid} ->
        {state, []}

      {:error, reason} ->
        modal = %Foglet.TUI.Modal{
          type: :error,
          message: "Door launch failed: #{inspect(reason)}"
        }

        {%{state | modal: modal}, []}
    end
  end

  defp door_handler_pid(%App{session_context: session_context}) when is_map(session_context),
    do: Map.get(session_context, :door_handler_pid)

  defp door_handler_pid(_state), do: nil

  defp session_identifier(pid) when is_pid(pid), do: inspect(pid)
  defp session_identifier(_pid), do: nil

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
