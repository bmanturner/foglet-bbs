defmodule Foglet.TUI.Screens.Sysop.Render do
  @moduledoc """
  Pure render entry point for the Sysop screen.
  """

  alias Foglet.TUI.Screens.Shared.InvitesState
  alias Foglet.TUI.Screens.Shared.InvitesSurface
  alias Foglet.TUI.Screens.ShellVisibility
  alias Foglet.TUI.Screens.Sysop.BoardsView
  alias Foglet.TUI.Screens.Sysop.LimitsForm
  alias Foglet.TUI.Screens.Sysop.SiteForm
  alias Foglet.TUI.Screens.Sysop.State
  alias Foglet.TUI.Screens.Sysop.SystemSnapshot
  alias Foglet.TUI.Screens.Sysop.UsersView
  alias Foglet.TUI.Theme
  alias Foglet.TUI.Widgets.Chrome.ScreenFrame
  alias Foglet.TUI.Widgets.Input.Tabs

  import Raxol.Core.Renderer.View

  def render(state) when is_map(state), do: render_app_state(state)

  defp render_app_state(state) do
    if ShellVisibility.sysop_visible?(state.current_user) do
      render_authorized(state)
    else
      render_unauthorized(state)
    end
  end

  defp render_authorized(state) do
    ss = get_screen_state(state)
    theme = Theme.from_state(state)
    width = inner_width(state)
    height = inner_height(state)
    content = build_content(ss, theme, width, height)
    # Phase 29 D-26 (SYSOP-07): jump hint reads `1-N` where N is the
    # actual tab count. No INVITES special-case — generalises to any
    # future tab visibility flag.
    jump_hint = "1-#{length(State.tab_labels(ss))}"

    ScreenFrame.render(state, chrome_model(ss), content, sysop_commands(ss, jump_hint))
  end

  defp render_unauthorized(state) do
    theme = Theme.from_state(state)

    empty =
      column style: %{gap: 0} do
        [text("Sysop tools are not available for this account.", fg: theme.warning.fg)]
      end

    ScreenFrame.render(state, %{breadcrumb_parts: ["Foglet", "Sysop"]}, empty, [
      %{label: "System", commands: [%{key: "Q", label: "Back", priority: 0}]}
    ])
  end

  defp chrome_model(_ss) do
    %{breadcrumb_parts: ["Foglet", "Sysop"]}
  end

  defp sysop_commands(ss, jump_hint) do
    case boards_modal_mode(ss) do
      :form ->
        boards_form_commands()

      :confirm ->
        boards_confirm_commands()

      nil ->
        case form_tab_label(ss) do
          nil -> base_sysop_commands(ss, jump_hint)
          label -> form_tab_commands(label, jump_hint)
        end
    end
  end

  # FOG-689: when the active Sysop tab is SITE or LIMITS, both rendered as
  # inline Modal.Form-style editors, advertise Save/Cancel/Field navigation in
  # the screen-level command bar at priority 5 so they outrank Tab/Tabs (10)
  # and survive 80x24 keybar compaction. Lower priority numbers are higher
  # retention in CommandBar. Tabs nav is preserved at priority 10 so wide
  # terminals still show it; the System Back hint uses priority 0 so it wins
  # at every width.
  defp form_tab_label(ss) do
    case Enum.at(State.tab_labels(ss), ss.active_tab) do
      "SITE" -> "SITE"
      "LIMITS" -> "LIMITS"
      _ -> nil
    end
  end

  defp form_tab_commands(label, jump_hint) do
    [
      %{
        label: "System",
        commands: [%{key: "Q", label: "Back", priority: 0}]
      },
      %{
        label: form_group_label(label),
        commands: [
          %{key: "Ctrl+S", label: "Save", priority: 5},
          %{key: "Enter", label: "Save", priority: 5},
          %{key: "Esc", label: "Cancel", priority: 5}
        ]
      },
      %{
        label: "Field",
        commands: [
          %{key: "Tab", label: "Next", priority: 10},
          %{key: "Shift+Tab", label: "Previous", priority: 10}
        ]
      },
      %{
        label: "Tabs",
        commands: tabs_commands_for(label, jump_hint)
      }
    ]
  end

  # FOG-739: LIMITS routes plain digits 0–9 into the focused numeric draft
  # (`Foglet.TUI.Screens.Sysop.digit_consumed_by_active_tab?/2`), so the global
  # `1-N Jump` shortcut is not actually wired up while the form has focus.
  # Advertising it caused sysops to press `4` expecting SYSTEM and silently
  # extend `Post length limit`. Suppress the Jump hint on LIMITS — arrow-key
  # tab navigation still works and remains advertised.
  #
  # SITE keeps the Jump advert (FOG-693): pinned at priority 0 so it survives
  # 64x22 compaction even when Save/Cancel (priority 5) compete for keybar
  # real estate.
  defp tabs_commands_for("LIMITS", _jump_hint) do
    [%{key: "←/→", label: "Switch", priority: 10}]
  end

  defp tabs_commands_for(_label, jump_hint) do
    [
      %{key: "←/→", label: "Switch", priority: 10},
      %{key: jump_hint, label: "Jump", priority: 0}
    ]
  end

  defp form_group_label("SITE"), do: "Site"
  defp form_group_label("BOARDS"), do: "Boards"
  defp form_group_label("LIMITS"), do: "Limits"
  defp form_group_label(_), do: "Form"

  defp base_sysop_commands(ss, jump_hint) do
    base = [
      %{
        label: "System",
        commands: [%{key: "Q", label: "Back", priority: 0}]
      },
      %{
        label: "Tabs",
        commands: [
          %{key: "←/→", label: "Switch", priority: 10},
          %{key: jump_hint, label: "Jump", priority: 10}
        ]
      }
    ]

    base
    |> maybe_add_boards(ss)
    |> maybe_add_retry(ss)
    |> maybe_add_revoke(ss)
  end

  # FOG-670: when the BOARDS tab has a modal/form active, the screen-level
  # command bar advertises save/cancel/field navigation instead of generic
  # tab-jump hints, so the form is not silently competing with stale list-mode
  # advice. Tab navigation is gated by the active screen reducer (Pitfall 5)
  # and would just fall through to no-ops while the modal is open.
  defp boards_form_commands do
    [
      %{
        label: "Form",
        commands: [
          %{key: "Tab/Shift+Tab", label: "Fields", priority: 0},
          %{key: "Enter/Ctrl+S", label: "Save", priority: 0},
          %{key: "Esc", label: "Cancel", priority: 0}
        ]
      }
    ]
  end

  defp boards_confirm_commands do
    [
      %{
        label: "Confirm",
        commands: [
          %{key: "Y", label: "Yes", priority: 0},
          %{key: "N/Esc", label: "No", priority: 0}
        ]
      }
    ]
  end

  defp boards_modal_mode(ss) do
    active_label = Enum.at(State.tab_labels(ss), ss.active_tab)

    case {active_label, ss.boards_view} do
      {"BOARDS", {:loaded, sub}} -> BoardsView.modal_mode(sub)
      _ -> nil
    end
  end

  defp maybe_add_boards(groups, ss) do
    case Enum.at(State.tab_labels(ss), ss.active_tab) do
      "BOARDS" ->
        groups ++
          [
            %{
              label: "Boards",
              commands: [
                %{key: "↑/↓", label: "Move", priority: 0},
                %{key: "Enter", label: "Collapse/expand", priority: 0},
                %{key: "n/e", label: "Board", priority: 5},
                %{key: "N/E", label: "Category", priority: 5},
                %{key: "D", label: "Archive", priority: 5}
              ]
            }
          ]

      _ ->
        groups
    end
  end

  # Phase 29 D-25 (SYSOP-06): [X] Revoke is advertised in the Sysop command
  # bar only when (a) the active tab is INVITES, (b) `armed_revoke?` is true
  # on the screen state (set by Enter on a focused non-revoked row), and
  # (c) the focused invite is still non-revoked.
  defp maybe_add_revoke(groups, ss) do
    active_label = Enum.at(State.tab_labels(ss), ss.active_tab)

    cond do
      active_label != "INVITES" ->
        groups

      not Map.get(ss, :armed_revoke?, false) ->
        groups

      true ->
        case InvitesState.selected_item(ss.invites) do
          %{status: status} when status != :revoked ->
            groups ++
              [%{label: "Invite", commands: [%{key: "X", label: "Revoke", priority: 5}]}]

          _ ->
            groups
        end
    end
  end

  # Phase 29 D-13: [R] Retry is advertised in the Sysop command bar only when
  # the *active* tab is in `{:error, reason}` with reason != :forbidden.
  defp maybe_add_retry(groups, ss) do
    active_label = Enum.at(State.tab_labels(ss), ss.active_tab)
    slot = slot_for(active_label)

    case slot && Map.get(ss, slot) do
      {:error, reason} when reason != :forbidden ->
        groups ++
          [%{label: "Action", commands: [%{key: "R", label: "Retry", priority: 5}]}]

      _ ->
        groups
    end
  end

  defp slot_for("BOARDS"), do: :boards_view
  defp slot_for("LIMITS"), do: :limits_form
  defp slot_for("SYSTEM"), do: :system_snapshot
  defp slot_for("USERS"), do: :users_view
  defp slot_for(_), do: nil

  # ScreenFrame uses padding: 1 and border: :single, consuming 4 columns total.
  defp inner_width(state) do
    case Map.get(state, :terminal_size) do
      {w, _} when is_integer(w) -> max(w - 4, 0)
      _ -> 76
    end
  end

  # ScreenFrame contributes the top and bottom rows; sysop content then spends
  # one row on tabs and one row on its divider before rendering the active tab.
  defp inner_height(state) do
    case Map.get(state, :terminal_size) do
      {_, h} when is_integer(h) -> max(h - 4, 1)
      _ -> 20
    end
  end

  defp build_content(ss, theme, width, height) do
    active_label = Enum.at(State.tab_labels(ss), ss.active_tab)
    body = render_tab_body(active_label, ss, theme, width, height)

    column style: %{gap: 0} do
      [
        Tabs.render(ss.tabs, theme: theme, width: width),
        divider(char: "─", style: %{fg: theme.border.fg}),
        body
      ]
    end
  end

  defp render_tab_body("SITE", ss, theme, width, height) do
    case ss.site_form do
      nil -> loading_panel(theme)
      form -> SiteForm.render(form, theme, form_viewport_opts(height, :site, width))
    end
  end

  defp render_tab_body("BOARDS", ss, theme, width, height) do
    case ss.boards_view do
      :not_loaded -> loading_panel(theme)
      :loading -> loading_panel(theme)
      {:loaded, sub} -> BoardsView.render(sub, theme, width: width, visible_height: height)
      {:error, :forbidden} -> forbidden_panel(theme)
      {:error, _other} -> error_panel("boards", theme)
    end
  end

  defp render_tab_body("LIMITS", ss, theme, width, height) do
    case ss.limits_form do
      :not_loaded -> loading_panel(theme)
      :loading -> loading_panel(theme)
      {:loaded, sub} -> LimitsForm.render(sub, theme, width: width, visible_height: height)
      {:error, :forbidden} -> forbidden_panel(theme)
      {:error, _other} -> error_panel("limits", theme)
    end
  end

  defp render_tab_body("SYSTEM", ss, theme, _width, _height) do
    case ss.system_snapshot do
      :not_loaded -> loading_panel(theme)
      :loading -> loading_panel(theme)
      {:loaded, sub} -> SystemSnapshot.render(sub, theme)
      {:error, :forbidden} -> forbidden_panel(theme)
      {:error, _other} -> error_panel("system", theme)
    end
  end

  defp render_tab_body("USERS", ss, theme, _width, _height) do
    case ss.users_view do
      :not_loaded -> loading_panel(theme)
      :loading -> loading_panel(theme)
      {:loaded, sub} -> UsersView.render(sub, theme)
      {:error, :forbidden} -> forbidden_panel(theme)
      {:error, _other} -> error_panel("users", theme)
    end
  end

  defp render_tab_body("INVITES", ss, theme, _width, _height),
    do: InvitesSurface.render(ss.invites, theme)

  # Lifecycle panels (D-08, D-11, D-12). Pattern-match order in
  # `render_tab_body/3` MUST keep `{:error, :forbidden}` BEFORE
  # `{:error, _other}` — see Pitfall 3.
  defp loading_panel(theme) do
    column style: %{gap: 0} do
      [text("Loading sysop tools…", fg: theme.dim.fg)]
    end
  end

  defp forbidden_panel(theme) do
    column style: %{gap: 0} do
      [text("Your role no longer allows access to this tab.", fg: theme.warning.fg)]
    end
  end

  defp error_panel(tab, theme) do
    column style: %{gap: 0} do
      [text("Could not load #{tab}. Press R to try again.", fg: theme.error.fg)]
    end
  end

  defp form_viewport_opts(height, _section, width) when is_integer(height) and height <= 18,
    do: [max_visible: 2, width: width]

  defp form_viewport_opts(_height, _section, width), do: [width: width]

  defp get_screen_state(state) do
    ss =
      case get_in(state.screen_state, [:sysop]) do
        %State{} = ss ->
          ss

        _ ->
          State.render_fallback(
            current_user: state.current_user,
            session_context: state.session_context
          )
      end

    State.refresh_tabs(ss,
      invites_visible?:
        ShellVisibility.invites_visible?(state.current_user, state.session_context)
    )
  end
end
