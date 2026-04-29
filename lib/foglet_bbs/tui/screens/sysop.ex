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
  alias Foglet.TUI.Screens.ShellVisibility
  alias Foglet.TUI.Screens.Sysop.BoardsView
  alias Foglet.TUI.Screens.Sysop.LimitsForm
  alias Foglet.TUI.Screens.Sysop.Render
  alias Foglet.TUI.Screens.Sysop.SiteForm
  alias Foglet.TUI.Screens.Sysop.State
  alias Foglet.TUI.Screens.Sysop.SystemSnapshot
  alias Foglet.TUI.Screens.Sysop.UsersView
  alias Foglet.TUI.Widgets.Input.Tabs

  @impl true
  @spec init(Context.t()) :: State.t()
  def init(%Context{} = context) do
    State.new(
      current_user: context.current_user,
      session_context: context.session_context
    )
  end

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
    context
    |> render_model(local_state)
    |> Render.render()
  end

  def render(local_state, %Context{} = context),
    do: render(normalize_state(local_state, context), context)

  defp slot_for("BOARDS"), do: :boards_view
  defp slot_for("LIMITS"), do: :limits_form
  defp slot_for("SYSTEM"), do: :system_snapshot
  defp slot_for("USERS"), do: :users_view
  defp slot_for(_), do: nil

  # The arm survives only when the InvitesActions key was a pure vertical
  # move AND the focused row is unchanged. A focus move on j/k still clears
  # the arm because the row identity changed; a non-move key (R/G) clears
  # it unconditionally because the gesture context (focus snapshot at arm
  # time) is no longer trustworthy.
  defp invites_arm_preserved?(key, new_invites, old_invites) do
    key in [:up, :down, "j", "k", "J", "K"] and
      new_invites.selected_index == old_invites.selected_index
  end

  defp invite_key(%{key: :char, char: char}) when is_binary(char), do: char
  defp invite_key(%{key: key}), do: key
  defp invite_key(event), do: event

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
