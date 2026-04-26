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
  `invite_code_generators == "mods"` and the current actor is a moderator.
  """

  @behaviour Foglet.TUI.Screen

  import Raxol.Core.Renderer.View

  alias Foglet.TUI.Presentation
  alias Foglet.TUI.Screens.Moderation.State
  alias Foglet.TUI.Screens.Shared.InvitesActions
  alias Foglet.TUI.Screens.Shared.InvitesSurface
  alias Foglet.TUI.Screens.ShellVisibility
  alias Foglet.TUI.Theme
  alias Foglet.TUI.Widgets.Chrome.ScreenFrame
  alias Foglet.TUI.Widgets.Display.ConsoleTable
  alias Foglet.TUI.Widgets.Display.KvGrid
  alias Foglet.TUI.Widgets.Input.Tabs

  @key_list [{"←/→", "Tab"}, {"1-6", "Jump"}, {"Q", "Back"}]
  @text_limit 48

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

      ScreenFrame.render(state, moderation_chrome(), empty, [{"Q", "Back"}])
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

        {:ok, %Foglet.TUI.Screens.Moderation.State{} = new_ss} ->
          # Table-tab delegates return the full updated screen state
          update_screen_state(state, new_ss)

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
    width = inner_width(state)
    height = body_height(state)
    content = render_content(ss, theme, width, height, state.current_user, user_timezone(state))
    ScreenFrame.render(state, moderation_chrome(), content, @key_list)
  end

  defp moderation_chrome do
    %{title: "Moderation", mode: Presentation.mode_for!(:moderation)}
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

  defp render_tab_body("QUEUE", ss, theme, _width, _height, _user, _timezone) do
    column style: %{gap: 0} do
      [
        status_line(ss, theme),
        text("No report queue workflow is available in v1.1.", fg: theme.dim.fg)
      ]
      |> Enum.reject(&is_nil/1)
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
        text("No sanction workflow is available in v1.1.", fg: theme.dim.fg)
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

  defp render_tab_body("INVITES", ss, theme, _width, _height, _user, _timezone) do
    InvitesSurface.render(ss.invites, theme)
  end

  defp render_tab_body(_label, _ss, theme, _width, _height, _user, _timezone) do
    column style: %{gap: 0} do
      [text("No report queue workflow is available in v1.1.", fg: theme.dim.fg)]
    end
  end

  defp status_line(%{loading?: true}, theme),
    do: text("Loading moderation workspace…", fg: theme.dim.fg)

  defp status_line(%{error: nil}, _theme), do: nil

  defp status_line(%{error: error}, theme),
    do: text("Unable to load moderation workspace: #{truncate(error)}", fg: theme.error.fg)

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

  defp delegate_to_active_tab(event, state, ss) do
    case Enum.at(tab_labels_from_tabs(ss.tabs), ss.active_tab) do
      "INVITES" ->
        event
        |> key_for_invites()
        |> InvitesActions.handle_key(state.current_user, ss.invites)

      "LOG" ->
        log_table = ss.log_table || State.build_log_table(ss.mod_log)
        {new_table, _action} = ConsoleTable.handle_event(event, log_table)
        new_ss = %{ss | log_table: new_table}
        # LOG is read-only; no domain dispatch (Pitfall 7)
        {:ok, new_ss}

      "USERS" ->
        users_table = ss.users_table || State.build_users_table(ss.users)
        {new_table, _action} = ConsoleTable.handle_event(event, users_table)
        new_ss = %{ss | users_table: new_table}
        # USERS is read-only; no domain dispatch
        {:ok, new_ss}

      "BOARDS" ->
        boards_table = ss.boards_table || State.build_boards_table(ss.boards)
        {new_table, _action} = ConsoleTable.handle_event(event, boards_table)
        new_ss = %{ss | boards_table: new_table}
        # BOARDS is read-only; no domain dispatch
        {:ok, new_ss}

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

  # Wraps KvGrid output in a column container. KvGrid.render/2 can return a list
  # containing [text, badge] pairs (when entries have badge metadata). Raxol's
  # flexbox cannot process nested lists as children; List.flatten/1 normalises
  # the list so every child is a single element map before the column is built.
  # This does NOT touch the internals of map values — only collapses list nesting.
  defp kv_grid_column(summary, theme, width) do
    flat =
      KvGrid.render(summary, theme: theme, width: width, label_width: 16, gap: 2)
      |> List.flatten()

    column style: %{gap: 0} do
      flat
    end
  end

  defp compact_table_children(summary, table, theme, width, height) do
    table_node = ConsoleTable.render(table, theme: theme)

    if height <= 18 do
      [table_node]
    else
      [kv_grid_column(summary, theme, width), table_node]
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

  defp update_screen_state(state, ss) do
    new_screen_state = Map.put(Map.get(state, :screen_state) || %{}, :moderation, ss)
    {:update, %{state | screen_state: new_screen_state}, []}
  end
end
