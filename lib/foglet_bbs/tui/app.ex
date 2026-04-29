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

  alias Foglet.Accounts
  alias Foglet.PubSub
  alias Foglet.TUI.Context
  alias Foglet.TUI.Effect
  alias Foglet.TUI.PubSubForwarder
  alias Foglet.TUI.Screens
  alias Foglet.TUI.Screens.PostComposer
  alias Foglet.TUI.Screens.PostReader
  alias Foglet.TUI.Screens.ThreadList
  alias Foglet.TUI.SizeGate
  alias Foglet.TUI.Theme
  alias Foglet.TUI.Widgets
  alias Foglet.TUI.Widgets.Modal.Form, as: ModalForm
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
          | :account
          | :moderation
          | :sysop

  @type t :: %__MODULE__{
          current_screen: screen(),
          current_user: Foglet.Accounts.User.t() | nil,
          session_context: Foglet.TUI.SessionContext.t() | map(),
          session_pid: pid() | nil,
          terminal_size: {pos_integer(), pos_integer()},
          route_params: map(),
          modal: Foglet.TUI.Modal.t() | nil,
          screen_state: map(),
          board_list: list() | nil,
          # Phase 39 cleanup: these legacy App fields remain for unmigrated
          # flows/tests but are not sources of truth for Phase 37 screens.
          current_board: map() | nil,
          current_thread: ThreadEntry.t() | nil,
          current_thread_list: list() | nil,
          posts: list() | nil,
          read_position: map(),
          composer_draft: String.t() | nil
        }

  defstruct current_screen: :login,
            current_user: nil,
            session_context: %Foglet.TUI.SessionContext{},
            session_pid: nil,
            terminal_size: {80, 24},
            route_params: %{},
            modal: nil,
            screen_state: %{},
            board_list: nil,
            # Phase 39 cleanup: legacy shell fields kept for screens that have
            # not completed the reducer migration; Phase 37 screens own this data.
            current_board: nil,
            current_thread: nil,
            current_thread_list: nil,
            posts: nil,
            read_position: %{},
            composer_draft: nil

  @doc """
  Returns the current route value.

  During the Phase 34 transition App still stores the route screen in
  `current_screen`; route params are stored separately so legacy screens can
  continue to receive an atom route until their migration phase.
  """
  @spec current_route(t()) :: atom() | {atom(), map()}
  def current_route(%__MODULE__{current_screen: screen, route_params: params})
      when is_map(params) and map_size(params) > 0 do
    {screen, params}
  end

  def current_route(%__MODULE__{current_screen: screen}), do: screen

  @doc "Returns the storage key for a screen route."
  @spec screen_key(atom() | {atom(), map()}) :: atom()
  def screen_key({screen, _params}), do: screen
  def screen_key(screen) when is_atom(screen), do: screen

  @doc "Returns the local state for the current screen key."
  @spec current_screen_state(t()) :: term()
  def current_screen_state(%__MODULE__{} = state) do
    screen_state_for(state, screen_key(current_route(state)))
  end

  @doc "Returns screen-local state stored under `key`."
  @spec screen_state_for(t(), term()) :: term()
  def screen_state_for(%__MODULE__{screen_state: screen_state}, key) do
    Map.get(screen_state || %{}, key)
  end

  @doc "Stores screen-local state under `key` without changing legacy App fields."
  @spec put_screen_state(t(), term(), term()) :: t()
  def put_screen_state(%__MODULE__{} = state, key, local_state) do
    %{state | screen_state: Map.put(state.screen_state || %{}, key, local_state)}
  end

  @doc "Builds the narrow runtime context passed to new screen reducers."
  @spec build_context(t()) :: Context.t()
  def build_context(%__MODULE__{} = state) do
    build_context(state, state.route_params || %{})
  end

  @doc "Builds a screen context with explicit route params."
  @spec build_context(t(), map()) :: Context.t()
  def build_context(%__MODULE__{} = state, route_params) when is_map(route_params) do
    Context.new(
      current_user: state.current_user,
      session_context: state.session_context,
      session_pid: state.session_pid,
      terminal_size: state.terminal_size,
      route: state.current_screen,
      route_params: route_params,
      domain: domain_from_session_context(state.session_context)
    )
  end

  @doc "Interprets one Phase 34 runtime effect."
  @spec apply_effect(t(), Effect.t()) :: {t(), [Command.t()]}
  def apply_effect(%__MODULE__{} = state, %Effect{
        type: :navigate,
        payload: %{screen: screen, params: params}
      }) do
    state =
      state
      |> Map.put(:current_screen, screen)
      |> Map.put(:route_params, params || %{})
      |> Map.put(:modal, nil)
      |> maybe_seed_legacy_route_context(screen, params || %{})
      |> init_route_screen_state(screen, params || %{})

    maybe_dispatch_route_entry(state, screen, params || %{})
  end

  def apply_effect(%__MODULE__{} = state, %Effect{type: :modal, payload: {:open, modal}}) do
    {%{state | modal: modal}, []}
  end

  def apply_effect(%__MODULE__{} = state, %Effect{type: :modal, payload: :dismiss}) do
    {%{state | modal: nil}, []}
  end

  def apply_effect(%__MODULE__{} = state, %Effect{type: :session, payload: {:set_user, user}}) do
    update({:set_user, user}, state)
  end

  def apply_effect(%__MODULE__{} = state, %Effect{
        type: :session,
        payload: {:set_current_user, user}
      }) do
    {%{state | current_user: user}, []}
  end

  def apply_effect(%__MODULE__{} = state, %Effect{
        type: :session,
        payload: {:update_preferences, snapshot}
      }) do
    state =
      state
      |> merge_session_preferences(snapshot)
      |> refresh_session_preferences(snapshot)

    {state, []}
  end

  def apply_effect(%__MODULE__{} = state, %Effect{
        type: :session,
        payload: {:dispatch, message}
      }) do
    do_update(message, state)
  end

  def apply_effect(%__MODULE__{session_pid: session_pid} = state, %Effect{
        type: :session,
        payload: message
      }) do
    if is_pid(session_pid), do: send(session_pid, message)

    {state, []}
  end

  def apply_effect(%__MODULE__{} = state, %Effect{
        type: :terminal,
        payload: {:size, {cols, rows}}
      }) do
    update({:window_change, cols, rows}, state)
  end

  def apply_effect(%__MODULE__{} = state, %Effect{
        type: :publish,
        payload: %{topic: topic, message: message}
      }) do
    _ = Phoenix.PubSub.broadcast(FogletBbs.PubSub, topic, message)

    {state, []}
  end

  def apply_effect(%__MODULE__{} = state, %Effect{type: :quit}) do
    {state, [Command.quit()]}
  end

  def apply_effect(%__MODULE__{} = state, %Effect{
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
  @spec apply_effects(t(), [Effect.t()]) :: {t(), [Command.t()]}
  def apply_effects(%__MODULE__{} = state, effects) when is_list(effects) do
    Enum.reduce(effects, {state, []}, fn effect, {acc_state, acc_cmds} ->
      {next_state, cmds} = apply_effect(acc_state, effect)
      {next_state, acc_cmds ++ cmds}
    end)
  end

  # --- Raxol callbacks ---

  @impl true
  def init(context) do
    # When started via Raxol.Core.Runtime.Lifecycle.start_link/2, the map
    # passed to init/1 is %{width:, height:, options: [all_lifecycle_opts]}.
    # Our custom context is stored under the :context key in those options.
    # When called directly in tests, context may carry :session_context at the
    # top level — we support both to keep tests working unchanged.
    {session_context, terminal_size} = extract_context(context)

    user = Map.get(session_context, :user)
    session_pid = Map.get(session_context, :session_pid)

    # Register TUI pid with the Session so it can receive replace/heartbeat msgs.
    if is_pid(session_pid) do
      Foglet.Sessions.Session.set_tui_pid(session_pid, self())
    end

    screen = initial_screen(user)

    state =
      %__MODULE__{
        current_screen: screen,
        current_user: user,
        session_context: session_context,
        session_pid: session_pid,
        terminal_size: terminal_size
      }
      |> maybe_init_initial_screen_state()

    {:ok, state}
  end

  defp initial_screen(nil), do: :login
  defp initial_screen(user), do: Accounts.post_login_screen(user)

  # Extract session_context + terminal_size from either:
  #   (a) Lifecycle-produced map: %{width:, height:, options: [context: %{...}]}
  #   (b) Direct test call: %{session_context: %SessionContext{} | %{...}, terminal_size: {w, h}}
  #
  # The session_context value may be a `%Foglet.TUI.SessionContext{}` struct
  # (the production path via SSH.CLIHandler) or a plain map (tests and legacy
  # callers). Both are accepted so that test helpers can pass partial maps
  # without constructing a full struct.
  defp extract_context(context) do
    if is_map(context) and is_list(Map.get(context, :options)) do
      # Lifecycle path — context is in options[:context]
      opts = Map.get(context, :options, [])
      nested = Keyword.get(opts, :context, %{})
      session_context = Map.get(nested, :session_context, %Foglet.TUI.SessionContext{})
      w = Map.get(context, :width, 80)
      h = Map.get(context, :height, 24)
      terminal_size = Map.get(nested, :terminal_size, {w, h})
      {session_context, terminal_size}
    else
      # Direct/test path — session_context at top level
      session_context = Map.get(context, :session_context, %Foglet.TUI.SessionContext{})
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
  # Window and resize events are still unpacked into a plain
  # {width, height} tuple.
  defp normalize_message(%Raxol.Core.Events.Event{type: :key, data: data}) do
    {:key, data}
  end

  defp normalize_message(%Raxol.Core.Events.Event{type: :window, data: %{width: w, height: h}}) do
    {:window_change, w, h}
  end

  defp normalize_message(%Raxol.Core.Events.Event{type: :resize, data: %{width: w, height: h}}) do
    {:window_change, w, h}
  end

  defp normalize_message(other), do: other

  @impl true
  def view(state) do
    cond do
      SizeGate.too_small?(state) ->
        # FRAME-03 / D-04: render-time gate bypasses ScreenFrame entirely.
        # No outer border, no StatusBar, no KeyBar on the too-small screen.
        # State is never modified — current_screen / screen_state / modal
        # are all preserved for when the terminal resizes back.
        SizeGate.render(state)

      state.modal ->
        render_modal_overlay(state.modal, state)

      true ->
        render_screen(state)
    end
  end

  # Renders the modal as the sole visible content, centered in the terminal.
  # Extracts theme from state.session_context and passes it through to the
  # theme-aware Modal.render/2 (Phase 7 thin adapter, D-08).
  #
  # Modal.Form-backed :form modal callers (future) MUST pass `show_footer: true`
  # to `Modal.Form.init/1` so the [Enter] Submit / [Esc] Cancel footer is
  # advertised inside the centered overlay box (Phase 28 D-06). Inline tab-body
  # consumers (Account Profile/Prefs, Sysop Site) MUST omit the option (default
  # false) so the global command bar is the single advertiser of those keys.
  defp render_modal_overlay(modal, state) do
    theme = Theme.from_state(state)

    column justify: :center, align: :center do
      [
        box style: %{border: :double, padding: 1, border_fg: theme.border.fg} do
          Widgets.Modal.render(modal, theme)
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

    clock =
      if state.current_user do
        [subscribe_interval(60_000, :main_menu_clock_tick)]
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

    heartbeat ++ clock ++ pubsub_subs
  end

  # Compute which PubSub topics to subscribe to based on current screen and user.
  # Topics follow the convention: "user:<id>", "boards", "board:<id>", "thread:<id>".
  # Phase 2 may not yet broadcast to all of these; subscriptions are wired now so
  # the TUI reacts automatically when Phase 2 starts emitting events.
  defp build_pubsub_topics(state) do
    topics =
      if state.current_user do
        [PubSub.user_topic(state.current_user.id)]
      else
        []
      end

    topics =
      if state.current_screen in [:board_list] do
        [PubSub.boards_aggregate() | topics]
      else
        topics
      end

    topics =
      case thread_list_board_topic(state) do
        nil -> topics
        topic -> [topic | topics]
      end

    topics =
      case routed_thread_topic(state) do
        nil -> topics
        topic -> [topic | topics]
      end

    topics
  end

  defp routed_thread_topic(%__MODULE__{current_screen: screen} = state)
       when screen in [:post_reader, :post_composer] do
    state
    |> routed_thread_id()
    |> case do
      thread_id when is_binary(thread_id) -> PubSub.thread_topic(thread_id)
      _other -> nil
    end
  end

  defp routed_thread_topic(_state), do: nil

  defp routed_thread_id(%__MODULE__{} = state) do
    params = state.route_params || %{}

    Map.get(params, :thread_id) || Map.get(params, "thread_id") ||
      post_reader_state_thread_id(state.screen_state) ||
      post_composer_state_thread_id(state.screen_state)
  end

  defp post_reader_state_thread_id(screen_state) do
    case Map.get(screen_state || %{}, :post_reader) do
      %PostReader.State{thread_id: thread_id} when is_binary(thread_id) -> thread_id
      _other -> nil
    end
  end

  defp post_composer_state_thread_id(screen_state) do
    case Map.get(screen_state || %{}, :post_composer) do
      %PostComposer.State{} = state ->
        case Map.get(state, :thread_id) do
          thread_id when is_binary(thread_id) -> thread_id
          _other -> nil
        end

      _other ->
        nil
    end
  end

  defp thread_list_board_topic(%__MODULE__{current_screen: :thread_list} = state) do
    state
    |> thread_list_board_id()
    |> case do
      nil -> nil
      board_id -> PubSub.board_topic(board_id)
    end
  end

  defp thread_list_board_topic(_state), do: nil

  defp thread_list_board_id(%__MODULE__{} = state) do
    params = state.route_params || %{}

    Map.get(params, :board_id) || Map.get(params, "board_id") ||
      thread_list_state_board_id(state.screen_state)
  end

  defp thread_list_state_board_id(screen_state) do
    case Map.get(screen_state || %{}, :thread_list) do
      %ThreadList.State{board_id: board_id} when is_binary(board_id) -> board_id
      _other -> nil
    end
  end

  # --- Private: update/2 dispatch ---

  defp do_update({:window_change, cols, rows}, state)
       when is_integer(cols) and is_integer(rows) and cols > 0 and rows > 0 do
    # D-09: same-size guard — short-circuit bursty SIGWINCH events at the
    # same terminal size to avoid render storms during tmux/iTerm drags.
    # Raxol coalesces frame renders so no time-based debounce is needed
    # (D-10); this guard is sufficient per research Pitfall 4.
    if state.terminal_size == {cols, rows} do
      {state, []}
    else
      # SSH-06: terminal resize — also notify Session for presence/analytics.
      if is_pid(state.session_pid) do
        Foglet.Sessions.Session.set_terminal_size(state.session_pid, {cols, rows})
      end

      {%{state | terminal_size: {cols, rows}}, []}
    end
  end

  defp do_update({:navigate, screen}, state) when is_atom(screen) do
    apply_effect(state, Effect.navigate(screen, %{}))
  end

  defp do_update({:set_user, user}, state) do
    route_screen_update(
      %{
        state
        | current_user: user,
          current_screen: :main_menu,
          route_params: %{}
      },
      :main_menu,
      :load_oneliners
    )
  end

  defp do_update({:show_modal, modal}, state) when is_struct(modal, Foglet.TUI.Modal) do
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
    cond do
      SizeGate.too_small?(state) ->
        # D-11: swallow keys entirely while gated. Screens behind the gate
        # are hidden — we must not let their handle_key/2 silently mutate
        # state (e.g., scroll a list, advance a cursor, consume a char).
        # D-12: Ctrl+C / EOF reach CLIHandler at the SSH channel layer
        # independently of update/2, so disconnect still works.
        {state, []}

      state.modal != nil ->
        # Modal is active: route key directly to global_key_handler, which
        # contains all modal dismiss / confirm logic. Never delegate to the
        # screen module while a modal is open — screen handlers don't check
        # state.modal and will consume the key silently.
        global_key_handler(key_event, state)

      new_contract_screen?(state, state.current_screen) ->
        route_screen_update(state, screen_key(current_route(state)), {:key, key_event})

      true ->
        screen_module = screen_module_for(state.current_screen)

        case :erlang.apply(screen_module, :handle_key, [key_event, state]) do
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

  # PubSub message handlers (Audit #12).
  # These messages arrive via PubSubForwarder → {:subscription, msg} → Dispatcher
  # → update/2. Phase 2 may not yet emit all of these; the handlers are wired now
  # so real-time updates work as soon as Phase 2 starts broadcasting.

  # Board-level activity (new post, read-pointer changes) — refresh board list
  # to update unread counts if the user is on the board_list screen.
  defp do_update({:board_activity, _board_id, _event}, state)
       when state.current_screen == :board_list do
    route_screen_update(state, :board_list, :load)
  end

  defp do_update({:board_activity, _board_id, _event}, state), do: {state, []}

  # Thread-level activity (new post) — refresh posts if the user is reading it.
  defp do_update({:thread_activity, thread_id, event}, state)
       when state.current_screen == :post_reader do
    route_screen_update(state, :post_reader, {:thread_activity, thread_id, event})
  end

  defp do_update({:thread_activity, _thread_id, _event}, state), do: {state, []}

  # User-level notifications — show a modal badge.
  defp do_update({:notification, _user_id, kind, payload}, state) do
    modal = %Foglet.TUI.Modal{
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

  defp do_update(:main_menu_clock_tick, state), do: {state, []}

  # A new SSH connection for the same user replaced this session.
  # Show a notice modal and quit cleanly.
  defp do_update({:session_replaced, _user_id}, state) do
    modal = %Foglet.TUI.Modal{
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

    route_screen_update(
      %{
        state
        | current_user: user,
          current_screen: :main_menu,
          route_params: %{}
      },
      :main_menu,
      :load_oneliners
    )
  end

  defp do_update({:command_result, inner}, state) do
    # Raxol's Command.task runtime wraps every task return value in
    # {:command_result, inner} before delivering to update/2 (Audit #11 follow-up).
    # Re-dispatch so all existing result handlers (:boards_loaded, :threads_loaded,
    # :posts_loaded, :read_pointers_flushed, etc.) fire correctly.
    do_update(inner, state)
  end

  defp do_update({:screen_task_result, key, op, result}, state) do
    route_screen_update(state, key, {:task_result, op, result})
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
        %Foglet.TUI.Modal{
          type: :info,
          message: "Session will now close.",
          on_confirm: fn s -> {s, [Command.quit()]} end,
          on_cancel: fn s -> {s, [Command.quit()]} end
        }
      end

    {%{state | modal: modal}, []}
  end

  defp do_update({:task_error, op, reason}, state) do
    require Logger
    Logger.error("[TUI.App] task #{inspect(op)} failed: #{reason}")

    modal = %Foglet.TUI.Modal{
      type: :error,
      message: "Something went wrong while trying to #{humanize_op(op)}. Please try again."
    }

    {%{state | modal: modal}, []}
  end

  defp do_update(_other, state) do
    # Unknown messages pass through unchanged.
    {state, []}
  end

  defp domain_from_session_context(session_context) when is_map(session_context) do
    case Map.get(session_context, :domain) do
      domain when is_map(domain) -> domain
      _ -> %{}
    end
  end

  defp domain_from_session_context(_session_context), do: %{}

  defp init_route_screen_state(%__MODULE__{} = state, screen, params) do
    key = screen_key(screen)
    module = screen_module_for(state, key)

    cond do
      route_owned_screen?(key) and Code.ensure_loaded?(module) and
          function_exported?(module, :init, 1) ->
        put_screen_state(state, key, module.init(build_context(state, params)))

      screen_state_for(state, key) != nil ->
        state

      Code.ensure_loaded?(module) and function_exported?(module, :init, 1) ->
        put_screen_state(state, key, module.init(build_context(state, params)))

      true ->
        state
    end
  end

  defp route_owned_screen?(key)
       when key in [:thread_list, :post_reader, :post_composer, :new_thread],
       do: true

  defp route_owned_screen?(_key), do: false

  defp maybe_seed_legacy_route_context(%__MODULE__{} = state, _screen, _params), do: state

  defp maybe_dispatch_route_entry(%__MODULE__{} = state, :main_menu, _params) do
    if state.current_user do
      route_screen_update(state, :main_menu, :load_oneliners)
    else
      {state, []}
    end
  end

  defp maybe_dispatch_route_entry(%__MODULE__{} = state, :moderation, _params) do
    if state.current_user do
      route_screen_update(state, :moderation, :load)
    else
      {state, []}
    end
  end

  defp maybe_dispatch_route_entry(%__MODULE__{} = state, :sysop, _params) do
    if state.current_user do
      route_screen_update(state, :sysop, :load)
    else
      {state, []}
    end
  end

  defp maybe_dispatch_route_entry(%__MODULE__{} = state, :thread_list, _params) do
    route_screen_update(state, :thread_list, :load)
  end

  defp maybe_dispatch_route_entry(%__MODULE__{} = state, :post_reader, params) do
    case route_param(params, :thread_id) do
      thread_id when is_binary(thread_id) -> route_screen_update(state, :post_reader, :load)
      _other -> {state, []}
    end
  end

  defp maybe_dispatch_route_entry(%__MODULE__{} = state, _screen, _params), do: {state, []}

  defp route_param(params, key) when is_map(params) do
    Map.get(params, key) || Map.get(params, Atom.to_string(key))
  end

  defp route_screen_update(%__MODULE__{} = state, key, message) do
    module = screen_module_for(state, key)

    if Code.ensure_loaded?(module) and function_exported?(module, :update, 3) do
      local_state = screen_state_for(state, key)
      context = context_for_screen_key(state, key)
      {new_local_state, effects} = module.update(message, local_state, context)

      state
      |> put_screen_state(key, new_local_state)
      |> apply_effects(List.wrap(effects))
    else
      {state, []}
    end
  end

  defp new_contract_screen?(%__MODULE__{} = state, screen) do
    module = screen_module_for(state, screen_key(screen))

    Code.ensure_loaded?(module) and function_exported?(module, :update, 3)
  end

  defp context_for_screen_key(%__MODULE__{} = state, key) do
    params =
      if screen_key(current_route(state)) == key do
        state.route_params
      else
        %{}
      end

    build_context(state, params)
  end

  defp maybe_init_initial_screen_state(%{current_screen: :main_menu, current_user: user} = state)
       when not is_nil(user) do
    main_menu_state =
      state
      |> build_context()
      |> Screens.MainMenu.init()
      |> Map.put(:oneliner_status, :idle)

    put_screen_state(state, :main_menu, main_menu_state)
  end

  defp maybe_init_initial_screen_state(%__MODULE__{} = state) do
    init_route_screen_state(state, state.current_screen, state.route_params)
  end

  defp take_screen_modal_submit do
    payload = Process.get({__MODULE__, :pending_screen_modal_submit})
    Process.delete({__MODULE__, :pending_screen_modal_submit})
    payload
  end

  defp humanize_op(op) when is_atom(op) do
    op |> to_string() |> String.replace("_", " ")
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

  defp format_notification(:dm, %{body: body}), do: "New message: #{body}"
  defp format_notification(:mention, %{thread_title: t}), do: "You were mentioned in: #{t}"
  defp format_notification(kind, _payload), do: "Notification: #{kind}"

  # Process the command list returned by a screen's handle_key/2.
  # Plain %Command{} structs pass through to Raxol unchanged. {:terminate, _}
  # becomes Command.quit(). Every other atom-keyed tuple is routed through
  # do_update/2 so it gets the same state access as a top-level update call.
  # This covers legacy I/O tuples ({:load_boards}, ...)
  # and state-transition tuples ({:promote_session, user}).
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
    key = screen_key(current_route(state))
    module = screen_module_for(state, key)

    if Code.ensure_loaded?(module) and function_exported?(module, :render, 2) do
      context = context_for_screen_key(state, key)
      module.render(render_local_state(state, key, module, context), context)
    else
      :erlang.apply(screen_module_for(state.current_screen), :render, [state])
    end
  end

  defp render_local_state(state, key, module, context) do
    case screen_state_for(state, key) do
      nil ->
        if function_exported?(module, :init, 1), do: module.init(context), else: nil

      local_state ->
        local_state
    end
  end

  # Modal key dismissal — takes precedence over screen-level and global handlers.
  # :confirm modals route Y/N to {:confirm_modal, :yes/:no}.
  # :info/:error/:warning modals dismiss on Enter, Escape, or Space.
  defp global_key_handler(key, %{modal: modal} = state) when not is_nil(modal) do
    modal_type = Map.get(modal, :type, :info)
    handle_modal_key(modal_type, key, state)
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

  defp handle_modal_key(
         :form,
         key,
         %{modal: %Foglet.TUI.Modal{message: %ModalForm{} = form}} = state
       ) do
    Process.delete({__MODULE__, :pending_screen_modal_submit})
    {new_form, action} = ModalForm.handle_event(key, form)
    state = %{state | modal: %{state.modal | message: new_form}}

    case action do
      :submitted ->
        case take_screen_modal_submit() do
          {screen_key, kind, payload} ->
            route_screen_update(state, screen_key, {:modal_submit, kind, payload})

          nil ->
            {state, []}
        end

      :cancelled ->
        do_update(:dismiss_modal, state)

      _other ->
        {state, []}
    end
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

  defp screen_module_for(%__MODULE__{} = state, screen) do
    case get_in(domain_from_session_context(state.session_context), [:screen_modules, screen]) do
      module when is_atom(module) and not is_nil(module) ->
        module

      _other ->
        if screen in known_screens() do
          screen_module_for(screen)
        else
          nil
        end
    end
  end

  defp known_screens do
    [
      :login,
      :register,
      :verify,
      :main_menu,
      :board_list,
      :thread_list,
      :post_reader,
      :post_composer,
      :new_thread,
      :account,
      :moderation,
      :sysop
    ]
  end

  defp screen_module_for(:login), do: Screens.Login
  defp screen_module_for(:register), do: Screens.Register
  defp screen_module_for(:verify), do: Screens.Verify
  defp screen_module_for(:main_menu), do: Screens.MainMenu
  defp screen_module_for(:board_list), do: Screens.BoardList
  defp screen_module_for(:thread_list), do: Screens.ThreadList
  defp screen_module_for(:post_reader), do: Screens.PostReader
  defp screen_module_for(:post_composer), do: Screens.PostComposer
  defp screen_module_for(:new_thread), do: Screens.NewThread
  defp screen_module_for(:account), do: Screens.Account
  defp screen_module_for(:moderation), do: Screens.Moderation
  defp screen_module_for(:sysop), do: Screens.Sysop
end
