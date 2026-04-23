defmodule Foglet.TUI.Screens.Account do
  @moduledoc """
  Account shell screen for Foglet BBS (ACCT-01, D-03, D-04, D-05, D-08, D-09, D-12, D-13).

  Implements `Foglet.TUI.Screen` behaviour with three tabs:
    * PROFILE  — scaffold placeholder (Phase 5 adds real profile data)
    * PREFS    — scaffold placeholder (Phase 5 adds real preferences)
    * INVITES  — conditional; shown when `ShellVisibility.invites_visible?/2` returns
                 true (D-09). Rendered via the shared `InvitesSurface` primitive (D-06).

  Tab focus is delegated entirely to `Foglet.TUI.Widgets.Input.Tabs` (D-05).
  Screen-local state lives at `state.screen_state[:account]` as a
  `%Foglet.TUI.Screens.Account.State{}` struct (D-04).

  Phase 0 scope (D-13): read-only. No save_profile, save_prefs, generate_invite, or
  revoke_invite operations are defined or dispatched. Commands list is always `[]`.

  Security:
    * T-00-01: No Repo/domain imports; no fake operator actions.
    * T-00-04: INVITES tab body delegates entirely to `InvitesSurface.render/2`.
    * T-00-INPUT: Unknown keys return `:no_match` — no silent state mutation.
  """

  @behaviour Foglet.TUI.Screen

  import Raxol.Core.Renderer.View

  alias Foglet.TUI.Screens.Account.State
  alias Foglet.TUI.Screens.Shared.InvitesSurface
  alias Foglet.TUI.Screens.ShellVisibility
  alias Foglet.TUI.Theme
  alias Foglet.TUI.Widgets.Chrome.ScreenFrame
  alias Foglet.TUI.Widgets.Input.Tabs

  @key_bar [{"←/→", "Tab"}, {"1-9", "Jump"}, {"Q", "Back"}]

  @impl true
  @spec init_screen_state(keyword()) :: State.t()
  def init_screen_state(opts \\ []) do
    State.new(translate_opts(opts))
  end

  @impl true
  @spec render(map()) :: any()
  def render(state) do
    ss = get_screen_state(state)
    theme = Theme.from_state(state)

    # IN-01: `invites?` is recomputed here each render and also inside
    # `init_opts_from_state/1` on the first render (when `screen_state.account`
    # is nil). The duplicate call is bounded to the first frame, and the
    # predicate is pattern-match-only (no I/O — see ShellVisibility.resolve_policy/1),
    # so the clarity trade-off is intentional for Phase 0. Phases 4+ that
    # mutate role/policy mid-session should either memoize `invites?` in
    # screen_state at init time or thread it through a single call site.
    invites? =
      ShellVisibility.invites_visible?(
        Map.get(state, :current_user),
        Map.get(state, :session_context)
      )

    labels = State.tab_labels(invites?)
    active_label = Enum.at(labels, ss.active_tab, "PROFILE")

    content =
      column style: %{gap: 0} do
        [
          Tabs.render(ss.tabs, theme: theme),
          divider(char: "─", style: %{fg: theme.border.fg}),
          render_tab_body(active_label, ss, theme)
        ]
      end

    ScreenFrame.render(state, "Account", content, @key_bar)
  end

  @impl true
  @spec handle_key(map(), map()) :: {:update, map(), list()} | :no_match
  def handle_key(%{key: :char, char: c}, state) when c in ["q", "Q"] do
    {:update, %{state | current_screen: :main_menu}, []}
  end

  def handle_key(event, state) do
    ss = get_screen_state(state)
    {new_tabs, action} = Tabs.handle_event(event, ss.tabs)

    new_active =
      case action do
        {:tab_changed, idx} -> idx
        _ -> ss.active_tab
      end

    if action == nil and new_tabs == ss.tabs do
      :no_match
    else
      new_ss = %{ss | tabs: new_tabs, active_tab: new_active}
      new_screen_state = Map.put(state.screen_state, :account, new_ss)
      {:update, %{state | screen_state: new_screen_state}, []}
    end
  end

  # --- private helpers ---

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
        )
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

  defp render_tab_body("PROFILE", _ss, theme) do
    column style: %{gap: 0} do
      [text("Profile details will arrive in a later phase.", fg: theme.warning.fg)]
    end
  end

  defp render_tab_body("PREFS", _ss, theme) do
    column style: %{gap: 0} do
      [text("Preferences will arrive in a later phase.", fg: theme.warning.fg)]
    end
  end

  defp render_tab_body("INVITES", ss, theme) do
    InvitesSurface.render(ss.invites, theme)
  end

  defp render_tab_body(_unknown, _ss, theme) do
    column style: %{gap: 0} do
      [text("", fg: theme.dim.fg)]
    end
  end
end
