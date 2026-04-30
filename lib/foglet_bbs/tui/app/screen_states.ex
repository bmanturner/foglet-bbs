defmodule Foglet.TUI.App.ScreenStates do
  @moduledoc """
  App-shell screen-state map helper.

  Owns get/put/update/delete for `state.screen_state` (note: the field is
  singular per `app.ex:58, 68`; D-18 explicitly does not rename it).

  Mirrors the `Foglet.TUI.App.Routing` / `Foglet.TUI.App.Modal` API style
  from Phase 42.
  """

  alias Foglet.TUI.App

  @spec get(App.t(), term()) :: term()
  def get(%App{screen_state: screen_state}, key) do
    Map.get(screen_state || %{}, key)
  end

  @spec put(App.t(), term(), term()) :: App.t()
  def put(%App{} = state, key, local_state) do
    %{state | screen_state: Map.put(state.screen_state || %{}, key, local_state)}
  end

  @spec update(App.t(), term(), term(), (term() -> term())) :: App.t()
  def update(%App{} = state, key, default, fun) when is_function(fun, 1) do
    current = state.screen_state || %{}
    %{state | screen_state: Map.update(current, key, default, fun)}
  end

  @spec delete(App.t(), term()) :: App.t()
  def delete(%App{} = state, key) do
    %{state | screen_state: Map.delete(state.screen_state || %{}, key)}
  end
end
