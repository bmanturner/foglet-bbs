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

  alias Foglet.TUI.Context
  alias Foglet.TUI.Effect
  alias Foglet.TUI.Modal
  alias Foglet.TUI.Screens.Shared.InvitesActions
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

  @impl true
  @spec init(Context.t()) :: State.t()
  def init(%Context{} = context) do
    State.new(
      current_user: context.current_user,
      session_context: context.session_context
    )
  end

  @impl true
  @spec init_screen_state(keyword()) :: State.t()
  def init_screen_state(opts \\ []), do: State.new(opts)

  @impl true
  @spec update(term(), State.t() | nil, Context.t()) :: {State.t(), [Effect.t()]}
  # Phase 39 D-01/D-03/D-14: screen owns its route-entry conditional load.
  # Preserves the user-conditional semantics today encoded in App's
  # `maybe_dispatch_route_entry/3` for `:sysop` (`app.ex:826-832`); Plan 39-05
  # will collapse the App-side per-screen clauses into a single generic
  # dispatch.
  def update(:on_route_enter, local_state, %Context{} = context) do
    if context.current_user do
      update(:load, local_state, context)
    else
      {normalize_state(local_state, context), []}
    end
  end

  def update(:load, local_state, %Context{} = context) do
    local_state
    |> normalize_state(context)
    |> maybe_request_active_load(context)
  end

  def update({:task_result, op, result}, local_state, %Context{} = context)
      when op in [
             :sysop_load_boards,
             :sysop_load_limits,
             :sysop_load_system,
             :sysop_load_users
           ] do
    ss = normalize_state(local_state, context)
    slot = slot_for_op(op)

    case unwrap_task_result(result) do
      {:ok, sub} ->
        {Map.put(ss, slot, {:loaded, sub}), []}

      {:error, reason} ->
        {Map.put(ss, slot, {:error, normalize_reason(reason)}), []}
    end
  end

  def update({:task_result, op, result}, local_state, %Context{} = context)
      when op in [:sysop_load_invites, :sysop_generate_invite, :sysop_revoke_invite] do
    ss = normalize_state(local_state, context)

    case unwrap_task_result(result) do
      {:ok, %InvitesState{} = invites} ->
        {%{ss | invites: invites, armed_revoke?: false}, []}

      {:error, reason} ->
        {%{
           ss
           | invites: InvitesState.with_error(ss.invites, to_string(reason)),
             armed_revoke?: false
         }, []}
    end
  end

  def update({:key, %{key: :char, char: c}}, local_state, %Context{} = context)
      when c in ["q", "Q"] do
    {normalize_state(local_state, context), [Effect.navigate(:main_menu, %{})]}
  end

  def update({:key, %{key: :enter} = event}, local_state, %Context{} = context) do
    ss = normalize_state(local_state, context)
    active_label = Enum.at(State.tab_labels(ss), ss.active_tab)

    case {active_label, InvitesState.selected_item(ss.invites)} do
      {"INVITES", %{status: status}} when status != :revoked ->
        {%{ss | armed_revoke?: true}, []}

      {"INVITES", %{status: :revoked}} ->
        {%{
           ss
           | invites: InvitesState.with_error(ss.invites, "Invite already revoked."),
             armed_revoke?: false
         }, []}

      _ ->
        handle_update_key(event, ss, context)
    end
  end

  def update({:key, %{key: :char, char: c} = event}, local_state, %Context{} = context)
      when c in ["x", "X"] do
    ss = normalize_state(local_state, context)
    active_label = Enum.at(State.tab_labels(ss), ss.active_tab)

    case {active_label, ss.armed_revoke?} do
      {"INVITES", true} ->
        {%{ss | armed_revoke?: false},
         [invites_effect(:sysop_revoke_invite, context, ss.invites)]}

      _ ->
        handle_update_key(event, ss, context)
    end
  end

  def update({:key, %{key: :char, char: c} = event}, local_state, %Context{} = context)
      when c in ["r", "R"] do
    ss = normalize_state(local_state, context)
    active_label = Enum.at(State.tab_labels(ss), ss.active_tab)
    slot = slot_for(active_label)
    current = slot && Map.get(ss, slot)

    case current do
      {:error, reason} when reason != :forbidden ->
        {Map.put(ss, slot, :loading), [load_effect_for_label(active_label, context)]}

      _ ->
        handle_update_key(event, ss, context)
    end
  end

  def update({:key, event}, local_state, %Context{} = context) do
    handle_update_key(event, normalize_state(local_state, context), context)
  end

  def update(_message, local_state, %Context{} = context),
    do: {normalize_state(local_state, context), []}

  @impl true
  @spec render(State.t(), Context.t()) :: any()
  def render(%State{} = local_state, %Context{} = context) do
    render(render_model(context, local_state))
  end

  def render(local_state, %Context{} = context),
    do: render(normalize_state(local_state, context), context)

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
    width = inner_width(state)
    content = build_content(ss, theme, width)
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
        [text("Sysop is not available.", fg: theme.warning.fg)]
      end

    ScreenFrame.render(state, %{breadcrumb_parts: ["Foglet", "Sysop"]}, empty, [
      %{label: "System", commands: [%{key: "Q", label: "Back", priority: 0}]}
    ])
  end

  defp chrome_model(_ss) do
    %{breadcrumb_parts: ["Foglet", "Sysop"]}
  end

  defp sysop_commands(ss, jump_hint) do
    base = [
      %{
        label: "System",
        commands: [%{key: "Q", label: "Back", priority: 0}]
      },
      %{
        label: "Tabs",
        commands: [
          %{key: "←/→", label: "Tab", priority: 10},
          %{key: jump_hint, label: "Jump", priority: 10}
        ]
      }
    ]

    base
    |> maybe_add_retry(ss)
    |> maybe_add_revoke(ss)
  end

  # Phase 29 D-25 (SYSOP-06): [X] Revoke is advertised in the Sysop command
  # bar only when (a) the active tab is INVITES, (b) `armed_revoke?` is true
  # on the screen state (set by Enter on a focused non-revoked row), and
  # (c) the focused invite is still non-revoked. Pressing X (handled below)
  # routes through the existing `InvitesActions.revoke_selected/2` path —
  # no new revoke logic introduced.
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
  # Forbidden suppresses the hint (and the keypress, in handle_key/2).
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

  defp dispatch_for("BOARDS"), do: {:load_sysop_boards}
  defp dispatch_for("LIMITS"), do: {:load_sysop_limits}
  defp dispatch_for("SYSTEM"), do: {:load_sysop_system}
  defp dispatch_for("USERS"), do: {:load_sysop_users}

  # ScreenFrame uses padding: 1 and border: :single, consuming 4 columns total.
  defp inner_width(state) do
    case Map.get(state, :terminal_size) do
      {w, _} when is_integer(w) -> max(w - 4, 0)
      _ -> 76
    end
  end

  defp build_content(ss, theme, width) do
    active_label = Enum.at(State.tab_labels(ss), ss.active_tab)
    body = render_tab_body(active_label, ss, theme)

    column style: %{gap: 0} do
      [
        Tabs.render(ss.tabs, theme: theme, width: width),
        divider(char: "─", style: %{fg: theme.border.fg}),
        body
      ]
    end
  end

  # SITE remains synchronous (D-03): SiteForm seeds drafts from
  # `Foglet.Config.get!/1` inside its own `init/1`; no lifecycle tagging.
  # On first entry `ss.site_form` is `nil` — lazy-init the form here so
  # the very first render shows the form rather than a placeholder.
  defp render_tab_body("SITE", ss, theme) do
    case ss.site_form do
      nil -> SiteForm.render(SiteForm.init([]), theme)
      form -> SiteForm.render(form, theme)
    end
  end

  defp render_tab_body("BOARDS", ss, theme) do
    case ss.boards_view do
      :not_loaded -> loading_panel(theme)
      :loading -> loading_panel(theme)
      {:loaded, sub} -> BoardsView.render(sub, theme)
      {:error, :forbidden} -> forbidden_panel(theme)
      {:error, _other} -> error_panel("boards", theme)
    end
  end

  defp render_tab_body("LIMITS", ss, theme) do
    case ss.limits_form do
      :not_loaded -> loading_panel(theme)
      :loading -> loading_panel(theme)
      {:loaded, sub} -> LimitsForm.render(sub, theme)
      {:error, :forbidden} -> forbidden_panel(theme)
      {:error, _other} -> error_panel("limits", theme)
    end
  end

  defp render_tab_body("SYSTEM", ss, theme) do
    case ss.system_snapshot do
      :not_loaded -> loading_panel(theme)
      :loading -> loading_panel(theme)
      {:loaded, sub} -> SystemSnapshot.render(sub, theme)
      {:error, :forbidden} -> forbidden_panel(theme)
      {:error, _other} -> error_panel("system", theme)
    end
  end

  defp render_tab_body("USERS", ss, theme) do
    case ss.users_view do
      :not_loaded -> loading_panel(theme)
      :loading -> loading_panel(theme)
      {:loaded, sub} -> UsersView.render(sub, theme)
      {:error, :forbidden} -> forbidden_panel(theme)
      {:error, _other} -> error_panel("users", theme)
    end
  end

  defp render_tab_body("INVITES", ss, theme),
    do: InvitesSurface.render(ss.invites, theme)

  # Lifecycle panels (D-08, D-11, D-12). Pattern-match order in
  # `render_tab_body/3` MUST keep `{:error, :forbidden}` BEFORE
  # `{:error, _other}` — see Pitfall 3.
  defp loading_panel(theme) do
    column style: %{gap: 0} do
      [text("Loading…", fg: theme.dim.fg)]
    end
  end

  defp forbidden_panel(theme) do
    column style: %{gap: 0} do
      [text("Insufficient role to view this tab.", fg: theme.warning.fg)]
    end
  end

  defp error_panel(tab, theme) do
    column style: %{gap: 0} do
      [text("Could not load #{tab}. Press R to retry.", fg: theme.error.fg)]
    end
  end

  @impl true
  @spec handle_key(map(), map()) :: {:update, map(), list()} | :no_match
  def handle_key(%{key: :char, char: c}, state) when c in ["q", "Q"] do
    {:update, %{state | current_screen: :main_menu}, []}
  end

  # Phase 29 D-25 (SYSOP-06): Enter on focused non-revoked INVITES row arms
  # the [X] Revoke advertisement. Enter on a revoked row surfaces an
  # explanatory error via InvitesState (WR-07) so the operator gets feedback
  # rather than a silent no-op when the [X] Revoke advertisement is absent.
  # Enter on any other tab (or when the focused row is missing) hands off to
  # do_handle_key/2 so SiteForm/LimitsForm/etc. continue to receive Enter
  # for their submit flow.
  def handle_key(%{key: :enter} = event, state) do
    ss = get_screen_state(state)
    active_label = Enum.at(State.tab_labels(ss), ss.active_tab)

    case {active_label, InvitesState.selected_item(ss.invites)} do
      {"INVITES", %{status: status}} when status != :revoked ->
        new_ss = %{ss | armed_revoke?: true}
        {:update, put_sysop_state(state, new_ss), []}

      {"INVITES", %{status: :revoked}} ->
        new_invites = InvitesState.with_error(ss.invites, "Invite already revoked.")
        new_ss = %{ss | invites: new_invites, armed_revoke?: false}
        {:update, put_sysop_state(state, new_ss), []}

      _ ->
        do_handle_key(event, state)
    end
  end

  # Phase 29 D-25 (SYSOP-06): When armed and active tab is INVITES, X
  # dispatches the existing InvitesActions.revoke_selected/2 path. The
  # `armed_revoke?` flag is cleared after the call regardless of the
  # boundary's outcome (the boundary may surface an error via
  # `InvitesState.error`; the gesture itself is one-shot). When NOT armed
  # the keypress hands off to do_handle_key/2 so the broader screen logic
  # (or fall-through to global handlers) still runs.
  def handle_key(%{key: :char, char: c} = event, state) when c in ["x", "X"] do
    ss = get_screen_state(state)
    active_label = Enum.at(State.tab_labels(ss), ss.active_tab)

    case {active_label, Map.get(ss, :armed_revoke?, false)} do
      {"INVITES", true} ->
        {:ok, new_invites} =
          InvitesActions.revoke_selected(state.current_user, ss.invites)

        new_ss = %{ss | invites: new_invites, armed_revoke?: false}
        {:update, put_sysop_state(state, new_ss), []}

      _ ->
        do_handle_key(event, state)
    end
  end

  # Phase 29 D-13: [R] Retry. When the active tab is in {:error, reason} with
  # reason != :forbidden, R re-dispatches the matching {:load_sysop_*} tuple
  # and flips the slot back to :loading. On any other slot state (including
  # {:error, :forbidden} and {:loaded, _}) this clause hands the event off to
  # the broader handle_key/2 logic so it can fall through to the active tab's
  # submodule — preserving the [R] Reject keybind on a loaded USERS tab.
  def handle_key(%{key: :char, char: c} = event, state) when c in ["r", "R"] do
    ss = get_screen_state(state)
    active_label = Enum.at(State.tab_labels(ss), ss.active_tab)
    slot = slot_for(active_label)
    current = slot && Map.get(ss, slot)

    case current do
      {:error, reason} when reason != :forbidden ->
        # WR-05: the App is the single writer for the :loading transition.
        # The matching {:load_sysop_*} clause in app.ex calls
        # `put_sysop_loading/2` synchronously before firing the off-process
        # task. The screen merely emits the dispatch tuple. Leaving the slot
        # in {:error, _} until the App processes the command is fine — the
        # screen does not re-render between Sysop.handle_key returning and
        # the App processing the command.
        {:update, state, [dispatch_for(active_label)]}

      _ ->
        do_handle_key(event, state)
    end
  end

  def handle_key(event, state), do: do_handle_key(event, state)

  defp do_handle_key(event, state) do
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

      # Phase 29 D-25 (A3 disambiguation): tab switch (or any tab-widget
      # event that mutates state) clears the armed [X] Revoke flag — the
      # gesture is local to the focused INVITES row and a tab change
      # invalidates the focus context.
      new_ss =
        ss
        |> Map.merge(%{tabs: new_tabs, active_tab: new_active, armed_revoke?: false})
        |> maybe_load_invites_on_entry(state)

      # D-05: tab-switch into a lifecycle tab whose slot is :not_loaded
      # transitions the slot to :loading and emits the matching
      # {:load_sysop_*} dispatch tuple. Re-entering an already-loaded
      # / loading / errored tab emits no command (idempotent — D-06).
      {new_ss, commands} = maybe_dispatch_lifecycle_load(new_ss, new_active)

      {:update, put_sysop_state(state, new_ss), commands}
    end
  end

  defp delegate_to_active_tab(event, state, ss) do
    case Enum.at(State.tab_labels(ss), ss.active_tab) do
      "SITE" -> delegate_to_submodule(event, state, ss, :site_form, SiteForm)
      "LIMITS" -> delegate_to_submodule(event, state, ss, :limits_form, LimitsForm)
      "BOARDS" -> delegate_to_submodule(event, state, ss, :boards_view, BoardsView)
      "SYSTEM" -> delegate_to_submodule(event, state, ss, :system_snapshot, SystemSnapshot)
      "USERS" -> delegate_to_submodule(event, state, ss, :users_view, UsersView)
      "INVITES" -> delegate_to_invites(event, state, ss)
      _ -> :no_match
    end
  end

  defp delegate_to_invites(event, state, ss) do
    key = invite_key(event)

    case InvitesActions.handle_key(key, state.current_user, ss.invites) do
      {:ok, invites} ->
        # Phase 29 D-25 (A3 disambiguation): the armed [X] Revoke flag is
        # bound to the row that was focused when Enter was pressed. Any
        # InvitesActions key that ISN'T a pure vertical move (R Refresh,
        # G Generate, refresh side effects, etc.) invalidates the gesture
        # context — even if `selected_index` happened to stay the same.
        # Only :up/:down/j/k preserve the arm.
        armed_after =
          ss.armed_revoke? and
            invites_arm_preserved?(key, invites, ss.invites)

        new_ss = %{ss | invites: invites, armed_revoke?: armed_after}
        {:update, put_sysop_state(state, new_ss), []}

      :no_match ->
        :no_match
    end
  end

  # The arm survives only when the InvitesActions key was a pure vertical
  # move AND the focused row is unchanged. A focus move on j/k still clears
  # the arm because the row identity changed; a non-move key (R/G) clears
  # it unconditionally because the gesture context (focus snapshot at arm
  # time) is no longer trustworthy.
  defp invites_arm_preserved?(key, new_invites, old_invites) do
    key in [:up, :down, "j", "k", "J", "K"] and
      new_invites.selected_index == old_invites.selected_index
  end

  defp maybe_load_invites_on_entry(ss, state) do
    with "INVITES" <- Enum.at(State.tab_labels(ss), ss.active_tab),
         nil <- ss.invites.items,
         {:ok, invites} <- InvitesActions.load(state.current_user, ss.invites) do
      %{ss | invites: invites}
    else
      _ -> ss
    end
  end

  defp invite_key(%{key: :char, char: char}) when is_binary(char), do: char
  defp invite_key(%{key: key}), do: key
  defp invite_key(event), do: event

  # SITE remains synchronous (D-03): `:site_form` defaults to `nil` and is
  # lazy-initialized on first key delegation, mirroring the pre-Phase-29
  # contract for this slot only. The four lifecycle slots route through
  # the {:loaded, sub} branch below — calls during :not_loaded / :loading
  # / {:error, _} are no-ops (D-09 — Pitfall 1).
  defp delegate_to_submodule(event, state, ss, :site_form = field, module) do
    sub = Map.get(ss, field) || module.init(current_user: state.current_user)
    {new_sub, events} = module.handle_key(event, sub)
    apply_submodule_result(state, ss, field, new_sub, sub, events)
  end

  defp delegate_to_submodule(event, state, ss, field, module) do
    case Map.get(ss, field) do
      {:loaded, sub} ->
        {new_sub, events} = module.handle_key(event, sub)
        apply_submodule_result(state, ss, field, {:loaded, new_sub}, {:loaded, sub}, events)

      _other ->
        :no_match
    end
  end

  # Submodule contract: a submodule must emit at most one `:error_modal`
  # event per `handle_key/2` return. Only the first matching event is
  # surfaced; any additional error_modal events in the same batch are
  # silently dropped. Multi-error submissions should be combined into a
  # single message at the submodule boundary.
  defp apply_submodule_result(state, ss, field, new_sub, old_sub, events) do
    new_ss = Map.put(ss, field, new_sub)
    base_state = put_sysop_state(state, new_ss)

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

  # Lifecycle dispatch helpers (D-05, D-06).
  #
  # `maybe_dispatch_lifecycle_load/2` inspects the active tab label and
  # returns `{ss', commands}`. When the matching slot is `:not_loaded`,
  # the slot is flipped to `:loading` synchronously AND the matching
  # `{:load_sysop_*}` dispatch tuple is emitted. Any other tag (`:loading`
  # / `{:loaded, _}` / `{:error, _}`) is a no-op so re-entry is idempotent.
  defp maybe_dispatch_lifecycle_load(ss, active_idx) do
    case Enum.at(State.tab_labels(ss), active_idx) do
      "BOARDS" -> dispatch_if_not_loaded(ss, :boards_view, {:load_sysop_boards})
      "LIMITS" -> dispatch_if_not_loaded(ss, :limits_form, {:load_sysop_limits})
      "SYSTEM" -> dispatch_if_not_loaded(ss, :system_snapshot, {:load_sysop_system})
      "USERS" -> dispatch_if_not_loaded(ss, :users_view, {:load_sysop_users})
      _ -> {ss, []}
    end
  end

  # Single-writer lifecycle (Phase 29 D-05/D-06): the App is the single
  # writer for the `:loading` slot transition. Each `{:load_sysop_*}` clause
  # in `app.ex` calls `put_sysop_loading/2` synchronously before firing the
  # off-process task. The screen merely emits the dispatch tuple when the
  # slot is `:not_loaded`; the App owns the slot mutation. This avoids the
  # double-write footgun where the screen flipped to `:loading` and then the
  # App flipped to `:loading` again (idempotent today, but a refactor hazard).
  defp dispatch_if_not_loaded(ss, slot, dispatch_tuple) do
    case Map.get(ss, slot) do
      :not_loaded -> {ss, [dispatch_tuple]}
      _ -> {ss, []}
    end
  end

  defp get_screen_state(state) do
    ss =
      case get_in(state.screen_state, [:sysop]) do
        %State{} = ss ->
          ss

        _ ->
          init_screen_state(
            current_user: state.current_user,
            session_context: state.session_context
          )
      end

    State.refresh_tabs(ss,
      invites_visible?:
        ShellVisibility.invites_visible?(state.current_user, state.session_context)
    )
  end

  # Slot writer for the :sysop screen state. %App{} defaults screen_state to
  # %{}; Phase 39 removed the legacy paths that could leave it nil, so we no
  # longer hedge with `|| %{}` here. A non-map screen_state would crash
  # earlier in the screen pipeline anyway (WR-03).
  defp put_sysop_state(state, sysop_ss) do
    new_screen_state = Map.put(state.screen_state, :sysop, sysop_ss)
    %{state | screen_state: new_screen_state}
  end

  defp normalize_state(nil, %Context{} = context), do: init(context)

  defp normalize_state(%State{} = ss, %Context{} = context) do
    State.refresh_tabs(ss,
      invites_visible?:
        ShellVisibility.invites_visible?(context.current_user, context.session_context)
    )
  end

  defp render_model(%Context{} = context, %State{} = local_state) do
    %{
      current_user: context.current_user,
      session_context: context.session_context,
      terminal_size: context.terminal_size,
      current_screen: :sysop,
      route_params: context.route_params,
      screen_state: %{sysop: local_state}
    }
  end

  defp handle_update_key(event, %State{} = ss, %Context{} = context) do
    {new_tabs, action} = Tabs.handle_event(event, ss.tabs)

    if action == nil and new_tabs == ss.tabs do
      delegate_update_to_active_tab(event, ss, context)
    else
      new_active =
        case action do
          {:tab_changed, idx} -> idx
          _ -> ss.active_tab
        end

      new_ss = %{ss | tabs: new_tabs, active_tab: new_active, armed_revoke?: false}

      new_ss
      |> maybe_request_invites_load(context)
      |> maybe_request_active_load(context)
    end
  end

  defp delegate_update_to_active_tab(event, %State{} = ss, %Context{} = context) do
    case Enum.at(State.tab_labels(ss), ss.active_tab) do
      "SITE" ->
        delegate_update_to_submodule(event, ss, :site_form, SiteForm, context)

      "LIMITS" ->
        delegate_update_to_submodule(event, ss, :limits_form, LimitsForm, context)

      "BOARDS" ->
        delegate_update_to_submodule(event, ss, :boards_view, BoardsView, context)

      "SYSTEM" ->
        delegate_update_to_submodule(event, ss, :system_snapshot, SystemSnapshot, context)

      "USERS" ->
        delegate_update_to_submodule(event, ss, :users_view, UsersView, context)

      "INVITES" ->
        delegate_update_to_invites(event, ss, context)

      _ ->
        {ss, []}
    end
  end

  defp delegate_update_to_invites(event, %State{} = ss, %Context{} = context) do
    key = invite_key(event)

    case key do
      key when key in ["r", "R"] ->
        {ss, [invites_effect(:sysop_load_invites, context, ss.invites)]}

      key when key in ["g", "G"] ->
        {ss, [invites_effect(:sysop_generate_invite, context, ss.invites)]}

      key when key in ["d", "D"] ->
        {ss, [invites_effect(:sysop_revoke_invite, context, ss.invites)]}

      _ ->
        case InvitesActions.handle_key(key, context.current_user, ss.invites) do
          {:ok, invites} ->
            armed_after =
              ss.armed_revoke? and
                invites_arm_preserved?(key, invites, ss.invites)

            {%{ss | invites: invites, armed_revoke?: armed_after}, []}

          :no_match ->
            {ss, []}
        end
    end
  end

  defp delegate_update_to_submodule(event, %State{} = ss, :site_form = field, module, context) do
    sub = Map.get(ss, field) || module.init(current_user: context.current_user)
    {new_sub, events} = module.handle_key(event, sub)
    apply_update_submodule_result(ss, field, new_sub, sub, events)
  end

  defp delegate_update_to_submodule(event, %State{} = ss, field, module, _context) do
    case Map.get(ss, field) do
      {:loaded, sub} ->
        {new_sub, events} = module.handle_key(event, sub)
        apply_update_submodule_result(ss, field, {:loaded, new_sub}, {:loaded, sub}, events)

      _other ->
        {ss, []}
    end
  end

  defp apply_update_submodule_result(%State{} = ss, field, new_sub, old_sub, events) do
    new_ss = Map.put(ss, field, new_sub)

    case Enum.find(events, fn
           {:error_modal, _msg, _dest} -> true
           _ -> false
         end) do
      {:error_modal, msg, dest} ->
        {new_ss,
         [Effect.open_modal(%Modal{type: :error, message: msg}), Effect.navigate(dest, %{})]}

      nil ->
        if new_sub == old_sub and events == [] do
          {ss, []}
        else
          {new_ss, []}
        end
    end
  end

  defp maybe_request_invites_load(%State{} = ss, %Context{} = context) do
    case {Enum.at(State.tab_labels(ss), ss.active_tab), ss.invites.items} do
      {"INVITES", items} when not is_list(items) ->
        {ss, [invites_effect(:sysop_load_invites, context, ss.invites)]}

      _ ->
        {ss, []}
    end
  end

  defp maybe_request_active_load({%State{} = ss, effects}, %Context{} = context) do
    {new_ss, load_effects} = maybe_request_active_load(ss, context)
    {new_ss, effects ++ load_effects}
  end

  defp maybe_request_active_load(%State{} = ss, %Context{} = context) do
    active_label = Enum.at(State.tab_labels(ss), ss.active_tab)
    slot = slot_for(active_label)

    case slot && Map.get(ss, slot) do
      :not_loaded ->
        {Map.put(ss, slot, :loading), [load_effect_for_label(active_label, context)]}

      _other ->
        {ss, []}
    end
  end

  defp load_effect_for_label("BOARDS", context),
    do: lifecycle_effect(:sysop_load_boards, context)

  defp load_effect_for_label("LIMITS", context),
    do: lifecycle_effect(:sysop_load_limits, context)

  defp load_effect_for_label("SYSTEM", context),
    do: lifecycle_effect(:sysop_load_system, context)

  defp load_effect_for_label("USERS", context),
    do: lifecycle_effect(:sysop_load_users, context)

  defp lifecycle_effect(:sysop_load_boards, %Context{} = context) do
    Effect.task(:sysop_load_boards, :sysop, fn ->
      BoardsView.init(current_user: context.current_user)
    end)
  end

  defp lifecycle_effect(:sysop_load_limits, %Context{} = context) do
    Effect.task(:sysop_load_limits, :sysop, fn ->
      LimitsForm.init(current_user: context.current_user)
    end)
  end

  defp lifecycle_effect(:sysop_load_system, %Context{}) do
    Effect.task(:sysop_load_system, :sysop, fn -> SystemSnapshot.init([]) end)
  end

  defp lifecycle_effect(:sysop_load_users, %Context{} = context) do
    accounts_mod = domain_module(context, :accounts, Foglet.Accounts)

    Effect.task(:sysop_load_users, :sysop, fn ->
      case accounts_mod.list_user_status_admin_targets(context.current_user) do
        {:ok, groups} -> {:ok, UsersView.from_groups(groups, context.current_user)}
        {:error, reason} -> {:error, reason}
      end
    end)
  end

  defp invites_effect(op, %Context{} = context, invites) do
    Effect.task(op, :sysop, fn ->
      case op do
        :sysop_load_invites -> InvitesActions.load(context.current_user, invites)
        :sysop_generate_invite -> InvitesActions.generate(context.current_user, invites)
        :sysop_revoke_invite -> InvitesActions.revoke_selected(context.current_user, invites)
      end
    end)
  end

  defp slot_for_op(:sysop_load_boards), do: :boards_view
  defp slot_for_op(:sysop_load_limits), do: :limits_form
  defp slot_for_op(:sysop_load_system), do: :system_snapshot
  defp slot_for_op(:sysop_load_users), do: :users_view

  defp domain_module(%Context{} = context, key, default) do
    Map.get(context.domain || %{}, key) ||
      (is_map(context.session_context) &&
         get_in(context.session_context, [:domain, key])) ||
      default
  end

  defp unwrap_task_result({:ok, {:ok, value}}), do: {:ok, value}
  defp unwrap_task_result({:ok, {:error, reason}}), do: {:error, reason}
  defp unwrap_task_result({:ok, value}), do: {:ok, value}
  defp unwrap_task_result({:error, reason}), do: {:error, reason}

  defp normalize_reason(reason) when is_atom(reason), do: reason
  defp normalize_reason(_reason), do: :error
end
