defmodule Foglet.TUI.Screens.Account.State do
  @moduledoc """
  Screen-local state for `Foglet.TUI.Screens.Account` (D-04, D-08, D-09).

  The app stores this struct at `state.screen_state[:account]`.

  Tabs (D-08, D-09):
    * base — `["PROFILE", "PREFS"]`
    * with INVITES visibility — `["PROFILE", "PREFS", "INVITES"]`

  Phase 0 scope: this state holds UI focus only — no profile data, no preference
  values. Those arrive in Phase 5.
  """

  alias Foglet.TUI.Screens.Shared.InvitesState
  alias Foglet.TUI.Screens.Shared.InvitesSurface
  alias Foglet.TUI.Widgets.Input.Tabs

  @base_tabs ["PROFILE", "PREFS"]
  @invites_tab "INVITES"

  @type t :: %__MODULE__{
          tabs: Tabs.t(),
          active_tab: non_neg_integer(),
          invites: InvitesState.t()
        }

  defstruct [:tabs, active_tab: 0, invites: nil]

  @doc """
  Build a fresh Account screen-state struct.

  Options:
    * `:invites_visible?` — boolean (default `false`). When true, includes the
      future-facing `INVITES` tab in the tab set (D-09).
    * `:active` — initial active tab index (default `0`).
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    invites? = Keyword.get(opts, :invites_visible?, false)
    active = Keyword.get(opts, :active, 0)

    %__MODULE__{
      tabs: Tabs.init(tabs: tab_labels(invites?), active: active),
      active_tab: active,
      invites: InvitesSurface.default_state()
    }
  end

  @doc "Returns the tab label list in the order they appear on screen."
  @spec tab_labels(boolean()) :: [String.t()]
  def tab_labels(true), do: @base_tabs ++ [@invites_tab]
  def tab_labels(false), do: @base_tabs
end
