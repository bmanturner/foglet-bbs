defmodule Foglet.TUI.Screens.Moderation.State do
  @moduledoc """
  Screen-local state for `Foglet.TUI.Screens.Moderation` (D-04, D-10, MODR-01).

  The app stores this struct at `state.screen_state[:moderation]`.

  Tabs (D-10, locked order):
      ["QUEUE", "LOG", "USERS", "SANCTIONS", "BOARDS"]

  The state holds bounded, scope-aware read rows populated by the TUI app.
  Phase 4 appends the shared INVITES tab when runtime invite policy permits
  moderators to generate codes.
  """

  alias Foglet.TUI.Screens.Shared.InvitesState
  alias Foglet.TUI.Screens.Shared.InvitesSurface
  alias Foglet.TUI.Widgets.Input.Tabs

  @base_tabs ["QUEUE", "LOG", "USERS", "SANCTIONS", "BOARDS"]
  @invites_tab "INVITES"

  @type t :: %__MODULE__{
          tabs: Tabs.t(),
          active_tab: non_neg_integer(),
          invites: InvitesState.t(),
          scopes: list(),
          queue: list(),
          mod_log: list(),
          users: list(),
          boards: list(),
          loading?: boolean(),
          error: term()
        }

  defstruct [
    :tabs,
    active_tab: 0,
    invites: nil,
    scopes: [],
    queue: [],
    mod_log: [],
    users: [],
    boards: [],
    loading?: false,
    error: nil
  ]

  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    invites? = Keyword.get(opts, :invites_visible?, false)
    active = Keyword.get(opts, :active, 0)
    labels = tab_labels(invites?)
    active = min(active, length(labels) - 1)

    %__MODULE__{
      tabs: Tabs.init(tabs: labels, active: active),
      active_tab: active,
      invites: InvitesSurface.default_state(),
      scopes: Keyword.get(opts, :scopes, []),
      queue: Keyword.get(opts, :queue, []),
      mod_log: Keyword.get(opts, :mod_log, []),
      users: Keyword.get(opts, :users, []),
      boards: Keyword.get(opts, :boards, []),
      loading?: Keyword.get(opts, :loading?, false),
      error: Keyword.get(opts, :error)
    }
  end

  @spec tab_labels() :: [String.t()]
  def tab_labels, do: @base_tabs

  @spec tab_labels(boolean()) :: [String.t()]
  def tab_labels(true), do: @base_tabs ++ [@invites_tab]
  def tab_labels(false), do: @base_tabs
end
