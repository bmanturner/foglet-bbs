defmodule Foglet.TUI.Screens.Account.Render do
  @moduledoc """
  Pure render entry point for the Account screen.
  """

  alias Foglet.TUI.Presentation
  alias Foglet.TUI.Screens.Account.PrefsForm
  alias Foglet.TUI.Screens.Account.ProfileForm
  alias Foglet.TUI.Screens.Account.SSHKeysSurface
  alias Foglet.TUI.Screens.Account.State
  alias Foglet.TUI.Screens.Shared.InvitesSurface
  alias Foglet.TUI.Screens.ShellVisibility
  alias Foglet.TUI.Theme
  alias Foglet.TUI.Widgets.Chrome.ScreenFrame
  alias Foglet.TUI.Widgets.Input.Tabs

  import Raxol.Core.Renderer.View

  def render(state) when is_map(state), do: render_app_state(state)

  defp render_app_state(state) do
    ss = synced_screen_state(state)
    theme = account_theme(state, ss)
    active_label = active_label(ss) || "PROFILE"
    width = inner_width(state)
    height = terminal_height(state)

    content =
      column style: %{gap: 0} do
        [
          Tabs.render(ss.tabs, theme: theme, width: width),
          divider(char: "─", style: %{fg: theme.border.fg}),
          render_tab_body(active_label, ss, theme, width, height)
        ]
      end

    ScreenFrame.render(preview_state(state, theme), account_chrome(), content, key_bar(ss))
  end

  # FOG-130 Item 1: the key bar is tab-context-aware. The Tabs and System
  # groups are constant; the middle groups (Fields/List, Actions) reflect the
  # active tab and the SSH/INVITES sub-mode (list vs. add vs. confirm).
  # The 1-arity entry point is preserved for the D-26 contract
  # (layout_smoke_test).
  defp key_bar(ss), do: key_bar_for(ss, active_label(ss) || "PROFILE")

  defp key_bar_for(ss, active_label) do
    form_tab_navigation? = form_tab?(active_label) and not Map.get(ss, :tab_navigation?, false)

    tabs_group = %{
      label: "Tabs",
      commands: [%{key: tab_arrow_hint(form_tab_navigation?), label: "Tabs", priority: 10}]
    }

    system_group = %{
      label: "System",
      commands: [%{key: "Ctrl+Q", label: "Back", priority: 0}]
    }

    middle = middle_groups(active_label, ss)

    [tabs_group | middle] ++ [system_group]
  end

  defp middle_groups("PROFILE", ss), do: form_middle_groups(ss, :profile)
  defp middle_groups("PREFS", ss), do: form_middle_groups(ss, :prefs)

  defp middle_groups("SSH KEYS", %State{ssh_keys: %{mode: :add}}) do
    [
      %{label: "Field", commands: [%{key: "Tab", label: "Field", priority: 10}]},
      %{
        label: "Actions",
        commands: [
          %{key: "Enter", label: "Add key", priority: 30},
          %{key: "Esc", label: "Cancel", priority: 30}
        ]
      }
    ]
  end

  defp middle_groups("SSH KEYS", %State{ssh_keys: %{mode: :confirm_revoke}}) do
    [
      %{
        label: "Actions",
        commands: [
          %{key: "Enter", label: "Revoke key", priority: 30},
          %{key: "Esc", label: "Keep key", priority: 30}
        ]
      }
    ]
  end

  defp middle_groups("SSH KEYS", _ss) do
    [
      %{label: "List", commands: [%{key: "↑/↓", label: "Select", priority: 20}]},
      %{
        label: "Actions",
        commands: [
          %{key: "A", label: "Add key", priority: 30},
          %{key: "R", label: "Refresh", priority: 25},
          %{key: "D", label: "Revoke key", priority: 30}
        ]
      }
    ]
  end

  defp middle_groups("INVITES", %State{invites: %{mode: invites_mode}}) do
    case invites_mode do
      :confirm_revoke ->
        [
          %{
            label: "Actions",
            commands: [
              %{key: "Enter", label: "Revoke invite", priority: 30},
              %{key: "Esc", label: "Keep invite", priority: 30}
            ]
          }
        ]

      _ ->
        [
          %{label: "List", commands: [%{key: "↑/↓", label: "Select", priority: 20}]},
          %{
            label: "Actions",
            commands: [
              %{key: "G", label: "Generate invite", priority: 30},
              %{key: "R", label: "Refresh", priority: 25},
              %{key: "D", label: "Revoke invite", priority: 30}
            ]
          }
        ]
    end
  end

  defp middle_groups(_unknown, _ss) do
    [
      %{
        label: "Field",
        commands: [
          %{key: "Tab", label: "Next", priority: 10},
          %{key: "Shift+Tab", label: "Previous", priority: 10}
        ]
      },
      %{
        label: "Actions",
        commands: [
          %{key: "Enter/Ctrl+S", label: "Save", priority: 30},
          %{key: "Esc", label: "Cancel", priority: 30}
        ]
      }
    ]
  end

  defp form_tab?("PROFILE"), do: true
  defp form_tab?("PREFS"), do: true
  defp form_tab?(_), do: false

  # PROFILE/PREFS share the form-tab key cluster. PREFS adds an explicit
  # `↑/↓ Change` advert when an enum field (Time format / Theme) is focused
  # so users can discover the cycling affordance (FOG-130 Item 4).
  #
  # FOG-689: when a Modal.Form is active on PROFILE/PREFS, the Save/Cancel
  # actions must outrank Field Tab/Shift+Tab and Tabs in the priority
  # compaction so they survive 80-column compaction. CommandBar treats lower
  # priority numbers as higher retention, so Save/Cancel use priority 0 to
  # stay visible at 80x24 even when Field nav and Tabs are dropped.
  defp form_middle_groups(%State{} = ss, section) do
    base = [
      %{
        label: "Field",
        commands: [
          %{key: "Tab", label: "Next", priority: 10},
          %{key: "Shift+Tab", label: "Previous", priority: 10}
        ]
      }
    ]

    fields =
      if section == :prefs and prefs_enum_focused?(ss) do
        base ++
          [
            %{
              label: "Value",
              commands: [%{key: "↑/↓", label: "Change", priority: 5}]
            }
          ]
      else
        base
      end

    fields ++
      [
        %{
          label: "Actions",
          commands: [
            %{key: "Enter/Ctrl+S", label: "Save", priority: 5},
            %{key: "Esc", label: "Cancel", priority: 5}
          ]
        }
      ]
  end

  defp prefs_enum_focused?(%State{prefs_focus: focus}) when focus in [:time_format, :theme],
    do: true

  defp prefs_enum_focused?(_), do: false

  defp tab_arrow_hint(true), do: "Esc,←/→"
  defp tab_arrow_hint(false), do: "←/→"

  # ScreenFrame uses padding: 1 and border: :single, consuming 4 columns total.
  defp inner_width(state) do
    case Map.get(state, :terminal_size) do
      {w, _} when is_integer(w) -> max(w - 4, 0)
      _ -> 76
    end
  end

  defp terminal_height(state) do
    case Map.get(state, :terminal_size) do
      {_w, h} when is_integer(h) -> h
      _ -> 24
    end
  end

  defp synced_screen_state(state) do
    state
    |> get_screen_state()
    |> State.ensure_visibility(invites_visible?(state))
  end

  defp invites_visible?(state) do
    ShellVisibility.invites_visible?(
      Map.get(state, :current_user),
      Map.get(state, :session_context)
    )
  end

  defp get_screen_state(state) do
    case get_in(state.screen_state, [:account]) do
      nil -> State.new(init_opts_from_state(state))
      ss -> ss
    end
  end

  defp init_opts_from_state(state) do
    [
      invites_visible?:
        ShellVisibility.invites_visible?(
          Map.get(state, :current_user),
          Map.get(state, :session_context)
        ),
      current_user: Map.get(state, :current_user)
    ]
  end

  defp tab_labels(%State{tabs: %Tabs{raxol_state: raxol_state}}) do
    raxol_state
    |> Map.get(:tabs, [])
    |> Enum.map(&Map.fetch!(&1, :label))
  end

  defp active_label(%State{} = ss), do: Enum.at(tab_labels(ss), ss.active_tab)

  defp account_theme(state, %State{candidate_theme_id: nil}), do: Theme.from_state(state)

  defp account_theme(state, %State{candidate_theme_id: theme_id}) do
    case resolve_theme_id(theme_id) do
      nil -> Theme.from_state(state)
      id -> Theme.resolve(id)
    end
  end

  defp preview_state(state, theme) do
    sc = Map.get(state, :session_context) || %Foglet.TUI.SessionContext{}
    %{state | session_context: Map.put(sc, :theme, theme)}
  end

  defp account_chrome do
    %{
      title: "Account",
      mode: Presentation.mode_for!(:account),
      breadcrumb_parts: ["Foglet", "Account"]
    }
  end

  defp resolve_theme_id(theme_id) when is_binary(theme_id) do
    Enum.find(Theme.ids(), &(Atom.to_string(&1) == theme_id))
  end

  defp render_tab_body("PROFILE", ss, theme, _width, height),
    do: ProfileForm.render(ss, theme, form_viewport_opts(height, :profile))

  defp render_tab_body("PREFS", ss, theme, _width, height),
    do: PrefsForm.render(ss, theme, form_viewport_opts(height, :prefs))

  defp render_tab_body("SSH KEYS", ss, theme, width, _height),
    do: SSHKeysSurface.render(ss.ssh_keys, theme, width)

  defp render_tab_body("INVITES", ss, theme, _width, _height) do
    InvitesSurface.render(ss.invites, theme)
  end

  defp render_tab_body(_unknown, _ss, theme, _width, _height) do
    column style: %{gap: 0} do
      [text("", fg: theme.dim.fg)]
    end
  end

  defp form_viewport_opts(height, :prefs) when is_integer(height) and height <= 18,
    do: [max_visible: 1]

  defp form_viewport_opts(height, _section) when is_integer(height) and height <= 18,
    do: [max_visible: 2]

  defp form_viewport_opts(_height, _section), do: []
end
