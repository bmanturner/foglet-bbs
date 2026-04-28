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
  alias Foglet.Sessions.Preferences
  alias Foglet.Sessions.Session
  alias Foglet.TUI.Context
  alias Foglet.TUI.Effect
  alias Foglet.TUI.PubSubForwarder
  alias Foglet.TUI.Screens
  alias Foglet.TUI.Screens.Account.State, as: AccountState
  alias Foglet.TUI.Screens.Domain
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
      if state.current_screen in [:post_reader, :post_composer] and state.current_thread do
        [PubSub.thread_topic(state.current_thread.id) | topics]
      else
        topics
      end

    topics
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
    new_state = %{state | current_screen: screen, route_params: %{}, modal: nil}

    cond do
      screen == :main_menu and new_state.current_user ->
        route_screen_update(new_state, :main_menu, :load_oneliners)

      screen == :moderation and new_state.current_user ->
        do_update({:load_moderation_workspace}, new_state)

      screen == :sysop and new_state.current_user ->
        maybe_dispatch_initial_sysop_load(new_state)

      true ->
        {new_state, []}
    end
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

  defp do_update({:load_moderation_workspace}, state) do
    user = state.current_user
    moderation_mod = domain_module(state, :moderation)

    state = put_moderation_loading(state)

    task =
      Foglet.TUI.Command.task(:load_moderation_workspace, fn ->
        {:moderation_workspace_loaded, moderation_mod.workspace_snapshot(user)}
      end)

    {state, [task]}
  end

  defp do_update({:moderation_workspace_loaded, {:ok, snapshot}}, state) when is_map(snapshot) do
    {%{state | screen_state: put_moderation_snapshot(state, snapshot)}, []}
  end

  defp do_update({:moderation_workspace_loaded, {:error, reason}}, state) do
    {%{state | screen_state: put_moderation_error(state, reason)}, []}
  end

  # -------------------------------------------------------------------------
  # Sysop load triad (Phase 29 — D-01, D-02, D-04, D-06).
  #
  # Each lifecycle tab (BOARDS, LIMITS, SYSTEM, USERS) has a dispatch clause
  # that flips the matching slot to `:loading` and returns a single
  # `Foglet.TUI.Command.task/2` to run the boundary call off-process.
  # The result clauses pair with `put_sysop_loaded/3` (success) and
  # `put_sysop_error/3` (any failure including `:forbidden`).
  #
  # Closure capture (Pitfall 8): `user` and `accounts_mod` are bound BEFORE
  # the task closure so the test override `domain_module/2` swap evaluates
  # at dispatch time, not at task-execution time.
  # -------------------------------------------------------------------------

  defp do_update({:load_sysop_users}, state) do
    user = state.current_user
    accounts_mod = domain_module(state, :accounts)
    state = put_sysop_loading(state, :users_view)

    task =
      Foglet.TUI.Command.task(:load_sysop_users, fn ->
        result =
          case accounts_mod.list_user_status_admin_targets(user) do
            {:ok, groups} ->
              {:ok, Foglet.TUI.Screens.Sysop.UsersView.from_groups(groups, user)}

            {:error, reason} ->
              {:error, reason}
          end

        {:sysop_users_loaded, result}
      end)

    {state, [task]}
  end

  defp do_update({:load_sysop_boards}, state) do
    user = state.current_user
    state = put_sysop_loading(state, :boards_view)

    task =
      Foglet.TUI.Command.task(:load_sysop_boards, fn ->
        {:sysop_boards_loaded,
         {:ok, Foglet.TUI.Screens.Sysop.BoardsView.init(current_user: user)}}
      end)

    {state, [task]}
  end

  defp do_update({:load_sysop_limits}, state) do
    user = state.current_user
    state = put_sysop_loading(state, :limits_form)

    task =
      Foglet.TUI.Command.task(:load_sysop_limits, fn ->
        {:sysop_limits_loaded,
         {:ok, Foglet.TUI.Screens.Sysop.LimitsForm.init(current_user: user)}}
      end)

    {state, [task]}
  end

  defp do_update({:load_sysop_system}, state) do
    state = put_sysop_loading(state, :system_snapshot)

    task =
      Foglet.TUI.Command.task(:load_sysop_system, fn ->
        {:sysop_system_loaded, {:ok, Foglet.TUI.Screens.Sysop.SystemSnapshot.init([])}}
      end)

    {state, [task]}
  end

  defp do_update({:sysop_users_loaded, {:ok, sub}}, state),
    do: {put_sysop_loaded(state, :users_view, sub), []}

  defp do_update({:sysop_users_loaded, {:error, reason}}, state),
    do: {put_sysop_error(state, :users_view, reason), []}

  defp do_update({:sysop_boards_loaded, {:ok, sub}}, state),
    do: {put_sysop_loaded(state, :boards_view, sub), []}

  defp do_update({:sysop_boards_loaded, {:error, reason}}, state),
    do: {put_sysop_error(state, :boards_view, reason), []}

  defp do_update({:sysop_limits_loaded, {:ok, sub}}, state),
    do: {put_sysop_loaded(state, :limits_form, sub), []}

  defp do_update({:sysop_limits_loaded, {:error, reason}}, state),
    do: {put_sysop_error(state, :limits_form, reason), []}

  defp do_update({:sysop_system_loaded, {:ok, sub}}, state),
    do: {put_sysop_loaded(state, :system_snapshot, sub), []}

  defp do_update({:sysop_system_loaded, {:error, reason}}, state),
    do: {put_sysop_error(state, :system_snapshot, reason), []}

  defp do_update({:load_boards_for_new_thread}, state) do
    user = state.current_user
    boards_mod = domain_module(state, :boards)

    task =
      Foglet.TUI.Command.task(:load_boards_for_new_thread, fn ->
        directory = boards_mod.board_directory_for(user)

        boards =
          directory
          |> Enum.flat_map(& &1.boards)
          |> Enum.filter(& &1.subscribed?)
          |> Enum.map(& &1.board)

        active_board_count =
          directory
          |> Enum.reduce(0, fn category, acc -> acc + length(category.boards) end)

        {:boards_for_new_thread_loaded, boards, active_board_count}
      end)

    {state, [task]}
  end

  defp do_update({:boards_for_new_thread_loaded, boards}, state) do
    do_update({:boards_for_new_thread_loaded, boards, nil}, state)
  end

  defp do_update({:boards_for_new_thread_loaded, boards, active_board_count}, state) do
    ss =
      case Map.get(state.screen_state, :new_thread) do
        %Foglet.TUI.Screens.NewThread.State{} = ss -> ss
        _ -> nil
      end ||
        Foglet.TUI.Screens.NewThread.init_screen_state()

    new_ss = %{ss | boards: boards, active_board_count: active_board_count}
    new_screen_state = Map.put(state.screen_state, :new_thread, new_ss)
    {%{state | screen_state: new_screen_state}, []}
  end

  # --- Load posts (with optional `jump_last: true` for reply-submit jump) ---

  # 2-arity backward compat: existing callers dispatch {:load_posts, thread_id}.
  defp do_update({:load_posts, thread_id}, state),
    do: do_update({:load_posts, thread_id, []}, state)

  # 3-arity with opts — Plan 04-03 D-05 reply-jump path.
  defp do_update({:load_posts, thread_id, opts}, state) when is_list(opts) do
    posts_mod = domain_module(state, :posts)

    task =
      Foglet.TUI.Command.task(:load_posts, fn ->
        {:posts_loaded, posts_mod.list_posts(thread_id), opts}
      end)

    {state, [task]}
  end

  # 2-arity backward compat for the sink (other paths still emit the 2-tuple).
  defp do_update({:posts_loaded, posts}, state),
    do: do_update({:posts_loaded, posts, []}, state)

  # 3-arity sink — consumes `jump_last: true` to set selected_post_index to
  # the last post in the freshly-loaded list. Also calls prepare_after_load/3
  # to warm the render cache and guarantee a fully-shaped screen_state
  # (render_cache, viewport, etc. are always present after this handler).
  defp do_update({:posts_loaded, posts, opts}, state) when is_list(opts) do
    jump_last? = Keyword.get(opts, :jump_last, false)
    screen_state = state.screen_state || %{}

    # Compute the target index using existing PostReader.State as the base.
    existing_ss =
      case Map.get(screen_state, :post_reader) do
        %Foglet.TUI.Screens.PostReader.State{} = ss ->
          ss

        nil ->
          Foglet.TUI.Screens.PostReader.init_screen_state([])
      end

    existing_idx = existing_ss.selected_post_index

    new_idx =
      if jump_last? and posts != [] do
        length(posts) - 1
      else
        existing_idx
      end

    # Seed posts and idx into state so prepare_after_load/3 can read
    # terminal_size and session_context while warming the cache.
    state_with_posts = %{
      state
      | posts: posts,
        screen_state:
          Map.put(screen_state, :post_reader, %{existing_ss | selected_post_index: new_idx})
    }

    warmed_ss =
      Foglet.TUI.Screens.PostReader.prepare_after_load(state_with_posts, posts, new_idx)

    new_screen_state = Map.put(screen_state, :post_reader, warmed_ss)

    {%{state | posts: posts, screen_state: new_screen_state}, []}
  end

  defp do_update({:flush_read_pointers, ctx}, state) do
    # Flush runs off-process so it doesn't block the UI on the way out of a thread.
    boards_mod = domain_module(state, :boards)
    threads_mod = domain_module(state, :threads)
    user_id = ctx[:user_id] || (state.current_user && state.current_user.id)

    task =
      Foglet.TUI.Command.task(:flush_read_pointers, fn ->
        flush_read_pointers_task(ctx, user_id, boards_mod, threads_mod)
      end)

    {state, [task]}
  end

  defp do_update({:read_pointers_flushed, thread_id}, state) do
    new_rp =
      if thread_id, do: Map.delete(state.read_position, thread_id), else: state.read_position

    new_state = %{state | read_position: new_rp}

    if new_state.current_screen == :board_list do
      route_screen_update(new_state, :board_list, :load)
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
    route_screen_update(state, :board_list, :load)
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

  defp do_update({:account_save_profile, attrs}, state) when is_map(attrs) do
    save_account(state, :profile, Map.take(attrs, [:location, :tagline, :real_name]))
  end

  defp do_update({:account_save_prefs, attrs}, state) when is_map(attrs) do
    allowed_attrs =
      attrs
      |> Map.take([:timezone, :preferences, :theme])
      |> normalize_account_preferences()

    save_account(state, :prefs, allowed_attrs)
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

  defp domain_module(state, key) do
    ctx = Map.get(state, :session_context) || %{}

    case Domain.get(ctx, key) do
      {:ok, mod} -> mod
      {:error, :not_configured} -> default_domain_module(key)
    end
  end

  defp default_domain_module(:boards), do: Foglet.Boards
  defp default_domain_module(:threads), do: Foglet.Threads
  defp default_domain_module(:posts), do: Foglet.Posts
  defp default_domain_module(:moderation), do: Foglet.Moderation
  defp default_domain_module(:accounts), do: Foglet.Accounts

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

    if function_exported?(module, :init, 1) do
      put_screen_state(state, key, module.init(build_context(state, params)))
    else
      state
    end
  end

  defp maybe_seed_legacy_route_context(%__MODULE__{} = state, :post_reader, params) do
    # Phase 37 compatibility: PostReader is not yet a new-contract screen, so
    # keep its legacy App fields warm when ThreadList navigates into it.
    %{
      state
      | current_board: route_param(params, :board),
        current_thread: route_param(params, :thread),
        posts: nil
    }
  end

  defp maybe_seed_legacy_route_context(%__MODULE__{} = state, _screen, _params), do: state

  defp maybe_dispatch_route_entry(%__MODULE__{} = state, :thread_list, _params) do
    route_screen_update(state, :thread_list, :load)
  end

  defp maybe_dispatch_route_entry(%__MODULE__{} = state, :post_reader, params) do
    case route_param(params, :thread_id) do
      thread_id when is_binary(thread_id) -> do_update({:load_posts, thread_id}, state)
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

    Code.ensure_loaded?(module) and function_exported?(module, :update, 3) and
      not function_exported?(module, :handle_key, 2)
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

  defp put_moderation_loading(state) do
    ss =
      state
      |> moderation_screen_state()
      |> Map.put(:loading?, true)
      |> Map.put(:error, nil)

    %{state | screen_state: Map.put(state.screen_state || %{}, :moderation, ss)}
  end

  defp put_moderation_snapshot(state, snapshot) do
    ss =
      state
      |> moderation_screen_state()
      |> Map.merge(%{
        scopes: Map.get(snapshot, :scopes, []),
        queue: Map.get(snapshot, :queue, []),
        mod_log: Map.get(snapshot, :log, []),
        users: Map.get(snapshot, :users, []),
        boards: Map.get(snapshot, :boards, []),
        loading?: false,
        error: nil
      })

    Map.put(state.screen_state || %{}, :moderation, ss)
  end

  defp put_moderation_error(state, reason) do
    ss =
      state
      |> moderation_screen_state()
      |> Map.put(:loading?, false)
      |> Map.put(:error, reason)

    Map.put(state.screen_state || %{}, :moderation, ss)
  end

  defp moderation_screen_state(state) do
    case Map.get(state.screen_state || %{}, :moderation) do
      %Foglet.TUI.Screens.Moderation.State{} = ss -> ss
      _other -> Screens.Moderation.init_screen_state()
    end
  end

  # -------------------------------------------------------------------------
  # Sysop slot helpers (Phase 29 — D-02).
  #
  # Each helper writes a tagged-enum value into one of the four lifecycle
  # slots on `state.screen_state[:sysop]`, mirroring the
  # `put_moderation_loading|snapshot|error` pattern above. The slot atom is
  # restricted to the four lifecycle tabs; SITE (`:site_form`) stays sync
  # (D-03) and is never routed through these helpers.
  # -------------------------------------------------------------------------

  defp put_sysop_loading(state, slot),
    do: update_sysop_slot(state, slot, :loading)

  defp put_sysop_loaded(state, slot, sub),
    do: update_sysop_slot(state, slot, {:loaded, sub})

  defp put_sysop_error(state, slot, reason),
    do: update_sysop_slot(state, slot, {:error, reason})

  defp update_sysop_slot(state, slot, value)
       when slot in [:boards_view, :limits_form, :system_snapshot, :users_view] do
    ss =
      state
      |> sysop_screen_state()
      |> Map.put(slot, value)

    %{state | screen_state: Map.put(state.screen_state || %{}, :sysop, ss)}
  end

  defp sysop_screen_state(state) do
    case Map.get(state.screen_state || %{}, :sysop) do
      %Foglet.TUI.Screens.Sysop.State{} = ss ->
        ss

      _other ->
        Foglet.TUI.Screens.Sysop.init_screen_state(
          current_user: state.current_user,
          session_context: state.session_context
        )
    end
  end

  # First-entry guard for `{:navigate, :sysop}` (D-06 — secondary defense).
  # Inspects the active tab on screen entry and re-enters `do_update/2` with
  # the matching `{:load_sysop_*}` tuple when the slot is `:not_loaded`.
  # SITE / INVITES / unknown labels short-circuit to `{state, []}`.
  defp maybe_dispatch_initial_sysop_load(state) do
    ss = sysop_screen_state(state)
    labels = Foglet.TUI.Screens.Sysop.State.tab_labels(ss)
    active_label = Enum.at(labels, ss.active_tab)

    case active_label do
      "BOARDS" ->
        dispatch_if_not_loaded_initial(state, ss, :boards_view, {:load_sysop_boards})

      "LIMITS" ->
        dispatch_if_not_loaded_initial(state, ss, :limits_form, {:load_sysop_limits})

      "SYSTEM" ->
        dispatch_if_not_loaded_initial(state, ss, :system_snapshot, {:load_sysop_system})

      "USERS" ->
        dispatch_if_not_loaded_initial(state, ss, :users_view, {:load_sysop_users})

      _ ->
        {state, []}
    end
  end

  defp dispatch_if_not_loaded_initial(state, ss, slot, dispatch_tuple) do
    case Map.get(ss, slot) do
      :not_loaded -> do_update(dispatch_tuple, state)
      _ -> {state, []}
    end
  end

  defp humanize_op(op) when is_atom(op) do
    op |> to_string() |> String.replace("_", " ")
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
    if ctx[:thread_id] && user_id && ctx[:last_read_post_id] do
      threads_mod.advance_thread_read_pointer(user_id, ctx[:thread_id], ctx[:last_read_post_id])
    end
  end

  defp save_account(%{current_user: nil} = state, section, _attrs) do
    {put_account_errors(state, section, %{base: "User session is not available."}), []}
  end

  defp save_account(state, section, attrs) do
    case Accounts.update_profile(state.current_user, attrs) do
      {:ok, updated_user} ->
        snapshot = Preferences.from_user(updated_user)

        state =
          state
          |> Map.put(:current_user, updated_user)
          |> merge_session_preferences(snapshot)
          |> refresh_session_preferences(snapshot)
          |> clear_account_save_state(updated_user)

        {state, []}

      {:error, %Ecto.Changeset{} = changeset} ->
        {put_account_errors(state, section, changeset_errors(changeset)), []}
    end
  end

  defp normalize_account_preferences(%{preferences: preferences} = attrs)
       when is_map(preferences) do
    time_format = Map.get(preferences, "time_format") || Map.get(preferences, :time_format)
    %{attrs | preferences: %{"time_format" => time_format}}
  end

  defp normalize_account_preferences(attrs), do: attrs

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
    Session.update_preferences(session_pid, snapshot)
    state
  end

  defp refresh_session_preferences(state, _snapshot), do: state

  defp clear_account_save_state(state, updated_user) do
    account_state =
      state
      |> account_screen_state(updated_user)
      |> AccountState.seed_from_user(updated_user)
      |> Map.put(:status_message, "Account changes saved.")

    put_account_screen_state(state, account_state)
  end

  defp put_account_errors(state, section, errors) do
    account_state =
      state
      |> account_screen_state(state.current_user)
      |> Map.put(error_field(section), errors)
      |> Map.put(:status_message, "Account save failed.")
      |> apply_form_errors(section, errors)

    put_account_screen_state(state, account_state)
  end

  @profile_labels %{location: "Location", tagline: "Tagline", real_name: "Real name"}
  @prefs_labels %{timezone: "Timezone", time_format: "Time format", theme: "Theme"}

  defp apply_form_errors(%{profile_form: form} = account_state, :profile, errors)
       when not is_nil(form) do
    alias Foglet.TUI.Widgets.Modal.Form, as: ModalForm
    prefixed = prefix_errors(errors, @profile_labels)
    %{account_state | profile_form: ModalForm.set_errors(form, prefixed)}
  end

  defp apply_form_errors(%{prefs_form: form} = account_state, :prefs, errors)
       when not is_nil(form) do
    alias Foglet.TUI.Widgets.Modal.Form, as: ModalForm
    prefixed = prefix_errors(errors, @prefs_labels)
    %{account_state | prefs_form: ModalForm.set_errors(form, prefixed)}
  end

  defp apply_form_errors(account_state, _section, _errors), do: account_state

  # Prefix each error value with "FieldLabel error: " so Modal.Form inline
  # error display matches the pre-Phase-25 test expectations (D-19).
  defp prefix_errors(errors, labels) do
    Map.new(errors, fn {field, message} ->
      label = Map.get(labels, field, to_string(field))
      {field, "#{label} error: #{message}"}
    end)
  end

  defp account_screen_state(state, user) do
    case Map.get(state.screen_state || %{}, :account) do
      %AccountState{} = account_state ->
        account_state

      _other ->
        Screens.Account.init_screen_state(current_user: user)
    end
  end

  defp put_account_screen_state(state, %AccountState{} = account_state) do
    %{state | screen_state: Map.put(state.screen_state || %{}, :account, account_state)}
  end

  defp error_field(:profile), do: :profile_errors
  defp error_field(:prefs), do: :prefs_errors

  defp changeset_errors(%Ecto.Changeset{} = changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Enum.reduce(opts, message, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
    |> Enum.into(%{}, fn {field, messages} -> {field, Enum.join(messages, ", ")} end)
  end

  defp format_notification(:dm, %{body: body}), do: "New message: #{body}"
  defp format_notification(:mention, %{thread_title: t}), do: "You were mentioned in: #{t}"
  defp format_notification(kind, _payload), do: "Notification: #{kind}"

  # Process the command list returned by a screen's handle_key/2.
  # Plain %Command{} structs pass through to Raxol unchanged. {:terminate, _}
  # becomes Command.quit(). Every other atom-keyed tuple is routed through
  # do_update/2 so it gets the same state access as a top-level update call.
  # This covers legacy I/O tuples ({:load_boards}, {:load_posts, id}, ...)
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

    if Code.ensure_loaded?(module) and function_exported?(module, :render, 2) and
         not function_exported?(module, :render, 1) do
      module.render(screen_state_for(state, key), context_for_screen_key(state, key))
    else
      :erlang.apply(screen_module_for(state.current_screen), :render, [state])
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
