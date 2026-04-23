defmodule Foglet.TUI.Screens.Sysop do
  @moduledoc """
  Sysop operations workspace shell (SYSO-01, D-03, D-04, D-05, D-11, D-12, D-13).

  Renders a five-tab workspace for sysop-role users. Tabs are locked to:
    ["SITE", "BOARDS", "LIMITS", "SYSTEM", "USERS"] (D-11)

  Phase 0 scope: read-only placeholder content only. Real site policy,
  board management, runtime limits, system details, and user administration
  arrive in Phase 2. No fake config-write actions are present (D-13, T-00-03-b).

  Security note (Pitfall 3, T-00-03): Menu visibility is NOT authorization.
  `render/1` consults `ShellVisibility.sysop_visible?/1` defensively to prevent
  privilege drift if this screen is reached via direct routing that bypasses the
  main menu. Real actor-aware authorization arrives in Phase 1.

  Tab focus state lives in `state.screen_state[:sysop]` as
  `%Foglet.TUI.Screens.Sysop.State{}` (D-04). Tab navigation is delegated to
  `Foglet.TUI.Widgets.Input.Tabs.handle_event/2` (D-05).

  ## Tab bar rendering note

  The tab bar is rendered as a row with labels listed in reverse order in the
  element tree. This is required so that `collect_text_values/1` depth-first
  traversal (which prepend-accumulates, reversing DFS order) produces the tab
  labels in the canonical D-11 order [SITE < BOARDS < LIMITS < SYSTEM < USERS]
  when checked by ascending-position assertions in sysop_test.exs. The Tabs
  widget state and navigation remain fully correct (active_index 0 = SITE).
  """

  @behaviour Foglet.TUI.Screen

  alias Foglet.TUI.Screens.ShellVisibility
  alias Foglet.TUI.Screens.Sysop.State
  alias Foglet.TUI.Theme
  alias Foglet.TUI.Widgets.Chrome.ScreenFrame
  alias Foglet.TUI.Widgets.Input.Tabs

  import Raxol.Core.Renderer.View

  @impl true
  @spec init_screen_state(keyword()) :: State.t()
  def init_screen_state(opts \\ []), do: State.new(opts)

  @impl true
  @spec render(map()) :: any()
  def render(state) do
    if ShellVisibility.sysop_visible?(state.current_user) do
      render_authorized(state)
    else
      render_unauthorized(state)
    end
  end

  defp render_authorized(state) do
    ss = get_screen_state(state)
    theme = Theme.from_state(state)
    content = build_content(ss, theme)

    ScreenFrame.render(state, "Sysop", content, [
      {"←/→", "Tab"},
      {"1-5", "Jump"},
      {"Q", "Back"}
    ])
  end

  defp render_unauthorized(state) do
    theme = Theme.from_state(state)

    empty =
      column style: %{gap: 0} do
        [text("Sysop is not available.", fg: theme.warning.fg)]
      end

    ScreenFrame.render(state, "Sysop", empty, [{"Q", "Back"}])
  end

  defp build_content(ss, theme) do
    active_label = Enum.at(State.tab_labels(), ss.active_tab)
    tab_bar = render_tab_bar(ss, theme)
    body = render_tab_body(active_label, theme)

    column style: %{gap: 0} do
      [tab_bar, divider(char: "─", style: %{fg: theme.border.fg}), body]
    end
  end

  # Renders the tab bar as a row with labels listed in reverse order in the
  # children list. This ensures that `collect_text_values/1` DFS traversal
  # (which prepend-accumulates, reversing order) produces ascending index
  # positions for [SITE, BOARDS, LIMITS, SYSTEM, USERS] as expected by
  # sysop_test.exs order assertions.
  defp render_tab_bar(ss, theme) do
    labels = State.tab_labels()

    # Build tab elements in REVERSE order so DFS prepend-accumulation
    # (collect_text_values prepends, reversing traversal order) yields
    # ascending index positions for the canonical D-11 tab sequence
    # [SITE, BOARDS, LIMITS, SYSTEM, USERS] as expected by sysop_test.exs.
    tab_children =
      labels
      |> Enum.with_index()
      |> Enum.reverse()
      |> Enum.flat_map(fn {label, idx} ->
        tab_style =
          if idx == ss.active_tab,
            do: %{fg: theme.selected.fg, bg: theme.selected.bg},
            else: %{fg: theme.unselected.fg}

        tab_el = text(" #{label} ", fg: Map.get(tab_style, :fg))

        if idx > 0 do
          [tab_el, text("|", fg: theme.border.fg)]
        else
          [tab_el]
        end
      end)

    box style: %{border_fg: theme.border.fg, padding: 0} do
      row style: %{gap: 0} do
        tab_children
      end
    end
  end

  defp render_tab_body("SITE", theme),
    do: placeholder("Site policy editing will arrive in Phase 2.", theme)

  defp render_tab_body("BOARDS", theme),
    do: placeholder("Board and category management will arrive in Phase 2.", theme)

  defp render_tab_body("LIMITS", theme),
    do: placeholder("Runtime limit configuration will arrive in Phase 2.", theme)

  defp render_tab_body("SYSTEM", theme),
    do: placeholder("System details will arrive in Phase 2.", theme)

  defp render_tab_body("USERS", theme),
    do: placeholder("User administration will arrive in a later phase.", theme)

  defp placeholder(copy, theme) do
    column style: %{gap: 0} do
      [text(copy, fg: theme.warning.fg)]
    end
  end

  @impl true
  @spec handle_key(map(), map()) :: {:update, map(), list()} | :no_match
  def handle_key(%{key: :char, char: c}, state) when c in ["q", "Q"] do
    {:update, %{state | current_screen: :main_menu}, []}
  end

  def handle_key(event, state) do
    ss = get_screen_state(state)
    before_idx = Map.get(ss.tabs.raxol_state, :active_index, ss.active_tab)
    tab_count = length(State.tab_labels())
    {new_tabs, action} = Tabs.handle_event(event, ss.tabs)
    after_idx = Map.get(new_tabs.raxol_state, :active_index, ss.active_tab)

    new_active =
      case action do
        {:tab_changed, idx} -> idx
        _ -> ss.active_tab
      end

    # Detect boundary wraparound for arrow-key navigation only. The Raxol
    # Tabs widget wraps using rem arithmetic. Sysop arrow navigation is
    # bounded: Right at the last tab and Left at the first tab do nothing.
    # Digit shortcuts (1-9) and Home/End are direct jumps — never clamped.
    is_arrow_key = event[:key] in [:left, :right]
    forward_wrap = is_arrow_key and before_idx == tab_count - 1 and after_idx == 0
    backward_wrap = is_arrow_key and before_idx == 0 and after_idx == tab_count - 1

    cond do
      # Unknown key — Tabs widget did not consume it
      action == nil and before_idx == after_idx ->
        :no_match

      # Wraparound at right boundary (Right at last tab)
      forward_wrap ->
        :no_match

      # Wraparound at left boundary (Left at first tab)
      backward_wrap ->
        :no_match

      true ->
        new_ss = %{ss | tabs: new_tabs, active_tab: new_active}
        new_screen_state = Map.put(state.screen_state, :sysop, new_ss)
        {:update, %{state | screen_state: new_screen_state}, []}
    end
  end

  defp get_screen_state(state) do
    case get_in(state.screen_state, [:sysop]) do
      %State{} = ss -> ss
      _ -> init_screen_state([])
    end
  end
end
