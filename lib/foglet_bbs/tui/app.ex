defmodule Foglet.TUI.App do
  @moduledoc """
  Raxol application entry point for the Foglet BBS TUI.

  Metaphor (D-15): `app.ex` is the conductor; `screens/*` are the scores;
  `widgets/*` are the instruments. This module holds the top-level model
  and the view-routing table; each screen is a pure render/1 + handle_key/2
  pair.

  State flow (D-16):
    * Domain state → Postgres (accessed via Foglet.Boards/Threads/Posts)
    * Session-scoped identity → Foglet.Sessions.Session
    * UI state → this model (%__MODULE__{})

  See docs/ARCHITECTURE.md §4 and CONTEXT 03 D-13..D-21.
  """

  use Raxol.Core.Runtime.Application

  alias Foglet.TUI.PubSubForwarder
  alias Foglet.TUI.Screens
  alias Foglet.TUI.Widgets
  alias Raxol.Core.Runtime.Command
  alias Raxol.Core.Runtime.Subscription

  @type screen ::
          :login
          | :register
          | :verify
          | :main_menu
          | :board_list
          | :thread_list
          | :post_reader
          | :post_composer
          | :new_thread

  @type t :: %__MODULE__{
          current_screen: screen(),
          current_user: Foglet.Accounts.User.t() | nil,
          session_context: map(),
          session_pid: pid() | nil,
          terminal_size: {pos_integer(), pos_integer()},
          modal: map() | nil,
          screen_state: map(),
          board_list: list() | nil,
          current_board: map() | nil,
          current_thread: map() | nil,
          current_thread_list: list() | nil,
          posts: list() | nil,
          read_position: map(),
          composer_draft: String.t() | nil,
          register_wizard: map() | nil,
          verify_state: map() | nil,
          subscribed_topics: MapSet.t()
        }

  defstruct current_screen: :login,
            current_user: nil,
            session_context: %{},
            session_pid: nil,
            terminal_size: {80, 24},
            modal: nil,
            screen_state: %{},
            board_list: nil,
            current_board: nil,
            current_thread: nil,
            current_thread_list: nil,
            posts: nil,
            read_position: %{},
            composer_draft: nil,
            register_wizard: nil,
            verify_state: nil,
            subscribed_topics: MapSet.new()

  # --- Raxol callbacks ---

  @impl true
  def init(context) do
    # When started via Raxol.Core.Runtime.Lifecycle.start_link/2, the map
    # passed to init/1 is %{width:, height:, options: [all_lifecycle_opts]}.
    # Our custom context is stored under the :context key in those options.
    # When called directly in tests, context may carry :session_context at the
    # top level — we support both to keep tests working unchanged.
    {session_context, terminal_size} = extract_context(context)

    user = session_context[:user]
    session_pid = session_context[:session_pid]

    # Register TUI pid with the Session so it can receive replace/heartbeat msgs.
    if is_pid(session_pid) do
      Foglet.Sessions.Session.set_tui_pid(session_pid, self())
    end

    screen = if user, do: :main_menu, else: :login

    state = %__MODULE__{
      current_screen: screen,
      current_user: user,
      session_context: session_context,
      session_pid: session_pid,
      terminal_size: terminal_size
    }

    {:ok, state}
  end

  # Extract session_context + terminal_size from either:
  #   (a) Lifecycle-produced map: %{width:, height:, options: [context: %{...}]}
  #   (b) Direct test call: %{session_context: %{...}, terminal_size: {w, h}}
  defp extract_context(context) do
    if is_map(context) and is_list(Map.get(context, :options)) do
      # Lifecycle path — context is in options[:context]
      opts = Map.get(context, :options, [])
      nested = Keyword.get(opts, :context, %{})
      session_context = Map.get(nested, :session_context, %{})
      w = Map.get(context, :width, 80)
      h = Map.get(context, :height, 24)
      terminal_size = Map.get(nested, :terminal_size, {w, h})
      {session_context, terminal_size}
    else
      # Direct/test path — session_context at top level
      session_context = Map.get(context, :session_context, %{})
      terminal_size = Map.get(context, :terminal_size, {80, 24})
      {session_context, terminal_size}
    end
  end

  @impl true
  def update(message, state) do
    do_update(normalize_message(message), state)
  end

  # Pass Raxol %Event{} key structs through as {:key, event_data_map} so that
  # screens can pattern-match directly on the Raxol-native data shape.
  # Window events are still unpacked into a plain {width, height} tuple.
  defp normalize_message(%Raxol.Core.Events.Event{type: :key, data: data}) do
    {:key, data}
  end

  defp normalize_message(%Raxol.Core.Events.Event{type: :window, data: %{width: w, height: h}}) do
    {:window_change, w, h}
  end

  defp normalize_message(other), do: other

  @impl true
  def view(state) do
    if state.modal do
      render_modal_overlay(state.modal, state.terminal_size)
    else
      render_screen(state)
    end
  end

  # Renders the modal as the sole visible content, centered in the terminal.
  # This is not a true z-index overlay — the screen behind is suspended while
  # the modal is active — but it gives the user clear modal focus with no
  # Raxol widget-render surprises, and dismissal restores the screen unchanged.
  #
  # Design: a full-screen flex column (justify: :center centers the box
  # vertically; align: :center centers it horizontally) containing a
  # double-border box that holds the modal body.
  defp render_modal_overlay(modal, _terminal_size) do
    column justify: :center, align: :center do
      [
        box style: %{border: :double, padding: 1} do
          Widgets.Modal.render(modal)
        end
      ]
    end
  end

  @impl true
  def subscribe(state) do
    # Heartbeat tick — keeps last_seen_at fresh in the Session GenServer.
    # Only subscribed when a session_pid is wired (i.e., CLIHandler started us).
    heartbeat =
      if is_pid(state.session_pid) do
        [subscribe_interval(10_000, :heartbeat_tick)]
      else
        []
      end

    # PubSub subscriptions (Audit #12).
    #
    # Raxol's Lifecycle and Dispatcher do NOT route arbitrary Erlang messages
    # to update/2. Only messages wrapped as {:subscription, msg} by Raxol's own
    # timer infrastructure reach update/2.
    #
    # Solution: use Subscription.custom/2 with PubSubForwarder — a lightweight
    # GenServer that subscribes to the requested Phoenix.PubSub topics and
    # forwards each arriving message as {:subscription, msg} to the Dispatcher
    # process (context.pid, which is self() here in subscribe/1).
    #
    # This uses Raxol's documented "External data streams" custom subscription
    # API (Subscription.custom/2 → module.start_link(args, context)).
    pubsub_topics = build_pubsub_topics(state)

    pubsub_subs =
      if pubsub_topics != [] do
        [Subscription.custom(PubSubForwarder, %{topics: pubsub_topics})]
      else
        []
      end

    heartbeat ++ pubsub_subs
  end

  # Compute which PubSub topics to subscribe to based on current screen and user.
  # Topics follow the convention: "user:<id>", "boards", "board:<id>", "thread:<id>".
  # Phase 2 may not yet broadcast to all of these; subscriptions are wired now so
  # the TUI reacts automatically when Phase 2 starts emitting events.
  defp build_pubsub_topics(state) do
    topics =
      if state.current_user do
        ["user:#{state.current_user.id}"]
      else
        []
      end

    topics =
      if state.current_screen in [:board_list] do
        ["boards" | topics]
      else
        topics
      end

    topics =
      if state.current_screen in [:thread_list] and state.current_board do
        ["board:#{state.current_board.id}" | topics]
      else
        topics
      end

    topics =
      if state.current_screen in [:post_reader, :post_composer] and state.current_thread do
        ["thread:#{state.current_thread.id}" | topics]
      else
        topics
      end

    topics
  end

  # --- Private: update/2 dispatch ---

  defp do_update({:window_change, cols, rows}, state)
       when is_integer(cols) and is_integer(rows) and cols > 0 and rows > 0 do
    # SSH-06: terminal resize — also notify Session for presence/analytics.
    if is_pid(state.session_pid) do
      Foglet.Sessions.Session.set_terminal_size(state.session_pid, {cols, rows})
    end

    {%{state | terminal_size: {cols, rows}}, []}
  end

  defp do_update({:navigate, screen}, state) when is_atom(screen) do
    {%{state | current_screen: screen, modal: nil}, []}
  end

  defp do_update({:set_user, user}, state) do
    {%{state | current_user: user, current_screen: :main_menu}, []}
  end

  defp do_update({:show_modal, modal}, state) when is_map(modal) do
    {%{state | modal: modal}, []}
  end

  defp do_update(:dismiss_modal, state) do
    {%{state | modal: nil}, []}
  end

  # Confirm modal — invoke on_confirm or on_cancel callback if present.
  # Callbacks may return {:navigate, screen} or a full {state, commands} tuple.
  # If absent, just dismiss.
  defp do_update({:confirm_modal, answer}, state) do
    modal = state.modal
    cleared = %{state | modal: nil}

    callback_key = if answer == :yes, do: :on_confirm, else: :on_cancel
    callback = modal && Map.get(modal, callback_key)

    case callback do
      nil ->
        {cleared, []}

      :dismiss_modal ->
        {cleared, []}

      fun when is_function(fun, 1) ->
        result = fun.(cleared)

        case result do
          {%__MODULE__{} = new_state, cmds} when is_list(cmds) ->
            {new_state, wrap_commands(cmds)}

          msg ->
            do_update(msg, cleared)
        end
    end
  end

  defp do_update({:key, key_event}, state) do
    if state.modal != nil do
      # Modal is active: route key directly to global_key_handler, which
      # contains all modal dismiss / confirm logic. Never delegate to the
      # screen module while a modal is open — screen handlers don't check
      # state.modal and will consume the key silently.
      global_key_handler(key_event, state)
    else
      screen_module = screen_module_for(state.current_screen)

      case screen_module.handle_key(key_event, state) do
        {:update, new_state, commands} ->
          # process_screen_commands/2 converts I/O dispatch tuples returned by
          # screens (e.g. {:load_boards}, {:load_threads, id}) into real
          # Command.task structs by routing them through their do_update/2 clauses,
          # which have access to the current state (user, session_context, domain
          # overrides). Plain %Command{} structs pass through unchanged.
          process_screen_commands(new_state, commands)

        :no_match ->
          global_key_handler(key_event, state)
      end
    end
  end

  defp do_update({:register_wizard, event}, state) do
    # Delegated from register screen during wizard transitions.
    Screens.Register.handle_wizard_event(event, state)
  end

  defp do_update({:verify_event, event}, state) do
    Screens.Verify.handle_verify_event(event, state)
  end

  # I/O commands — each spawns a real off-process task that performs the DB work
  # and returns a typed result message back to update/2 (Audit #11).
  # Previously these wrapped the tuple in a no-op Command.task that returned
  # the tuple unchanged, causing the DB call to run synchronously on the
  # Lifecycle process inside update/2 instead of off-process.

  defp do_update({:load_boards}, state) do
    # Snapshot what we need inside the closure so we don't capture the whole state.
    user = state.current_user
    ctx = Map.get(state, :session_context) || %{}
    boards_mod = get_in(ctx, [:domain, :boards]) || Foglet.Boards

    task =
      Command.task(fn ->
        {:boards_loaded, boards_mod.list_subscribed_boards(user)}
      end)

    {state, [task]}
  end

  defp do_update({:boards_loaded, boards}, state) do
    {%{state | board_list: boards}, []}
  end

  defp do_update({:load_boards_for_new_thread}, state) do
    user = state.current_user
    ctx = Map.get(state, :session_context) || %{}
    boards_mod = get_in(ctx, [:domain, :boards]) || Foglet.Boards

    task =
      Command.task(fn ->
        {:boards_for_new_thread_loaded, boards_mod.list_subscribed_boards(user)}
      end)

    {state, [task]}
  end

  defp do_update({:boards_for_new_thread_loaded, boards}, state) do
    ss =
      get_in(state.screen_state, [:new_thread]) ||
        Foglet.TUI.Screens.NewThread.init_screen_state()

    new_ss = %{ss | boards: boards}
    new_screen_state = Map.put(state.screen_state, :new_thread, new_ss)
    {%{state | screen_state: new_screen_state}, []}
  end

  defp do_update({:load_threads, board_id}, state) do
    ctx = Map.get(state, :session_context) || %{}
    threads_mod = get_in(ctx, [:domain, :threads]) || Foglet.Threads
    user_id = state.current_user && state.current_user.id

    task =
      Command.task(fn ->
        {:threads_loaded, load_threads_for_user(threads_mod, board_id, user_id)}
      end)

    {state, [task]}
  end

  defp load_threads_for_user(threads_mod, board_id, user_id) do
    cond do
      function_exported?(threads_mod, :list_threads, 2) ->
        threads_mod.list_threads(board_id, user_id)

      function_exported?(threads_mod, :list_threads, 1) ->
        threads_mod.list_threads(board_id)
        |> Enum.map(fn t ->
          case t do
            %Foglet.Threads.Thread{} ->
              t |> Map.from_struct() |> Map.put(:has_unread, false)

            %{} ->
              Map.put_new(t, :has_unread, false)
          end
        end)

      true ->
        []
    end
  end

  defp do_update({:threads_loaded, threads}, state) do
    {%{state | current_thread_list: threads}, []}
  end

  defp do_update({:load_posts, thread_id}, state) do
    ctx = Map.get(state, :session_context) || %{}
    posts_mod = get_in(ctx, [:domain, :posts]) || Foglet.Posts

    task =
      Command.task(fn ->
        {:posts_loaded, posts_mod.list_posts(thread_id)}
      end)

    {state, [task]}
  end

  defp do_update({:posts_loaded, posts}, state) do
    {%{state | posts: posts}, []}
  end

  defp do_update({:flush_read_pointers, ctx}, state) do
    # Flush runs off-process so it doesn't block the UI on the way out of a thread.
    sc = Map.get(state, :session_context) || %{}
    boards_mod = get_in(sc, [:domain, :boards]) || Foglet.Boards
    threads_mod = get_in(sc, [:domain, :threads]) || Foglet.Threads
    user_id = ctx[:user_id] || (state.current_user && state.current_user.id)

    task = Command.task(fn -> flush_read_pointers_task(ctx, user_id, boards_mod, threads_mod) end)
    {state, [task]}
  end

  defp do_update({:read_pointers_flushed, thread_id}, state) do
    new_rp =
      if thread_id, do: Map.delete(state.read_position, thread_id), else: state.read_position

    new_state = %{state | read_position: new_rp}

    if new_state.current_screen == :board_list do
      do_update({:load_boards}, new_state)
    else
      {new_state, []}
    end
  end

  # PubSub message handlers (Audit #12).
  # These messages arrive via PubSubForwarder → {:subscription, msg} → Dispatcher
  # → update/2. Phase 2 may not yet emit all of these; the handlers are wired now
  # so real-time updates work as soon as Phase 2 starts broadcasting.

  # Board-level activity (new post, read-pointer changes) — refresh board list
  # to update unread counts if the user is on the board_list screen.
  defp do_update({:board_activity, _board_id, _event}, state)
       when state.current_screen == :board_list do
    # Delegate to {:load_boards} which will spawn its own real task.
    do_update({:load_boards}, state)
  end

  defp do_update({:board_activity, _board_id, _event}, state), do: {state, []}

  # Thread-level activity (new post) — refresh posts if the user is reading it.
  defp do_update({:thread_activity, thread_id, _event}, state)
       when state.current_screen == :post_reader do
    current_thread_id = state.current_thread && state.current_thread.id

    if current_thread_id == thread_id do
      # Delegate to {:load_posts, thread_id} which spawns a real task.
      do_update({:load_posts, thread_id}, state)
    else
      {state, []}
    end
  end

  defp do_update({:thread_activity, _thread_id, _event}, state), do: {state, []}

  # User-level notifications — show a modal badge.
  defp do_update({:notification, _user_id, kind, payload}, state) do
    modal = %{
      type: :info,
      message: format_notification(kind, payload)
    }

    {%{state | modal: modal}, []}
  end

  # Heartbeat — keep last_seen_at alive in the Session GenServer.
  defp do_update(:heartbeat_tick, state) do
    if is_pid(state.session_pid) do
      Foglet.Sessions.Session.heartbeat(state.session_pid)
    end

    {state, []}
  end

  # A new SSH connection for the same user replaced this session.
  # Show a notice modal and quit cleanly.
  defp do_update({:session_replaced, _user_id}, state) do
    modal = %{
      type: :warning,
      message: "Your session was replaced by a new connection. Goodbye."
    }

    {%{state | modal: modal}, [Command.quit()]}
  end

  # TUI login screen authenticated a user — promote the guest session.
  # Routes through the Supervisor so one-session-per-user (SSH-05 / D-25) is
  # enforced: any pre-existing session for this user is replaced before this
  # guest pid registers under the user_id key.
  defp do_update({:promote_session, user}, state) do
    if is_pid(state.session_pid) do
      Foglet.Sessions.Supervisor.promote_guest_session(state.session_pid, user)
    end

    {%{state | current_user: user, current_screen: :main_menu}, []}
  end

  defp do_update({:command_result, inner}, state) do
    # Raxol's Command.task runtime wraps every task return value in
    # {:command_result, inner} before delivering to update/2 (Audit #11 follow-up).
    # Re-dispatch so all existing result handlers (:boards_loaded, :threads_loaded,
    # :posts_loaded, :read_pointers_flushed, etc.) fire correctly.
    do_update(inner, state)
  end

  # After the user dismisses the pending-approval modal, quit the session so the
  # pending user cannot continue navigating the BBS. The modal is already set
  # by Register.submit/2; we patch its on_confirm/on_cancel callbacks here so
  # either dismiss path issues Command.quit().
  defp do_update({:terminate_after_modal, _reason}, state) do
    modal =
      if state.modal do
        Map.merge(state.modal, %{
          on_confirm: fn s -> {s, [Command.quit()]} end,
          on_cancel: fn s -> {s, [Command.quit()]} end
        })
      else
        %{
          type: :info,
          message: "Session will now close.",
          on_confirm: fn s -> {s, [Command.quit()]} end,
          on_cancel: fn s -> {s, [Command.quit()]} end
        }
      end

    {%{state | modal: modal}, []}
  end

  defp do_update(_other, state) do
    # Unknown messages pass through unchanged.
    {state, []}
  end

  # Helpers for {:flush_read_pointers, ctx} task closure — extracted to keep
  # the do_update clause within credo's cyclomatic complexity limit.
  defp flush_read_pointers_task(ctx, user_id, boards_mod, threads_mod) do
    maybe_flush_board_pointer(boards_mod, user_id, ctx)
    maybe_flush_thread_pointer(threads_mod, user_id, ctx)
    {:read_pointers_flushed, ctx[:thread_id]}
  end

  defp maybe_flush_board_pointer(boards_mod, user_id, ctx) do
    if ctx[:board_id] && user_id do
      boards_mod.advance_board_read_pointer(
        user_id,
        ctx[:board_id],
        ctx[:last_read_message_number] || 0
      )
    end
  end

  defp maybe_flush_thread_pointer(threads_mod, user_id, ctx) do
    if ctx[:thread_id] && user_id do
      threads_mod.advance_thread_read_pointer(user_id, ctx[:thread_id], ctx[:last_read_post_id])
    end
  end

  defp format_notification(:dm, %{body: body}), do: "New message: #{body}"
  defp format_notification(:mention, %{thread_title: t}), do: "You were mentioned in: #{t}"
  defp format_notification(kind, _payload), do: "Notification: #{kind}"

  # Process the command list returned by a screen's handle_key/2.
  # Plain %Command{} structs pass through to Raxol unchanged. {:terminate, _}
  # becomes Command.quit(). Every other atom-keyed tuple is routed through
  # do_update/2 so it gets the same state access as a top-level update call —
  # this covers both I/O tuples ({:load_boards}, {:load_posts, id}, ...) and
  # state-transition tuples ({:promote_session, user}, {:register_wizard, ev}).
  # Unknown messages hit do_update/2's catch-all and become a no-op.
  defp process_screen_commands(state, commands) do
    Enum.reduce(commands, {state, []}, fn cmd, {acc_state, acc_cmds} ->
      case cmd do
        %Command{} ->
          {acc_state, acc_cmds ++ [cmd]}

        {:terminate, _} ->
          {acc_state, acc_cmds ++ [Command.quit()]}

        tuple when is_tuple(tuple) and tuple_size(tuple) >= 1 and is_atom(elem(tuple, 0)) ->
          {next_state, new_cmds} = do_update(tuple, acc_state)
          {next_state, acc_cmds ++ new_cmds}

        other ->
          require Logger
          Logger.warning("[TUI.App] unexpected command from screen: #{inspect(other)}")
          {acc_state, acc_cmds}
      end
    end)
  end

  defp render_screen(state) do
    screen_module_for(state.current_screen).render(state)
  end

  # Modal key dismissal — takes precedence over screen-level and global handlers.
  # :confirm modals route Y/N to {:confirm_modal, :yes/:no}.
  # :info/:error/:warning modals dismiss on Enter, Escape, or Space.
  defp global_key_handler(key, %{modal: modal} = state) when not is_nil(modal) do
    modal_type = Map.get(modal, :type, :info)
    handle_modal_key(modal_type, key, state)
  end

  # "q" is a typed character in Raxol's native event shape: %{key: :char, char: "q"}
  defp global_key_handler(%{key: :char, char: "q"}, state) when state.current_screen == :login do
    {state, [Command.quit()]}
  end

  defp global_key_handler(_key, state), do: {state, []}

  # :confirm modal — Y/y confirm, N/n/Escape cancel
  defp handle_modal_key(:confirm, %{key: :char, char: c}, state) when c in ["y", "Y"] do
    do_update({:confirm_modal, :yes}, state)
  end

  defp handle_modal_key(:confirm, %{key: :char, char: c}, state) when c in ["n", "N"] do
    do_update({:confirm_modal, :no}, state)
  end

  defp handle_modal_key(:confirm, %{key: :escape}, state) do
    do_update({:confirm_modal, :no}, state)
  end

  # :info/:error/:warning modals — dismiss on Enter, Escape, or Space (spacebar)
  defp handle_modal_key(type, %{key: :enter}, state) when type in [:info, :error, :warning] do
    do_update(:dismiss_modal, state)
  end

  defp handle_modal_key(type, %{key: :escape}, state) when type in [:info, :error, :warning] do
    do_update(:dismiss_modal, state)
  end

  defp handle_modal_key(type, %{key: :char, char: " "}, state)
       when type in [:info, :error, :warning] do
    do_update(:dismiss_modal, state)
  end

  defp handle_modal_key(_type, _key, state), do: {state, []}

  # wrap_commands/wrap_command are used only for modal callback results, which
  # return full %Command{} structs or {:terminate, reason}. Screen handle_key/2
  # I/O dispatch tuples are handled by process_screen_commands/2 above, which
  # routes them through do_update/2 to get real Command.task closures with
  # proper state access (user, session_context, domain overrides).
  defp wrap_commands(commands), do: Enum.map(commands, &wrap_command/1)

  defp wrap_command({:terminate, _reason}), do: Command.quit()
  defp wrap_command(%Command{} = cmd), do: cmd
  defp wrap_command(other), do: other

  defp screen_module_for(:login), do: Screens.Login
  defp screen_module_for(:register), do: Screens.Register
  defp screen_module_for(:verify), do: Screens.Verify
  defp screen_module_for(:main_menu), do: Screens.MainMenu
  defp screen_module_for(:board_list), do: Screens.BoardList
  defp screen_module_for(:thread_list), do: Screens.ThreadList
  defp screen_module_for(:post_reader), do: Screens.PostReader
  defp screen_module_for(:post_composer), do: Screens.PostComposer
  defp screen_module_for(:new_thread), do: Screens.NewThread
end
