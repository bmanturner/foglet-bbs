defmodule Foglet.TUI.Screens.Moderation do
  @moduledoc """
  Moderation shell screen (D-03, D-04, D-05, D-10, D-12, D-13, MODR-01).

  Provides a read-only workspace for moderators and sysops with five tabs
  (D-10, locked order): `QUEUE`, `LOG`, `USERS`, `SANCTIONS`, `BOARDS`.

  ## Security: Defensive Role Check (Pitfall 3 / T-00-02)

  Menu visibility (`ShellVisibility.moderation_visible?/1`) controls entry via
  the main menu in Plan 07. The shell's own `render/1` re-checks the same
  predicate to prevent drift if a user is somehow routed here directly (e.g.
  direct `{:navigate, :moderation}` from a test harness or future typed action).
  On authorization failure the shell renders a "not available" column rather
  than crashing. The Plan 01 tests exercise `:mod` and `:sysop` roles only, so
  this defensive branch is not exercised by unit tests but prevents EoP drift.

  ## Phase 0 Scope

  All tab bodies are scaffold placeholders (D-12). Real moderation data
  (report queue, audit log, user administration, sanctions, board-scoped
  moderation) arrives in Phase 8 (Moderation Workspace Population). No
  fake ban/approve/remove/sanction operations are defined (D-13, T-00-02-b).

  ## INVITES Tab

  CONTEXT.md D-10 locks the base Moderation tab set to exactly the five
  listed above. Phase 4 appends the shared INVITES surface when
  `invite_code_generators == "mods"` and the current actor is a moderator.
  """

  @behaviour Foglet.TUI.Screen

  import Raxol.Core.Renderer.View

  alias Foglet.TUI.Screens.Moderation.State
  alias Foglet.TUI.Screens.Shared.InvitesActions
  alias Foglet.TUI.Screens.Shared.InvitesSurface
  alias Foglet.TUI.Screens.ShellVisibility
  alias Foglet.TUI.Theme
  alias Foglet.TUI.Widgets.Chrome.ScreenFrame
  alias Foglet.TUI.Widgets.Input.Tabs

  @key_list [{"←/→", "Tab"}, {"1-6", "Jump"}, {"Q", "Back"}]

  # ---------------------------------------------------------------------------
  # Screen behaviour callbacks
  # ---------------------------------------------------------------------------

  @impl true
  @spec init_screen_state(keyword()) :: State.t()
  def init_screen_state(opts \\ []), do: State.new(opts)

  @impl true
  @spec render(map()) :: any()
  def render(state) do
    if ShellVisibility.moderation_visible?(state.current_user) do
      render_authorized(state)
    else
      theme = Theme.from_state(state)

      empty =
        column style: %{gap: 0} do
          [text("Moderation is not available.", fg: theme.warning.fg)]
        end

      ScreenFrame.render(state, "Moderation", empty, [{"Q", "Back"}])
    end
  end

  @impl true
  @spec handle_key(map(), map()) :: {:update, map(), list()} | :no_match
  def handle_key(%{key: :char, char: c}, state) when c in ["Q", "q"],
    do: {:update, %{state | current_screen: :main_menu}, []}

  def handle_key(event, state) do
    old_ss = get_screen_state(state)
    ss = synced_screen_state(state)
    {new_tabs, action} = Tabs.handle_event(event, ss.tabs)

    new_active =
      case action do
        {:tab_changed, idx} -> idx
        _ -> ss.active_tab
      end

    if action == nil and new_tabs == ss.tabs do
      case delegate_to_active_tab(event, state, ss) do
        :no_match when ss == old_ss ->
          # Tabs widget neither recognized the key nor persisted any internal
          # state mutation — treat as unhandled so global_key_handler can run.
          :no_match

        :no_match ->
          update_screen_state(state, ss)

        {:ok, new_invites} ->
          update_screen_state(state, %{ss | invites: new_invites})
      end
    else
      new_ss = %{ss | tabs: new_tabs, active_tab: new_active}
      update_screen_state(state, maybe_load_invites(new_ss, state))
    end
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp get_screen_state(state) do
    ss = Map.get(state, :screen_state) || %{}
    Map.get(ss, :moderation) || init_screen_state()
  end

  defp render_authorized(state) do
    ss = synced_screen_state(state)
    theme = Theme.from_state(state)
    content = render_content(ss, theme)
    ScreenFrame.render(state, "Moderation", content, @key_list)
  end

  defp render_content(ss, theme) do
    active_label = Enum.at(tab_labels_from_tabs(ss.tabs), ss.active_tab, "QUEUE")
    tab_body = render_tab_body(active_label, ss, theme)

    column style: %{gap: 0} do
      [Tabs.render(ss.tabs, theme: theme), tab_body]
    end
  end

  defp render_tab_body("QUEUE", _ss, theme) do
    column style: %{gap: 0} do
      [text("Report queue will arrive in Phase 8.", fg: theme.warning.fg)]
    end
  end

  defp render_tab_body("LOG", _ss, theme) do
    column style: %{gap: 0} do
      [text("Audit log will arrive in Phase 8.", fg: theme.warning.fg)]
    end
  end

  defp render_tab_body("USERS", _ss, theme) do
    column style: %{gap: 0} do
      [text("User administration will arrive in Phase 8.", fg: theme.warning.fg)]
    end
  end

  defp render_tab_body("SANCTIONS", _ss, theme) do
    column style: %{gap: 0} do
      [text("Sanctions tooling will arrive in Phase 8.", fg: theme.warning.fg)]
    end
  end

  defp render_tab_body("BOARDS", _ss, theme) do
    column style: %{gap: 0} do
      [text("Board-scoped moderation will arrive in Phase 8.", fg: theme.warning.fg)]
    end
  end

  defp render_tab_body("INVITES", ss, theme) do
    InvitesSurface.render(ss.invites, theme)
  end

  defp render_tab_body(_label, _ss, theme) do
    column style: %{gap: 0} do
      [text("Report queue will arrive in Phase 8.", fg: theme.warning.fg)]
    end
  end

  defp synced_screen_state(state) do
    ss = get_screen_state(state)

    invites? =
      ShellVisibility.invites_visible?(
        Map.get(state, :current_user),
        Map.get(state, :session_context)
      )

    labels = State.tab_labels(invites?)
    active = min(ss.active_tab, length(labels) - 1)

    if tab_labels_from_tabs(ss.tabs) == labels and active == ss.active_tab do
      ss
    else
      %{ss | tabs: Tabs.init(tabs: labels, active: active), active_tab: active}
    end
  end

  defp tab_labels_from_tabs(%Tabs{raxol_state: %{tabs: tabs}}) when is_list(tabs) do
    Enum.map(tabs, fn
      %{label: label} -> label
      other -> to_string(other)
    end)
  end

  defp delegate_to_active_tab(event, state, ss) do
    case Enum.at(tab_labels_from_tabs(ss.tabs), ss.active_tab) do
      "INVITES" ->
        event
        |> key_for_invites()
        |> InvitesActions.handle_key(state.current_user, ss.invites)

      _other ->
        :no_match
    end
  end

  defp maybe_load_invites(ss, state) do
    case {Enum.at(tab_labels_from_tabs(ss.tabs), ss.active_tab), ss.invites.items} do
      {"INVITES", items} when not is_list(items) ->
        {:ok, invites} = InvitesActions.load(state.current_user, ss.invites)
        %{ss | invites: invites}

      _other ->
        ss
    end
  end

  defp key_for_invites(%{key: :char, char: char}), do: char
  defp key_for_invites(%{key: key}), do: key

  defp update_screen_state(state, ss) do
    new_screen_state = Map.put(Map.get(state, :screen_state) || %{}, :moderation, ss)
    {:update, %{state | screen_state: new_screen_state}, []}
  end
end
