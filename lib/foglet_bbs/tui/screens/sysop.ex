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
  `Foglet.TUI.Widgets.Input.Tabs.handle_event/2` (D-05) and rendering to
  `Foglet.TUI.Widgets.Input.Tabs.render/2` so the themed widget remains the
  single source of truth for the tab bar's visual styling.
  """

  @behaviour Foglet.TUI.Screen

  alias Foglet.TUI.Modal
  alias Foglet.TUI.Screens.ShellVisibility
  alias Foglet.TUI.Screens.Sysop.BoardsView
  alias Foglet.TUI.Screens.Sysop.LimitsForm
  alias Foglet.TUI.Screens.Sysop.SiteForm
  alias Foglet.TUI.Screens.Sysop.State
  alias Foglet.TUI.Screens.Sysop.SystemSnapshot
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
    body = render_tab_body(active_label, ss, theme)

    column style: %{gap: 0} do
      [
        Tabs.render(ss.tabs, theme: theme),
        divider(char: "─", style: %{fg: theme.border.fg}),
        body
      ]
    end
  end

  defp render_tab_body("SITE", ss, theme) do
    case ss.site_form do
      nil -> placeholder("Press any key to load site policy.", theme)
      form -> SiteForm.render(form, theme)
    end
  end

  defp render_tab_body("BOARDS", ss, theme) do
    case ss.boards_view do
      nil -> placeholder("Press any key to load boards and categories.", theme)
      view -> BoardsView.render(view, theme)
    end
  end

  defp render_tab_body("LIMITS", ss, theme) do
    case ss.limits_form do
      nil -> placeholder("Press any key to load runtime limits.", theme)
      form -> LimitsForm.render(form, theme)
    end
  end

  defp render_tab_body("SYSTEM", ss, theme) do
    case ss.system_snapshot do
      nil -> placeholder("Press any key to load system snapshot.", theme)
      snap -> SystemSnapshot.render(snap, theme)
    end
  end

  defp render_tab_body("USERS", _ss, theme),
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
    {new_tabs, action} = Tabs.handle_event(event, ss.tabs)

    if action == nil and new_tabs == ss.tabs do
      # Tab widget ignored — delegate to the active tab's submodule (if any).
      delegate_to_active_tab(event, state, ss)
    else
      new_active =
        case action do
          {:tab_changed, idx} -> idx
          _ -> ss.active_tab
        end

      new_ss = %{ss | tabs: new_tabs, active_tab: new_active}
      new_screen_state = Map.put(state.screen_state, :sysop, new_ss)
      {:update, %{state | screen_state: new_screen_state}, []}
    end
  end

  defp delegate_to_active_tab(event, state, ss) do
    case Enum.at(State.tab_labels(), ss.active_tab) do
      "SITE" -> delegate_to_submodule(event, state, ss, :site_form, SiteForm)
      "LIMITS" -> delegate_to_submodule(event, state, ss, :limits_form, LimitsForm)
      "BOARDS" -> delegate_to_submodule(event, state, ss, :boards_view, BoardsView)
      "SYSTEM" -> delegate_to_submodule(event, state, ss, :system_snapshot, SystemSnapshot)
      _ -> :no_match
    end
  end

  defp delegate_to_submodule(event, state, ss, field, module) do
    sub = Map.get(ss, field) || module.init(current_user: state.current_user)
    {new_sub, events} = module.handle_key(event, sub)
    apply_submodule_result(state, ss, field, new_sub, sub, events)
  end

  # Submodule contract: a submodule must emit at most one `:error_modal`
  # event per `handle_key/2` return. Only the first matching event is
  # surfaced; any additional error_modal events in the same batch are
  # silently dropped. Multi-error submissions should be combined into a
  # single message at the submodule boundary.
  defp apply_submodule_result(state, ss, field, new_sub, old_sub, events) do
    new_ss = Map.put(ss, field, new_sub)
    new_screen_state = Map.put(state.screen_state, :sysop, new_ss)
    base_state = %{state | screen_state: new_screen_state}

    case Enum.find(events, fn
           {:error_modal, _msg, _dest} -> true
           _ -> false
         end) do
      {:error_modal, msg, dest} ->
        {:update,
         %{
           base_state
           | modal: %Modal{type: :error, message: msg},
             current_screen: dest
         }, []}

      nil ->
        if new_sub == old_sub and events == [] do
          :no_match
        else
          {:update, base_state, []}
        end
    end
  end

  defp get_screen_state(state) do
    case get_in(state.screen_state, [:sysop]) do
      %State{} = ss -> ss
      _ -> init_screen_state([])
    end
  end
end
