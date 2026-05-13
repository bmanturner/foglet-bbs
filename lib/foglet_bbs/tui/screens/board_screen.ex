defmodule Foglet.TUI.Screens.BoardScreen do
  @moduledoc """
  Board screen wrapper introduced in FOG-242 C5 (FOG-253).

  Replaces `Foglet.TUI.Screens.ThreadList` as the screen module bound to the
  `:thread_list` route. For boards where chat is disabled (the default for
  every board today) the wrapper is a structural pass-through to
  `ThreadList`; the rendered output, screen-local state struct, route
  params, and subscriptions are byte-equivalent to pre-FOG-253 behaviour.

  When the active board has `chat_enabled: true`, the wrapper:

    * owns `current_tab :: :threads | :chat` state,
    * renders a tab strip above the board content showing
      `▌ THREADS   CHAT (#)` where `#` is
      `Foglet.Sessions.BoardScreen.count/1`,
    * delegates to `ThreadList` for the `:threads` tab and to a placeholder
      view for the `:chat` tab (FOG-254 C6 will replace the placeholder with
      the real `ChatRoom` view),
    * tracks the user's presence in `Foglet.Sessions.BoardScreen` and
      re-renders the count from `{:board_screen, _, _}` PubSub events on
      the `Foglet.PubSub.board_screen_topic/1` topic.

  Keybinding pattern (decision recorded on issue document `design`):
  digit `1` / `2` jumps directly to a tab and Left / Right cycle. Tab /
  Shift-Tab is intentionally not bound — see the `design` document on
  FOG-253 for rationale.
  """

  @behaviour Foglet.TUI.Screen

  alias Foglet.BoardFeeds
  alias Foglet.PubSub, as: PubSubTopics
  alias Foglet.Sessions.ActivityPresence
  alias Foglet.Sessions.BoardScreen, as: PresenceTracker
  alias Foglet.TUI.Context
  alias Foglet.TUI.Effect
  alias Foglet.TUI.Screens.BoardConfig
  alias Foglet.TUI.Screens.BoardNews
  alias Foglet.TUI.Screens.BoardScreen.State
  alias Foglet.TUI.Screens.ChatRoom
  alias Foglet.TUI.Screens.ThreadList
  alias Foglet.TUI.Theme
  alias Foglet.TUI.Widgets.Chrome.ScreenFrame

  import Raxol.Core.Renderer.View

  @tab_labels %{threads: "THREADS", chat: "CHAT", news: "NEWS", config: "CONFIG"}
  @screen_frame_rows 2
  @tab_strip_rows 1
  @chat_flash_interval_ms 750
  @chat_flash_tick :board_chat_flash_tick

  @impl true
  @spec init(Context.t()) :: ThreadList.State.t() | State.t()
  def init(%Context{} = context) do
    thread_state = ThreadList.init(context)
    tabs = tabs_for(context, thread_state.board_id)

    if tabs == [:threads] do
      thread_state
    else
      %State{
        thread_list: thread_state,
        chat_room: if(:chat in tabs, do: ChatRoom.init(context), else: nil),
        news: if(:news in tabs, do: BoardNews.init(context), else: nil),
        config: if(:config in tabs, do: BoardConfig.init(context), else: nil),
        tabs: tabs,
        current_tab: :threads,
        presence_count: 0,
        presence_tracked?: false,
        board: thread_state.board,
        board_id: thread_state.board_id,
        user_id: context.current_user && context.current_user.id
      }
    end
  end

  # --- update --------------------------------------------------------------

  @impl true
  @spec update(term(), ThreadList.State.t() | State.t() | nil, Context.t()) ::
          {ThreadList.State.t() | State.t(), [Effect.t()]}

  # Chat-disabled boards: pass everything through to ThreadList unchanged.
  def update(message, %ThreadList.State{} = state, %Context{} = context) do
    ThreadList.update(message, state, context)
  end

  # Chat-enabled boards: route entry first loads threads via ThreadList and
  # then begins presence tracking on the :threads tab. Presence calls happen
  # after ThreadList.update so a track-failure cannot prevent threads from
  # loading.
  def update(:on_route_enter, %State{} = state, %Context{} = context) do
    {new_thread_state, effects} =
      ThreadList.update(:on_route_enter, state.thread_list, context)

    state = %{state | thread_list: new_thread_state}
    state = ensure_tracked(state, :threads)
    track_activity_tab(state, :threads)
    state = refresh_presence_count(state)

    {state, child_effects} = load_visible_children(state, context)

    {state, effects ++ child_effects}
  end

  # Tab-switch keys: digit shortcuts are gated to the :threads tab so they do
  # not steal characters from the chat composer or CONFIG fields. Left / Right
  # cycle across the visible tabs from any tab.
  def update(
        {:key, %{key: :char, char: <<digit::binary-size(1)>>}},
        %State{current_tab: :threads} = state,
        %Context{} = context
      )
      when digit in ["1", "2", "3", "4", "5", "6", "7", "8", "9"] do
    index = String.to_integer(digit) - 1

    case Enum.at(state.tabs, index) do
      nil -> {state, []}
      tab -> switch_tab(state, context, tab)
    end
  end

  def update({:key, %{key: :left}}, %State{} = state, %Context{} = context),
    do: switch_tab(state, context, adjacent_tab(state, -1))

  def update({:key, %{key: :right}}, %State{} = state, %Context{} = context),
    do: switch_tab(state, context, adjacent_tab(state, 1))

  # Q from the threads tab: untrack presence before delegating ThreadList's
  # back-nav. ThreadList still owns the navigate-to-board_list effect, so the
  # wrapper only adds the explicit untrack. The match is gated to
  # `current_tab: :threads` so `q`/`Q` typed in the chat composer (a text
  # input) is not consumed as back-nav and falls through to the chat-tab
  # forwarder below — see FOG-279.
  def update(
        {:key, %{key: :char, char: c} = ev},
        %State{current_tab: :threads} = state,
        %Context{} = context
      )
      when c in ["q", "Q"] do
    state = untrack_presence(state)
    {new_thread_state, effects} = ThreadList.update({:key, ev}, state.thread_list, context)
    {%{state | thread_list: new_thread_state}, effects}
  end

  # PubSub presence events from FOG-250 — refresh the tab-strip counter and
  # let the chat-tab reducer refresh its sidebar list.
  def update({:board_screen, _event, _payload} = msg, %State{} = state, %Context{} = context) do
    state = refresh_presence_count(state)
    {chat_state, chat_effects} = ChatRoom.update(msg, state.chat_room, context)
    {%{state | chat_room: chat_state}, chat_effects}
  end

  # Live chat messages are owned by the chat-tab reducer regardless of which
  # tab is currently active so transcripts stay current when the user flips
  # back from threads.
  def update({:board_chat, _event, _payload} = msg, %State{} = state, %Context{} = context) do
    {chat_state, chat_effects} = ChatRoom.update(msg, state.chat_room, context)
    state = %{state | chat_room: chat_state} |> maybe_start_chat_alert(msg)
    {state, chat_effects}
  end

  def update(
        @chat_flash_tick,
        %State{chat_alert?: true, chat_flash_phase: :on} = state,
        %Context{}
      ),
      do: {%{state | chat_flash_phase: :off}, []}

  def update(
        @chat_flash_tick,
        %State{chat_alert?: true, chat_flash_phase: :off} = state,
        %Context{}
      ),
      do: {%{state | chat_flash_phase: :on}, []}

  def update(@chat_flash_tick, %State{} = state, %Context{}), do: {state, []}

  # Chat history / send results are routed by op so the right reducer owns
  # the result regardless of which tab is currently active.
  def update({:task_result, op, _result} = msg, %State{} = state, %Context{} = context)
      when op in [:load_chat_history, :send_chat] do
    {chat_state, chat_effects} = ChatRoom.update(msg, state.chat_room, context)
    {%{state | chat_room: chat_state}, chat_effects}
  end

  def update(
        {:task_result, :load_board_news, _result} = msg,
        %State{} = state,
        %Context{} = context
      ) do
    {news_state, effects} = BoardNews.update(msg, state.news, context)
    {%{state | news: news_state}, effects}
  end

  def update(
        {:task_result, :load_board_feed_config, _result} = msg,
        %State{} = state,
        %Context{} = context
      ) do
    {config_state, effects} = BoardConfig.update(msg, state.config, context)
    {%{state | config: config_state}, effects}
  end

  # Threads tab is active: delegate every other message to ThreadList.
  def update(message, %State{current_tab: :threads} = state, %Context{} = context) do
    {new_thread_state, effects} = ThreadList.update(message, state.thread_list, context)
    {%{state | thread_list: new_thread_state}, effects}
  end

  # Chat tab is active: forward keys to ChatRoom; thread-flavoured task /
  # activity messages still go to ThreadList so its background loading
  # stays consistent if the user flips back.
  def update({:key, _ev} = msg, %State{current_tab: :chat} = state, %Context{} = context) do
    {chat_state, chat_effects} = ChatRoom.update(msg, state.chat_room, context)
    {%{state | chat_room: chat_state}, chat_effects}
  end

  def update(
        {:task_result, _op, _result} = msg,
        %State{current_tab: :chat} = state,
        %Context{} = context
      ) do
    {new_thread_state, effects} = ThreadList.update(msg, state.thread_list, context)
    {%{state | thread_list: new_thread_state}, effects}
  end

  def update({:key, _ev} = msg, %State{current_tab: :news} = state, %Context{} = context) do
    {news_state, effects} = BoardNews.update(msg, state.news, context)
    {%{state | news: news_state}, effects}
  end

  def update({:key, _ev} = msg, %State{current_tab: :config} = state, %Context{} = context) do
    {config_state, effects} = BoardConfig.update(msg, state.config, context)
    {%{state | config: config_state}, effects}
  end

  def update(
        {:board_activity, _board_id, _event} = msg,
        %State{current_tab: :chat} = state,
        %Context{} = context
      ) do
    {new_thread_state, effects} = ThreadList.update(msg, state.thread_list, context)
    {%{state | thread_list: new_thread_state}, effects}
  end

  def update(_message, %State{} = state, %Context{}), do: {state, []}

  # --- render --------------------------------------------------------------

  @impl true
  @spec render(ThreadList.State.t() | State.t(), Context.t()) :: any()

  # Chat-disabled boards render exactly as ThreadList did before FOG-253.
  def render(%ThreadList.State{} = state, %Context{} = context) do
    ThreadList.render(state, context)
  end

  def render(%State{} = state, %Context{} = context) do
    frame_state = frame_state(state, context)
    theme = Theme.from_state(frame_state)
    chrome = %{breadcrumb_parts: Foglet.AppName.breadcrumb([board_label(state)])}

    body =
      column style: %{gap: 0} do
        [
          render_tab_strip(state, theme),
          render_active_tab(state, context, theme)
        ]
      end

    ScreenFrame.render(frame_state, chrome, body, keybar_groups(state, context))
  end

  defp render_tab_strip(%State{current_tab: current_tab, presence_count: count} = state, theme) do
    parts =
      Enum.flat_map(state.tabs, fn tab ->
        base_label = Map.fetch!(@tab_labels, tab)
        label = if tab == :chat, do: "#{base_label} (#{count})", else: base_label

        if tab == current_tab do
          [
            text("▌ ", fg: theme.accent.fg),
            text(label, fg: theme.accent.fg, style: [:bold]),
            text("   ", fg: theme.border.fg)
          ]
        else
          [render_inactive_tab_label(tab, label, state, theme), text("   ", fg: theme.border.fg)]
        end
      end)

    row style: %{gap: 0} do
      parts
    end
  end

  defp render_active_tab(%State{current_tab: :threads} = state, context, _theme) do
    ThreadList.render_inner_content(state.thread_list, context)
  end

  defp render_active_tab(%State{current_tab: :chat} = state, context, _theme) do
    ChatRoom.render(state.chat_room, content_context(context))
  end

  defp render_active_tab(%State{current_tab: :news} = state, context, theme) do
    BoardNews.render(state.news, content_context(context), theme)
  end

  defp render_active_tab(%State{current_tab: :config} = state, context, theme) do
    BoardConfig.render(state.config, content_context(context), theme)
  end

  defp keybar_groups(%State{current_tab: current_tab} = state, context) do
    tab_group = %{
      label: "Tabs",
      commands:
        state.tabs
        |> Enum.with_index(1)
        |> Enum.map(fn {tab, idx} ->
          %{
            key: Integer.to_string(idx),
            label: tab_command_label(tab, current_tab, state.presence_count),
            priority: 9
          }
        end)
    }

    case current_tab do
      :threads ->
        [tab_group | ThreadList.keybar_groups(state.thread_list, context)]

      :chat ->
        [%{tab_group | commands: [%{key: "←", label: "Threads", priority: 9}]}] ++
          ChatRoom.keybar_groups(state.chat_room, context)

      :news ->
        [%{tab_group | commands: [%{key: "←/→", label: "Switch tab", priority: 9}]}] ++
          BoardNews.keybar_groups(state.news, context)

      :config ->
        [%{tab_group | commands: [%{key: "←/→", label: "Switch tab", priority: 9}]}] ++
          BoardConfig.keybar_groups(state.config, context)
    end
  end

  defp tab_command_label(tab, tab, count), do: tab_command_label(tab, nil, count) <> "*"
  defp tab_command_label(:threads, _, _count), do: "Threads"
  defp tab_command_label(:chat, _, count), do: "Chat (#{count})"
  defp tab_command_label(:news, _, _count), do: "News"
  defp tab_command_label(:config, _, _count), do: "Config"

  # --- subscriptions ------------------------------------------------------

  @impl true
  @spec subscriptions(ThreadList.State.t() | State.t() | nil, Context.t()) :: [String.t()]
  def subscriptions(%ThreadList.State{} = state, context),
    do: ThreadList.subscriptions(state, context)

  def subscriptions(%State{board_id: board_id} = state, context) when is_binary(board_id) do
    thread_topics = ThreadList.subscriptions(state.thread_list, context)

    %{
      topics: [
        PubSubTopics.board_screen_topic(board_id),
        PubSubTopics.board_chat_topic(board_id) | thread_topics
      ],
      intervals: [{@chat_flash_interval_ms, @chat_flash_tick}]
    }
  end

  def subscriptions(_state, %Context{route_params: params} = context) do
    board_id = board_id_from_params(params)
    tabs = tabs_for(context, board_id)
    base = ThreadList.subscriptions(nil, context)

    if tabs != [:threads] and is_binary(board_id) do
      chat_topics = if :chat in tabs, do: [PubSubTopics.board_chat_topic(board_id)], else: []

      %{
        topics: [PubSubTopics.board_screen_topic(board_id) | chat_topics ++ base],
        intervals: [{@chat_flash_interval_ms, @chat_flash_tick}]
      }
    else
      base
    end
  end

  # --- helpers ------------------------------------------------------------

  defp content_context(%Context{terminal_size: {width, height}} = context) do
    reserved_rows = @screen_frame_rows + @tab_strip_rows
    %{context | terminal_size: {width, max(height - reserved_rows, 1)}}
  end

  defp content_context(%Context{} = context), do: context

  defp render_inactive_tab_label(
         :chat,
         label,
         %State{chat_alert?: true, chat_flash_phase: :on},
         theme
       ) do
    selected = theme.selected

    text(label,
      fg: Map.get(selected, :fg, theme.primary.fg),
      bg: Map.get(selected, :bg),
      style: Map.get(selected, :style, [:bold])
    )
  end

  defp render_inactive_tab_label(_tab, label, _state, theme), do: text(label, fg: theme.dim.fg)

  defp chat_enabled?(params) when is_map(params) do
    case Map.get(params, :board) || Map.get(params, "board") do
      %{chat_enabled: true} -> true
      %{"chat_enabled" => true} -> true
      _ -> false
    end
  end

  defp chat_enabled?(_), do: false

  defp board_id_from_params(params) when is_map(params) do
    Map.get(params, :board_id) || Map.get(params, "board_id") ||
      case Map.get(params, :board) || Map.get(params, "board") do
        %{id: id} -> id
        %{"id" => id} -> id
        _ -> nil
      end
  end

  defp switch_tab(%State{current_tab: tab} = state, _context, tab), do: {state, []}

  defp switch_tab(%State{} = state, _context, new_tab) do
    state = %{state | current_tab: new_tab}
    state = if new_tab == :chat, do: clear_chat_alert(state), else: state
    state = ensure_tracked(state, new_tab)
    track_activity_tab(state, new_tab)
    state = refresh_presence_count(state)
    {state, []}
  end

  defp track_activity_tab(%State{user_id: nil}, _tab), do: :ok
  defp track_activity_tab(%State{board: nil}, _tab), do: :ok

  defp track_activity_tab(%State{user_id: user_id, board: board}, :chat),
    do: ActivityPresence.track(user_id, {:chatting_in_board, board})

  defp track_activity_tab(%State{user_id: user_id, board: board}, :threads),
    do: ActivityPresence.track(user_id, {:browsing_board, board})

  defp track_activity_tab(%State{user_id: user_id, board: board}, tab)
       when tab in [:news, :config],
       do: ActivityPresence.track(user_id, {:browsing_board, board})

  defp ensure_tracked(%State{board_id: nil} = state, _tab), do: state
  defp ensure_tracked(%State{user_id: nil} = state, _tab), do: state

  defp ensure_tracked(%State{board_id: board_id, user_id: user_id} = state, tab) do
    if state.presence_tracked? do
      :ok = PresenceTracker.update_tab(board_id, user_id, tab)
      state
    else
      :ok = PresenceTracker.track(board_id, user_id, tab)
      %{state | presence_tracked?: true}
    end
  end

  defp untrack_presence(%State{presence_tracked?: false} = state), do: state
  defp untrack_presence(%State{board_id: nil} = state), do: state
  defp untrack_presence(%State{user_id: nil} = state), do: state

  defp untrack_presence(%State{board_id: board_id, user_id: user_id} = state) do
    :ok = PresenceTracker.untrack(board_id, user_id)
    %{state | presence_tracked?: false, presence_count: 0} |> clear_chat_alert()
  end

  defp maybe_start_chat_alert(%State{} = state, {:board_chat, :new_message, msg}) do
    if starts_chat_alert?(state, msg) do
      %{state | chat_alert?: true, chat_flash_phase: :on}
    else
      state
    end
  end

  defp maybe_start_chat_alert(%State{} = state, _msg), do: state

  defp starts_chat_alert?(%State{current_tab: :threads} = state, msg) do
    message_board_id(msg) == state.board_id and message_user_id(msg) != state.user_id
  end

  defp starts_chat_alert?(_state, _msg), do: false

  defp message_board_id(msg), do: message_field(msg, :board_id)
  defp message_user_id(msg), do: message_field(msg, :user_id)

  defp message_field(msg, key) when is_map(msg),
    do: Map.get(msg, key) || Map.get(msg, Atom.to_string(key))

  defp clear_chat_alert(%State{} = state),
    do: %{state | chat_alert?: false, chat_flash_phase: :off}

  defp refresh_presence_count(%State{board_id: nil} = state), do: state

  defp refresh_presence_count(%State{board_id: board_id} = state) do
    %{state | presence_count: PresenceTracker.chat_count(board_id)}
  end

  defp board_label(%State{board: %{name: name}}) when is_binary(name), do: name
  defp board_label(%State{}), do: "Boards"

  defp tabs_for(%Context{route_params: params, current_user: actor}, board_id) do
    board_id = board_id || board_id_from_params(params)
    tabs = [:threads]
    tabs = if chat_enabled?(params), do: tabs ++ [:chat], else: tabs
    tabs = if news_enabled?(params, actor, board_id), do: tabs ++ [:news], else: tabs
    tabs = if config_visible?(actor, board_id), do: tabs ++ [:config], else: tabs
    tabs
  end

  defp news_enabled?(params, _actor, board_id) do
    route_flag = Map.get(params, :news_enabled) || Map.get(params, "news_enabled")

    cond do
      route_flag == true -> true
      is_binary(board_id) -> BoardFeeds.enabled_feed_count(board_id) > 0
      true -> false
    end
  rescue
    _ -> false
  end

  defp config_visible?(nil, _board_id), do: false
  defp config_visible?(_actor, nil), do: false

  defp config_visible?(actor, board_id),
    do: Bodyguard.permit?(Foglet.Authorization, :manage_board_feeds, actor, {:board, board_id})

  defp adjacent_tab(%State{tabs: tabs, current_tab: current}, delta) do
    index = Enum.find_index(tabs, &(&1 == current)) || 0
    Enum.at(tabs, rem(index + delta + length(tabs), length(tabs)))
  end

  defp load_visible_children(%State{} = state, context) do
    {state, effects} =
      if :chat in state.tabs do
        {chat_state, chat_effects} = ChatRoom.load_effects(state.chat_room, context)
        {%{state | chat_room: chat_state}, chat_effects}
      else
        {state, []}
      end

    {state, effects} =
      if :news in state.tabs do
        {news_state, news_effects} = BoardNews.load_effects(state.news, context)
        {%{state | news: news_state}, effects ++ news_effects}
      else
        {state, effects}
      end

    if :config in state.tabs do
      {config_state, config_effects} = BoardConfig.load_effects(state.config, context)
      {%{state | config: config_state}, effects ++ config_effects}
    else
      {state, effects}
    end
  end

  defp frame_state(%State{} = _state, %Context{} = context) do
    %{
      current_screen: :thread_list,
      current_user: context.current_user,
      unread_count: context.unread_count,
      session_context: context.session_context,
      terminal_size: context.terminal_size,
      route: context.route,
      route_params: context.route_params
    }
  end
end
