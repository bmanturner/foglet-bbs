defmodule Foglet.TUI.Screens.ChatRoom do
  @moduledoc """
  Chat tab content for board screens with `chat_enabled: true` (FOG-254 C6
  of FOG-242).

  Embedded inside `Foglet.TUI.Screens.BoardScreen` rather than mounted as a
  standalone screen route. The wrapper:

    * holds a `%ChatRoom.State{}` next to its `ThreadList.State`,
    * forwards key events and PubSub messages to `update/3` while the
      `:chat` tab is active,
    * calls `render/2` for the chat-tab body and merges `keybar_groups/2`
      into the screen frame's command bar.

  ## Responsive layout

  `terminal_size` from `Foglet.TUI.Context` drives a three-mode layout:

    * `width >= 80` — transcript + sidebar visible by default.
    * `60 <= width < 80` — sidebar collapsed by default, Ctrl+B toggles.
    * `width < 60` — single-pane transcript only; toggle is hidden.

  The user's most-recent toggle override is sticky across width changes
  via `sidebar_user_pref` (`:show | :hide | nil`), but a freshly-mounted
  screen always derives its initial state from width.

  See the `design` document on FOG-254 for the keybinding rationale and
  rejected alternatives.

  ## Backend wiring

  Reads recent history via `Foglet.BoardChat.recent/1`, writes via
  `Foglet.BoardChat.post/3`, and listens for `{:board_chat, :new_message,
  msg}` on `Foglet.PubSub.board_chat_topic/1` plus presence updates on
  `Foglet.PubSub.board_screen_topic/1`. The façade dispatches to the
  permanent or ephemeral backend based on the board's `chat_storage_mode`,
  so this view never branches on storage mode for read/write — only for
  the ephemeral notice band.
  """

  alias Foglet.BoardChat
  alias Foglet.BoardChat.Message, as: ChatMessage
  alias Foglet.Boards.Board
  alias Foglet.Sessions.BoardScreen, as: PresenceTracker
  alias Foglet.TimeAgo
  alias Foglet.TUI.Context
  alias Foglet.TUI.Effect
  alias Foglet.TUI.Guest
  alias Foglet.TUI.Screens.ChatRoom.State
  alias Foglet.TUI.Screens.Domain
  alias Foglet.TUI.TextWidth
  alias Foglet.TUI.Theme
  alias Foglet.TUI.Widgets.Display.Handle

  import Raxol.Core.Renderer.View

  @sidebar_width 20
  @sidebar_separator_width 3
  @sidebar_min_width 60
  @sidebar_default_width 80
  @transcript_history_lines 1_000
  @chat_body_max ChatMessage.body_max()
  @ephemeral_notice_placeholder "Ephemeral chat — messages fade after the board's TTL."
  @empty_transcript_placeholder "No messages yet. Be the first to say hello."
  @send_failure_message "Could not send message."
  @message_too_long "Message is too long (max #{@chat_body_max} characters)."

  # ---------------------------------------------------------------------------
  # init / load
  # ---------------------------------------------------------------------------

  @spec init(Context.t()) :: State.t()
  def init(%Context{route_params: params} = context) do
    board = board_from_params(params)
    board_id = board_id_from_params(params)
    user_id = context.current_user && context.current_user.id

    %State{
      board: board,
      board_id: board_id,
      user_id: user_id
    }
  end

  @doc """
  Effects to run when the chat tab becomes active. Loads recent history and
  the current online list. Idempotent — only loads once per State instance.
  """
  @spec load_effects(State.t() | nil, Context.t()) :: {State.t() | nil, [Effect.t()]}
  def load_effects(nil, _context), do: {nil, []}
  def load_effects(%State{loaded?: true} = state, _context), do: {state, []}
  def load_effects(%State{board: nil} = state, _context), do: {state, []}

  def load_effects(%State{} = state, %Context{} = context) do
    board = to_board_struct(state.board)
    screen_key = task_screen_key(context)

    history_effect =
      Effect.task(:load_chat_history, screen_key, fn ->
        BoardChat.recent(board)
      end)

    state =
      %{state | status: :loading, online: refresh_online(state)}
      |> resolve_handles(context)

    {state, [history_effect]}
  end

  # ---------------------------------------------------------------------------
  # update
  # ---------------------------------------------------------------------------

  @spec update(term(), State.t() | nil, Context.t()) :: {State.t() | nil, [Effect.t()]}
  def update(_msg, nil, _context), do: {nil, []}

  # Sidebar toggle (Ctrl+B). Decision documented on FOG-254 `design`.
  def update({:key, %{key: :char, char: "b", ctrl: true}}, %State{} = state, %Context{} = context) do
    {toggle_sidebar(state, context), []}
  end

  # Transcript viewport navigation. These keys are reserved for history
  # browsing and must not leak into the composer buffer.
  def update({:key, %{key: key}}, %State{} = state, %Context{} = context)
      when key in [:up, :down, :page_up, :page_down, :pageup, :pagedown, :home, :end] do
    {scroll_transcript(state, key, context), []}
  end

  # Submit composer.
  def update({:key, %{key: :enter}}, %State{} = state, %Context{} = context) do
    if Guest.guest?(context),
      do: {state, [Effect.open_modal(Guest.denial_modal(:chat))]},
      else: submit_composer(state, context)
  end

  # Backspace.
  def update({:key, %{key: :backspace}}, %State{composer: ""} = state, %Context{}) do
    {state, []}
  end

  def update({:key, %{key: :backspace}}, %State{} = state, %Context{} = context) do
    if Guest.guest?(context),
      do: {state, []},
      else: {%{state | composer: String.slice(state.composer, 0..-2//1)}, []}
  end

  # Printable char into composer. Ignore ctrl/alt-modified chars we did not
  # explicitly bind above so they don't leak into the buffer.
  def update(
        {:key, %{key: :char, char: <<c::utf8>>} = ev},
        %State{} = state,
        %Context{} = context
      ) do
    cond do
      Guest.guest?(context) ->
        {state, []}

      Map.get(ev, :ctrl, false) ->
        {state, []}

      Map.get(ev, :alt, false) ->
        {state, []}

      String.length(state.composer) >= @chat_body_max ->
        {%{state | last_error: :message_too_long}, []}

      true ->
        {%{state | composer: state.composer <> <<c::utf8>>, last_error: nil}, []}
    end
  end

  # Live updates from the chat backend.
  def update({:board_chat, :new_message, msg}, %State{} = state, %Context{} = context) do
    state =
      state
      |> append_message(msg)
      |> resolve_handles(context)

    {state, []}
  end

  # Presence updates from FOG-250.
  def update({:board_screen, _event, _payload}, %State{} = state, %Context{} = context) do
    {%{state | online: refresh_online(state)} |> resolve_handles(context), []}
  end

  # History load result.
  def update(
        {:task_result, :load_chat_history, result},
        %State{} = state,
        %Context{} = context
      ) do
    messages =
      case Effect.unwrap_task_result(result) do
        {:ok, msgs} when is_list(msgs) -> msgs
        _ -> []
      end

    state =
      %{state | messages: messages, status: :idle, loaded?: true}
      |> resolve_handles(context)

    {state, []}
  end

  # Send result.
  def update({:task_result, :send_chat, result}, %State{} = state, %Context{}) do
    case Effect.unwrap_task_result(result) do
      {:ok, _msg} ->
        # Live message arrives via PubSub; just clear the sending status.
        {%{state | status: :idle, last_error: nil, pending_composer: nil}, []}

      {:error, {:command_validation, _message} = reason} ->
        {%{
           state
           | status: :idle,
             composer: state.pending_composer || state.composer,
             pending_composer: nil,
             last_error: reason
         }, []}

      {:error, reason} ->
        {%{state | status: :idle, last_error: reason, pending_composer: nil}, []}
    end
  end

  def update(_msg, %State{} = state, %Context{}), do: {state, []}

  # ---------------------------------------------------------------------------
  # render
  # ---------------------------------------------------------------------------

  @spec render(State.t(), Context.t()) :: any()
  def render(%State{} = state, %Context{} = context) do
    theme = Theme.from_state(%{session_context: context.session_context})
    {width, height} = context.terminal_size || {80, 24}
    show_sidebar? = sidebar_visible?(state, width)

    column style: %{gap: 0} do
      [
        ephemeral_notice(state, theme),
        body_row(state, theme, width, transcript_height(height), show_sidebar?),
        composer_row(state, theme, width)
      ]
    end
  end

  defp ephemeral_notice(%State{board: %{chat_storage_mode: :ephemeral}}, theme) do
    text("  " <> @ephemeral_notice_placeholder, fg: theme.dim.fg, style: [:italic])
  end

  defp ephemeral_notice(_state, _theme), do: text("")

  defp body_row(state, theme, width, height, true) when width >= @sidebar_min_width do
    transcript_width = max(width - @sidebar_width - @sidebar_separator_width, 20)

    row style: %{gap: 0} do
      [
        transcript_pane(state, theme, transcript_width, height),
        sidebar_separator(theme),
        sidebar_pane(state, theme, @sidebar_width)
      ]
    end
  end

  defp body_row(state, theme, width, height, _show_sidebar?) do
    transcript_pane(state, theme, max(width - 2, 20), height)
  end

  defp sidebar_separator(theme) do
    column style: %{gap: 0} do
      [text(" │ ", fg: theme.border.fg)]
    end
  end

  defp transcript_pane(%State{messages: []} = _state, theme, width, _height) do
    box style: %{width: width} do
      column style: %{gap: 0} do
        [
          text(
            TextWidth.pad_trailing("  " <> @empty_transcript_placeholder, width),
            fg: theme.dim.fg,
            style: [:italic]
          )
        ]
      end
    end
  end

  defp transcript_pane(%State{messages: messages} = state, theme, width, height) do
    row_limit = max(height, 0)

    rows =
      messages
      |> Enum.take(-@transcript_history_lines)
      |> visible_messages(state.scroll_offset, height)
      |> transcript_rows_until(row_limit, state, theme, width)

    box style: %{width: width} do
      column style: %{gap: 0} do
        rows
      end
    end
  end

  defp transcript_rows_until(_messages, 0, _state, _theme, _width), do: []

  defp transcript_rows_until(messages, row_limit, %State{} = state, theme, width) do
    {rows, _remaining} =
      Enum.reduce_while(messages, {[], row_limit}, fn msg, {rows, remaining} ->
        msg_rows = transcript_rows(msg, state, theme, width, remaining)
        remaining = remaining - length(msg_rows)
        rows = rows ++ msg_rows

        if remaining <= 0, do: {:halt, {rows, 0}}, else: {:cont, {rows, remaining}}
      end)

    rows
  end

  defp transcript_rows(msg, %State{} = state, theme, width, row_limit) do
    user = user_for_message(state, msg)
    handle = user |> Handle.handle_text() |> TextWidth.truncate(min(20, max(div(width, 3), 1)))
    body = Map.get(msg, :body, "")
    when_label = relative_time(msg)

    if action_message?(msg) do
      action_transcript_rows(user, handle, body, when_label, theme, width, row_limit)
    else
      text_transcript_rows(user, handle, body, when_label, theme, width, row_limit)
    end
  end

  defp text_transcript_rows(user, handle, body, when_label, theme, width, row_limit) do
    prefix = handle <> " • "
    suffix = "  " <> when_label

    first_body_width =
      max(width - TextWidth.display_width(prefix) - TextWidth.display_width(suffix), 1)

    continuation_body_width = max(width - TextWidth.display_width(prefix), 1)
    body_lines = bounded_body_lines(body, first_body_width, continuation_body_width, row_limit)

    [first_body | rest] = body_lines

    [
      transcript_first_row(
        %{user | handle: handle},
        first_body,
        when_label,
        first_body_width,
        theme
      )
      | Enum.map(rest, fn line ->
          transcript_continuation_row(prefix, line, continuation_body_width, theme)
        end)
    ]
  end

  defp action_transcript_rows(_user, handle, body, when_label, theme, width, row_limit) do
    action_prefix = "*#{handle}* "
    action_body = action_prefix <> body
    suffix = "  " <> when_label
    first_body_width = max(width - TextWidth.display_width(suffix), 1)
    continuation_indent = TextWidth.display_width(action_prefix)
    continuation_body_width = max(width - continuation_indent, 1)

    body_lines =
      bounded_body_lines(action_body, first_body_width, continuation_body_width, row_limit)

    [first_body | rest] = body_lines

    [
      transcript_action_first_row(first_body, when_label, first_body_width, theme)
      | Enum.map(rest, fn line ->
          transcript_action_continuation_row(
            continuation_indent,
            line,
            continuation_body_width,
            theme
          )
        end)
    ]
  end

  defp transcript_first_row(user, body, when_label, body_width, theme) do
    row style: %{gap: 0} do
      [
        Handle.render(user, theme, prefix: ""),
        text(" • ", fg: theme.dim.fg),
        text(TextWidth.pad_trailing(body, body_width), fg: theme.primary.fg),
        text("  ", fg: theme.dim.fg),
        text(when_label, fg: theme.dim.fg)
      ]
    end
  end

  defp transcript_action_first_row(body, when_label, body_width, theme) do
    row style: %{gap: 0} do
      [
        text(TextWidth.pad_trailing(body, body_width), fg: theme.primary.fg, style: [:italic]),
        text("  ", fg: theme.dim.fg),
        text(when_label, fg: theme.dim.fg)
      ]
    end
  end

  defp bounded_body_lines(_body, _first_width, _continuation_width, row_limit)
       when row_limit <= 0,
       do: []

  defp bounded_body_lines(body, first_width, continuation_width, row_limit) do
    prefix_chars = bounded_wrap_prefix(body, first_width, continuation_width, row_limit)

    body
    |> String.slice(0, prefix_chars)
    |> TextWidth.wrap(first_width)
    |> case do
      [] -> [""]
      lines -> lines
    end
    |> Enum.take(row_limit)
  end

  defp bounded_wrap_prefix(_body, first_width, continuation_width, row_limit) do
    # Cap the source text before wrapping so a bad in-memory message cannot force
    # row allocation for the full body. The bound scales with viewport rows and
    # transcript width, while also respecting the shared domain chat body limit.
    width_budget = first_width + max(row_limit - 1, 0) * continuation_width
    min(@chat_body_max, max(width_budget + row_limit, row_limit))
  end

  defp transcript_continuation_row(prefix, body, body_width, theme) do
    row style: %{gap: 0} do
      [
        text(TextWidth.pad_trailing("", TextWidth.display_width(prefix)), fg: theme.dim.fg),
        text(TextWidth.pad_trailing(body, body_width), fg: theme.primary.fg)
      ]
    end
  end

  defp transcript_action_continuation_row(indent, body, body_width, theme) do
    row style: %{gap: 0} do
      [
        text(TextWidth.pad_trailing("", indent), fg: theme.dim.fg),
        text(TextWidth.pad_trailing(body, body_width), fg: theme.primary.fg, style: [:italic])
      ]
    end
  end

  defp action_message?(msg), do: Map.get(msg, :kind) in [:action, "action"]

  defp sidebar_pane(%State{} = state, theme, width) do
    rows = sidebar_entries(state, theme)

    box style: %{width: width} do
      column style: %{gap: 0} do
        [text("Online", fg: theme.accent.fg, style: [:bold]) | rows]
      end
    end
  end

  defp sidebar_entries(%State{online: []} = _state, theme) do
    [text("(no one)", fg: theme.dim.fg, style: [:italic])]
  end

  defp sidebar_entries(%State{} = state, theme) do
    Enum.map(state.online, fn entry ->
      user = user_for_id(state, entry.user_id)
      handle = Handle.handle_text(user)
      label = if entry.user_id == state.user_id, do: "#{handle} (you)", else: handle

      text("• " <> label, fg: Handle.color_for(user, theme))
    end)
  end

  defp composer_row(%State{} = state, theme, width) do
    if is_nil(state.user_id) do
      text("  Guest chat is read-only. Log in to send messages.", fg: theme.dim.fg)
    else
      prompt = "> "
      cursor_glyph = if state.status == :sending, do: "…", else: "▎"
      available = max(width - 4, 10)
      body = String.slice(state.composer, 0, available)

      error_line =
        case state.last_error do
          nil ->
            text("")

          :message_too_long ->
            text("  " <> @message_too_long, fg: theme.error.fg)

          {:command_validation, message} when is_binary(message) ->
            text("  " <> message, fg: theme.error.fg)

          _ ->
            text("  " <> @send_failure_message, fg: theme.error.fg)
        end

      column style: %{gap: 0} do
        [
          row style: %{gap: 0} do
            [
              text(prompt, fg: theme.dim.fg),
              text(body, fg: theme.primary.fg),
              text(cursor_glyph, fg: theme.accent.fg)
            ]
          end,
          error_line
        ]
      end
    end
  end

  # ---------------------------------------------------------------------------
  # subscriptions / keybar
  # ---------------------------------------------------------------------------

  @spec subscriptions(State.t() | nil, Context.t()) :: [String.t()]
  def subscriptions(%State{board_id: board_id}, _context) when is_binary(board_id) do
    [
      Foglet.PubSub.board_chat_topic(board_id),
      Foglet.PubSub.board_screen_topic(board_id)
    ]
  end

  def subscriptions(_state, %Context{route_params: params}) do
    case board_id_from_params(params) do
      id when is_binary(id) ->
        [Foglet.PubSub.board_chat_topic(id), Foglet.PubSub.board_screen_topic(id)]

      _ ->
        []
    end
  end

  @doc """
  Keybar groups for the chat tab, merged into the BoardScreen wrapper's
  command bar. Always advertises Send; advertises sidebar toggle only when
  the layout is wide enough for collapse/visible to be a meaningful choice.
  """
  @spec keybar_groups(State.t(), Context.t()) :: [map()]
  def keybar_groups(%State{} = state, %Context{} = context) do
    {width, _} = context.terminal_size || {80, 24}

    chat_commands =
      if Guest.guest?(context), do: [], else: [%{key: "Enter", label: "Send", priority: 30}]

    chat_group = %{
      label: "Chat",
      commands: chat_commands
    }

    if width >= @sidebar_min_width do
      toggle_label =
        if sidebar_visible?(state, width), do: "Hide sidebar", else: "Show sidebar"

      [
        Map.update!(chat_group, :commands, fn cmds ->
          cmds ++ [%{key: "Ctrl+B", label: toggle_label, priority: 20}]
        end)
      ]
    else
      [chat_group]
    end
  end

  @doc """
  Returns true when the sidebar should be rendered at `width` given the
  user's preference. Public so the wrapper / tests can compute the same
  layout decision without re-rendering.
  """
  @spec sidebar_visible?(State.t(), pos_integer()) :: boolean()
  def sidebar_visible?(%State{sidebar_user_pref: pref}, width) do
    cond do
      width < @sidebar_min_width -> false
      pref == :show -> true
      pref == :hide -> false
      true -> width >= @sidebar_default_width
    end
  end

  # ---------------------------------------------------------------------------
  # helpers
  # ---------------------------------------------------------------------------

  defp toggle_sidebar(%State{} = state, %Context{} = context) do
    {width, _} = context.terminal_size || {80, 24}
    new_pref = if sidebar_visible?(state, width), do: :hide, else: :show
    %{state | sidebar_user_pref: new_pref}
  end

  defp submit_composer(%State{composer: ""} = state, _context), do: {state, []}
  defp submit_composer(%State{board: nil} = state, _context), do: {state, []}

  defp submit_composer(%State{} = state, %Context{current_user: nil}) do
    {%{state | last_error: :not_authenticated}, []}
  end

  defp submit_composer(%State{} = state, %Context{current_user: user} = context) do
    body = String.trim(state.composer)

    cond do
      body == "" ->
        {%{state | composer: ""}, []}

      String.length(body) > @chat_body_max ->
        {%{state | last_error: :message_too_long}, []}

      true ->
        board = to_board_struct(state.board)
        screen_key = task_screen_key(context)

        effect =
          Effect.task(:send_chat, screen_key, fn ->
            BoardChat.post(board, user, body)
          end)

        {%{
           state
           | composer: "",
             pending_composer: state.composer,
             status: :sending,
             last_error: nil
         }, [effect]}
    end
  end

  # ChatRoom is embedded inside `BoardScreen` at the `:thread_list` route key —
  # there is no top-level `:chat_room` screen. Tasks must be dispatched with the
  # active route's key so `Foglet.TUI.App.Routing.route_screen_update/3` can find
  # the screen module (`BoardScreen`) and forward the `{:task_result, ...}` to
  # this reducer. Falls back to `:thread_list` when context.route is missing.
  defp task_screen_key(%Context{route: route}) when is_atom(route) and not is_nil(route),
    do: route

  defp task_screen_key(_context), do: :thread_list

  # Route params land here as a plain map (see BoardList.board_identity/1) but
  # `Foglet.BoardChat` dispatches on `%Board{}` field guards. Coerce so the task
  # closure does not raise FunctionClauseError before reaching Repo.insert.
  defp to_board_struct(%Board{} = b), do: b
  defp to_board_struct(%{} = m), do: struct(Board, m)
  defp to_board_struct(other), do: other

  defp append_message(%State{messages: msgs} = state, msg) do
    scroll_offset = if state.autoscroll?, do: 0, else: state.scroll_offset
    %{state | messages: msgs ++ [msg], scroll_offset: scroll_offset}
  end

  defp scroll_transcript(%State{} = state, key, %Context{} = context) do
    {_width, height} = context.terminal_size || {80, 24}
    step = scroll_step(key, transcript_height(height))
    max_scroll = max_scroll_offset(state, transcript_height(height))

    new_offset =
      case key do
        :home -> max_scroll
        :end -> 0
        _ -> state.scroll_offset + step
      end
      |> min(max_scroll)
      |> max(0)

    %{state | scroll_offset: new_offset, autoscroll?: new_offset == 0}
  end

  defp scroll_step(key, height) when key in [:page_up, :pageup], do: height
  defp scroll_step(key, height) when key in [:page_down, :pagedown], do: -height
  defp scroll_step(:up, _height), do: 1
  defp scroll_step(:down, _height), do: -1
  defp scroll_step(_key, _height), do: 0

  defp max_scroll_offset(%State{messages: messages}, height) do
    messages
    |> Enum.take(-@transcript_history_lines)
    |> length()
    |> Kernel.-(height)
    |> max(0)
  end

  defp visible_messages(messages, scroll_offset, height) do
    total = length(messages)
    count = max(height, 1)
    max_scroll = max(total - count, 0)
    offset = scroll_offset |> min(max_scroll) |> max(0)
    start = max(total - count - offset, 0)

    messages
    |> Enum.drop(start)
    |> Enum.take(count)
  end

  defp transcript_height(height), do: max(height - 4, 1)

  defp refresh_online(%State{board_id: nil}), do: []

  defp refresh_online(%State{board_id: board_id}) do
    PresenceTracker.list(board_id)
    |> unique_online_users()
  rescue
    _ -> []
  catch
    :exit, _ -> []
  end

  defp unique_online_users(entries) do
    entries
    |> Enum.sort_by(fn entry ->
      {Map.get(entry, :user_id), if(Map.get(entry, :tab) == :chat, do: 0, else: 1)}
    end)
    |> Enum.uniq_by(&Map.get(&1, :user_id))
  end

  defp resolve_handles(%State{} = state, %Context{} = context) do
    accounts_mod = resolve_accounts_module(context)

    needed =
      ([state.user_id] ++
         Enum.map(state.online, & &1.user_id) ++
         Enum.map(state.messages, &Map.get(&1, :user_id)))
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()
      |> Enum.reject(&Map.has_key?(state.handles, &1))

    if needed == [] do
      state
    else
      additions =
        needed
        |> Enum.map(fn id -> {id, fetch_user(accounts_mod, id)} end)
        |> Map.new()

      %{state | handles: Map.merge(state.handles, additions)}
    end
  end

  defp fetch_user(nil, _id), do: nil

  defp fetch_user(mod, id) do
    if function_exported?(mod, :get_user, 1) do
      case mod.get_user(id) do
        %{handle: h} = user when is_binary(h) ->
          %{handle: h, handle_color: Map.get(user, :handle_color)}

        _ ->
          nil
      end
    end
  rescue
    _ -> nil
  end

  defp resolve_accounts_module(%Context{} = context) do
    case Domain.get(context.session_context || %{}, :accounts) do
      {:ok, mod} -> mod
      {:error, :not_configured} -> Foglet.Accounts
    end
  end

  defp user_for_message(state, msg) do
    user_for_id(state, Map.get(msg, :user_id))
  end

  defp user_for_id(_state, nil), do: %{handle: "unknown"}

  defp user_for_id(%State{handles: handles}, user_id) do
    case Map.get(handles, user_id) do
      %{handle: h} = user when is_binary(h) and h != "" -> user
      h when is_binary(h) and h != "" -> %{handle: h}
      _ -> %{handle: "user-" <> String.slice(user_id, 0, 6)}
    end
  end

  defp relative_time(msg) do
    case Map.get(msg, :inserted_at) do
      %DateTime{} = dt ->
        TimeAgo.format(dt)

      %NaiveDateTime{} = ndt ->
        ndt |> DateTime.from_naive!("Etc/UTC") |> TimeAgo.format()

      ts when is_integer(ts) ->
        case DateTime.from_unix(ts) do
          {:ok, dt} -> TimeAgo.format(dt)
          _ -> "?"
        end

      _ ->
        "?"
    end
  end

  defp board_from_params(params) when is_map(params) do
    Map.get(params, :board) || Map.get(params, "board")
  end

  defp board_from_params(_), do: nil

  defp board_id_from_params(params) when is_map(params) do
    Map.get(params, :board_id) || Map.get(params, "board_id") ||
      case board_from_params(params) do
        %{id: id} -> id
        %{"id" => id} -> id
        _ -> nil
      end
  end

  defp board_id_from_params(_), do: nil
end
