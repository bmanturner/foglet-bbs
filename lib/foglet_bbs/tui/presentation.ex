defmodule Foglet.TUI.Presentation do
  @moduledoc """
  Presentation metadata for routed Foglet TUI screens.

  Implements Phase 17 decisions D-01 through D-07: presentation mode is a
  shared TUI-level contract keyed by existing screen ids, the only supported
  modes are `:bbs` and `:operator`, and every current screen id is declared
  explicitly.

  Presentation mode is display metadata only. It is not an authorization or
  permission boundary; access decisions remain in `Foglet.Authorization` and
  the owning domain contexts.

  Mode resolution intentionally ignores user theme state, active palette data,
  and Account theme preview state. Themes change color treatment, not a
  screen's layout category.
  """

  @type mode :: :bbs | :operator
  @type screen :: Foglet.TUI.App.screen()

  @bbs_screens [
    :login,
    :register,
    :verify,
    :main_menu,
    :board_list,
    :thread_list,
    :post_reader,
    :new_thread,
    :post_composer
  ]

  @operator_screens [:account, :moderation, :sysop]

  @screen_modes Map.new(@bbs_screens, &{&1, :bbs})
                |> Map.merge(Map.new(@operator_screens, &{&1, :operator}))

  @doc """
  Returns the locked list of supported presentation modes.
  """
  @spec modes() :: [mode(), ...]
  def modes, do: [:bbs, :operator]

  @doc """
  Returns the full current screen id to presentation mode map.
  """
  @spec screen_modes() :: %{screen() => mode()}
  def screen_modes, do: @screen_modes

  @doc """
  Returns every current screen id with a declared presentation mode.
  """
  @spec screen_ids() :: [screen()]
  def screen_ids, do: Map.keys(screen_modes())

  @doc """
  Returns the presentation mode for a known TUI screen id.

  Unknown ids raise instead of silently defaulting to a valid mode.
  """
  @spec mode_for!(screen() | atom()) :: mode()
  def mode_for!(screen) do
    case Map.fetch(screen_modes(), screen) do
      {:ok, mode} -> mode
      :error -> raise ArgumentError, "unknown TUI screen: #{inspect(screen)}"
    end
  end
end
