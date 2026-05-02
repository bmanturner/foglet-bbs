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
      `▌ 1 THREADS   2 CHAT (#)` where `#` is
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

  alias Foglet.PubSub, as: PubSubTopics
  alias Foglet.Sessions.BoardScreen, as: PresenceTracker
  alias Foglet.TUI.Context
  alias Foglet.TUI.Effect
  alias Foglet.TUI.Screens.BoardScreen.State
  alias Foglet.TUI.Screens.ChatRoom
  alias Foglet.TUI.Screens.ThreadList
  alias Foglet.TUI.Theme
  alias Foglet.TUI.Widgets.Chrome.ScreenFrame

  import Raxol.Core.Renderer.View

  @tabs [{:threads, "1 THREADS"}, {:chat, "2 CHAT"}]

  @impl true
  @spec init(Context.t()) :: ThreadList.State.t() | State.t()
  def init(%Context{route_params: params} = context) do
    if chat_enabled?(params) do
      thread_state = ThreadList.init(context)

      %State{
        thread_list: thread_state,
        chat_room: ChatRoom.init(context),
        current_tab: :threads,
        presence_count: 0,
        presence_tracked?: false,
        board: thread_state.board,
        board_id: thread_state.board_id,
        user_id: context.current_user && context.current_user.id
      }
    else
      ThreadList.init(context)
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
    state = refresh_presence_count(state)

    # Pre-load chat history so the first flip to :chat is instant.
    {chat_state, chat_effects} = ChatRoom.load_effects(state.chat_room, context)
    state = %{state | chat_room: chat_state}

    {state, effects ++ chat_effects}
  end

  # Tab-switch keys: digit and arrows.
  def update({:key, %{key: :char, char: "1"}}, %State{} = state, %Context{} = context),
    do: switch_tab(state, context, :threads)

  def update({:key, %{key: :char, char: "2"}}, %State{} = state, %Context{} = context),
    do: switch_tab(state, context, :chat)

  def update({:key, %{key: :left}}, %State{current_tab: :chat} = state, %Context{} = context),
    do: switch_tab(state, context, :threads)

  def update({:key, %{key: :right}}, %State{current_tab: :threads} = state, %Context{} = context),
    do: switch_tab(state, context, :chat)

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
    {%{state | chat_room: chat_state}, chat_effects}
  end

  # Chat history / send results are routed by op so the right reducer owns
  # the result regardless of which tab is currently active.
  def update({:task_result, op, _result} = msg, %State{} = state, %Context{} = context)
      when op in [:load_chat_history, :send_chat] do
    {chat_state, chat_effects} = ChatRoom.update(msg, state.chat_room, context)
    {%{state | chat_room: chat_state}, chat_effects}
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
    chrome = %{breadcrumb_parts: ["Foglet", board_label(state)]}

    body =
      column style: %{gap: 0} do
        [
          render_tab_strip(state, theme),
          render_active_tab(state, context, theme)
        ]
      end

    ScreenFrame.render(frame_state, chrome, body, keybar_groups(state, context))
  end

  defp render_tab_strip(%State{current_tab: current_tab, presence_count: count}, theme) do
    parts =
      Enum.flat_map(@tabs, fn {tab, base_label} ->
        label = if tab == :chat, do: "#{base_label} (#{count})", else: base_label

        if tab == current_tab do
          [
            text("▌ ", fg: theme.accent.fg),
            text(label, fg: theme.accent.fg, style: [:bold]),
            text("   ", fg: theme.border.fg)
          ]
        else
          [text(label, fg: theme.dim.fg), text("   ", fg: theme.border.fg)]
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
    ChatRoom.render(state.chat_room, context)
  end

  defp keybar_groups(%State{current_tab: current_tab} = state, context) do
    threads_group = ThreadList.keybar_groups(state.thread_list, context)

    tab_group = %{
      label: "Tabs",
      commands: [
        %{key: "1", label: tab_command_label(:threads, current_tab), priority: 9},
        %{
          key: "2",
          label: tab_command_label(:chat, current_tab, state.presence_count),
          priority: 9
        }
      ]
    }

    case current_tab do
      :threads ->
        [tab_group | threads_group]

      :chat ->
        # When the chat tab is active, suppress threads-only actions
        # (j/k/Enter/C) — they belong to the threads body. Keep the System
        # group (Q/back-nav) by isolating it from the threads group, then
        # let ChatRoom contribute its Send / Sidebar commands.
        system_groups = Enum.filter(threads_group, &(&1.label == "System"))
        chat_groups = ChatRoom.keybar_groups(state.chat_room, context)
        [tab_group] ++ chat_groups ++ system_groups
    end
  end

  defp tab_command_label(:threads, :threads), do: "Threads*"
  defp tab_command_label(:threads, _), do: "Threads"
  defp tab_command_label(:chat, :chat, count), do: "Chat (#{count})*"
  defp tab_command_label(:chat, _, count), do: "Chat (#{count})"

  # --- subscriptions ------------------------------------------------------

  @impl true
  @spec subscriptions(ThreadList.State.t() | State.t() | nil, Context.t()) :: [String.t()]
  def subscriptions(%ThreadList.State{} = state, context),
    do: ThreadList.subscriptions(state, context)

  def subscriptions(%State{board_id: board_id} = state, context) when is_binary(board_id) do
    thread_topics = ThreadList.subscriptions(state.thread_list, context)

    [
      PubSubTopics.board_screen_topic(board_id),
      PubSubTopics.board_chat_topic(board_id) | thread_topics
    ]
  end

  def subscriptions(_state, %Context{route_params: params} = context) do
    if chat_enabled?(params) do
      board_id = board_id_from_params(params)

      base = ThreadList.subscriptions(nil, context)

      if is_binary(board_id) do
        [
          PubSubTopics.board_screen_topic(board_id),
          PubSubTopics.board_chat_topic(board_id) | base
        ]
      else
        base
      end
    else
      ThreadList.subscriptions(nil, context)
    end
  end

  # --- helpers ------------------------------------------------------------

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
    state = ensure_tracked(state, new_tab)
    state = refresh_presence_count(state)
    {state, []}
  end

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
    %{state | presence_tracked?: false, presence_count: 0}
  end

  defp refresh_presence_count(%State{board_id: nil} = state), do: state

  defp refresh_presence_count(%State{board_id: board_id} = state) do
    %{state | presence_count: PresenceTracker.count(board_id)}
  end

  defp board_label(%State{board: %{name: name}}) when is_binary(name), do: name
  defp board_label(%State{}), do: "Boards"

  defp frame_state(%State{} = _state, %Context{} = context) do
    %{
      current_screen: :thread_list,
      current_user: context.current_user,
      session_context: context.session_context,
      terminal_size: context.terminal_size,
      route: context.route,
      route_params: context.route_params
    }
  end
end
