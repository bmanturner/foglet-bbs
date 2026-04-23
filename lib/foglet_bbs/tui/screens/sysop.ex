defmodule Foglet.TUI.Screens.Sysop do
  @moduledoc """
  Sysop shell screen stub.

  The real implementation is created by Plan 06. This stub exists so
  `Foglet.TUI.App.screen_module_for(:sysop)` can compile cleanly and the
  app routing seam is in place before the shell module is built.

  This file will be replaced by the full implementation from Plan 06.
  """

  @doc "Stub render — replaced by Plan 06."
  @spec render(map()) :: any()
  def render(_state), do: nil

  @doc "Stub handle_key — replaced by Plan 06."
  @spec handle_key(map(), map()) :: {map(), list()}
  def handle_key(_key, state), do: {state, []}
end
