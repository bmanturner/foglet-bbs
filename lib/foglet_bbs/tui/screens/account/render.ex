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

    content =
      column style: %{gap: 0} do
        [
          Tabs.render(ss.tabs, theme: theme, width: width),
          divider(char: "─", style: %{fg: theme.border.fg}),
          render_tab_body(active_label, ss, theme)
        ]
      end

    ScreenFrame.render(preview_state(state, theme), account_chrome(), content, key_bar(ss))
  end

  # Phase 29 D-26 (SYSOP-07): the key bar is rendered at request time so the
  # `1-N Jump` hint reflects the actual tab count (3 without INVITES, 4 with).
  # Inserted between `←/→ Tab` and `Tab Field` so the navigation cluster reads
  # left-to-right: arrows / numbers / tab-cycle.
  defp key_bar(ss) do
    [
      {"←/→", "Tab"},
      {jump_hint(length(tab_labels(ss))), "Jump"},
      {"Tab", "Field"},
      {"Enter", "Save"},
      {"Esc", "Cancel"},
      {"Ctrl+Q", "Back"}
    ]
  end

  defp jump_hint(n) when is_integer(n) and n > 0, do: "1-#{n}"

  # ScreenFrame uses padding: 1 and border: :single, consuming 4 columns total.
  defp inner_width(state) do
    case Map.get(state, :terminal_size) do
      {w, _} when is_integer(w) -> max(w - 4, 0)
      _ -> 76
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

  defp render_tab_body("PROFILE", ss, theme), do: ProfileForm.render(ss, theme)

  defp render_tab_body("PREFS", ss, theme), do: PrefsForm.render(ss, theme)

  defp render_tab_body("SSH KEYS", ss, theme), do: SSHKeysSurface.render(ss.ssh_keys, theme)

  defp render_tab_body("INVITES", ss, theme) do
    InvitesSurface.render(ss.invites, theme)
  end

  defp render_tab_body(_unknown, _ss, theme) do
    column style: %{gap: 0} do
      [text("", fg: theme.dim.fg)]
    end
  end
end
