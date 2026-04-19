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

  alias Foglet.TUI.Screens
  alias Foglet.TUI.Widgets
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
          verify_state: map() | nil
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
            verify_state: nil

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

  # Translate Raxol %Event{} structs into the internal tuple format that
  # do_update/2 and all screen handle_key/2 functions expect.
  defp normalize_message(%Raxol.Core.Events.Event{type: :key, data: data}) do
    {:key, normalize_key(data)}
  end

  defp normalize_message(%Raxol.Core.Events.Event{type: :window, data: %{width: w, height: h}}) do
    {:window_change, w, h}
  end

  defp normalize_message(other), do: other

  defp normalize_key(%{key: :char, ctrl: true, char: c}), do: %{key: "ctrl_#{c}"}
  defp normalize_key(%{key: :char, char: " "}), do: %{key: "space"}
  defp normalize_key(%{key: :char, char: c}), do: %{key: c}
  defp normalize_key(%{key: :page_up}), do: %{key: "pageup"}
  defp normalize_key(%{key: :page_down}), do: %{key: "pagedown"}
  defp normalize_key(%{key: atom}) when is_atom(atom), do: %{key: Atom.to_string(atom)}
  defp normalize_key(other), do: other

  @impl true
  def view(state) do
    screen_view = render_screen(state)

    if state.modal do
      box(children: [screen_view, Widgets.Modal.render(state.modal)])
    else
      screen_view
    end
  end

  @impl true
  def subscribe(state) do
    # Heartbeat tick — keeps last_seen_at fresh in the Session GenServer.
    # Only subscribed when a session_pid is wired (i.e., CLIHandler started us).
    if is_pid(state.session_pid) do
      [subscribe_interval(10_000, :heartbeat_tick)]
    else
      []
    end
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

  defp do_update({:key, key_event}, state) do
    screen_module = screen_module_for(state.current_screen)

    case screen_module.handle_key(key_event, state) do
      {:update, new_state, commands} -> {new_state, wrap_commands(commands)}
      :no_match -> global_key_handler(key_event, state)
    end
  end

  # Command results from Command.task/1 — route inner message back through dispatch.
  defp do_update({:command_result, inner}, state) do
    do_update(inner, state)
  end

  defp do_update({:register_wizard, event}, state) do
    # Delegated from register screen during wizard transitions.
    Screens.Register.handle_wizard_event(event, state)
  end

  defp do_update({:verify_event, event}, state) do
    Screens.Verify.handle_verify_event(event, state)
  end

  defp do_update({:load_boards}, state) do
    Foglet.TUI.Screens.BoardList.load_boards(state)
  end

  defp do_update({:load_threads, board_id}, state) do
    Foglet.TUI.Screens.ThreadList.load_threads(state, board_id)
  end

  defp do_update({:load_posts, thread_id}, state) do
    Foglet.TUI.Screens.PostReader.load_posts(state, thread_id)
  end

  defp do_update({:flush_read_pointers, ctx}, state) do
    Foglet.TUI.Screens.PostReader.flush_read_pointers(state, ctx)
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
  defp do_update({:promote_session, user}, state) do
    if is_pid(state.session_pid) do
      Foglet.Sessions.Session.promote_to_user(state.session_pid, user)
    end

    {%{state | current_user: user, current_screen: :main_menu}, []}
  end

  defp do_update(_other, state) do
    # Unknown messages pass through unchanged.
    {state, []}
  end

  defp render_screen(state) do
    case state.current_screen do
      :login -> Screens.Login.render(state)
      :register -> Screens.Register.render(state)
      :verify -> Screens.Verify.render(state)
      :main_menu -> Screens.MainMenu.render(state)
      :board_list -> Screens.BoardList.render(state)
      :thread_list -> Screens.ThreadList.render(state)
      :post_reader -> Screens.PostReader.render(state)
      :post_composer -> Screens.PostComposer.render(state)
    end
  end

  defp global_key_handler(%{key: "q"} = _key, state) when state.current_screen == :login do
    {state, [Command.quit()]}
  end

  defp global_key_handler(_key, state), do: {state, []}

  # Convert screen-returned tuples to proper %Command{} structs that the
  # Raxol dispatcher can execute.
  defp wrap_commands(commands), do: Enum.map(commands, &wrap_command/1)

  defp wrap_command({:terminate, _reason}), do: Command.quit()
  defp wrap_command(msg) when is_tuple(msg), do: Command.task(fn -> msg end)
  defp wrap_command(cmd), do: cmd

  defp screen_module_for(:login), do: Screens.Login
  defp screen_module_for(:register), do: Screens.Register
  defp screen_module_for(:verify), do: Screens.Verify
  defp screen_module_for(:main_menu), do: Screens.MainMenu
  defp screen_module_for(:board_list), do: Screens.BoardList
  defp screen_module_for(:thread_list), do: Screens.ThreadList
  defp screen_module_for(:post_reader), do: Screens.PostReader
  defp screen_module_for(:post_composer), do: Screens.PostComposer
end
