defmodule Foglet.TUI.Screens.Moderation.State do
  @moduledoc """
  Screen-local state for `Foglet.TUI.Screens.Moderation` (D-04, D-10, MODR-01).

  The app stores this struct at `state.screen_state[:moderation]`.

  Tabs (D-10, locked order):
      ["QUEUE", "LOG", "USERS", "SANCTIONS", "BOARDS"]

  Phase 0 scope: UI focus only. Real queue/log/user/sanction/board data arrives
  in Phase 8 (Moderation Workspace Population). The shared INVITES tab is NOT
  part of the Phase 0 Moderation tab set; Phase 4 may introduce it when
  `invite_code_generators == "mods"`, but Phase 0's locked D-10 list excludes it.
  """

  alias Foglet.TUI.Widgets.Input.Tabs

  @tabs ["QUEUE", "LOG", "USERS", "SANCTIONS", "BOARDS"]

  @type t :: %__MODULE__{
          tabs: Tabs.t(),
          active_tab: non_neg_integer()
        }

  defstruct [:tabs, active_tab: 0]

  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    active = Keyword.get(opts, :active, 0)
    %__MODULE__{tabs: Tabs.init(tabs: @tabs, active: active), active_tab: active}
  end

  @spec tab_labels() :: [String.t()]
  def tab_labels, do: @tabs
end
