defmodule Foglet.TUI.App do
  @moduledoc """
  Raxol application entry point for the Foglet BBS TUI.

  Metaphor (D-15): `app.ex` is the conductor; `screens/*` are the scores;
  `widgets/*` are the instruments. This module holds the canonical UI
  shell — an 8-field struct (`current_screen`, `current_user`,
  `session_context`, `session_pid`, `terminal_size`, `route_params`,
  `modal`, `screen_state`) — while `Foglet.TUI.App.{Bootstrap, Door,
  MessageNormalizer, PubSubRouter, Routing, Modal, Effects, Subscriptions,
  ScreenStates, SessionAlias, Tasks}` own the extracted runtime details. Per-screen state lives in screen-owned `%State{}`
  structs stored under `screen_state`, keyed by screen atom; each screen is a
  reducer that exposes `update/3` + `render/2` and an optional
  `subscriptions/2` callback. Terminal handoff to external door programs is
  owned by `Foglet.TUI.App.Door`: while a door is active, `view/1` returns nil
  so the SSH door runner can write directly to the PTY without Raxol fighting
  it for bytes.

  State flow (D-16): domain → Postgres (Foglet.Boards/Threads/Posts);
  session-scoped identity → Foglet.Sessions.Session; UI shell → this model
  (%__MODULE__{}); per-screen UI state → screen-owned %State{} under
  `screen_state[key]`. See docs/ARCHITECTURE.md §4 and CONTEXT 03 D-13..D-21.
  """

  use Raxol.Core.Runtime.Application

  alias Foglet.TUI.App.Bootstrap
  alias Foglet.TUI.App.Door
  alias Foglet.TUI.App.MessageNormalizer
  alias Foglet.TUI.App.Modal, as: AppModal
  alias Foglet.TUI.App.Routing
  alias Foglet.TUI.App.RuntimeMessages
  alias Foglet.TUI.App.ScreenStates
  alias Foglet.TUI.App.Subscriptions
  alias Foglet.TUI.Context
  alias Foglet.TUI.SizeGate

  @type screen ::
          :login
          | :register
          | :verify
          | :main_menu
          | :notifications
          | :online_now
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
  defdelegate init(context), to: Bootstrap

  @impl true
  def update(message, state) do
    {new_state, commands} = do_update(MessageNormalizer.normalize(message), state)
    _ = Subscriptions.refresh_dynamic(state, new_state)
    {new_state, commands}
  end

  @impl true
  def view(state) do
    cond do
      Door.suppress_render?(state) ->
        nil

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

  # WR-02: `:set_user`, `:promote_session`, navigation effects, and
  # PubSub-driven messages flow through unconditionally — they are NOT
  # gated behind `SizeGate.too_small?`. Rationale: these messages are
  # exogenous (auth state changes, server-side promotions, broadcast
  # activity) and must not be silently dropped because the user happens
  # to be on a too-small frame. The gate only governs the rendered
  # surface (`view/1`) and the reducer for keypresses (D-11) so user
  # input cannot mutate hidden screens. State-changing effects from
  # outside the keyboard pipeline are intentionally exempt.
  defp do_update(message, state), do: RuntimeMessages.handle(message, state)
end
