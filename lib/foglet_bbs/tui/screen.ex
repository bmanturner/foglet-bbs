defmodule Foglet.TUI.Screen do
  @moduledoc """
  Behaviour for Foglet TUI screens.

  Phase 34 defines the target screen runtime contract:

  - `init/1` builds screen-local state from `Foglet.TUI.Context`.
  - `update/3` consumes normalized runtime messages plus screen-local state.
  - `render/2` renders from screen-local state plus context.

  Production screens migrate to that contract in phases 35-38. Until then,
  the legacy `render/1`, `handle_key/2`, and `init_screen_state/1` callbacks
  remain transitional callbacks so existing screens continue compiling while
  the new reducer boundary lands.

  See `docs/ARCHITECTURE.md` section 4 and `app.ex` for the legacy dispatch
  path still in use during the migration.
  """

  @type message :: term()
  @type local_state :: term()
  @type effects :: [Foglet.TUI.Effect.t()]
  @type update_result :: {local_state(), effects()}

  @type key_event :: map()
  @type app_state :: map()
  @type command :: tuple() | Raxol.Core.Runtime.Command.t()
  @type handle_key_result :: {:update, app_state(), [command()]} | :no_match

  @callback init(Foglet.TUI.Context.t()) :: local_state()
  @callback update(message(), local_state(), Foglet.TUI.Context.t()) :: update_result()
  @callback render(local_state(), Foglet.TUI.Context.t()) :: any()

  @doc """
  Transitional legacy render callback that receives broad App state.
  """
  @callback render(state :: app_state()) :: any()

  @doc """
  Transitional legacy key handler that receives broad App state.
  """
  @callback handle_key(key :: key_event(), state :: app_state()) :: handle_key_result()

  @doc """
  Transitional legacy screen-state initializer. Optional — stateless screens
  (e.g. MainMenu) may omit this callback.
  """
  @callback init_screen_state(opts :: keyword()) :: map()

  @optional_callbacks init: 1,
                      update: 3,
                      render: 2,
                      render: 1,
                      handle_key: 2,
                      init_screen_state: 1
end
