defmodule Foglet.TUI.LayoutSmoke.ModerationHelper do
  @moduledoc """
  Per-tab size-contract registry for the Moderation screen (Phase 25, D-09/D-11).

  Plan 03 fills in LOG/USERS/BOARDS/INVITES blocks here.

  Plans that add blocks here do NOT modify layout_smoke_test.exs directly,
  keeping wave-2 merge conflict surface at zero.
  """

  defmacro register_moderation_size_contracts do
    quote do
      # Plan 03 adds QUEUE/LOG/USERS/SANCTIONS/BOARDS describe blocks here.
      # Stub intentionally empty so Plan 01 wiring compiles without errors.
    end
  end
end
