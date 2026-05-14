defmodule Foglet.TUI.Screens.BBSMail do
  @moduledoc """
  Terminal-native BBS Mail hub, compose, and two-party conversation reader.
  """

  @behaviour Foglet.TUI.Screen

  import Raxol.Core.Renderer.View

  alias Foglet.{Accounts, DMs, Moderation, TimeAgo}
  alias Foglet.DMs.Message
  alias Foglet.TUI.{Context, Effect, KeyBinding, Theme}
  alias Foglet.TUI.Widgets.Chrome.ScreenFrame
  alias Foglet.TUI.Widgets.Post.MarkdownBody

  @default_terminal_size {80, 24}
  @live_refresh_ms 2_000

  defmodule State do
    @moduledoc false
    defstruct mode: :inbox,
              status: :idle,
              conversations: [],
              selected_index: 0,
              participant: nil,
              messages: [],
              body: "",
              recipient: "",
              compose_focus: :recipient,
              error: nil,
              info: nil,
              scroll: 0,
              pending_delete_id: nil
  end

  @impl true
  def init(%Context{} = context) do
    params = context.route_params || %{}

    %State{}
    |> apply_route_params(params)
  end

  @impl true
  def subscriptions(_state, %Context{current_user: %{id: id}}),
    do: %{
      topics: [Foglet.PubSub.notifications_topic(id)],
      intervals: [{@live_refresh_ms, :refresh_mail}]
    }

  def subscriptions(_state, _context), do: []

  @impl true
  def update(:on_route_enter, state, %Context{} = context) do
    state = normalize(state, context)

    case state.mode do
      :conversation -> load_conversation(state, context)
      _ -> load_conversations(state, context)
    end
  end

  def update({:task_result, :load_mail, result}, state, _context) do
    case Effect.unwrap_task_result(result) do
      {:ok, rows} -> {%{normalize(state) | status: :loaded, conversations: rows, error: nil}, []}
      {:error, reason} -> task_error(state, reason)
    end
  end

  def update({:task_result, :load_conversation, result}, state, _context) do
    case Effect.unwrap_task_result(result) do
      {:ok, messages} ->
        loaded = %{normalize(state) | status: :loaded, messages: messages, error: nil}
        loaded = if state.info == "Message sent.", do: scroll_to_latest(loaded), else: loaded
        {loaded, []}

      {:error, reason} ->
        task_error(state, reason)
    end
  end

  def update({:task_result, :send_mail, result}, state, context) do
    case Effect.unwrap_task_result(result) do
      {:ok, %Message{} = message} ->
        participant =
          if message.sender_id == context.current_user.id,
            do: message.recipient,
            else: message.sender

        new_state = %{
          normalize(state)
          | mode: :conversation,
            participant: participant,
            body: "",
            recipient: "",
            info: "Message sent."
        }

        load_conversation(new_state, context)

      {:error, reason} ->
        task_error(state, reason)
    end
  end

  def update({:task_result, :delete_mail, result}, state, context) do
    case Effect.unwrap_task_result(result) do
      {:ok, _message} ->
        state = %{normalize(state) | pending_delete_id: nil, info: "Hidden from your view."}

        if state.mode == :conversation,
          do: load_conversation(state, context),
          else: load_conversations(state, context)

      {:error, reason} ->
        task_error(state, reason)
    end
  end

  def update({:task_result, :report_mail, result}, state, _context) do
    case Effect.unwrap_task_result(result) do
      {:ok, _report} -> {%{normalize(state) | info: "Report submitted.", error: nil}, []}
      {:error, reason} -> task_error(state, reason)
    end
  end

  def update({:notifications, :created, %{kind: :dm}}, state, context),
    do: refresh_for_dm_event(state, context)

  def update({:notifications, :created, %{"kind" => "dm"}}, state, context),
    do: refresh_for_dm_event(state, context)

  def update({:notifications, _event, _payload}, state, _context), do: {normalize(state), []}

  def update(:refresh_mail, state, context), do: refresh_for_dm_event(state, context)

  def update({:key, %{key: key}}, state, %Context{} = context) when key in [:up, :down] do
    state = normalize(state, context)
    delta = if key == :up, do: -1, else: 1

    case state.mode do
      :conversation -> {%{state | scroll: max(state.scroll + delta, 0)}, []}
      _ -> {select_delta(state, delta), []}
    end
  end

  def update({:key, %{key: :char, char: c, ctrl: true}}, state, context) when c in ["s", "S"],
    do: send_current(normalize(state, context), context)

  def update({:key, %{key: :char, char: c}}, %State{mode: mode} = state, _context)
      when mode in [:compose, :reply] and is_binary(c) do
    {append_draft_char(state, c), []}
  end

  def update({:key, %{key: :backspace}}, %State{mode: mode} = state, _context)
      when mode in [:compose, :reply] do
    {delete_draft_char(state), []}
  end

  def update({:key, %{key: key}}, %State{mode: :compose} = state, _context)
      when key in [:tab, :enter] do
    {%{state | compose_focus: :body, error: nil}, []}
  end

  def update({:key, %{key: :char, char: c} = event}, state, context) when c in ["j", "k"] do
    state = normalize(state, context)
    delta = KeyBinding.vertical_delta(event) || 0

    case state.mode do
      :conversation -> {%{state | scroll: max(state.scroll + delta, 0)}, []}
      _ -> {select_delta(state, delta), []}
    end
  end

  def update({:key, %{key: :enter}}, state, context),
    do: open_selected(normalize(state, context), context)

  def update({:key, %{key: :char, char: c}}, state, context) when c in ["o", "O"],
    do: update({:key, %{key: :enter}}, state, context)

  def update({:key, %{key: :char, char: c}}, state, context) when c in ["i", "I"],
    do: load_conversations(%{normalize(state) | mode: :inbox, selected_index: 0}, context)

  def update({:key, %{key: :char, char: c}}, state, context) when c in ["s", "S"],
    do: load_conversations(%{normalize(state) | mode: :sent, selected_index: 0}, context)

  def update({:key, %{key: :char, char: c}}, state, _context) when c in ["c", "C"],
    do:
      {%{
         normalize(state)
         | mode: :compose,
           body: "",
           recipient: "",
           compose_focus: :recipient,
           error: nil
       }, []}

  def update({:key, %{key: :char, char: c}}, state, _context) when c in ["r", "R"] do
    state = normalize(state)

    if state.mode == :conversation and state.participant,
      do: {%{state | mode: :reply, body: "", error: nil}, []},
      else: {state, []}
  end

  def update({:key, %{key: :char, char: c}}, state, context) when c in ["d", "D"] do
    state = normalize(state, context)
    message = selected_message(state)
    if message, do: {%{state | pending_delete_id: message.id}, []}, else: {state, []}
  end

  def update({:key, %{key: :char, char: "!"}}, state, context),
    do: report_selected_message(normalize(state, context), context)

  def update({:key, %{key: :char, char: c}}, state, context) when c in ["y", "Y"] do
    state = normalize(state, context)

    if state.pending_delete_id,
      do:
        {%{state | status: :deleting},
         [
           Effect.task(:delete_mail, fn ->
             DMs.delete_from_my_view(context.current_user, state.pending_delete_id)
           end)
         ]},
      else: {state, []}
  end

  def update({:key, %{key: :char, char: c}}, state, _context) when c in ["n", "N"],
    do: {%{normalize(state) | pending_delete_id: nil}, []}

  def update({:key, %{key: :ctrl_s}}, state, context),
    do: send_current(normalize(state, context), context)

  def update({:input, value}, state, _context) when is_binary(value) do
    state = normalize(state)

    case state.mode do
      :compose -> {put_compose_input(state, value), []}
      :reply -> {%{state | body: value}, []}
      _ -> {state, []}
    end
  end

  def update({:recipient, value}, state, _context) when is_binary(value),
    do: {%{normalize(state) | recipient: value}, []}

  def update({:key, %{key: :char, char: c}}, state, _context) when c in ["q", "Q", "b", "B"] do
    state = normalize(state)

    case state.mode do
      :conversation -> {%{state | mode: :inbox, participant: nil, messages: []}, []}
      :compose -> {%{state | mode: :inbox}, []}
      :reply -> {%{state | mode: :conversation}, []}
      _ -> {state, [Effect.navigate(:main_menu)]}
    end
  end

  def update({:key, event}, state, _context) when is_map(event) do
    state = normalize(state)

    if KeyBinding.cancel?(event) do
      case state.mode do
        :conversation -> {%{state | mode: :inbox, participant: nil, messages: []}, []}
        :compose -> {%{state | mode: :inbox}, []}
        :reply -> {%{state | mode: :conversation}, []}
        _ -> {state, [Effect.navigate(:main_menu)]}
      end
    else
      {state, []}
    end
  end

  def update(_event, state, context), do: {normalize(state, context), []}

  @impl true
  def render(state, %Context{} = context) do
    state = normalize(state, context)
    theme = Theme.from_state(frame_state(context))
    {width, _height} = context.terminal_size || @default_terminal_size

    ScreenFrame.render(
      frame_state(context),
      %{breadcrumb_parts: Foglet.AppName.breadcrumb([title_for(state)])},
      body_for(state, theme, width),
      commands_for(state)
    )
  end

  defp body_for(%State{pending_delete_id: id} = state, theme, _width) when is_binary(id) do
    column style: %{gap: 1, padding: 1} do
      [
        text("Hide this message from your view? The other participant will keep their copy.",
          style: %{fg: theme.warning.fg}
        ),
        text("Y confirm   N cancel", style: %{fg: theme.dim.fg})
      ] ++ status_lines(state, theme)
    end
  end

  defp body_for(%State{mode: mode} = state, theme, width) when mode in [:inbox, :sent] do
    rows = Enum.with_index(state.conversations)
    unread = Enum.reduce(state.conversations, 0, &(&1.unread_count + &2))

    list =
      if rows == [],
        do: [text("No BBS Mail conversations yet.", style: %{fg: theme.dim.fg})],
        else:
          Enum.map(rows, fn {row, idx} ->
            conversation_row(row, idx == state.selected_index, theme, width)
          end)

    column style: %{gap: 1, padding: 1} do
      [
        text("Foglet > BBS Mail", style: %{fg: theme.dim.fg}),
        text("#{String.capitalize(to_string(mode))} - #{unread} unread",
          style: %{fg: theme.title.fg}
        )
      ] ++ status_lines(state, theme) ++ list
    end
  end

  defp body_for(%State{mode: mode} = state, theme, width) when mode in [:conversation, :reply] do
    participant = handle(state.participant)
    messages = state.messages |> Enum.drop(state.scroll) |> Enum.take(8)
    rendered = Enum.flat_map(messages, &message_card(&1, theme, max(width - 8, 20)))

    reply =
      if mode == :reply,
        do: [text("Reply draft: #{empty_marker(state.body)}", style: %{fg: theme.accent.fg})],
        else: []

    column style: %{gap: 1, padding: 1} do
      [text("Foglet > BBS Mail > @#{participant}", style: %{fg: theme.dim.fg})] ++
        notice_lines(theme) ++ status_lines(state, theme) ++ rendered ++ reply
    end
  end

  defp body_for(%State{mode: :compose} = state, theme, _width) do
    column style: %{gap: 1, padding: 1} do
      [
        text("Foglet > BBS Mail > Compose", style: %{fg: theme.dim.fg}),
        text("Recipient#{focus_marker(state, :recipient)}: #{empty_marker(state.recipient)}",
          style: %{fg: theme.primary.fg}
        ),
        text("Body#{focus_marker(state, :body)}: #{empty_marker(state.body)}",
          style: %{fg: theme.primary.fg}
        )
      ] ++ status_lines(state, theme)
    end
  end

  defp conversation_row(row, selected?, theme, width) do
    marker = if selected?, do: ">", else: " "
    unread = if row.unread_count > 0, do: "* [#{row.unread_count}]", else: "  "
    preview = String.slice(row.preview || "", 0, max(width - 35, 10))

    text(
      "#{marker} #{unread} @#{handle(row.participant)}  #{TimeAgo.format(row.last_at)}  #{preview}",
      style: %{fg: if(selected?, do: theme.accent.fg, else: theme.primary.fg)}
    )
  end

  defp message_card(message, theme, width) do
    who =
      if message.sender && message.sender_id == message.sender.id,
        do: handle(message.sender),
        else: handle(message.sender)

    [
      text("@#{who}  #{TimeAgo.format(message.inserted_at)}", style: %{fg: theme.accent.fg}),
      MarkdownBody.render(message.body || "", width, theme, wrap: true, max_lines: 4)
    ]
  end

  defp status_lines(state, theme) do
    [
      state.error && text("Error: #{state.error}", style: %{fg: theme.error.fg}),
      state.info && text(state.info, style: %{fg: theme.success.fg})
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp notice_lines(theme) do
    [
      text("Private to participants in normal UI. Not encrypted at rest;",
        style: %{fg: theme.warning.fg}
      ),
      text("may be visible to sysops/moderation/retention by policy.",
        style: %{fg: theme.warning.fg}
      )
    ]
  end

  defp commands_for(%State{pending_delete_id: id}) when is_binary(id),
    do: [
      %{key: "Y", label: "Hide from my view", priority: 5},
      %{key: "N", label: "Cancel", priority: 10}
    ]

  defp commands_for(%State{mode: mode}) when mode in [:inbox, :sent],
    do: [
      %{key: "Enter", label: "Open", priority: 5},
      %{key: "I/S", label: "Inbox/Sent", priority: 10},
      %{key: "C", label: "Compose", priority: 10},
      %{key: "B", label: "Back", priority: 20}
    ]

  defp commands_for(%State{mode: :conversation}),
    do: [
      %{key: "R", label: "Reply", priority: 5},
      %{key: "!", label: "Report", priority: 10},
      %{key: "D", label: "Hide from my view", priority: 10},
      %{key: "B", label: "Back", priority: 20}
    ]

  defp commands_for(%State{mode: :reply}),
    do: [
      %{key: "Ctrl+S", label: "Send reply", priority: 5},
      %{key: "B", label: "Back", priority: 20}
    ]

  defp commands_for(%State{mode: :compose}),
    do: [%{key: "Ctrl+S", label: "Send", priority: 5}, %{key: "B", label: "Back", priority: 20}]

  defp title_for(%State{mode: :compose}), do: "BBS Mail - Compose"
  defp title_for(%State{mode: :reply}), do: "BBS Mail - Reply"
  defp title_for(%State{mode: :conversation, participant: p}), do: "BBS Mail - @#{handle(p)}"
  defp title_for(_), do: "BBS Mail"

  defp frame_state(%Context{} = context) do
    %{
      current_screen: :bbs_mail,
      current_user: context.current_user,
      session_context: context.session_context,
      session_pid: context.session_pid,
      terminal_size: context.terminal_size || @default_terminal_size,
      route_params: context.route_params || %{},
      unread_count: context.unread_count,
      screen_state: %{}
    }
  end

  defp load_conversations(state, %{current_user: nil}),
    do: {%{state | status: :loaded, error: "Sign in to use BBS Mail."}, []}

  defp load_conversations(state, context),
    do:
      {%{state | status: :loading},
       [
         Effect.task(:load_mail, fn ->
           {:ok, DMs.list_conversations(context.current_user, state.mode)}
         end)
       ]}

  defp refresh_for_dm_event(state, context) do
    state = normalize(state, context)

    case state.mode do
      :conversation -> load_conversation(state, context)
      mode when mode in [:compose, :reply] -> {state, []}
      _ -> load_conversations(state, context)
    end
  end

  defp load_conversation(%State{participant: nil} = state, _context),
    do: {%{state | status: :loaded}, []}

  defp load_conversation(state, context) do
    participant = state.participant

    {%{state | status: :loading},
     [
       Effect.task(:load_conversation, fn ->
         _ = DMs.mark_conversation_read(context.current_user, participant)
         {:ok, DMs.list_conversation(context.current_user, participant)}
       end)
     ]}
  end

  defp open_selected(state, context) do
    case Enum.at(state.conversations, state.selected_index) do
      nil ->
        {state, []}

      row ->
        load_conversation(
          %{state | mode: :conversation, participant: row.participant, messages: [], scroll: 0},
          context
        )
    end
  end

  defp send_current(%State{mode: :compose} = state, context) do
    with recipient_handle when recipient_handle != "" <- String.trim(state.recipient),
         %{} = recipient <- Accounts.get_user_by_handle(recipient_handle),
         body when body != "" <- String.trim(state.body) do
      {%{state | status: :sending},
       [
         Effect.task(:send_mail, fn ->
           DMs.send_message(context.current_user, recipient, %{body: body})
         end)
       ]}
    else
      nil -> {%{state | error: "Recipient not found; draft preserved."}, []}
      "" -> {%{state | error: "Recipient and body are required; draft preserved."}, []}
    end
  end

  defp send_current(%State{mode: :reply, participant: recipient} = state, context)
       when not is_nil(recipient) do
    body = String.trim(state.body)

    if body == "",
      do: {%{state | error: "Body is required; draft preserved."}, []},
      else:
        {%{state | status: :sending},
         [
           Effect.task(:send_mail, fn ->
             DMs.send_message(context.current_user, recipient, %{body: body})
           end)
         ]}
  end

  defp send_current(state, _context), do: {state, []}

  defp report_selected_message(state, context) do
    case selected_message(state) do
      %Message{id: message_id} ->
        {%{state | status: :reporting, error: nil},
         [
           Effect.task(:report_mail, fn ->
             Moderation.create_report(context.current_user, %{
               target_kind: :dm,
               target_id: message_id,
               reason: "Reported from BBS Mail conversation"
             })
           end)
         ]}

      nil ->
        {state, []}
    end
  end

  defp selected_message(%State{mode: :conversation, messages: messages, scroll: scroll}),
    do: Enum.at(messages, scroll)

  defp selected_message(_), do: nil

  defp select_delta(state, delta),
    do: %{
      state
      | selected_index:
          clamp(state.selected_index + delta, 0, max(length(state.conversations) - 1, 0))
    }

  defp clamp(value, min, max), do: value |> Kernel.max(min) |> Kernel.min(max)

  defp trim_last_grapheme(""), do: ""

  defp trim_last_grapheme(value) when is_binary(value) do
    value
    |> String.graphemes()
    |> Enum.drop(-1)
    |> Enum.join()
  end

  defp append_draft_char(%State{mode: :compose, compose_focus: :recipient} = state, c),
    do: %{state | recipient: state.recipient <> c, error: nil}

  defp append_draft_char(%State{} = state, c), do: %{state | body: state.body <> c, error: nil}

  defp delete_draft_char(%State{mode: :compose, compose_focus: :recipient} = state),
    do: %{state | recipient: trim_last_grapheme(state.recipient), error: nil}

  defp delete_draft_char(%State{} = state),
    do: %{state | body: trim_last_grapheme(state.body), error: nil}

  defp put_compose_input(%State{compose_focus: :recipient} = state, value),
    do: %{state | recipient: value, error: nil}

  defp put_compose_input(%State{} = state, value), do: %{state | body: value, error: nil}

  defp focus_marker(%State{compose_focus: field}, field), do: " *"
  defp focus_marker(%State{}, _field), do: ""

  defp scroll_to_latest(%State{messages: messages} = state),
    do: %{state | scroll: max(length(messages) - 4, 0)}

  defp apply_route_params(state, %{"participant_id" => id}),
    do: %{state | mode: :conversation, participant: %{id: id}}

  defp apply_route_params(state, %{participant_id: id}),
    do: %{state | mode: :conversation, participant: %{id: id}}

  defp apply_route_params(state, %{mode: mode}) when mode in [:inbox, :sent, :compose],
    do: %{state | mode: mode}

  defp apply_route_params(state, _), do: state

  defp normalize(nil), do: %State{}
  defp normalize(%State{} = state), do: state
  defp normalize(state, _context), do: normalize(state)

  defp handle(%{handle: handle}) when is_binary(handle), do: handle
  defp handle(%{id: id}) when is_binary(id), do: String.slice(id, 0, 8)
  defp handle(nil), do: "unknown"
  defp empty_marker(""), do: "<empty>"
  defp empty_marker(value), do: value

  defp task_error(state, reason),
    do: {%{normalize(state) | status: :loaded, error: error_text(reason)}, []}

  defp error_text(%Ecto.Changeset{}), do: "Message could not be saved."
  defp error_text(reason), do: inspect(reason)
end
