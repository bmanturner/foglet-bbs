defmodule Foglet.TUI.Screens.Account do
  @moduledoc """
  Account shell screen for Foglet BBS (ACCT-01, D-03, D-04, D-05, D-08, D-09, D-12, D-13).

  Implements `Foglet.TUI.Screen` behaviour with three tabs:
    * PROFILE  — inline private profile draft form
    * PREFS    — inline presentation preference draft form with local theme preview
    * SSH KEYS — self-service SSH public-key management
    * INVITES  — conditional; shown when `ShellVisibility.invites_visible?/2` returns
                 true (D-09). Rendered via the shared `InvitesSurface` primitive (D-06).

  Tab focus is delegated entirely to `Foglet.TUI.Widgets.Input.Tabs` (D-05).
  Screen-local state lives at `state.screen_state[:account]` as a
  `%Foglet.TUI.Screens.Account.State{}` struct (D-04).

  Account PROFILE/PREFS save keys emit command tuples for the app layer to persist
  later in Phase 5. INVITES live actions still delegate to the shared surface.

  Security:
    * T-00-01: No Repo/domain imports; no fake operator actions.
    * T-00-04: INVITES tab body delegates entirely to `InvitesSurface.render/2`.
    * T-05-09: Candidate theme previews only through Account rendering.
  """

  @behaviour Foglet.TUI.Screen

  import Raxol.Core.Renderer.View

  alias Foglet.TUI.Presentation
  alias Foglet.TUI.Screens.Account.PrefsForm
  alias Foglet.TUI.Screens.Account.ProfileForm
  alias Foglet.TUI.Screens.Account.SSHKeysActions
  alias Foglet.TUI.Screens.Account.SSHKeysSurface
  alias Foglet.TUI.Screens.Account.State
  alias Foglet.TUI.Screens.Shared.InvitesActions
  alias Foglet.TUI.Screens.Shared.InvitesSurface
  alias Foglet.TUI.Screens.ShellVisibility
  alias Foglet.TUI.Theme
  alias Foglet.TUI.Widgets.Chrome.ScreenFrame
  alias Foglet.TUI.Widgets.Input.Tabs

  @impl true
  @spec init_screen_state(keyword()) :: State.t()
  def init_screen_state(opts \\ []) do
    State.new(translate_opts(opts))
  end

  @impl true
  @spec render(map()) :: any()
  def render(state) do
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

  @impl true
  @spec handle_key(map(), map()) :: {:update, map(), list()} | :no_match
  # Ctrl+Q leaves the screen. Bare q/Q would eat input on form fields, and Esc
  # is reserved for in-form cancel (e.g., dropping a theme preview).
  def handle_key(%{key: :char, char: c, ctrl: true}, state) when c in ["q", "Q"] do
    {:update, %{state | current_screen: :main_menu}, []}
  end

  def handle_key(event, state) do
    ss = synced_screen_state(state)
    {new_tabs, action} = Tabs.handle_event(event, ss.tabs)

    new_active =
      case action do
        {:tab_changed, idx} -> idx
        _ -> ss.active_tab
      end

    new_ss = %{ss | tabs: new_tabs, active_tab: new_active}

    cond do
      action != nil ->
        actor = Map.get(state, :current_user)

        new_ss =
          new_ss
          |> maybe_load_ssh_keys(actor)
          |> maybe_load_invites(actor)

        {:update, put_screen_state(state, new_ss), []}

      active_label(ss) == "SSH KEYS" ->
        delegate_ssh_keys_key(event, state, ss)

      active_label(ss) == "INVITES" ->
        delegate_invites_key(event, state, ss)

      active_label(ss) == "PROFILE" ->
        delegate_profile_key(event, state, ss)

      active_label(ss) == "PREFS" ->
        delegate_prefs_key(event, state, ss)

      true ->
        :no_match
    end
  end

  # --- private helpers ---

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
      nil -> init_screen_state(init_opts_from_state(state))
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

  # Translate :role option to :invites_visible? so that
  # init_screen_state(role: :sysop) works from tests and direct callers.
  defp translate_opts(opts) do
    case Keyword.pop(opts, :role) do
      {nil, opts} ->
        opts

      {role, opts} ->
        visible? = InvitesSurface.visible?(%{role: role}, nil)
        Keyword.put_new(opts, :invites_visible?, visible?)
    end
  end

  defp tab_labels(%State{tabs: %Tabs{raxol_state: raxol_state}}) do
    raxol_state
    |> Map.get(:tabs, [])
    |> Enum.map(&Map.fetch!(&1, :label))
  end

  defp active_label(%State{} = ss), do: Enum.at(tab_labels(ss), ss.active_tab)

  defp maybe_load_invites(%State{} = ss, actor) do
    if active_label(ss) == "INVITES" and not is_list(ss.invites.items) do
      {:ok, invites} = InvitesActions.load(actor, ss.invites)
      %{ss | invites: invites}
    else
      ss
    end
  end

  defp maybe_load_ssh_keys(%State{} = ss, actor) do
    if active_label(ss) == "SSH KEYS" and not is_list(ss.ssh_keys.items) do
      {:ok, ssh_keys} = SSHKeysActions.load(actor, ss.ssh_keys)
      %{ss | ssh_keys: ssh_keys}
    else
      ss
    end
  end

  defp delegate_ssh_keys_key(%{key: :char, char: char}, state, %State{} = ss) do
    case SSHKeysActions.handle_key(char, Map.get(state, :current_user), ss.ssh_keys) do
      {:ok, ssh_keys} -> {:update, put_screen_state(state, %{ss | ssh_keys: ssh_keys}), []}
      :no_match -> :no_match
    end
  end

  defp delegate_ssh_keys_key(%{key: key}, state, %State{} = ss) do
    case SSHKeysActions.handle_key(key, Map.get(state, :current_user), ss.ssh_keys) do
      {:ok, ssh_keys} -> {:update, put_screen_state(state, %{ss | ssh_keys: ssh_keys}), []}
      :no_match -> :no_match
    end
  end

  defp delegate_invites_key(%{key: :char, char: char}, state, %State{} = ss) do
    case InvitesActions.handle_key(char, Map.get(state, :current_user), ss.invites) do
      {:ok, invites} -> {:update, put_screen_state(state, %{ss | invites: invites}), []}
      :no_match -> :no_match
    end
  end

  defp delegate_invites_key(%{key: key}, state, %State{} = ss) do
    case InvitesActions.handle_key(key, Map.get(state, :current_user), ss.invites) do
      {:ok, invites} -> {:update, put_screen_state(state, %{ss | invites: invites}), []}
      :no_match -> :no_match
    end
  end

  defp delegate_profile_key(event, state, %State{} = ss) do
    case ProfileForm.handle_key(event, ss, Map.get(state, :current_user)) do
      {:ok, new_ss, cmds} -> {:update, put_screen_state(state, new_ss), cmds}
      :no_match -> :no_match
    end
  end

  defp delegate_prefs_key(event, state, %State{} = ss) do
    # Sync form focus_index from prefs_focus so tests that set prefs_focus
    # directly (D-19 compatibility) also update the form's active field.
    ss = sync_prefs_focus(ss)

    case PrefsForm.handle_key(event, ss, Map.get(state, :current_user)) do
      {:ok, new_ss, cmds} -> {:update, put_screen_state(state, new_ss), cmds}
      :no_match -> :no_match
    end
  end

  @prefs_focus_index %{timezone: 0, time_format: 1, theme: 2}

  defp sync_prefs_focus(%State{prefs_focus: pf, prefs_form: form} = ss)
       when not is_nil(form) do
    idx = Map.get(@prefs_focus_index, pf, 0)

    if form.focus_index == idx do
      ss
    else
      %{ss | prefs_form: %{form | focus_index: idx}}
    end
  end

  defp sync_prefs_focus(ss), do: ss

  defp put_screen_state(state, %State{} = ss) do
    %{state | screen_state: Map.put(state.screen_state, :account, ss)}
  end

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
    %{title: "Account", mode: Presentation.mode_for!(:account)}
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
