defmodule Foglet.TUI.Screens.Shared.AppStateBridge do
  @moduledoc """
  Builds the App-state shell expected by widgets and helpers that pre-date
  per-screen local-state ownership (Phase 47 D-14).

  ## Why this exists

  Several screens (Login menu, LoginForm, Login.Render, Register, Verify)
  reduce/render against a `state.screen_state` map shape. Their reducers
  receive `local_state` + `Context` directly and need to bridge those into
  the legacy App-state shape so existing helpers keep working unchanged.

  Before WR-04 each screen carried its own near-verbatim copy of this
  helper (five sites). Drift had already started — `:session_pid` was
  missing from `login/reset_consume`'s call site — and adding any new
  App-state field would require touching all five in lockstep.

  ## Contract

  `from_context/4` returns a map with the canonical App-state keys
  (`:current_screen`, `:current_user`, `:session_context`, `:session_pid`,
  `:terminal_size`, `:route_params`, `:domain`, `:screen_state`). The
  `:screen_state` slot is keyed by `screen_atom` and holds either
  `local_state` or, when `local_state` is `nil`, the result of `default_fun.()`.

  ## Where to use it

  Anywhere the pattern below appears verbatim:

      defp app_state_from_local(local_state, %Context{} = context) do
        %{
          current_screen: :foo,
          current_user: context.current_user,
          session_context: context.session_context,
          session_pid: context.session_pid,
          terminal_size: context.terminal_size,
          route_params: context.route_params,
          domain: context.domain,
          screen_state: %{foo: local_state || FooState.default()}
        }
      end

  Replace with:

      defp app_state_from_local(local_state, %Context{} = context) do
        AppStateBridge.from_context(local_state, context, :foo, &FooState.default/0)
      end
  """

  alias Foglet.TUI.Context

  @type screen_atom :: atom()
  @type default_fun :: (-> any())

  @doc """
  Builds the App-state shell from a `Context` and screen-local state.

  * `local_state` — the per-screen local state map. When `nil`, `default_fun.()` is used.
  * `context` — `%Context{}` carrying current_user, session_context, session_pid,
    terminal_size, route_params, and domain.
  * `screen_atom` — the screen identifier (e.g. `:login`, `:register`, `:verify`).
  * `default_fun` — zero-arity function returning the screen's default local state.
    Invoked only when `local_state` is `nil`.
  """
  @spec from_context(map() | nil, Context.t(), screen_atom(), default_fun()) :: map()
  def from_context(local_state, %Context{} = context, screen_atom, default_fun)
      when is_atom(screen_atom) and is_function(default_fun, 0) do
    %{
      current_screen: screen_atom,
      current_user: context.current_user,
      unread_count: context.unread_count,
      session_context: context.session_context,
      session_pid: context.session_pid,
      terminal_size: context.terminal_size,
      route_params: context.route_params,
      domain: context.domain,
      screen_state: %{screen_atom => local_state || default_fun.()}
    }
  end
end
