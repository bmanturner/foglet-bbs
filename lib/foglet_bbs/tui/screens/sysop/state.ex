defmodule Foglet.TUI.Screens.Sysop.State do
  @moduledoc """
  Screen-local state for `Foglet.TUI.Screens.Sysop` (D-04, D-11, SYSO-01).

  The app stores this struct at `state.screen_state[:sysop]`.

  Tabs (D-11, locked order):
      ["SITE", "BOARDS", "LIMITS", "SYSTEM", "USERS"]

  Phase 0 scope: UI focus only. Real site policy, boards, limits, system
  details, and user administration arrive in Phase 2. The shared INVITES
  tab is NOT part of the Phase 0 Sysop tab set; Phase 4 adds it when
  `invite_code_generators == "sysop_only"` per SYSO-05.
  """

  alias Foglet.TUI.Widgets.Input.Tabs

  @tabs ["SITE", "BOARDS", "LIMITS", "SYSTEM", "USERS"]

  @type t :: %__MODULE__{
          tabs: Tabs.t(),
          active_tab: non_neg_integer(),
          site_form: term() | nil,
          limits_form: term() | nil,
          boards_view: term() | nil,
          system_snapshot: term() | nil
        }

  defstruct [
    :tabs,
    active_tab: 0,
    site_form: nil,
    limits_form: nil,
    boards_view: nil,
    system_snapshot: nil
  ]

  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    active = Keyword.get(opts, :active, 0)
    %__MODULE__{tabs: Tabs.init(tabs: @tabs, active: active), active_tab: active}
  end

  @spec tab_labels() :: [String.t()]
  def tab_labels, do: @tabs
end
