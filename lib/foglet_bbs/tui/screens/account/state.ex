defmodule Foglet.TUI.Screens.Account.State do
  @moduledoc """
  Screen-local state for `Foglet.TUI.Screens.Account` (D-04, D-08, D-09).

  The app stores this struct at `state.screen_state[:account]`.

  Inline Account drafts use atom keys matching the field names because the
  drafts are screen-local structs/maps, not user-supplied persistence params.

  Tabs (D-08, D-09):
    * base — `["PROFILE", "PREFS", "SSH KEYS"]`
    * with INVITES visibility — `["PROFILE", "PREFS", "SSH KEYS", "INVITES"]`

  Profile and preference drafts are seeded from the current user. They remain
  local until Account save handling emits an explicit command; `candidate_theme_id`
  is only a render preview and does not mutate session context.
  """

  alias Foglet.TUI.Effect
  alias Foglet.TUI.Screens.Account.SSHKeysState
  alias Foglet.TUI.Screens.Account.Timezones
  alias Foglet.TUI.Screens.Shared.InvitesState
  alias Foglet.TUI.Screens.Shared.InvitesSurface
  alias Foglet.TUI.Theme
  alias Foglet.TUI.Widgets.Input.Tabs
  alias Foglet.TUI.Widgets.Modal.Form, as: ModalForm

  @base_tabs ["PROFILE", "PREFS", "SSH KEYS"]
  @invites_tab "INVITES"

  @type t :: %__MODULE__{
          tabs: Tabs.t(),
          active_tab: non_neg_integer(),
          tab_labels: [String.t()],
          ssh_keys: SSHKeysState.t(),
          invites: InvitesState.t(),
          profile_form: ModalForm.t() | nil,
          prefs_form: ModalForm.t() | nil,
          profile_draft: map(),
          prefs_draft: map(),
          profile_focus: atom(),
          prefs_focus: atom(),
          profile_errors: map(),
          prefs_errors: map(),
          profile_dirty?: boolean(),
          prefs_dirty?: boolean(),
          candidate_theme_id: String.t() | nil,
          status_message: String.t() | nil
        }

  defstruct [
    :tabs,
    active_tab: 0,
    tab_labels: @base_tabs,
    ssh_keys: nil,
    invites: nil,
    profile_form: nil,
    prefs_form: nil,
    profile_draft: %{},
    prefs_draft: %{},
    profile_focus: :location,
    prefs_focus: :timezone,
    profile_errors: %{},
    prefs_errors: %{},
    profile_dirty?: false,
    prefs_dirty?: false,
    candidate_theme_id: nil,
    status_message: nil
  ]

  @doc """
  Build a fresh Account screen-state struct.

  Options:
    * `:invites_visible?` — boolean (default `false`). When true, includes the
      future-facing `INVITES` tab in the tab set (D-09).
    * `:active` — initial active tab index (default `0`).
    * `:current_user` — optional user struct/map used to seed inline drafts.

  The INVITES tab's presence is synchronized from runtime
  `:invites_visible?` policy by `ensure_visibility/2`.
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    invites? = Keyword.get(opts, :invites_visible?, false)
    active = Keyword.get(opts, :active, 0)
    current_user = Keyword.get(opts, :current_user)
    labels = tab_labels(invites?)

    %__MODULE__{
      tabs: Tabs.init(tabs: labels, active: active),
      active_tab: active,
      tab_labels: labels,
      ssh_keys: SSHKeysState.new(),
      invites: InvitesSurface.default_state()
    }
    |> seed_from_user(current_user)
  end

  @doc """
  Seeds profile and preference drafts from the current user.

  Nil/missing values become empty strings for editable text fields. Time format
  and theme fall back to the Account defaults expected by Phase 05.
  """
  @spec seed_from_user(t(), map() | struct() | nil) :: t()
  def seed_from_user(%__MODULE__{} = state, user) do
    pd = profile_draft(user)
    prd = prefs_draft(user)

    %{
      state
      | profile_draft: pd,
        prefs_draft: prd,
        profile_form: build_profile_form(pd),
        prefs_form: build_prefs_form(prd),
        profile_errors: %{},
        prefs_errors: %{},
        profile_dirty?: false,
        prefs_dirty?: false,
        candidate_theme_id: nil
    }
  end

  @doc """
  Rebuilds the tab widget when runtime INVITES visibility changes.

  Preserves PROFILE/PREFS order and clamps the active tab if INVITES
  disappears while selected.
  """
  @spec ensure_visibility(t(), boolean()) :: t()
  def ensure_visibility(%__MODULE__{} = state, invites_visible?) do
    labels = tab_labels(invites_visible?)

    if current_tab_labels(state.tabs) == labels do
      state
    else
      active = clamp_active(state.active_tab, labels)

      %{
        state
        | tabs: Tabs.init(tabs: labels, active: active),
          active_tab: active,
          tab_labels: labels
      }
    end
  end

  @doc "Returns the tab label list in the order they appear on screen."
  @spec tab_labels(boolean()) :: [String.t()]
  def tab_labels(true), do: @base_tabs ++ [@invites_tab]
  def tab_labels(false), do: @base_tabs

  defp current_tab_labels(%Tabs{raxol_state: raxol_state}) do
    raxol_state
    |> Map.get(:tabs, [])
    |> Enum.map(&Map.fetch!(&1, :label))
  end

  defp clamp_active(active, labels) when is_integer(active) do
    active |> max(0) |> min(length(labels) - 1)
  end

  defp clamp_active(_active, _labels), do: 0

  defp profile_draft(user) do
    %{
      location: user_value(user, :location, ""),
      tagline: user_value(user, :tagline, ""),
      real_name: user_value(user, :real_name, "")
    }
  end

  defp prefs_draft(user) do
    preferences = user_value(user, :preferences, %{}) || %{}

    %{
      timezone: user_value(user, :timezone, "Etc/UTC") || "Etc/UTC",
      time_format:
        Map.get(preferences, "time_format") || Map.get(preferences, :time_format) || "12h",
      theme: user_value(user, :theme, "gray") || "gray"
    }
  end

  defp user_value(nil, _key, default), do: default

  defp user_value(user, key, default) when is_map(user) do
    Map.get(user, key, default)
  end

  # ---------------------------------------------------------------------------
  # Modal.Form builders (Plan 02 — D-01 / Pattern 1)
  # ---------------------------------------------------------------------------

  defp build_profile_form(draft) do
    ModalForm.init(
      title: "Profile",
      fields: [
        %{name: :location, type: :text, label: "Location", value: draft.location || ""},
        %{name: :tagline, type: :text, label: "Tagline", value: draft.tagline || ""},
        %{
          name: :real_name,
          type: :text,
          label: "Real name",
          description: "For friends and the sysop; blank uses your handle.",
          value: draft.real_name || ""
        }
      ],
      on_submit: fn payload -> Effect.modal_submit(:account, :profile, payload) end,
      on_cancel: fn -> :ok end
    )
  end

  defp build_prefs_form(draft) do
    theme_ids = theme_id_strings()

    ModalForm.init(
      title: "Preferences",
      fields: [
        %{
          name: :timezone,
          type: :select_list,
          label: "Timezone",
          required: true,
          choices: Timezones.choices_for(draft.timezone),
          description: "Search by city or IANA name; save to keep it.",
          value: draft.timezone || "Etc/UTC",
          max_height: 6
        },
        %{
          name: :time_format,
          type: :enum,
          label: "Time format",
          choices: ["12h", "24h"],
          value: draft.time_format || "12h"
        },
        %{
          name: :theme,
          type: :enum,
          label: "Theme",
          choices: theme_ids,
          description: "Preview changes here; save to keep them.",
          value: draft.theme || "gray"
        }
      ],
      on_submit: fn payload -> Effect.modal_submit(:account, :prefs, payload) end,
      on_cancel: fn -> :ok end
    )
  end

  defp theme_id_strings, do: Enum.map(Theme.ids(), &Atom.to_string/1)
end
