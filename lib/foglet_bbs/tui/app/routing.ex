defmodule Foglet.TUI.App.Routing do
  @moduledoc """
  App-shell routing helper for screen state, context, reducer dispatch, and rendering.

  This module owns routing plumbing for `%Foglet.TUI.App{}` while leaving the
  App module as the Raxol callback integration point and leaving durable domain
  work inside screen reducers and domain contexts.
  """

  import Raxol.Core.Renderer.View

  alias Foglet.TUI.App
  alias Foglet.TUI.App.Effects
  alias Foglet.TUI.App.ScreenStates
  alias Foglet.TUI.Context
  alias Foglet.TUI.Screens

  @type route :: atom() | {atom(), map()}

  @doc """
  Returns the current route value.

  Routes are encoded as the screen atom alone when `route_params` is empty, or
  as `{screen, params}` when params are present.
  """
  @spec current_route(App.t()) :: route()
  def current_route(%App{current_screen: screen, route_params: params})
      when is_map(params) and map_size(params) > 0 do
    {screen, params}
  end

  def current_route(%App{current_screen: screen}), do: screen

  @doc "Returns the storage key for a screen route."
  @spec screen_key(route()) :: atom()
  def screen_key({screen, _params}), do: screen
  def screen_key(screen) when is_atom(screen), do: screen

  @doc "Returns the local state for the current screen key."
  @spec current_screen_state(App.t()) :: term()
  def current_screen_state(%App{} = state) do
    screen_state_for(state, screen_key(current_route(state)))
  end

  @doc "Returns screen-local state stored under `key`."
  @spec screen_state_for(App.t(), term()) :: term()
  def screen_state_for(%App{} = state, key), do: ScreenStates.get(state, key)

  @doc "Stores screen-local state under `key`."
  @spec put_screen_state(App.t(), term(), term()) :: App.t()
  def put_screen_state(%App{} = state, key, local_state),
    do: ScreenStates.put(state, key, local_state)

  @doc "Builds the narrow runtime context passed to screen reducers."
  @spec build_context(App.t()) :: Context.t()
  def build_context(%App{} = state) do
    build_context(state, state.route_params || %{})
  end

  @doc "Builds a screen context with explicit route params."
  @spec build_context(App.t(), map()) :: Context.t()
  def build_context(%App{} = state, route_params) when is_map(route_params) do
    Context.new(
      current_user: state.current_user,
      session_context: state.session_context,
      session_pid: state.session_pid,
      terminal_size: state.terminal_size,
      route: state.current_screen,
      route_params: route_params,
      unread_count: state.unread_count,
      domain: domain_from_session_context(state.session_context)
    )
  end

  @doc "Initializes or reinitializes screen-local state for a route entry."
  @spec init_route_screen_state(App.t(), atom() | route(), map()) :: App.t()
  def init_route_screen_state(%App{} = state, screen, params) when is_map(params) do
    key = screen_key(screen)
    module = screen_module_for(state, key)

    cond do
      reinitialize_route_state?(key, module, params) ->
        put_screen_state(state, key, module.init(build_context(state, params)))

      screen_state_for(state, key) != nil ->
        state

      Code.ensure_loaded?(module) and function_exported?(module, :init, 1) ->
        put_screen_state(state, key, module.init(build_context(state, params)))

      true ->
        state
    end
  end

  @doc "Dispatches the route-entry reducer message to the active screen."
  @spec dispatch_route_entry(App.t(), atom() | route(), map()) ::
          {App.t(), [Raxol.Core.Runtime.Command.t()]}
  def dispatch_route_entry(%App{} = state, screen, _params) do
    route_screen_update(state, screen_key(screen), :on_route_enter)
  end

  @doc "Routes a message to a screen reducer and interprets returned effects."
  @spec route_screen_update(App.t(), atom(), term()) ::
          {App.t(), [Raxol.Core.Runtime.Command.t()]}
  def route_screen_update(%App{} = state, key, message) do
    module = screen_module_for(state, key)

    if Code.ensure_loaded?(module) and function_exported?(module, :update, 3) do
      local_state = screen_state_for(state, key)
      context = context_for_screen_key(state, key)
      {new_local_state, effects} = module.update(message, local_state, context)

      state
      |> put_screen_state(key, new_local_state)
      |> Effects.apply_effects(List.wrap(effects))
    else
      {state, []}
    end
  end

  @doc "Builds a context scoped to `key`, carrying params only for the active route."
  @spec context_for_screen_key(App.t(), atom()) :: Context.t()
  def context_for_screen_key(%App{} = state, key) do
    params =
      if screen_key(current_route(state)) == key do
        state.route_params
      else
        %{}
      end

    build_context(state, params)
  end

  @doc "Resolves a screen module, honoring loadable domain overrides first."
  @spec screen_module_for(App.t(), atom()) :: module() | nil
  def screen_module_for(%App{} = state, screen) do
    override =
      get_in(domain_from_session_context(state.session_context), [:screen_modules, screen])

    active_route? = screen_key(current_route(state)) == screen

    cond do
      is_atom(override) and not is_nil(override) and Code.ensure_loaded?(override) ->
        override

      is_atom(override) and not is_nil(override) ->
        require Logger

        Logger.warning(
          "[TUI.App.Routing] domain.screen_modules[#{inspect(screen)}] = " <>
            "#{inspect(override)} is not loadable; falling back to built-in resolver"
        )

        maybe_known_screen_module(screen, active_route?)

      true ->
        maybe_known_screen_module(screen, active_route?)
    end
  end

  @doc "Renders the active screen through its `render/2` callback."
  @spec render_screen(App.t()) :: term()
  def render_screen(%App{} = state) do
    key = screen_key(current_route(state))
    module = screen_module_for(state, key)

    if Code.ensure_loaded?(module) and function_exported?(module, :render, 2) do
      context = context_for_screen_key(state, key)
      module.render(render_local_state(state, key, module, context), context)
    else
      require Logger

      Logger.warning(
        "[TUI.App.Routing] screen #{inspect(key)} does not export render/2; " <>
          "returning bounded empty view"
      )

      text("")
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

  defp route_owned_screen?(key)
       when key in [:thread_list, :post_reader, :post_composer, :new_thread, :bbs_mail],
       do: true

  defp route_owned_screen?(_key), do: false

  defp reinitialize_route_state?(key, module, params) do
    Code.ensure_loaded?(module) and function_exported?(module, :init, 1) and
      (route_owned_screen?(key) or
         (map_size(params) > 0 and function_exported?(module, :update, 3)))
  end

  defp domain_from_session_context(session_context) when is_map(session_context) do
    case Map.get(session_context, :domain) do
      domain when is_map(domain) ->
        domain

      nil ->
        %{}

      other ->
        require Logger

        Logger.warning(
          "[TUI.App.Routing] session_context.:domain is non-map (#{inspect(other)}); " <>
            "coercing to %{}. This usually indicates a misshapen test fixture " <>
            "or stale session_context."
        )

        %{}
    end
  end

  defp domain_from_session_context(_session_context), do: %{}

  defp maybe_known_screen_module(screen, active_route?) do
    if screen in known_screens() do
      built_in_screen_module_for(screen)
    else
      if active_route? do
        require Logger

        Logger.error(
          "[TUI.App.Routing] no screen module for #{inspect(screen)}; falling back to :main_menu"
        )

        Screens.MainMenu
      end
    end
  end

  defp known_screens do
    [
      :login,
      :register,
      :verify,
      :main_menu,
      :notifications,
      :bbs_mail,
      :online_now,
      :board_list,
      :thread_list,
      :post_reader,
      :post_composer,
      :new_thread,
      :door_list,
      :account,
      :moderation,
      :sysop
    ]
  end

  defp built_in_screen_module_for(:login), do: Screens.Login
  defp built_in_screen_module_for(:register), do: Screens.Register
  defp built_in_screen_module_for(:verify), do: Screens.Verify
  defp built_in_screen_module_for(:main_menu), do: Screens.MainMenu
  defp built_in_screen_module_for(:notifications), do: Screens.Notifications
  defp built_in_screen_module_for(:bbs_mail), do: Screens.BBSMail
  defp built_in_screen_module_for(:online_now), do: Screens.OnlineNow
  defp built_in_screen_module_for(:board_list), do: Screens.BoardList
  defp built_in_screen_module_for(:thread_list), do: Screens.BoardScreen
  defp built_in_screen_module_for(:post_reader), do: Screens.PostReader
  defp built_in_screen_module_for(:post_composer), do: Screens.PostComposer
  defp built_in_screen_module_for(:new_thread), do: Screens.NewThread
  defp built_in_screen_module_for(:door_list), do: Screens.DoorList
  defp built_in_screen_module_for(:account), do: Screens.Account
  defp built_in_screen_module_for(:moderation), do: Screens.Moderation
  defp built_in_screen_module_for(:sysop), do: Screens.Sysop
end
