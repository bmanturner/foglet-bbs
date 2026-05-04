defmodule Foglet.TUI.App do
  @moduledoc """
  Raxol application entry point for the Foglet BBS TUI.

  Metaphor (D-15): `app.ex` is the conductor; `screens/*` are the scores;
  `widgets/*` are the instruments. This module holds the canonical UI
  shell — an 8-field struct (`current_screen`, `current_user`,
  `session_context`, `session_pid`, `terminal_size`, `route_params`,
  `modal`, `screen_state`) — while `Foglet.TUI.App.{Routing, Modal, Effects,
  Subscriptions, ScreenStates, SessionAlias}` own the extracted runtime
  details. Per-screen state lives in screen-owned `%State{}` structs stored
  under `screen_state`, keyed by screen atom; each screen is a reducer that
  exposes `update/3` + `render/2` and an optional `subscriptions/2` callback.

  State flow (D-16): domain → Postgres (Foglet.Boards/Threads/Posts);
  session-scoped identity → Foglet.Sessions.Session; UI shell → this model
  (%__MODULE__{}); per-screen UI state → screen-owned %State{} under
  `screen_state[key]`. See docs/ARCHITECTURE.md §4 and CONTEXT 03 D-13..D-21.
  """

  use Raxol.Core.Runtime.Application

  alias Foglet.Accounts
  alias Foglet.TUI.App.Effects
  alias Foglet.TUI.App.Modal, as: AppModal
  alias Foglet.TUI.App.Routing
  alias Foglet.TUI.App.ScreenStates
  alias Foglet.TUI.App.SessionAlias
  alias Foglet.TUI.App.Subscriptions
  alias Foglet.TUI.Context
  alias Foglet.TUI.Guest
  alias Foglet.TUI.SizeGate
  alias Raxol.Core.Runtime.Command

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
          | :door_list
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

  # Public delegators kept on App as stable public boundaries for render
  # fixtures, smoke helpers, and screen tests that construct App state outside
  # the live Raxol shell. Bodies delegate to the extracted helper modules
  # (Routing, ScreenStates) which own the implementations.

  @doc "Returns the current route value through the routing helper."
  @spec current_route(t()) :: atom() | {atom(), map()}
  def current_route(%__MODULE__{} = state), do: Routing.current_route(state)

  @doc "Returns the storage key for a screen route through the routing helper."
  @spec screen_key(atom() | {atom(), map()}) :: atom()
  def screen_key(route), do: Routing.screen_key(route)

  @doc "Returns local state for the current screen key through the routing helper."
  @spec current_screen_state(t()) :: term()
  def current_screen_state(%__MODULE__{} = state), do: Routing.current_screen_state(state)

  @doc "Returns screen-local state stored under `key` through the ScreenStates helper."
  @spec screen_state_for(t(), term()) :: term()
  def screen_state_for(%__MODULE__{} = state, key), do: ScreenStates.get(state, key)

  @doc "Stores screen-local state under `key` through the ScreenStates helper."
  @spec put_screen_state(t(), term(), term()) :: t()
  def put_screen_state(%__MODULE__{} = state, key, local_state),
    do: ScreenStates.put(state, key, local_state)

  @doc "Builds the narrow runtime context passed to screen reducers."
  @spec build_context(t()) :: Context.t()
  def build_context(%__MODULE__{} = state), do: Routing.build_context(state)

  @doc "Builds a screen context with explicit route params through the routing helper."
  @spec build_context(t(), map()) :: Context.t()
  def build_context(%__MODULE__{} = state, route_params),
    do: Routing.build_context(state, route_params)

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

    screen = initial_screen(user, session_context)

    state =
      %__MODULE__{
        current_screen: screen,
        current_user: user,
        session_context: session_context,
        session_pid: session_pid,
        terminal_size: terminal_size
      }
      |> maybe_put_account_gate_modal(user)
      |> maybe_init_initial_screen_state()

    {:ok, state}
  end

  defp initial_screen(nil, session_context) do
    if Guest.guest?(session_context), do: :main_menu, else: :login
  end

  defp initial_screen(%{status: status}, _session_context)
       when status in [:pending, :rejected, :suspended],
       do: :login

  defp initial_screen(%{status: :active, confirmed_at: nil} = user, _session_context),
    do: Accounts.post_login_screen(user)

  defp initial_screen(user, _session_context), do: Accounts.post_login_screen(user)

  defp maybe_put_account_gate_modal(state, %{status: status})
       when status in [:pending, :rejected, :suspended] do
    %{state | modal: account_gate_modal(status)}
  end

  defp maybe_put_account_gate_modal(state, _user), do: state

  defp account_gate_modal(:pending) do
    %Foglet.TUI.Modal{
      type: :error,
      message: "Your account is waiting for sysop approval. Try again once you've heard back."
    }
  end

  defp account_gate_modal(:rejected) do
    %Foglet.TUI.Modal{
      type: :error,
      message: "Your registration was turned down. Reach the sysop if you think that's a mistake."
    }
  end

  defp account_gate_modal(:suspended) do
    %Foglet.TUI.Modal{
      type: :error,
      message: "Your account is suspended. Reach the sysop to ask why."
    }
  end

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
    _ = Subscriptions.refresh_dynamic(state, new_state)
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

  defp normalize_message(%Raxol.Core.Events.Event{
         type: :foglet_runtime,
         data: %{message: message}
       }) do
    message
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
        AppModal.render_overlay(state.modal, state)

      true ->
        Routing.render_screen(state)
    end
  end

  @impl true
  def subscribe(state) do
    Subscriptions.subscribe(state)
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
    Effects.apply_effect(state, Foglet.TUI.Effect.navigate(screen, %{}))
  end

  # WR-02: `:set_user`, `:promote_session`, navigation effects, and
  # PubSub-driven messages flow through unconditionally — they are NOT
  # gated behind `SizeGate.too_small?`. Rationale: these messages are
  # exogenous (auth state changes, server-side promotions, broadcast
  # activity) and must not be silently dropped because the user happens
  # to be on a too-small frame. The gate only governs the rendered
  # surface (`view/1`) and the reducer for keypresses (D-11) so user
  # input cannot mutate hidden screens. State-changing effects from
  # outside the keyboard pipeline are intentionally exempt.
  defp do_update({:set_user, user}, state), do: SessionAlias.set_user(state, user)

  defp do_update(:enter_guest, state) do
    session_context = Guest.enter(state.session_context || %Foglet.TUI.SessionContext{})

    state = %{
      state
      | current_user: nil,
        current_screen: :main_menu,
        route_params: %{},
        session_context: session_context,
        modal: nil
    }

    local_state = Foglet.TUI.Screens.MainMenu.init(build_context(state))

    {ScreenStates.put(state, :main_menu, local_state), []}
  end

  defp do_update({:show_modal, modal}, state) when is_struct(modal, Foglet.TUI.Modal) do
    {%{state | modal: modal}, []}
  end

  defp do_update(:dismiss_modal, state) do
    AppModal.dismiss(state)
  end

  defp do_update({:confirm_modal, answer}, state) do
    AppModal.confirm(state, answer)
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
        AppModal.handle_key(key_event, state)

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

  # FOG-253: forward board-screen presence broadcasts (FOG-250) to the active
  # screen so `BoardScreen` can re-render its `2 CHAT (#)` counter.
  defp do_update({:board_screen, _event, _payload} = msg, state) do
    Routing.route_screen_update(state, Routing.screen_key(Routing.current_route(state)), msg)
  end

  # FOG-284: forward live chat broadcasts (FOG-254/256) to the active screen so
  # `BoardScreen` can append `{:board_chat, :new_message, _}` events into the
  # chat tab transcript. Without this clause the catch-all silently drops the
  # message and the sender's own session never sees its post — which made
  # C8 scenario 7/8 fail on chat-enabled (esp. ephemeral) boards.
  defp do_update({:board_chat, _event, _payload} = msg, state) do
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

  defp do_update({:door_exited, door_id, {:error, _reason}, _status}, state) do
    modal = %Foglet.TUI.Modal{
      type: :error,
      message:
        "#{door_display_name(door_id)} could not start. You are still connected and back in Foglet. Check server logs for launch details."
    }

    {%{state | modal: modal}, []}
  end

  defp do_update({:door_exited, door_id, reason, _status}, state) do
    modal = %Foglet.TUI.Modal{
      type: :info,
      message: "Door #{door_id} exited (#{inspect(reason)}). You are back in Foglet."
    }

    {%{state | modal: modal}, []}
  end

  defp do_update({:door_launch_failed, door_id, reason}, state) do
    modal = %Foglet.TUI.Modal{
      type: :error,
      message: "Door #{door_id} failed to launch: #{inspect(reason)}"
    }

    {%{state | modal: modal}, []}
  end

  defp do_update(:heartbeat_tick, state), do: SessionAlias.heartbeat(state)

  defp do_update(:main_menu_clock_tick, state), do: {state, []}

  defp do_update(:login_menu_scramble_tick, state) do
    if state.current_screen == :login do
      Routing.route_screen_update(state, :login, :menu_scramble_tick)
    else
      {state, []}
    end
  end

  # Phase 39 CR-01 / SPEC R4 / D-04: deliver :on_route_enter to the active
  # screen after `App.init/1` has run. Raxol's init/1 contract returns
  # `{:ok, model}` (no commands), so `init/1` itself can't fan out the
  # route-entry reducer message. The InitialRouteEnterForwarder subscription
  # (started by setup_subscriptions/1 right after init) sends us this message
  # exactly once; we route it through to the screen as :on_route_enter.
  #
  # Direct production navigations still dispatch :on_route_enter through
  # Foglet.TUI.App.Effects and Foglet.TUI.App.Routing, so this path only fires
  # for the very first screen of the session.
  defp do_update(:initial_route_enter, state) do
    Routing.route_screen_update(
      state,
      Routing.screen_key(Routing.current_route(state)),
      :on_route_enter
    )
  end

  defp do_update({:session_replaced, payload}, state),
    do: SessionAlias.session_replaced(state, payload)

  defp do_update({:promote_session, user}, state), do: SessionAlias.promote_session(state, user)

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

  defp humanize_op(op) when is_atom(op) do
    op |> to_string() |> String.replace("_", " ")
  end

  defp door_display_name(door_id) when is_binary(door_id) do
    door_id
    |> String.replace(["-", "_"], " ")
    |> String.split(" ", trim: true)
    |> Enum.map_join(" ", &String.capitalize/1)
  end

  defp format_notification(:dm, %{body: body}), do: "New message: #{body}"
  defp format_notification(:mention, %{thread_title: t}), do: "You were mentioned in: #{t}"
  defp format_notification(kind, _payload), do: "Notification: #{kind}"
end
