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
  alias Foglet.TUI.Screens.Sysop.BoardsView
  alias Foglet.TUI.Screens.Sysop.LimitsForm
  alias Foglet.TUI.Screens.Sysop.SiteForm
  alias Foglet.TUI.Screens.Sysop.SystemSnapshot
  alias Foglet.TUI.Screens.Sysop.UsersView
  alias Foglet.TUI.Widgets.Input.Tabs

  @base_tabs ["SITE", "BOARDS", "LIMITS", "SYSTEM", "USERS"]

  @typedoc """
  Tagged lifecycle enum for Sysop tab body slots (Phase 29 D-07, D-10).

  `:not_loaded` is the default — the tab has never been requested. The
  Sysop screen / `Foglet.TUI.App` flips it to `:loading` synchronously
  with the dispatch tuple so the very first render after entry shows
  the Loading panel rather than a stale `:not_loaded`. `{:loaded, sub}`
  carries the existing submodule struct verbatim. `{:error, reason}`
  surfaces a tab-body error panel; `:forbidden` is rendered as the
  "Insufficient role" copy and any other reason is rendered as
  "Could not load <tab>. Press R to retry." (D-08, D-12).
  """
  @type lifecycle(struct_t) ::
          :not_loaded
          | :loading
          | {:loaded, struct_t}
          | {:error, atom()}

  @type t :: %__MODULE__{
          tabs: Tabs.t(),
          active_tab: non_neg_integer(),
          tab_labels: [String.t()],
          invites: InvitesState.t(),
          site_form: term() | nil,
          limits_form: lifecycle(LimitsForm.t()),
          boards_view: lifecycle(BoardsView.t()),
          system_snapshot: lifecycle(SystemSnapshot.t()),
          users_view: lifecycle(UsersView.t()),
          armed_revoke?: boolean()
        }

  defstruct [
    :tabs,
    active_tab: 0,
    tab_labels: @base_tabs,
    invites: InvitesState.new(),
    site_form: nil,
    limits_form: :not_loaded,
    boards_view: :not_loaded,
    system_snapshot: :not_loaded,
    users_view: :not_loaded,
    # Phase 29 D-25: two-step `[X] Revoke` gesture. Pressing Enter on a
    # focused non-revoked INVITES row arms this flag, advertising the
    # `[X] Revoke` group in the Sysop command bar. Pressing X (while
    # armed) dispatches `InvitesActions.revoke_selected/2`. Navigation
    # away (focus move within INVITES, tab switch) clears the flag back
    # to false. Lives on Sysop.State (option b) so the shared
    # InvitesState surface stays free of Sysop-specific UI concepts.
    armed_revoke?: false
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
      invites: Keyword.get(opts, :invites, InvitesState.new()),
      site_form:
        Keyword.get_lazy(opts, :site_form, fn ->
          SiteForm.init(current_user: Keyword.get(opts, :current_user))
        end)
    }
  end

  @doc """
  Builds a defensive render-only fallback without initializing config-backed
  SITE form state.
  """
  @spec render_fallback(keyword()) :: t()
  def render_fallback(opts \\ []) do
    active = Keyword.get(opts, :active, 0)
    labels = tab_labels(opts)
    active = clamp_active(active, labels)

    %__MODULE__{
      tabs: Tabs.init(tabs: labels, active: active),
      active_tab: active,
      tab_labels: labels,
      invites: Keyword.get(opts, :invites, InvitesState.new()),
      site_form: nil
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
