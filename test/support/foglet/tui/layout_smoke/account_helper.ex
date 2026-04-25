defmodule Foglet.TUI.LayoutSmoke.AccountHelper do
  @moduledoc """
  Per-tab size-contract registry for the Account screen (Phase 25, D-09/D-11).

  Plan 02 fills in PROFILE/PREFS/SSH KEYS blocks here.

  Plans that add blocks here do NOT modify layout_smoke_test.exs directly,
  keeping wave-2 merge conflict surface at zero.
  """

  defmacro register_account_size_contracts do
    quote do
      # Plan 02 adds PROFILE/PREFS/SSH KEYS describe blocks here.
      # Stub intentionally empty so Plan 01 wiring compiles without errors.
    end
  end
end
