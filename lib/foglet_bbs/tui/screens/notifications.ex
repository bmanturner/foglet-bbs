defmodule Foglet.TUI.Screens.Notifications do
  @moduledoc """
  Routed notifications inbox for durable user notifications.
  """

  @behaviour Foglet.TUI.Screen

  import Raxol.Core.Renderer.View

  alias Foglet.TerminalText
  alias Foglet.TimeAgo
  alias Foglet.TUI.{Context, Effect}
  alias Foglet.TUI.Screens.Notifications.State
  alias Foglet.TUI.TextWidth
  alias Foglet.TUI.Theme
  alias Foglet.TUI.Widgets.Chrome.ScreenFrame
  alias Foglet.TUI.Widgets.Display.KvGrid

  @default_terminal_size {80, 24}
  @recent_limit 50
  @wide_breakpoint 100
  @medium_breakpoint 80
  @list_title "Notifications"

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
      normalize_state(local_state)
      |> State.ensure_selected_visible(visible_row_limit(context))

    frame_state = frame_state(context)
    theme = Theme.from_state(frame_state)

    ScreenFrame.render(
      frame_state,
      %{breadcrumb_parts: Foglet.AppName.breadcrumb(["Inbox"])},
      content_body(state, context, theme),
      action_groups(state)
    )
  end

  defp content_body(%State{} = state, %Context{} = context, theme) do
    column style: %{gap: 1, padding: 1} do
      [
        header_block(state, context, theme),
        body_block(state, context, theme)
      ]
    end
  end

  defp header_block(%State{} = state, %Context{} = context, theme) do
    unread = State.unread_count(state)
    count_label = if unread == 1, do: "1 unread", else: "#{unread} unread"

    helper =
      cond do
        state.status == :error ->
          state.last_error || "Unable to load notifications."

        state.rows == [] ->
          "All caught up. New notifications will appear here."

        wide_layout?(context) ->
          "Inbox • #{count_label} • list on the left, selected detail on the right"

        medium_layout?(context) ->
          "Inbox • #{count_label} • selected detail appears below the list"

        true ->
          "Inbox • #{count_label}"
      end

    column style: %{gap: 0} do
      [
        text("Inbox", fg: theme.title.fg, style: theme.title[:style]),
        text(helper, fg: header_helper_fg(state, theme))
      ]
    end
  end

  defp body_block(%State{} = state, %Context{} = context, theme) do
    cond do
      wide_layout?(context) ->
        split_pane(
          direction: :horizontal,
          ratio: {3, 2},
          min_size: 28,
          divider_char: " ",
          children: [
            list_panel(state, context, theme, wide_list_width(context)),
            detail_panel(state, context, theme, wide_detail_width(context))
          ]
        )

      medium_layout?(context) ->
        column style: %{gap: 1} do
          [
            list_panel(state, context, theme, narrow_list_width(context)),
            detail_panel(state, context, theme, narrow_list_width(context), title: "Selected")
          ]
        end

      true ->
        list_panel(state, context, theme, narrow_list_width(context))
    end
  end

  defp list_panel(%State{} = state, %Context{} = context, theme, width) do
    %{
      type: :panel,
      attrs: %{
        title: @list_title,
        title_attrs: %{fg: theme.title.fg},
        border: :single,
        border_fg: theme.border.fg,
        width: 9999,
        height: 9999
      },
      children: [
        column style: %{gap: 0} do
          list_rows(state, context, theme, width)
        end
      ]
    }
  end

  defp detail_panel(%State{} = state, _context, theme, width, opts \\ []) do
    title = Keyword.get(opts, :title, "Selected")

    %{
      type: :panel,
      attrs: %{
        title: title,
        title_attrs: %{fg: theme.title.fg},
        border: :single,
        border_fg: theme.border.fg,
        width: 9999,
        height: 9999
      },
      children: [
        column style: %{gap: 0} do
          detail_rows(state, theme, width)
        end
      ]
    }
  end

  defp list_rows(%State{rows: []} = state, _context, theme, _width) do
    status_line =
      case state.status do
        :loading -> "Loading notifications…"
        :error -> state.last_error || "Unable to load notifications."
        _ -> "All caught up."
      end

    [text(status_line, fg: empty_fg(state, theme))]
  end

  defp list_rows(%State{} = state, %Context{} = context, theme, width) do
    state
    |> State.visible_rows(visible_row_limit(context))
    |> Enum.flat_map(fn {notification, index} ->
      selected? = index == state.selected_index
      render_notification_row(notification, width, selected?, theme)
    end)
  end

  defp detail_rows(%State{} = state, theme, width) do
    case State.selected_row(state) do
      nil ->
        [text("No selection", fg: theme.dim.fg)]

      notification ->
        details = selected_details(notification)

        summary =
          notification
          |> format_summary()
          |> maybe_expand_summary(width)

        [
          text(kind_title(notification),
            fg: detail_title_fg(notification, theme),
            style: [:bold]
          ),
          text("", fg: theme.dim.fg),
          column style: %{gap: 0} do
            KvGrid.render(details,
              theme: theme,
              width: max(width - 4, 24),
              label_width: 12,
              gap: 2
            )
          end,
          text("", fg: theme.dim.fg),
          text("Summary", fg: theme.title.fg),
          text(summary, fg: detail_summary_fg(notification, theme))
        ]
    end
  end

  defp render_notification_row(notification, width, selected?, theme) do
    marker = if selected?, do: ">", else: " "
    unread_marker = if unread?(notification), do: "●", else: "·"
    kind = "[#{kind_badge(notification)}]"
    source = "from #{source_label(notification)}"
    time = relative_timestamp(notification)
    left = Enum.join([marker, unread_marker, kind, source], " ")
    row_width = max(width - 4, 24)
    gap = max(row_width - TextWidth.display_width(left) - TextWidth.display_width(time), 1)
    padding = TextWidth.pad_trailing("", gap)
    summary_indent = if selected?, do: "    ", else: "      "

    summary =
      clip_summary(
        format_summary(notification),
        row_width - TextWidth.display_width(summary_indent)
      )

    [
      row [] do
        [
          text(left, fg: row_meta_fg(notification, selected?, theme)),
          text(padding <> time, fg: theme.dim.fg)
        ]
      end,
      text(summary_indent <> summary, fg: row_summary_fg(notification, selected?, theme))
    ]
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

  defp visible_row_limit(%Context{terminal_size: {_w, h}} = context) when is_integer(h) do
    reserved = if wide_layout?(context), do: 12, else: 10
    max(div(max(h - reserved, 4), 2), 1)
  end

  defp visible_row_limit(%Context{}), do: 6

  defp wide_layout?(%Context{terminal_size: {w, _h}}) when is_integer(w),
    do: w >= @wide_breakpoint

  defp wide_layout?(%Context{}), do: false

  defp medium_layout?(%Context{terminal_size: {w, _h}}) when is_integer(w),
    do: w >= @medium_breakpoint

  defp medium_layout?(%Context{}), do: false

  defp narrow_list_width(%Context{terminal_size: {w, _h}}) when is_integer(w), do: max(w - 12, 24)
  defp narrow_list_width(%Context{}), do: 68

  defp wide_list_width(%Context{terminal_size: {w, _h}}) when is_integer(w) do
    available = max(w - 12, 40)
    max(div(available * 3, 5) - 4, 30)
  end

  defp wide_list_width(%Context{}), do: 54

  defp wide_detail_width(%Context{terminal_size: {w, _h}}) when is_integer(w) do
    available = max(w - 12, 40)
    max(available - wide_list_width(%Context{terminal_size: {w, 0}}) - 4, 28)
  end

  defp wide_detail_width(%Context{}), do: 34

  defp selected_details(notification) do
    [
      %{label: "Kind", value: kind_title(notification)},
      %{label: "Source", value: "from " <> source_label(notification)},
      %{
        label: "Read state",
        value: read_state_label(notification),
        badge: read_state_badge(notification)
      },
      %{label: "When", value: absolute_timestamp(notification)}
    ]
  end

  defp read_state_badge(notification) do
    if unread?(notification) do
      %{state: :pending, label: "unread", role: :accent}
    else
      %{state: :healthy, label: "read", role: :success}
    end
  end

  defp read_state_label(notification),
    do: if(unread?(notification), do: "Needs review", else: "Already read")

  defp header_helper_fg(%State{status: :error}, theme), do: theme.error.fg
  defp header_helper_fg(%State{rows: []}, theme), do: theme.primary.fg
  defp header_helper_fg(_state, theme), do: theme.dim.fg

  defp empty_fg(%State{status: :error}, theme), do: theme.error.fg
  defp empty_fg(%State{status: :loading}, theme), do: theme.dim.fg
  defp empty_fg(_state, theme), do: theme.primary.fg

  defp row_meta_fg(notification, selected?, theme) do
    cond do
      selected? and unread?(notification) -> theme.accent.fg
      selected? -> theme.title.fg
      unread?(notification) -> theme.primary.fg
      true -> theme.dim.fg
    end
  end

  defp row_summary_fg(notification, selected?, theme) do
    cond do
      selected? and unread?(notification) -> theme.accent.fg
      selected? -> theme.primary.fg
      unread?(notification) -> theme.primary.fg
      true -> theme.dim.fg
    end
  end

  defp detail_title_fg(notification, theme) do
    if unread?(notification), do: theme.accent.fg, else: theme.title.fg
  end

  defp detail_summary_fg(notification, theme) do
    if unread?(notification), do: theme.primary.fg, else: theme.dim.fg
  end

  defp kind_badge(notification) do
    notification
    |> notification_kind()
    |> case do
      :mention -> "mention"
      :reply -> "reply"
      :dm -> "dm"
      :mod_action -> "mod"
      :thread_update -> "thread"
      kind when is_binary(kind) -> String.downcase(kind)
      _ -> "notice"
    end
  end

  defp kind_title(notification) do
    notification
    |> notification_kind()
    |> case do
      :mention -> "Mention"
      :reply -> "Reply"
      :dm -> "Direct message"
      :mod_action -> "Moderator action"
      :thread_update -> "Thread update"
      kind when is_binary(kind) and kind != "" -> kind
      _ -> "Notification"
    end
  end

  defp notification_kind(notification),
    do: Map.get(notification, :kind) || Map.get(notification, "kind")

  defp source_label(notification) do
    notification
    |> Map.get(:actor, %{})
    |> Map.get(:handle, "system")
    |> TerminalText.sanitize_plain_text()
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
    |> case do
      "" -> "system"
      handle -> "@" <> TextWidth.slice_to_width(handle, 20)
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
    kind = notification_kind(notification)

    payload_summary(payload, kind) || kind_title(notification)
  end

  defp payload_summary(payload, :mention), do: payload["snippet"]
  defp payload_summary(payload, :reply), do: payload["snippet"]
  defp payload_summary(payload, :dm), do: payload["preview"]
  defp payload_summary(payload, :mod_action), do: payload["reason"]

  defp payload_summary(payload, _kind),
    do: payload["snippet"] || payload["preview"] || payload["reason"]

  defp clip_summary(summary, width), do: TextWidth.slice_to_width(summary, max(width, 8))

  defp maybe_expand_summary(summary, width) do
    max_width = max(width - 4, 20)
    TextWidth.slice_to_width(summary, max_width)
  end

  defp unread?(notification),
    do: is_nil(Map.get(notification, :read_at) || Map.get(notification, "read_at"))

  defp relative_timestamp(notification) do
    case notification_datetime(notification) do
      %DateTime{} = dt -> TimeAgo.format(dt) <> " ago"
      _ -> "—"
    end
  end

  defp absolute_timestamp(notification) do
    case notification_datetime(notification) do
      %DateTime{} = dt -> Calendar.strftime(dt, "%Y-%m-%d %H:%M:%SZ")
      _ -> "—"
    end
  end

  defp notification_datetime(notification) do
    case Map.get(notification, :inserted_at) || Map.get(notification, "inserted_at") do
      %DateTime{} = dt -> dt
      %NaiveDateTime{} = naive -> DateTime.from_naive!(naive, "Etc/UTC")
      _ -> nil
    end
  end
end
