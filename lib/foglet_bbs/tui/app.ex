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
  alias Foglet.Threads.ThreadEntry
  alias Foglet.TUI.PubSubForwarder
  alias Foglet.TUI.Screens
  alias Foglet.TUI.Screens.Account.State, as: AccountState
  alias Foglet.TUI.Screens.Domain
  alias Foglet.TUI.SizeGate
  alias Foglet.TUI.Theme
  alias Foglet.TUI.Widgets
  alias Foglet.TUI.Widgets.Modal.Form, as: ModalForm
  alias Raxol.Core.Runtime.Command
  alias Raxol.Core.Runtime.Subscription

  @oneliner_limit 5

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
          modal: Foglet.TUI.Modal.t() | nil,
          screen_state: map(),
          board_list: list() | nil,
          current_board: map() | nil,
          current_thread: ThreadEntry.t() | nil,
          current_thread_list: list() | nil,
          posts: list() | nil,
          recent_oneliners: list(),
          selected_oneliner_index: non_neg_integer(),
          pending_hide_oneliner_id: String.t() | nil,
          read_position: map(),
          composer_draft: String.t() | nil
        }

  defstruct current_screen: :login,
            current_user: nil,
            session_context: %Foglet.TUI.SessionContext{},
            session_pid: nil,
            terminal_size: {80, 24},
            modal: nil,
            screen_state: %{},
            board_list: nil,
            current_board: nil,
            current_thread: nil,
            current_thread_list: nil,
            posts: nil,
            recent_oneliners: [],
            selected_oneliner_index: 0,
            pending_hide_oneliner_id: nil,
            read_position: %{},
            composer_draft: nil

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
      |> maybe_load_initial_oneliners()

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
      if state.current_screen in [:thread_list] and state.current_board do
        [PubSub.board_topic(state.current_board.id) | topics]
      else
        topics
      end

    topics =
      if state.current_screen in [:post_reader, :post_composer] and state.current_thread do
        [PubSub.thread_topic(state.current_thread.id) | topics]
      else
        topics
      end

    topics
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
    new_state = %{state | current_screen: screen, modal: nil}

    cond do
      screen == :main_menu and new_state.current_user ->
        do_update({:load_oneliners}, new_state)

      screen == :moderation and new_state.current_user ->
        do_update({:load_moderation_workspace}, new_state)

      true ->
        {new_state, []}
    end
  end

  defp do_update({:set_user, user}, state) do
    do_update({:load_oneliners}, %{state | current_user: user, current_screen: :main_menu})
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

      true ->
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
    # Snapshot the module atom before entering the closure so the task captures only
    # the atom, not the full state map.
    user = state.current_user
    boards_mod = domain_module(state, :boards)

    task =
      Foglet.TUI.Command.task(:load_boards, fn ->
        {:boards_loaded, boards_mod.board_directory_for(user)}
      end)

    {state, [task]}
  end

  defp do_update({:boards_loaded, boards}, state) do
    screen_state =
      case Map.get(state.screen_state || %{}, :board_list) do
        %Screens.BoardList.State{} = board_list_state ->
          Map.put(state.screen_state || %{}, :board_list, %{board_list_state | board_tree: nil})

        _other ->
          state.screen_state || %{}
      end

    {%{state | board_list: boards, screen_state: screen_state}, []}
  end

  defp do_update({:subscribe_to_board, board_id}, state) do
    user = state.current_user
    boards_mod = domain_module(state, :boards)

    task =
      Foglet.TUI.Command.task(:subscribe_to_board, fn ->
        {:board_subscription_changed, :subscribe,
         boards_mod.subscribe_user_to_board(user, board_id)}
      end)

    {state, [task]}
  end

  defp do_update({:unsubscribe_from_board, board_id}, state) do
    user = state.current_user
    boards_mod = domain_module(state, :boards)

    task =
      Foglet.TUI.Command.task(:unsubscribe_from_board, fn ->
        {:board_subscription_changed, :unsubscribe,
         boards_mod.unsubscribe_user_from_board(user, board_id)}
      end)

    {state, [task]}
  end

  defp do_update({:board_subscription_changed, action, {:ok, _result}}, state) do
    feedback =
      case action do
        :subscribe -> "Subscribed."
        :unsubscribe -> "Unsubscribed."
      end

    state
    |> put_board_list_feedback(feedback)
    |> then(&do_update({:load_boards}, &1))
  end

  defp do_update({:board_subscription_changed, _action, {:error, :required_subscription}}, state) do
    {put_board_list_feedback(state, "This board is a required subscription."), []}
  end

  defp do_update({:board_subscription_changed, _action, {:error, :board_archived}}, state) do
    {put_board_list_feedback(state, "That board is archived."), []}
  end

  defp do_update({:board_subscription_changed, _action, {:error, reason}}, state) do
    {put_board_list_feedback(state, "Subscription change failed: #{inspect(reason)}"), []}
  end

  defp do_update({:load_oneliners}, state) do
    oneliners_mod = domain_module(state, :oneliners)

    task =
      Foglet.TUI.Command.task(:load_oneliners, fn ->
        {:oneliners_loaded, oneliners_mod.list_recent_visible(@oneliner_limit)}
      end)

    {state, [task]}
  end

  defp do_update({:oneliners_loaded, entries}, state) when is_list(entries) do
    {%{state | recent_oneliners: entries}, []}
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

  defp do_update({:open_oneliner_composer}, state) do
    form =
      ModalForm.init(
        title: "Post Oneliner",
        fields: [
          %{
            name: :body,
            type: :text,
            label: "Oneliner",
            max_length: 120,
            placeholder: "120 chars max"
          }
        ],
        on_submit: &stash_oneliner_submit/1,
        on_cancel: fn -> :dismiss_modal end
      )

    modal = %Foglet.TUI.Modal{type: :form, title: "Post Oneliner", message: form}

    {%{state | current_screen: :main_menu, modal: modal}, []}
  end

  defp do_update({:submit_oneliner, %{body: body}}, %{current_user: user} = state)
       when not is_nil(user) do
    oneliners_mod = domain_module(state, :oneliners)

    task =
      Foglet.TUI.Command.task(:submit_oneliner, fn ->
        {:oneliner_created, oneliners_mod.create_entry(user, %{body: body})}
      end)

    {state, [task]}
  end

  defp do_update({:submit_oneliner, _payload}, state) do
    {put_oneliner_form_errors(state, %{base: "User session is not available."}), []}
  end

  defp do_update({:oneliner_created, {:ok, _entry}}, state) do
    do_update({:load_oneliners}, %{state | current_screen: :main_menu, modal: nil})
  end

  defp do_update({:oneliner_created, {:error, :same_user_latest_visible}}, state) do
    {put_oneliner_form_errors(state, %{base: "Let someone else post before posting again."}), []}
  end

  defp do_update({:oneliner_created, {:error, %Ecto.Changeset{} = changeset}}, state) do
    errors = changeset_errors(changeset)

    visible_errors =
      if Map.has_key?(errors, :body) do
        %{body: "Enter 1-120 characters."}
      else
        %{base: "Enter 1-120 characters."}
      end

    {put_oneliner_form_errors(state, visible_errors), []}
  end

  defp do_update({:open_hide_oneliner_modal, entry_id}, state)
       when is_binary(entry_id) and entry_id != "" do
    form =
      ModalForm.init(
        title: "Hide Oneliner",
        fields: [
          %{
            name: :reason,
            type: :text,
            label: "Reason",
            placeholder: "Required",
            max_length: 240
          }
        ],
        on_submit: &stash_hide_oneliner_submit/1,
        on_cancel: fn -> :dismiss_modal end
      )

    modal = %Foglet.TUI.Modal{type: :form, title: "Hide Oneliner", message: form}

    {%{state | modal: modal, pending_hide_oneliner_id: entry_id}, []}
  end

  defp do_update({:submit_hide_oneliner, %{reason: reason}}, state) do
    reason = reason |> to_string() |> String.trim()

    cond do
      reason == "" ->
        {put_hide_oneliner_form_errors(state, %{reason: "Reason is required."}), []}

      is_nil(state.current_user) ->
        {put_hide_oneliner_form_errors(state, %{base: "User session is not available."}), []}

      is_nil(state.pending_hide_oneliner_id) ->
        {put_hide_oneliner_form_errors(state, %{base: "No oneliner is selected."}), []}

      true ->
        user = state.current_user
        entry_id = state.pending_hide_oneliner_id
        oneliners_mod = domain_module(state, :oneliners)

        task =
          Foglet.TUI.Command.task(:submit_hide_oneliner, fn ->
            {:oneliner_hidden, oneliners_mod.hide_entry(user, entry_id, reason)}
          end)

        {state, [task]}
    end
  end

  defp do_update({:submit_hide_oneliner, _payload}, state) do
    {put_hide_oneliner_form_errors(state, %{reason: "Reason is required."}), []}
  end

  defp do_update({:oneliner_hidden, {:ok, hidden}}, state) do
    hidden_id = hidden_id(hidden) || state.pending_hide_oneliner_id

    recent_oneliners =
      Enum.reject(state.recent_oneliners || [], fn entry ->
        entry_id(entry) == hidden_id
      end)

    {%{
       state
       | modal: nil,
         pending_hide_oneliner_id: nil,
         recent_oneliners: recent_oneliners,
         selected_oneliner_index:
           clamp_selected_oneliner_index(state.selected_oneliner_index, recent_oneliners)
     }, []}
  end

  defp do_update({:oneliner_hidden, {:error, :forbidden}}, state) do
    {put_hide_oneliner_form_errors(state, %{base: "You are not allowed to hide this oneliner."}),
     []}
  end

  defp do_update({:oneliner_hidden, {:error, %Ecto.Changeset{} = changeset}}, state) do
    {put_hide_oneliner_form_errors(state, changeset_errors(changeset)), []}
  end

  defp do_update({:oneliner_hidden, {:error, reason}}, state) do
    {put_hide_oneliner_form_errors(state, %{base: "Unable to hide oneliner: #{inspect(reason)}"}),
     []}
  end

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

  defp do_update({:load_threads, board_id}, state) do
    threads_mod = domain_module(state, :threads)
    user_id = state.current_user && state.current_user.id

    task =
      Foglet.TUI.Command.task(:load_threads, fn ->
        {:threads_loaded, load_threads_for_user(threads_mod, board_id, user_id)}
      end)

    {state, [task]}
  end

  defp do_update({:threads_loaded, threads}, state) do
    {%{state | current_thread_list: threads}, []}
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

    do_update({:load_oneliners}, %{state | current_user: user, current_screen: :main_menu})
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

  defp put_board_list_feedback(state, feedback) do
    ss =
      case Map.get(state.screen_state || %{}, :board_list) do
        %Screens.BoardList.State{} = ss -> ss
        _other -> Screens.BoardList.init_screen_state()
      end

    %{
      state
      | screen_state: Map.put(state.screen_state || %{}, :board_list, %{ss | feedback: feedback})
    }
  end

  defp default_domain_module(:boards), do: Foglet.Boards
  defp default_domain_module(:threads), do: Foglet.Threads
  defp default_domain_module(:posts), do: Foglet.Posts
  defp default_domain_module(:oneliners), do: Foglet.Oneliners
  defp default_domain_module(:moderation), do: Foglet.Moderation

  defp maybe_load_initial_oneliners(%{current_screen: :main_menu, current_user: user} = state)
       when not is_nil(user) do
    oneliners_mod = domain_module(state, :oneliners)
    %{state | recent_oneliners: oneliners_mod.list_recent_visible(@oneliner_limit)}
  end

  defp maybe_load_initial_oneliners(state), do: state

  defp stash_oneliner_submit(payload) do
    Process.put({__MODULE__, :pending_oneliner_submit}, payload)
    :ok
  end

  defp stash_hide_oneliner_submit(payload) do
    Process.put({__MODULE__, :pending_hide_oneliner_submit}, payload)
    :ok
  end

  defp take_oneliner_submit do
    payload = Process.get({__MODULE__, :pending_oneliner_submit})
    Process.delete({__MODULE__, :pending_oneliner_submit})
    payload
  end

  defp take_hide_oneliner_submit do
    payload = Process.get({__MODULE__, :pending_hide_oneliner_submit})
    Process.delete({__MODULE__, :pending_hide_oneliner_submit})
    payload
  end

  defp put_oneliner_form_errors(
         %{modal: %Foglet.TUI.Modal{message: %ModalForm{} = form}} = state,
         errors
       ) do
    form = ModalForm.set_errors(form, errors)
    %{state | modal: %{state.modal | message: form}}
  end

  defp put_oneliner_form_errors(state, errors) do
    {state, []} = do_update({:open_oneliner_composer}, state)
    put_oneliner_form_errors(state, errors)
  end

  defp put_hide_oneliner_form_errors(
         %{modal: %Foglet.TUI.Modal{message: %ModalForm{} = form}} = state,
         errors
       ) do
    form = ModalForm.set_errors(form, errors)
    %{state | modal: %{state.modal | message: form}}
  end

  defp put_hide_oneliner_form_errors(state, errors) do
    entry_id = state.pending_hide_oneliner_id || ""

    if entry_id == "" do
      state
    else
      {state, []} = do_update({:open_hide_oneliner_modal, entry_id}, state)
      put_hide_oneliner_form_errors(state, errors)
    end
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

  defp hidden_id(%{} = hidden), do: Map.get(hidden, :id) || Map.get(hidden, "id")
  defp hidden_id(_other), do: nil

  defp entry_id(%{} = entry), do: Map.get(entry, :id) || Map.get(entry, "id")
  defp entry_id(_other), do: nil

  defp clamp_selected_oneliner_index(_index, []), do: 0

  defp clamp_selected_oneliner_index(index, entries) when is_integer(index) do
    index
    |> max(0)
    |> min(length(entries) - 1)
  end

  defp clamp_selected_oneliner_index(_index, entries),
    do: clamp_selected_oneliner_index(0, entries)

  defp humanize_op(op) when is_atom(op) do
    op |> to_string() |> String.replace("_", " ")
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
              %ThreadEntry{
                id: t.id,
                title: t.title,
                board_id: t.board_id,
                sticky: t.sticky,
                locked: t.locked,
                post_count: t.post_count,
                first_post_id: t.first_post_id,
                last_post_at: t.last_post_at,
                deleted_at: t.deleted_at,
                inserted_at: t.inserted_at,
                created_by_id: t.created_by_id,
                has_unread: false,
                created_by: t.created_by
              }

            %{} ->
              Map.put_new(t, :has_unread, false)
          end
        end)

      true ->
        []
    end
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

  defp handle_modal_key(
         :form,
         key,
         %{modal: %Foglet.TUI.Modal{message: %ModalForm{} = form}} = state
       ) do
    Process.delete({__MODULE__, :pending_oneliner_submit})
    Process.delete({__MODULE__, :pending_hide_oneliner_submit})
    {new_form, action} = ModalForm.handle_event(key, form)
    state = %{state | modal: %{state.modal | message: new_form}}

    case action do
      :submitted ->
        case {take_hide_oneliner_submit(), take_oneliner_submit()} do
          {payload, _oneliner_payload} when not is_nil(payload) ->
            do_update({:submit_hide_oneliner, payload}, state)

          {nil, payload} when not is_nil(payload) ->
            do_update({:submit_oneliner, payload}, state)

          {nil, nil} ->
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
