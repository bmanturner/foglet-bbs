defmodule Foglet.TUI.App do
  @moduledoc """
  Raxol application entry point for the Foglet BBS TUI.

  Metaphor (D-15): `app.ex` is the conductor; `screens/*` are the scores;
  `widgets/*` are the instruments. This module holds the canonical UI
  shell — an 8-field struct (`current_screen`, `current_user`,
  `session_context`, `session_pid`, `terminal_size`, `route_params`,
  `modal`, `screen_state`) — and the view-routing table. Per-screen state
  lives in screen-owned `%State{}` structs stored under `screen_state`,
  keyed by screen atom; each screen is a reducer that exposes
  `update/3` + `render/2` and an optional `subscriptions/2` callback.

  State flow (D-16):
    * Domain state → Postgres (accessed via Foglet.Boards/Threads/Posts)
    * Session-scoped identity → Foglet.Sessions.Session
    * UI shell → this model (%__MODULE__{})
    * Per-screen UI state → screen-owned %State{} under screen_state[key]

  See docs/ARCHITECTURE.md §4 and CONTEXT 03 D-13..D-21.
  """

  use Raxol.Core.Runtime.Application

  alias Foglet.Accounts
  alias Foglet.PubSub
  alias Foglet.TUI.App.Routing
  alias Foglet.TUI.Context
  alias Foglet.TUI.Effect
  alias Foglet.TUI.InitialRouteEnterForwarder
  alias Foglet.TUI.PubSubForwarder
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
          screen_state: map()
        }

  defstruct current_screen: :login,
            current_user: nil,
            session_context: %Foglet.TUI.SessionContext{},
            session_pid: nil,
            terminal_size: {80, 24},
            route_params: %{},
            modal: nil,
            screen_state: %{}

  @doc """
  Returns the current route value through the routing helper.

  This remains a public App boundary for render fixtures, smoke helpers, and
  screen tests that construct App state directly outside the live Raxol shell.
  """
  @spec current_route(t()) :: atom() | {atom(), map()}
  def current_route(%__MODULE__{} = state), do: Routing.current_route(state)

  @doc """
  Returns the storage key for a screen route through the routing helper.

  This public seam is used by non-live render/test fixtures that need the same
  route-key semantics as the App runtime.
  """
  @spec screen_key(atom() | {atom(), map()}) :: atom()
  def screen_key(route), do: Routing.screen_key(route)

  @doc """
  Returns local state for the current screen key through the routing helper.

  This stays public for fixture code that inspects App-local screen state
  without starting a dispatcher process.
  """
  @spec current_screen_state(t()) :: term()
  def current_screen_state(%__MODULE__{} = state), do: Routing.current_screen_state(state)

  @doc """
  Returns screen-local state stored under `key` through the routing helper.

  This remains public for render fixtures and screen-level tests that assemble
  App state directly.
  """
  @spec screen_state_for(t(), term()) :: term()
  def screen_state_for(%__MODULE__{} = state, key), do: Routing.screen_state_for(state, key)

  @doc """
  Stores screen-local state under `key` through the routing helper.

  Render fixtures use this public boundary to seed screen-owned local state
  before invoking the same render paths used by the live TUI.
  """
  @spec put_screen_state(t(), term(), term()) :: t()
  def put_screen_state(%__MODULE__{} = state, key, local_state),
    do: Routing.put_screen_state(state, key, local_state)

  @doc """
  Builds the narrow runtime context passed to screen reducers.

  This public boundary supports render fixtures and screen-focused tests while
  Routing owns the implementation.
  """
  @spec build_context(t()) :: Context.t()
  def build_context(%__MODULE__{} = state), do: Routing.build_context(state)

  @doc """
  Builds a screen context with explicit route params through the routing helper.

  This public boundary supports render fixtures and screen-focused tests while
  Routing owns the implementation.
  """
  @spec build_context(t(), map()) :: Context.t()
  def build_context(%__MODULE__{} = state, route_params),
    do: Routing.build_context(state, route_params)

  @doc """
  Interprets one runtime effect against the App shell.

  Effects (`%Foglet.TUI.Effect{}`) are emitted by screen reducers from
  `update/3`; this function applies them to the shell — `:navigate` updates
  `current_screen`/`route_params` and dispatches `:on_route_enter`,
  `:modal` opens/dismisses a modal, etc. Returns the updated state and any
  Raxol commands to execute.
  """
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
      |> Routing.init_route_screen_state(screen, params || %{})

    Routing.dispatch_route_entry(state, screen, params || %{})
  end

  def apply_effect(%__MODULE__{} = state, %Effect{type: :modal, payload: {:open, modal}}) do
    {%{state | modal: modal}, []}
  end

  def apply_effect(%__MODULE__{} = state, %Effect{type: :modal, payload: :dismiss}) do
    {%{state | modal: nil}, []}
  end

  def apply_effect(%__MODULE__{} = state, %Effect{
        type: :modal_submit,
        payload: %{screen_key: screen_key, kind: kind, payload: payload}
      })
      when is_atom(kind) do
    if modal_submit_target?(state, screen_key) do
      Routing.route_screen_update(state, screen_key, {:modal_submit, kind, payload})
    else
      modal_submit_error(state)
    end
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
    {new_state, commands} = do_update(normalize_message(message), state)
    _ = refresh_dynamic_subscriptions(state, new_state)
    {new_state, commands}
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
        Routing.render_screen(state)
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

    clock = [subscribe_interval(60_000, :main_menu_clock_tick)]

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

    pubsub_subs = [Subscription.custom(PubSubForwarder, %{topics: pubsub_topics})]

    # Phase 39 SPEC R4 / D-04: every route-entry must dispatch :on_route_enter.
    # Raxol's `init/1` contract returns {:ok, model} — it can't return commands
    # — so screens that get mounted directly via `App.init/1` (e.g. an SSH-
    # pubkey-authenticated user landing on :main_menu) would otherwise miss
    # their first-paint :on_route_enter dispatch and render un-hydrated until
    # the user navigated somewhere and back. The InitialRouteEnterForwarder is
    # a one-shot subscription that delivers `:initial_route_enter` to update/2
    # exactly once, immediately after the Dispatcher starts; the corresponding
    # do_update clause routes it through to the active screen as
    # `:on_route_enter`. See `do_update(:initial_route_enter, state)` below.
    initial_route_subs = [Subscription.custom(InitialRouteEnterForwarder, %{})]

    heartbeat ++ clock ++ pubsub_subs ++ initial_route_subs
  end

  # Compute which PubSub topics to subscribe to based on current screen and user.
  # Topics follow the convention: "user:<id>", "boards", "board:<id>", "thread:<id>".
  #
  # User-level topics ("user:<id>") are always App-owned (they don't depend on
  # which screen is active). Screen-specific topics are sourced from the active
  # screen's optional `subscriptions/2` callback (Phase 39 D-06, D-22, R7), which
  # lets each screen own the binary topic strings it cares about. Screens that
  # don't implement `subscriptions/2` contribute nothing — App produces only
  # user-level topics for them.
  defp build_pubsub_topics(%__MODULE__{} = state) do
    user_topics =
      if state.current_user do
        [PubSub.user_topic(state.current_user.id)]
      else
        []
      end

    user_topics ++ screen_declared_topics(state)
  end

  defp refresh_dynamic_subscriptions(%__MODULE__{} = old_state, %__MODULE__{} = new_state) do
    old_topics = build_pubsub_topics(old_state)
    new_topics = build_pubsub_topics(new_state)

    if old_topics != new_topics do
      _ = PubSubForwarder.refresh(new_topics)
    end
  end

  # Defers screen-specific topic interest to the active screen's
  # `subscriptions/2` optional callback (Foglet.TUI.Screen). Mirrors the
  # `Code.ensure_loaded?/1` + `function_exported?/3` paired guard idiom used at
  # `route_screen_update/3` and `render_screen/1` for `update/3` and `render/2`.
  defp screen_declared_topics(%__MODULE__{} = state) do
    key = Routing.screen_key(Routing.current_route(state))
    module = Routing.screen_module_for(state, key)

    if Code.ensure_loaded?(module) and function_exported?(module, :subscriptions, 2) do
      module.subscriptions(Routing.screen_state_for(state, key), Routing.build_context(state))
    else
      []
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
    do_update({:promote_session, user}, state)
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
        # are hidden — we must not let their reducers silently mutate state
        # (e.g., scroll a list, advance a cursor, consume a char).
        # D-12: Ctrl+C / EOF reach CLIHandler at the SSH channel layer
        # independently of update/2, so disconnect still works.
        {state, []}

      state.modal != nil ->
        # Modal is active: route key directly to global_key_handler, which
        # contains all modal dismiss / confirm logic. Never delegate to the
        # screen module while a modal is open — screen handlers don't check
        # state.modal and will consume the key silently.
        global_key_handler(key_event, state)

      true ->
        Routing.route_screen_update(
          state,
          Routing.screen_key(Routing.current_route(state)),
          {:key, key_event}
        )
    end
  end

  # PubSub message handlers (Audit #12).
  # These messages arrive via PubSubForwarder → {:subscription, msg} → Dispatcher
  # → update/2. Phase 2 may not yet emit all of these; the handlers are wired now
  # so real-time updates work as soon as Phase 2 starts broadcasting.

  # PubSub broadcast routing (Phase 39 D-13, R8): forward {:board_activity, …}
  # and {:thread_activity, …} to the active screen via the generic update path.
  # Screens that care (BoardList for :board_activity, PostReader for
  # :thread_activity) handle the message in their update/3; screens that don't
  # hit their update(_message, …) catch-all and no-op.
  defp do_update({:board_activity, _board_id, _event} = msg, state) do
    Routing.route_screen_update(state, Routing.screen_key(Routing.current_route(state)), msg)
  end

  defp do_update({:thread_activity, _thread_id, _event} = msg, state) do
    Routing.route_screen_update(state, Routing.screen_key(Routing.current_route(state)), msg)
  end

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

  # Phase 39 CR-01 / SPEC R4 / D-04: deliver :on_route_enter to the active
  # screen after `App.init/1` has run. Raxol's init/1 contract returns
  # `{:ok, model}` (no commands), so `init/1` itself can't fan out the
  # route-entry reducer message. The InitialRouteEnterForwarder subscription
  # (started by setup_subscriptions/1 right after init) sends us this message
  # exactly once; we route it through to the screen as :on_route_enter.
  #
  # Direct production navigations (`apply_effect(navigate, ...)`) still
  # dispatch :on_route_enter via `maybe_dispatch_route_entry/3` (app.ex:138),
  # so this path only fires for the very first screen of the session.
  defp do_update(:initial_route_enter, state) do
    Routing.route_screen_update(
      state,
      Routing.screen_key(Routing.current_route(state)),
      :on_route_enter
    )
  end

  # A new SSH connection for the same user replaced this session.
  # Show a notice modal and defer the quit until the user dismisses it
  # (mirrors `:terminate_after_modal` so the user actually sees the message
  # rather than getting torn down on the next tick).
  defp do_update({:session_replaced, _user_id}, state) do
    modal = %Foglet.TUI.Modal{
      type: :warning,
      message: "Your session was replaced by a new connection. Goodbye.",
      on_confirm: fn s -> {s, [Command.quit()]} end,
      on_cancel: fn s -> {s, [Command.quit()]} end
    }

    {%{state | modal: modal}, []}
  end

  # TUI login screen authenticated a user — promote the guest session.
  # Routes through the Supervisor so one-session-per-user (SSH-05 / D-25) is
  # enforced: any pre-existing session for this user is replaced before this
  # guest pid registers under the user_id key.
  defp do_update({:promote_session, user}, state) do
    if is_pid(state.session_pid) do
      Foglet.Sessions.Supervisor.promote_guest_session(state.session_pid, user)
    end

    apply_effect(%{state | current_user: user}, Effect.navigate(:main_menu, %{}))
  end

  defp do_update({:command_result, inner}, state) do
    # Raxol's Command.task runtime wraps every task return value in
    # {:command_result, inner} before delivering to update/2 (Audit #11 follow-up).
    # Re-dispatch so all existing result handlers (:boards_loaded, :threads_loaded,
    # :posts_loaded, :read_pointers_flushed, etc.) fire correctly.
    do_update(inner, state)
  end

  defp do_update({:screen_task_result, key, op, result}, state) do
    Routing.route_screen_update(state, key, {:task_result, op, result})
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

  # Generic initial-screen-state seeding (Phase 39 D-15, R4):
  # init_route_screen_state/3 already covers MainMenu via the
  # function_exported?(module, :init, 1) branch. The MainMenu
  # `oneliner_status: :idle` shim is no longer needed — MainMenu's
  # :on_route_enter clause (Plan 39-04) sets :loading before the load task
  # fires.
  defp maybe_init_initial_screen_state(%__MODULE__{} = state) do
    Routing.init_route_screen_state(state, state.current_screen, state.route_params)
  end

  defp modal_submit_target?(%__MODULE__{} = state, screen_key) do
    module = Routing.screen_module_for(state, screen_key)
    Code.ensure_loaded?(module) and function_exported?(module, :update, 3)
  end

  defp modal_submit_error(%__MODULE__{} = state) do
    modal = %Foglet.TUI.Modal{
      type: :error,
      title: "Form Error",
      message: "Unable to submit form."
    }

    {%{state | modal: modal}, []}
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
    {new_form, action} = ModalForm.handle_event(key, form)
    state = %{state | modal: %{state.modal | message: new_form}}

    case action do
      {:submitted, %Effect{type: :modal_submit} = effect} ->
        apply_effect(state, effect)

      :submitted ->
        modal_submit_error(state)

      {:submitted, _other} ->
        modal_submit_error(state)

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
  # return full %Command{} structs or {:terminate, reason}. Screen reducers now
  # return Effect structs; App interprets those through apply_effects/2.
  defp wrap_commands(commands), do: Enum.map(commands, &wrap_command/1)

  defp wrap_command({:terminate, _reason}), do: Command.quit()
  defp wrap_command(%Command{} = cmd), do: cmd
  defp wrap_command(other), do: other
end
