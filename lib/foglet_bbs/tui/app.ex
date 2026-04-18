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
          terminal_size: {pos_integer(), pos_integer()},
          modal: map() | nil,
          screen_state: map(),
          board_list: list() | nil,
          current_board: map() | nil,
          current_thread: map() | nil,
          posts: list() | nil,
          read_position: map(),
          composer_draft: String.t() | nil,
          register_wizard: map() | nil,
          verify_state: map() | nil
        }

  defstruct current_screen: :login,
            current_user: nil,
            session_context: %{},
            terminal_size: {80, 24},
            modal: nil,
            screen_state: %{},
            board_list: nil,
            current_board: nil,
            current_thread: nil,
            posts: nil,
            read_position: %{},
            composer_draft: nil,
            register_wizard: nil,
            verify_state: nil

  # --- Raxol callbacks ---

  @impl true
  def init(context) do
    session_context = Map.get(context, :session_context, %{})
    terminal_size = Map.get(context, :terminal_size, {80, 24})
    user = session_context[:user]

    screen = if user, do: :main_menu, else: :login

    state = %__MODULE__{
      current_screen: screen,
      current_user: user,
      session_context: session_context,
      terminal_size: terminal_size
    }

    {state, []}
  end

  @impl true
  def update(message, state) do
    do_update(message, state)
  end

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
  def subscribe(_state) do
    # Plan 04 will add PubSub topic subscriptions (board activity, notifications).
    []
  end

  # --- Private: update/2 dispatch ---

  defp do_update({:window_change, cols, rows}, state)
       when is_integer(cols) and is_integer(rows) and cols > 0 and rows > 0 do
    # SSH-06: terminal resize
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
    # Delegate to current screen. Screens return either
    # {:update, new_state, commands} or :no_match.
    screen_module = screen_module_for(state.current_screen)

    case screen_module.handle_key(key_event, state) do
      {:update, new_state, commands} -> {new_state, commands}
      :no_match -> global_key_handler(key_event, state)
    end
  end

  defp do_update({:register_wizard, event}, state) do
    # Delegated from register screen during wizard transitions.
    Screens.Register.handle_wizard_event(event, state)
  end

  defp do_update({:verify_event, event}, state) do
    Screens.Verify.handle_verify_event(event, state)
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
    # Global Q from login → terminate
    {state, [{:terminate, :user_quit}]}
  end

  defp global_key_handler(_key, state), do: {state, []}

  defp screen_module_for(:login), do: Screens.Login
  defp screen_module_for(:register), do: Screens.Register
  defp screen_module_for(:verify), do: Screens.Verify
  defp screen_module_for(:main_menu), do: Screens.MainMenu
  defp screen_module_for(:board_list), do: Screens.BoardList
  defp screen_module_for(:thread_list), do: Screens.ThreadList
  defp screen_module_for(:post_reader), do: Screens.PostReader
  defp screen_module_for(:post_composer), do: Screens.PostComposer
end
