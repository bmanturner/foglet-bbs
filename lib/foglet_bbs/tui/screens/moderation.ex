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

  Tab bodies render scope-aware, read-only state loaded by the TUI app. Report
  queues, sanctions, user mutation, and board lifecycle workflows remain
  unavailable in v1.1, so those tabs show honest non-action states.

  ## INVITES Tab

  CONTEXT.md D-10 locks the base Moderation tab set to exactly the five
  listed above. Phase 4 appends the shared INVITES surface when
  `registration_mode == "invite_only"`, `invite_code_generators == "mods"`,
  and the current actor is a moderator.
  """

  @behaviour Foglet.TUI.Screen

  import Raxol.Core.Renderer.View

  alias Foglet.TUI.Context
  alias Foglet.TUI.Effect
  alias Foglet.TUI.Modal
  alias Foglet.TUI.Presentation
  alias Foglet.TUI.Screens.Moderation.State
  alias Foglet.TUI.Screens.Shared.InvitesActions
  alias Foglet.TUI.Screens.Shared.InvitesSurface
  alias Foglet.TUI.Screens.Shared.Reporting
  alias Foglet.TUI.Screens.ShellVisibility
  alias Foglet.TUI.Theme
  alias Foglet.TUI.Widgets.Chrome.ScreenFrame
  alias Foglet.TUI.Widgets.Display.ConsoleTable
  alias Foglet.TUI.Widgets.Display.KvGrid
  alias Foglet.TUI.Widgets.Input.Tabs
  alias Foglet.TUI.Widgets.Workspace.Inspector

  @text_limit 48

  # ---------------------------------------------------------------------------
  # Screen behaviour callbacks
  # ---------------------------------------------------------------------------

  @impl true
  @spec init(Context.t()) :: State.t()
  def init(%Context{} = context) do
    State.new(invites_visible?: moderation_invites_visible?(context))
  end

  @impl true
  @spec update(term(), State.t() | nil, Context.t()) :: {State.t(), [Effect.t()]}
  # Phase 39 D-01/D-03/D-14: screen owns its route-entry conditional load.
  # Preserves the user-conditional semantics today encoded in App's
  # `maybe_dispatch_route_entry/3` for `:moderation` (`app.ex:818-824`); Plan
  # 39-05 will collapse the App-side per-screen clauses into a single generic
  # dispatch.
  def update(:on_route_enter, local_state, %Context{} = context) do
    if context.current_user do
      update(:load, local_state, context)
    else
      {normalize_state(local_state, context), []}
    end
  end

  def update(:load, local_state, %Context{} = context) do
    ss =
      local_state
      |> normalize_state(context)
      |> Map.merge(%{loading?: true, error: nil})

    {ss, [load_workspace_effect(context)]}
  end

  def update(
        {:task_result, :load_moderation_workspace, result},
        local_state,
        %Context{} = context
      ) do
    ss = normalize_state(local_state, context)

    case unwrap_task_result(result) do
      {:ok, snapshot} when is_map(snapshot) ->
        queue = Map.get(snapshot, :queue, [])
        queue_selected_index = clamp_queue_selected_index(ss.queue_selected_index, queue)

        {%{
           ss
           | scopes: Map.get(snapshot, :scopes, []),
             queue: queue,
             queue_selected_index: queue_selected_index,
             queue_table: State.build_queue_table(queue, queue_selected_index),
             mod_log: Map.get(snapshot, :log, []),
             users: Map.get(snapshot, :users, []),
             boards: Map.get(snapshot, :boards, []),
             loading?: false,
             error: nil
         }, []}

      {:error, reason} ->
        {%{ss | loading?: false, error: reason}, []}
    end
  end

  def update({:task_result, op, result}, local_state, %Context{} = context)
      when op in [
             :moderation_load_invites,
             :moderation_generate_invite,
             :moderation_revoke_invite
           ] do
    ss = normalize_state(local_state, context)

    case unwrap_task_result(result) do
      {:ok, %Foglet.TUI.Screens.Shared.InvitesState{} = invites} ->
        {%{ss | invites: invites}, []}

      {:error, reason} ->
        {%{
           ss
           | invites:
               Foglet.TUI.Screens.Shared.InvitesState.with_error(ss.invites, to_string(reason))
         }, []}
    end
  end

  def update({:modal_submit, op, payload}, local_state, %Context{} = context)
      when op in [:resolve_report, :dismiss_report] do
    ss = normalize_state(local_state, context)
    moderation_mod = domain_module(context, :moderation, Foglet.Moderation)

    effect =
      Effect.task(op, :moderation, fn ->
        case op do
          :resolve_report ->
            moderation_mod.resolve_report(context.current_user, Map.get(payload, :report_id), %{
              resolution_note: Map.get(payload, :resolution_note)
            })

          :dismiss_report ->
            moderation_mod.dismiss_report(context.current_user, Map.get(payload, :report_id), %{
              resolution_note: Map.get(payload, :resolution_note)
            })
        end
      end)

    {ss, [effect]}
  end

  def update({:task_result, op, result}, local_state, %Context{} = context)
      when op in [:resolve_report, :dismiss_report] do
    ss = normalize_state(local_state, context)

    case unwrap_task_result(result) do
      {:ok, report} ->
        queue = remove_report_from_queue(ss.queue, report)
        queue_selected_index = clamp_queue_selected_index(ss.queue_selected_index, queue)

        {%{
           ss
           | queue: queue,
             queue_selected_index: queue_selected_index,
             queue_table: State.build_queue_table(queue, queue_selected_index)
         },
         [
           Effect.open_modal(
             Reporting.success_modal(
               if(op == :resolve_report, do: "Report resolved.", else: "Report dismissed.")
             )
           ),
           load_workspace_effect(context)
         ]}

      {:error, %Ecto.Changeset{} = changeset} ->
        title = if(op == :resolve_report, do: "Resolve Report", else: "Dismiss Report")

        modal =
          Reporting.resolution_modal(
            :moderation,
            op,
            %{report_id: Map.get(changeset.data, :id)},
            title: title,
            values: %{resolution_note: Map.get(changeset.changes, :resolution_note) || ""},
            errors: Reporting.changeset_errors(changeset)
          )

        {ss, [Effect.open_modal(modal)]}

      {:error, reason} ->
        title = if(op == :resolve_report, do: "Resolve Report", else: "Dismiss Report")

        modal =
          Reporting.resolution_modal(
            :moderation,
            op,
            %{report_id: selected_report_id(ss)},
            title: title,
            errors: %{base: "Unable to update report: #{inspect(reason)}"}
          )

        {ss, [Effect.open_modal(modal)]}
    end
  end

  def update({:key, %{key: :char, char: c}}, local_state, %Context{} = context)
      when c in ["Q", "q"] do
    {normalize_state(local_state, context), [Effect.navigate(:main_menu, %{})]}
  end

  def update({:key, event}, local_state, %Context{} = context) do
    ss = normalize_state(local_state, context)
    {new_tabs, action} = Tabs.handle_event(event, ss.tabs)

    # FOG-173: only treat the event as tab navigation when Tabs reports a real
    # action. Comparing `new_tabs == ss.tabs` is unsafe because `Tabs.handle_event/2`
    # always rewrites `last_action` (resetting it to nil after a previous
    # `{:tab_changed, _}`), so any post-tab-change keypress would falsely look
    # like a tab event and route around `handle_active_key`, silently dropping
    # G/D on the INVITES tab. Mirrors the `if action != nil` guard in Account.
    if action != nil do
      new_active =
        case action do
          {:tab_changed, idx} -> idx
          _ -> ss.active_tab
        end

      new_ss = %{ss | tabs: new_tabs, active_tab: new_active}
      {loaded_ss, effects} = maybe_request_invites(new_ss, context)
      {loaded_ss, effects}
    else
      handle_active_key(event, %{ss | tabs: new_tabs}, context)
    end
  end

  def update(_message, local_state, %Context{} = context),
    do: {normalize_state(local_state, context), []}

  @impl true
  @spec render(State.t(), Context.t()) :: any()
  def render(%State{} = state, %Context{} = context) do
    render_app_state(render_model(context, state))
  end

  # Previously had a `def render(local_state, %Context{})` fallback that
  # called `normalize_state/2`. Routing.render_local_state/4 always either
  # returns a stored `%State{}` or calls `init/1` (which returns `%State{}`),
  # so the fallback was unreachable and Dialyzer would flag the @spec.
  # See WR-01 in 47-REVIEW.md (and the matching WR-03 fix in BoardList).

  defp render_app_state(state) do
    if ShellVisibility.moderation_visible?(state.current_user) do
      render_authorized(state)
    else
      theme = Theme.from_state(state)

      empty =
        column style: %{gap: 0} do
          [text("Moderation is not available for this account.", fg: theme.warning.fg)]
        end

      ScreenFrame.render(state, moderation_chrome(), empty, [
        %{label: "System", commands: [%{key: "Q", label: "Back", priority: 0}]}
      ])
    end
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp get_screen_state(state) do
    ss = Map.get(state, :screen_state) || %{}
    Map.get(ss, :moderation) || State.new()
  end

  defp render_authorized(state) do
    ss = synced_screen_state(state)
    theme = Theme.from_state(state)
    width = inner_width(state)
    height = body_height(state)
    content = render_content(ss, theme, width, height, state.current_user, user_timezone(state))
    ScreenFrame.render(state, moderation_chrome(), content, key_list(ss))
  end

  defp key_list(ss) do
    tabs_group = %{
      label: "Tabs",
      commands: [%{key: "←/→", label: "Tabs", priority: 10}]
    }

    system_group = %{
      label: "System",
      commands: [%{key: "Q", label: "Back", priority: 0}]
    }

    middle = middle_groups(Enum.at(tab_labels_from_tabs(ss.tabs), ss.active_tab), ss)

    [tabs_group | middle] ++ [system_group]
  end

  # FOG-164: ScreenFrame keybar is active-tab aware on INVITES so revoke /
  # generate / refresh hints are first-class command-bar entries (not body-only).
  # Mirrors `Foglet.TUI.Screens.Account.Render.middle_groups/2`.
  defp middle_groups("QUEUE", %State{queue: queue}) do
    if queue == [] do
      []
    else
      [
        %{label: "Queue", commands: [%{key: "↑/↓", label: "Select", priority: 20}]},
        %{
          label: "Actions",
          commands: [
            %{key: "V", label: "View", priority: 5},
            %{key: "E", label: "Resolve", priority: 5},
            %{key: "D", label: "Dismiss", priority: 5},
            %{key: "R", label: "Refresh", priority: 5}
          ]
        }
      ]
    end
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

  defp middle_groups(_label, _ss), do: []

  defp moderation_chrome do
    %{
      title: "Moderation",
      mode: Presentation.mode_for!(:moderation),
      breadcrumb_parts: Foglet.AppName.breadcrumb(["Moderation"])
    }
  end

  # ScreenFrame uses padding: 1 and border: :single, consuming 4 columns total.
  defp inner_width(state) do
    case Map.get(state, :terminal_size) do
      {w, _} when is_integer(w) -> max(w - 4, 0)
      _ -> 76
    end
  end

  defp body_height(state) do
    case Map.get(state, :terminal_size) do
      {_, h} when is_integer(h) -> max(h - 4, 0)
      _ -> 20
    end
  end

  defp render_content(ss, theme, width, height, user, timezone) do
    active_label = Enum.at(tab_labels_from_tabs(ss.tabs), ss.active_tab, "QUEUE")
    tab_body = render_tab_body(active_label, ss, theme, width, height, user, timezone)

    column style: %{gap: 0} do
      [Tabs.render(ss.tabs, theme: theme, width: width), tab_body]
    end
  end

  defp render_tab_body("QUEUE", ss, theme, width, height, _user, _timezone) do
    selected = selected_report(ss)

    if width >= 100 do
      render_queue_workspace(ss, selected, theme, width, height)
    else
      render_queue_stack(ss, selected, theme, width, height)
    end
  end

  defp render_tab_body("LOG", ss, theme, width, height, user, timezone) do
    log_table = fresh_log_table(ss, width, height, user, timezone)
    log_summary = State.build_log_summary(ss.scopes, ss.error, ss.mod_log)
    children = compact_table_children(log_summary, log_table, theme, width, height)

    column style: %{gap: 1} do
      children
    end
  end

  defp render_tab_body("USERS", ss, theme, width, height, _user, _timezone) do
    users_table = fresh_users_table(ss, width, height)
    users_summary = State.build_users_summary(ss.users, ss.error)
    children = compact_table_children(users_summary, users_table, theme, width, height)

    column style: %{gap: 1} do
      children
    end
  end

  defp render_tab_body("SANCTIONS", ss, theme, _width, _height, _user, _timezone) do
    column style: %{gap: 0} do
      [
        status_line(ss, theme),
        text("Sanctions are not available yet.", fg: theme.dim.fg)
      ]
      |> Enum.reject(&is_nil/1)
    end
  end

  defp render_tab_body("BOARDS", ss, theme, width, height, _user, _timezone) do
    boards_table = fresh_boards_table(ss, width, height)
    boards_summary = State.build_boards_summary(ss.scopes, ss.boards, ss.error)
    children = compact_table_children(boards_summary, boards_table, theme, width, height)

    column style: %{gap: 1} do
      children
    end
  end

  defp render_tab_body("INVITES", ss, theme, width, height, _user, _timezone) do
    InvitesSurface.render(ss.invites, theme, width: width, height: max(height - 2, 1))
  end

  defp render_tab_body(_label, _ss, theme, _width, _height, _user, _timezone) do
    column style: %{gap: 0} do
      [text("This moderation tab is not available.", fg: theme.dim.fg)]
    end
  end

  defp status_line(%{loading?: true}, theme),
    do: text("Loading moderation workspace…", fg: theme.dim.fg)

  defp status_line(%{error: nil}, _theme), do: nil

  defp status_line(%{error: error}, theme),
    do: text("Could not load moderation workspace: #{truncate(error)}", fg: theme.error.fg)

  defp truncate(value, limit \\ @text_limit)

  defp truncate(value, limit) do
    value = to_string(value)

    if String.length(value) > limit do
      String.slice(value, 0, max(limit - 1, 0)) <> "…"
    else
      value
    end
  end

  defp synced_screen_state(state) do
    ss = get_screen_state(state)

    labels = State.tab_labels(moderation_invites_visible?(state))
    active = min(ss.active_tab, length(labels) - 1)

    if tab_labels_from_tabs(ss.tabs) == labels and active == ss.active_tab do
      ss
    else
      %{ss | tabs: Tabs.init(tabs: labels, active: active), active_tab: active}
    end
  end

  defp normalize_state(nil, %Context{} = context), do: init(context)

  defp normalize_state(%State{} = ss, %Context{} = context) do
    labels = State.tab_labels(moderation_invites_visible?(context))
    active = min(ss.active_tab, length(labels) - 1)

    if tab_labels_from_tabs(ss.tabs) == labels and active == ss.active_tab do
      ss
    else
      %{ss | tabs: Tabs.init(tabs: labels, active: active), active_tab: active}
    end
  end

  defp render_model(%Context{} = context, %State{} = state) do
    %{
      current_user: context.current_user,
      session_context: context.session_context,
      terminal_size: context.terminal_size,
      current_screen: :moderation,
      route_params: context.route_params,
      screen_state: %{moderation: state}
    }
  end

  defp moderation_invites_visible?(%Context{} = context) do
    case context.current_user do
      %{role: :mod} ->
        ShellVisibility.invites_visible?(context.current_user, context.session_context)

      _ ->
        false
    end
  end

  defp moderation_invites_visible?(%{current_user: %{role: :mod}} = state) do
    ShellVisibility.invites_visible?(
      Map.get(state, :current_user),
      Map.get(state, :session_context)
    )
  end

  defp moderation_invites_visible?(_state), do: false

  defp tab_labels_from_tabs(%Tabs{raxol_state: %{tabs: tabs}}) when is_list(tabs) do
    Enum.map(tabs, fn
      %{label: label} -> label
      other -> to_string(other)
    end)
  end

  # IN-03: fallback for corrupt `%Tabs{}` structures (raxol_state without
  # `:tabs`, or non-list `:tabs`). Used inside `render/1`, so silently
  # degrading to an empty list (treated as "QUEUE only" upstream) is
  # preferable to crashing the whole moderation screen.
  defp tab_labels_from_tabs(_tabs), do: []

  defp handle_active_key(event, %State{} = ss, %Context{} = context) do
    case Enum.at(tab_labels_from_tabs(ss.tabs), ss.active_tab) do
      "QUEUE" ->
        handle_queue_update(event, ss, context)

      "INVITES" ->
        handle_invites_update(event, ss, context)

      label when label in ["LOG", "USERS", "BOARDS"] ->
        handle_read_only_table_key(label, event, ss)

      _other ->
        {ss, []}
    end
  end

  defp handle_invites_update(event, %State{} = ss, %Context{} = context) do
    key = key_for_invites(event)
    invites = ss.invites
    mode = Map.get(invites, :mode, :list)

    case {key, mode} do
      {key, :list} when key in ["r", "R"] ->
        {ss, [invites_effect(:moderation_load_invites, context, invites)]}

      {key, :list} when key in ["g", "G"] ->
        {ss, [invites_effect(:moderation_generate_invite, context, invites)]}

      # FOG-164: D arms the confirm flow rather than dispatching the revoke directly.
      {key, :list} when key in ["d", "D"] ->
        {%{ss | invites: Foglet.TUI.Screens.Shared.InvitesState.start_confirm_revoke(invites)},
         []}

      {:enter, :confirm_revoke} ->
        cleared = %{invites | mode: :list, confirm_target: nil}
        {%{ss | invites: cleared}, [invites_effect(:moderation_revoke_invite, context, cleared)]}

      {:escape, :confirm_revoke} ->
        {%{ss | invites: Foglet.TUI.Screens.Shared.InvitesState.cancel_confirm_revoke(invites)},
         []}

      _ ->
        case InvitesActions.handle_key(key, context.current_user, invites) do
          {:ok, new_invites} -> {%{ss | invites: new_invites}, []}
          :no_match -> {ss, []}
        end
    end
  end

  defp handle_queue_update(event, %State{} = ss, %Context{} = context) do
    case key_for_queue(event) do
      :next ->
        {move_queue_selection(ss, %{key: :down}), []}

      :prev ->
        {move_queue_selection(ss, %{key: :up}), []}

      :view ->
        open_queue_target(ss)

      :refresh ->
        {ss, [load_workspace_effect(context)]}

      action when action in [:resolve, :dismiss] ->
        open_queue_resolution(action, ss)

      _ ->
        {ss, []}
    end
  end

  defp maybe_request_invites(%State{} = ss, %Context{} = context) do
    case {Enum.at(tab_labels_from_tabs(ss.tabs), ss.active_tab), ss.invites.items} do
      {"INVITES", items} when not is_list(items) ->
        {ss, [invites_effect(:moderation_load_invites, context, ss.invites)]}

      _ ->
        {ss, []}
    end
  end

  defp handle_read_only_table_key("LOG", event, %State{} = ss) do
    table = ss.log_table || State.build_log_table(ss.mod_log)
    {new_table, _action} = ConsoleTable.handle_event(event, table)
    {%{ss | log_table: new_table}, []}
  end

  defp handle_read_only_table_key("USERS", event, %State{} = ss) do
    table = ss.users_table || State.build_users_table(ss.users)
    {new_table, _action} = ConsoleTable.handle_event(event, table)
    {%{ss | users_table: new_table}, []}
  end

  defp handle_read_only_table_key("BOARDS", event, %State{} = ss) do
    table = ss.boards_table || State.build_boards_table(ss.boards)
    {new_table, _action} = ConsoleTable.handle_event(event, table)
    {%{ss | boards_table: new_table}, []}
  end

  defp open_queue_resolution(action, %State{} = ss) do
    case selected_report(ss) do
      nil -> {ss, []}
      report -> {ss, [Effect.open_modal(queue_resolution_modal(queue_action_op(action), report))]}
    end
  end

  defp open_queue_target(%State{} = ss) do
    case selected_report(ss) do
      nil ->
        {ss, []}

      report ->
        modal =
          %Modal{
            type: :info,
            title: "Reported Target",
            message: Enum.join(selected_report_summary_lines(report), "\n")
          }

        {ss, [Effect.open_modal(modal)]}
    end
  end

  defp queue_action_op(:resolve), do: :resolve_report
  defp queue_action_op(:dismiss), do: :dismiss_report

  defp selected_report_rows(nil, _theme), do: []

  defp selected_report_rows(report, theme) do
    [text("", fg: theme.dim.fg), text("Selected report", fg: theme.primary.fg)] ++
      Enum.map(selected_report_summary_lines(report), &text(&1, fg: theme.unselected.fg))
  end

  defp selected_report(%State{} = ss) do
    Enum.at(ss.queue, clamp_queue_selected_index(ss.queue_selected_index, ss.queue))
  end

  defp selected_report_id(%State{} = ss) do
    case selected_report(ss) do
      %{id: id} -> id
      _ -> nil
    end
  end

  defp move_queue_selection(%State{} = ss, event) do
    table = fresh_queue_table(ss)
    {new_table, _action} = ConsoleTable.handle_event(event, table)
    selected_index = queue_table_selected_index(new_table, ss.queue)

    %{
      ss
      | queue_selected_index: selected_index,
        queue_table: State.build_queue_table(ss.queue, selected_index)
    }
  end

  defp queue_table_selected_index(_table, []), do: 0

  defp queue_table_selected_index(%ConsoleTable{table: table}, queue) do
    table.raxol_state
    |> Map.get(:selected_row, 0)
    |> clamp_queue_selected_index(queue)
  end

  defp clamp_queue_selected_index(_index, []), do: 0

  defp clamp_queue_selected_index(index, queue) do
    index
    |> max(0)
    |> min(length(queue) - 1)
  end

  defp queue_resolution_modal(op, report) do
    title = if(op == :resolve_report, do: "Resolve Report", else: "Dismiss Report")

    Reporting.resolution_modal(:moderation, op, %{report_id: Map.get(report, :id)},
      title: title,
      values: %{resolution_note: ""},
      summary_lines: selected_report_summary_lines(report)
    )
  end

  defp render_queue_workspace(ss, selected, theme, width, height) do
    {queue_width, inspector_width} = queue_workspace_pane_widths(width)
    table = fresh_queue_table(ss, queue_width, height)
    inspector = queue_inspector(selected)

    queue_column =
      column style: %{gap: 0} do
        [
          status_line(ss, theme),
          text("Open reports: #{length(ss.queue)}", fg: theme.dim.fg),
          ConsoleTable.render(table, theme: theme)
        ]
        |> Enum.reject(&is_nil/1)
      end

    inspector_column =
      column style: %{gap: 0} do
        [Inspector.render(inspector, theme: theme, width: inspector_width, min_width: 40)]
      end

    split_pane(
      direction: :horizontal,
      ratio: {3, 2},
      min_size: 30,
      divider_char: " ",
      children: [queue_column, inspector_column],
      height: max(height - 2, 1)
    )
  end

  defp queue_workspace_pane_widths(width) do
    available = max(width - 1, 0)
    queue_width = max(div(available * 3, 5), 30)
    inspector_width = max(available - queue_width, 30)

    {queue_width, inspector_width}
  end

  defp render_queue_stack(ss, selected, theme, width, height) do
    table = fresh_queue_table(ss, width, height)

    column style: %{gap: 0} do
      ([
         status_line(ss, theme),
         text("Open reports: #{length(ss.queue)}", fg: theme.dim.fg),
         ConsoleTable.render(table, theme: theme)
       ] ++
         selected_report_rows(selected, theme))
      |> Enum.reject(&is_nil/1)
    end
  end

  defp fresh_queue_table(%State{} = ss, width \\ nil, height \\ nil) do
    State.build_queue_table(ss.queue, ss.queue_selected_index,
      width: width,
      page_size: page_size(height || 14)
    )
  end

  defp queue_inspector(nil), do: nil

  defp queue_inspector(report) do
    %{
      title: "Selected report",
      details: [
        %{label: "Target", value: report_target_label(report)},
        %{label: "Source", value: report_target_source(report)},
        %{label: "Reason", value: report_reason(report)},
        %{
          label: "Reported by",
          value: "@#{report |> Map.get(:reporter) |> Map.get(:handle, "unknown")}"
        },
        %{label: "Notes", value: report_notes(report)}
      ],
      actions: [
        %{key: "V", label: "View target"},
        %{key: "E", label: "Resolve", role: :primary},
        %{key: "D", label: "Dismiss", role: :destructive},
        %{key: "R", label: "Refresh"}
      ]
    }
  end

  defp selected_report_summary_lines(report) do
    [
      "Target: #{report_target_label(report)}",
      "Source: #{report_target_source(report)}",
      "Reason: #{report_reason(report)}",
      "Reported by: @#{report |> Map.get(:reporter) |> Map.get(:handle, "unknown")}",
      "Notes: #{report_notes(report)}",
      "Actions: [V] View  [E] Resolve  [D] Dismiss  [R] Refresh"
    ]
  end

  defp remove_report_from_queue(queue, %{id: report_id}) do
    Enum.reject(queue, &(Map.get(&1, :id) == report_id))
  end

  defp report_target_kind(report), do: report |> Map.get(:target_kind, "unknown") |> to_string()

  defp report_target_label(report) do
    Map.get(report, :target_label) || Map.get(report, "target_label") ||
      report_target_kind(report)
  end

  defp report_target_source(report) do
    case Map.get(report, :target_source) || Map.get(report, "target_source") do
      value when is_binary(value) and value != "" -> value
      _ -> report_target_label(report)
    end
  end

  defp report_reason(report), do: report |> Map.get(:reason, "unspecified") |> to_string()

  defp report_notes(report) do
    case Map.get(report, :notes) do
      value when is_binary(value) and value != "" -> value
      _ -> "—"
    end
  end

  defp key_for_queue(%{key: :down}), do: :next
  defp key_for_queue(%{key: :up}), do: :prev
  defp key_for_queue(%{key: :char, char: char}) when char in ["j", "J"], do: :next
  defp key_for_queue(%{key: :char, char: char}) when char in ["k", "K"], do: :prev
  defp key_for_queue(%{key: :char, char: char}) when char in ["v", "V"], do: :view
  defp key_for_queue(%{key: :char, char: char}) when char in ["r", "R"], do: :refresh
  defp key_for_queue(%{key: :char, char: char}) when char in ["e", "E"], do: :resolve
  defp key_for_queue(%{key: :char, char: char}) when char in ["d", "D"], do: :dismiss
  defp key_for_queue(_event), do: :no_match

  defp load_workspace_effect(%Context{} = context) do
    moderation_mod = domain_module(context, :moderation, Foglet.Moderation)

    Effect.task(:load_moderation_workspace, :moderation, fn ->
      moderation_mod.workspace_snapshot(context.current_user)
    end)
  end

  defp invites_effect(op, %Context{} = context, invites) do
    Effect.task(op, :moderation, fn ->
      case op do
        :moderation_load_invites -> InvitesActions.load(context.current_user, invites)
        :moderation_generate_invite -> InvitesActions.generate(context.current_user, invites)
        :moderation_revoke_invite -> InvitesActions.revoke_selected(context.current_user, invites)
      end
    end)
  end

  # IN-04: thin shim around the shared `Foglet.TUI.Effect.unwrap_task_result/1`.
  defp unwrap_task_result(result), do: Effect.unwrap_task_result(result)

  # WR-08: explicit case-based resolution so each branch is forced to
  # produce an atom (or `default`). The previous `||`-chain silently
  # returned `nil` whenever any intermediate value was `false`, causing
  # downstream `Effect.task` bodies to crash with `UndefinedFunctionError`.
  defp domain_module(%Context{} = context, key, default) do
    case Map.get(context.domain || %{}, key) do
      mod when is_atom(mod) and not is_nil(mod) -> mod
      _ -> session_context_domain(context, key, default)
    end
  end

  defp session_context_domain(%Context{session_context: sc}, key, default) when is_map(sc) do
    # `sc` may be a `%Foglet.TUI.SessionContext{}` struct; structs do not
    # implement the Access protocol, so `get_in/2` would crash with
    # `UndefinedFunctionError: SessionContext.fetch/2`. Use Map.get/2 so the
    # lookup is safe for both structs and plain test/legacy maps.
    case Map.get(sc, :domain) do
      domain when is_map(domain) ->
        case Map.get(domain, key) do
          mod when is_atom(mod) and not is_nil(mod) -> mod
          _ -> default
        end

      _ ->
        default
    end
  end

  defp session_context_domain(_context, _key, default), do: default

  defp compact_table_children(summary, table, theme, width, height) do
    table_node = ConsoleTable.render(table, theme: theme)

    if height <= 18 do
      [table_node]
    else
      # FOG-177: KvGrid.render/2 now returns one layout element per entry
      # (badge entries pre-wrapped in `row`), so the outer column receives
      # homogeneous map children with no embedded newline text nodes.
      kv_rows = KvGrid.render(summary, theme: theme, width: width, label_width: 16, gap: 2)

      kv_column =
        column style: %{gap: 0} do
          kv_rows
        end

      [kv_column, table_node]
    end
  end

  # Always rebuild tables from raw domain rows at render time.
  # This ensures struct!-based test helpers (which set mod_log/users/boards
  # without rebuilding the ConsoleTable) still produce correct output.
  # In production the State.new/1 path pre-builds tables; the rebuild here
  # is cheap (bounded list) and idempotent.
  defp fresh_log_table(%{mod_log: rows}, width, height, user, timezone) do
    State.build_log_table(rows,
      width: width,
      page_size: page_size(height),
      user: user,
      timezone: timezone
    )
  end

  defp fresh_users_table(%{users: rows}, width, height) do
    State.build_users_table(rows, width: width, page_size: page_size(height))
  end

  defp fresh_boards_table(%{boards: rows}, width, height) do
    State.build_boards_table(rows, width: width, page_size: page_size(height))
  end

  defp page_size(height), do: max(height - 4, 3)

  defp user_timezone(state) do
    case Map.get(state, :current_user) do
      %{timezone: timezone} -> timezone
      _ -> nil
    end
  end

  defp key_for_invites(%{key: :char, char: char}), do: char
  defp key_for_invites(%{key: key}), do: key
end
