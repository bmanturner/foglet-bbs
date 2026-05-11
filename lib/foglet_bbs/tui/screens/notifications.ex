defmodule Foglet.TUI.Screens.Notifications do
  @moduledoc """
  Routed notifications inbox for durable user notifications.
  """

  @behaviour Foglet.TUI.Screen

  alias Foglet.TerminalText
  alias Foglet.TUI.{Context, Effect}
  alias Foglet.TUI.Screens.Notifications.State
  alias Foglet.TUI.TextWidth
  alias Foglet.TUI.Theme
  alias Foglet.TUI.Widgets.Chrome.ScreenFrame
  alias Foglet.TUI.Widgets.Display.Handle

  import Raxol.Core.Renderer.View

  @default_terminal_size {80, 24}
  @row_summary_limit 40
  @actor_handle_limit 14
  @recent_limit 50

  @impl true
  def init(%Context{}), do: State.new()

  @impl true
  def subscriptions(_local_state, %Context{current_user: %{id: user_id}}) do
    [Foglet.PubSub.notifications_topic(user_id)]
  end

  def subscriptions(_local_state, %Context{}), do: []

  @impl true
  def update(:on_route_enter, local_state, %Context{} = context) do
    state = normalize_state(local_state)
    {%{state | status: :loading}, [load_notifications_effect(context)]}
  end

  def update({:task_result, :load_notifications, {:ok, rows}}, local_state, %Context{})
      when is_list(rows) do
    {State.from_rows(normalize_state(local_state), rows), []}
  end

  def update({:task_result, :load_notifications, {:error, reason}}, local_state, %Context{}) do
    {State.set_error(normalize_state(local_state), reason, "Unable to load notifications"), []}
  end

  def update(
        {:task_result, :mark_notification_read, {:ok, _notification}},
        local_state,
        %Context{} = context
      ) do
    state = normalize_state(local_state)
    {%{state | status: :loading}, [load_notifications_effect(context)]}
  end

  def update({:task_result, :mark_notification_read, {:error, reason}}, local_state, %Context{}) do
    {State.set_error(normalize_state(local_state), reason, "Unable to mark notification read"),
     []}
  end

  def update(
        {:task_result, :mark_all_notifications_read, {:ok, _count}},
        local_state,
        %Context{} = context
      ) do
    state = normalize_state(local_state)
    {%{state | status: :loading}, [load_notifications_effect(context)]}
  end

  def update(
        {:task_result, :mark_all_notifications_read, {:error, reason}},
        local_state,
        %Context{}
      ) do
    {State.set_error(
       normalize_state(local_state),
       reason,
       "Unable to mark all notifications read"
     ), []}
  end

  def update({:notifications, _event, _payload}, local_state, %Context{} = context) do
    state = normalize_state(local_state)
    {%{state | status: :loading}, [load_notifications_effect(context)]}
  end

  def update({:key, %{key: key}}, local_state, %Context{} = context) when key in [:up, :down] do
    state = normalize_state(local_state)
    delta = if key == :up, do: -1, else: 1
    {State.select_delta(state, delta, visible_row_limit(context)), []}
  end

  def update({:key, %{key: :char, char: c}}, local_state, %Context{} = context)
      when c in ["j", "k"] do
    state = normalize_state(local_state)
    delta = if c == "k", do: -1, else: 1
    {State.select_delta(state, delta, visible_row_limit(context)), []}
  end

  def update({:key, %{key: :char, char: c}}, local_state, %Context{} = context)
      when c in ["r", "R"] do
    state = normalize_state(local_state)

    case State.selected_row(state) do
      %{read_at: nil} = notification ->
        {%{state | status: :marking_read}, [mark_read_effect(context, notification)]}

      %{"read_at" => nil} = notification ->
        {%{state | status: :marking_read}, [mark_read_effect(context, notification)]}

      _other ->
        {state, []}
    end
  end

  def update({:key, %{key: :char, char: c}}, local_state, %Context{} = context)
      when c in ["a", "A"] do
    state = normalize_state(local_state)

    if State.unread_count(state) > 0 do
      {%{state | status: :marking_all_read}, [mark_all_read_effect(context)]}
    else
      {state, []}
    end
  end

  def update({:key, %{key: :char, char: c}}, local_state, %Context{})
      when c in ["q", "Q", "b", "B"] do
    {normalize_state(local_state), [Effect.navigate(:main_menu)]}
  end

  def update({:key, %{key: :escape}}, local_state, %Context{}) do
    {normalize_state(local_state), [Effect.navigate(:main_menu)]}
  end

  def update(_message, local_state, %Context{}), do: {normalize_state(local_state), []}

  @impl true
  def render(local_state, %Context{} = context) do
    state =
      normalize_state(local_state) |> State.ensure_selected_visible(visible_row_limit(context))

    theme = Theme.from_state(frame_state(context))

    ScreenFrame.render(
      frame_state(context),
      %{breadcrumb_parts: Foglet.AppName.breadcrumb(["Inbox"])},
      content_body(state, context, theme),
      action_groups(state)
    )
  end

  defp content_body(%State{} = state, %Context{} = context, theme) do
    column style: %{gap: 0, padding: 1} do
      header_rows(state, theme) ++ body_rows(state, context, theme)
    end
  end

  defp header_rows(%State{status: :error, last_error: error}, theme) do
    [
      text(error || "Unable to load notifications.", fg: theme.error.fg),
      text("", fg: theme.dim.fg)
    ]
  end

  defp header_rows(%State{status: status}, theme)
       when status in [:loading, :marking_read, :marking_all_read] do
    [text("Loading notifications…", fg: theme.dim.fg), text("", fg: theme.dim.fg)]
  end

  defp header_rows(%State{} = state, theme) do
    unread = State.unread_count(state)
    [text("Unread notifications: #{unread}", fg: theme.dim.fg), text("", fg: theme.dim.fg)]
  end

  defp body_rows(%State{rows: []}, _context, theme) do
    [text("No notifications yet.", fg: theme.primary.fg)]
  end

  defp body_rows(%State{} = state, %Context{} = context, theme) do
    row_width = row_width(context)

    state
    |> State.visible_rows(visible_row_limit(context))
    |> Enum.map(fn {notification, index} ->
      selected? = index == state.selected_index
      render_row(notification, row_width, selected?, theme)
    end)
  end

  defp render_row(notification, row_width, selected?, theme) do
    marker = if selected?, do: "> ", else: "  "
    unread_marker = if unread?(notification), do: "*", else: " "
    summary = format_summary(notification) |> clip_summary()
    actor = actor_handle(notification)
    left = marker <> unread_marker <> " @" <> actor

    padding =
      TextWidth.pad_trailing(
        "",
        max(row_width - TextWidth.display_width(left) - TextWidth.display_width(summary), 2)
      )

    row style: %{gap: 0} do
      [
        text(left, fg: actor_fg(notification, theme)),
        text(padding <> summary, fg: summary_fg(notification, selected?, theme))
      ]
    end
  end

  defp action_groups(%State{rows: []}) do
    [%{label: "Navigation", commands: [%{key: "Q", label: "Back", priority: 0}]}]
  end

  defp action_groups(%State{}) do
    [
      %{label: "Navigation", commands: [%{key: "Q", label: "Back", priority: 0}]},
      %{
        label: "Actions",
        commands: [
          %{key: "R", label: "Mark read", priority: 5},
          %{key: "A", label: "Mark all read", priority: 10},
          %{key: "↑/↓", label: "Select", priority: 20}
        ]
      }
    ]
  end

  defp load_notifications_effect(%Context{} = context) do
    notifications_mod = domain_module(context)

    Effect.task(:load_notifications, :notifications, fn ->
      notifications_mod.list_recent(context.current_user, @recent_limit)
    end)
  end

  defp mark_read_effect(%Context{} = context, notification) do
    notifications_mod = domain_module(context)
    notification_id = Map.get(notification, :id) || Map.get(notification, "id")

    Effect.task(:mark_notification_read, :notifications, fn ->
      notifications_mod.mark_read(context.current_user, notification_id)
    end)
  end

  defp mark_all_read_effect(%Context{} = context) do
    notifications_mod = domain_module(context)

    Effect.task(:mark_all_notifications_read, :notifications, fn ->
      notifications_mod.mark_all_read(context.current_user)
    end)
  end

  defp domain_module(%Context{domain: domain}) when is_map(domain) do
    Map.get(domain, :notifications, Foglet.Notifications)
  end

  defp domain_module(%Context{}), do: Foglet.Notifications

  defp normalize_state(%State{} = state), do: state
  defp normalize_state(_other), do: State.new()

  defp frame_state(%Context{} = context) do
    %{
      current_screen: :notifications,
      current_user: context.current_user,
      session_context: context.session_context,
      session_pid: context.session_pid,
      terminal_size: context.terminal_size || @default_terminal_size,
      route_params: context.route_params || %{},
      screen_state: %{}
    }
  end

  defp visible_row_limit(%Context{terminal_size: {_w, h}}) when is_integer(h), do: max(h - 8, 3)
  defp visible_row_limit(%Context{}), do: 10

  defp row_width(%Context{terminal_size: {w, _h}}) when is_integer(w), do: max(w - 8, 24)
  defp row_width(%Context{}), do: 72

  defp actor_handle(notification) do
    notification
    |> Map.get(:actor, %{})
    |> Map.get(:handle, "system")
    |> TerminalText.sanitize_plain_text()
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
    |> case do
      "" -> "system"
      handle -> TextWidth.slice_to_width(handle, @actor_handle_limit)
    end
  end

  defp format_summary(notification) do
    notification
    |> summary_value()
    |> TerminalText.sanitize_plain_text()
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
    |> case do
      "" -> "Notification"
      summary -> summary
    end
  end

  defp summary_value(notification) do
    payload = Map.get(notification, :payload) || Map.get(notification, "payload") || %{}
    kind = Map.get(notification, :kind) || Map.get(notification, "kind")

    payload_summary(payload, kind) || kind_summary(kind)
  end

  defp payload_summary(payload, :mention), do: payload["snippet"]
  defp payload_summary(payload, :reply), do: payload["snippet"]
  defp payload_summary(payload, :dm), do: payload["preview"]
  defp payload_summary(payload, :mod_action), do: payload["reason"]

  defp payload_summary(payload, _kind),
    do: payload["snippet"] || payload["preview"] || payload["reason"]

  defp kind_summary(:mention), do: "Mention"
  defp kind_summary(:reply), do: "Reply"
  defp kind_summary(:dm), do: "Direct message"
  defp kind_summary(:mod_action), do: "Moderator action"
  defp kind_summary(:thread_update), do: "Thread update"
  defp kind_summary(kind) when is_binary(kind), do: kind
  defp kind_summary(_kind), do: "Notification"

  defp clip_summary(summary), do: TextWidth.slice_to_width(summary, @row_summary_limit)

  defp unread?(notification),
    do: is_nil(Map.get(notification, :read_at) || Map.get(notification, "read_at"))

  defp actor_fg(notification, theme) do
    Handle.color_for(Map.get(notification, :actor) || %{}, theme)
  end

  defp summary_fg(notification, selected?, theme) do
    cond do
      unread?(notification) and selected? -> theme.accent.fg
      unread?(notification) -> theme.primary.fg
      true -> theme.dim.fg
    end
  end
end
