defmodule Foglet.TUI.Screens.Shared.InvitesSurface do
  @moduledoc """
  Stub module for the shared INVITES surface primitive.

  The real implementation is created by Plan 02. This stub exists so Plan 03
  (ShellVisibility) and Plan 04-06 (shell modules) can reference
  `InvitesSurface.visible?/2` at compile time without a missing-module warning.

  This file will be replaced by the full implementation from Plan 02 when
  both worktrees are merged.
  """

  @doc "Returns true when the user role and invite policy permit invite access."
  @spec visible?(map() | nil, String.t() | nil) :: boolean()
  def visible?(_user, _policy), do: false
end
