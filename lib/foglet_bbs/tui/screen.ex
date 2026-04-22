defmodule Foglet.TUI.Screen do
  @moduledoc """
  Behaviour for Foglet TUI screens. Every screen module under
  `lib/foglet_bbs/tui/screens/` implements this contract.

  See `docs/ARCHITECTURE.md` §4 and `app.ex` for how screens are dispatched.
  """

  @type key_event :: map()
  @type app_state :: map()
  @type command :: tuple() | Raxol.Core.Runtime.Command.t()
  @type handle_key_result :: {:update, app_state(), [command()]} | :no_match

  @callback render(state :: app_state()) :: any()
  @callback handle_key(key :: key_event(), state :: app_state()) :: handle_key_result()

  @doc """
  Build the screen's default screen_state map. Optional — stateless
  screens (e.g. MainMenu) may omit this callback.
  """
  @callback init_screen_state(opts :: keyword()) :: map()

  @optional_callbacks init_screen_state: 1
end
