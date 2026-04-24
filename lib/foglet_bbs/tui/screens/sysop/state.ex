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

  alias Foglet.TUI.Screens.Shared.InvitesState
  alias Foglet.TUI.Screens.ShellVisibility
  alias Foglet.TUI.Widgets.Input.Tabs

  @base_tabs ["SITE", "BOARDS", "LIMITS", "SYSTEM", "USERS"]

  @type t :: %__MODULE__{
          tabs: Tabs.t(),
          active_tab: non_neg_integer(),
          tab_labels: [String.t()],
          invites: InvitesState.t(),
          site_form: term() | nil,
          limits_form: term() | nil,
          boards_view: term() | nil,
          system_snapshot: term() | nil
        }

  defstruct [
    :tabs,
    active_tab: 0,
    tab_labels: @base_tabs,
    invites: InvitesState.new(),
    site_form: nil,
    limits_form: nil,
    boards_view: nil,
    system_snapshot: nil
  ]

  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    active = Keyword.get(opts, :active, 0)
    labels = tab_labels(opts)
    active = clamp_active(active, labels)

    %__MODULE__{
      tabs: Tabs.init(tabs: labels, active: active),
      active_tab: active,
      tab_labels: labels,
      invites: Keyword.get(opts, :invites, InvitesState.new())
    }
  end

  @spec tab_labels() :: [String.t()]
  def tab_labels, do: @base_tabs

  @spec tab_labels(t() | keyword() | boolean()) :: [String.t()]
  def tab_labels(%__MODULE__{tab_labels: labels}), do: labels

  def tab_labels(opts) when is_list(opts) do
    opts
    |> invites_visible?()
    |> tab_labels()
  end

  def tab_labels(invites_visible?) when is_boolean(invites_visible?) do
    if invites_visible?, do: @base_tabs ++ ["INVITES"], else: @base_tabs
  end

  @spec refresh_tabs(t(), keyword()) :: t()
  def refresh_tabs(%__MODULE__{} = state, opts) do
    labels = tab_labels(opts)
    active = clamp_active(state.active_tab, labels)

    if labels == state.tab_labels and active == state.active_tab do
      state
    else
      %{
        state
        | tabs: Tabs.init(tabs: labels, active: active),
          active_tab: active,
          tab_labels: labels
      }
    end
  end

  defp invites_visible?(opts) do
    case Keyword.fetch(opts, :invites_visible?) do
      {:ok, visible?} when is_boolean(visible?) ->
        visible?

      :error ->
        ShellVisibility.invites_visible?(
          Keyword.get(opts, :current_user),
          Keyword.get(opts, :session_context)
        )
    end
  end

  defp clamp_active(active, labels) when is_integer(active) do
    active |> max(0) |> min(length(labels) - 1)
  end

  defp clamp_active(_active, _labels), do: 0
end
