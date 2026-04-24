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

  alias Foglet.TUI.Screens.Moderation.State
  alias Foglet.TUI.Screens.Shared.InvitesActions
  alias Foglet.TUI.Screens.Shared.InvitesSurface
  alias Foglet.TUI.Screens.ShellVisibility
  alias Foglet.TUI.Theme
  alias Foglet.TUI.Widgets.Chrome.ScreenFrame
  alias Foglet.TUI.Widgets.Input.Tabs

  @key_list [{"←/→", "Tab"}, {"1-6", "Jump"}, {"Q", "Back"}]
  @max_rows 20
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

  defp render_tab_body("QUEUE", ss, theme) do
    column style: %{gap: 0} do
      [
        status_line(ss, theme),
        text("No report queue workflow is available in v1.1.", fg: theme.dim.fg)
      ]
      |> Enum.reject(&is_nil/1)
    end
  end

  defp render_tab_body("LOG", ss, theme) do
    column style: %{gap: 0} do
      [
        status_line(ss, theme),
        text("hide_oneliner audit log", fg: theme.accent.fg)
        | audit_rows(ss.mod_log, theme)
      ]
      |> Enum.reject(&is_nil/1)
    end
  end

  defp render_tab_body("USERS", ss, theme) do
    column style: %{gap: 0} do
      [
        status_line(ss, theme),
        text("Read-only active user context.", fg: theme.dim.fg)
        | user_rows(ss.users, theme)
      ]
      |> Enum.reject(&is_nil/1)
    end
  end

  defp render_tab_body("SANCTIONS", ss, theme) do
    column style: %{gap: 0} do
      [
        status_line(ss, theme),
        text("No sanction workflow is available in v1.1.", fg: theme.dim.fg)
      ]
      |> Enum.reject(&is_nil/1)
    end
  end

  defp render_tab_body("BOARDS", ss, theme) do
    column style: %{gap: 0} do
      [
        status_line(ss, theme),
        text("Read-only hide_oneliner scope context: #{format_scopes(ss.scopes)}",
          fg: theme.dim.fg
        )
        | board_rows(ss.boards, theme)
      ]
      |> Enum.reject(&is_nil/1)
    end
  end

  defp render_tab_body("INVITES", ss, theme) do
    InvitesSurface.render(ss.invites, theme)
  end

  defp render_tab_body(_label, _ss, theme) do
    column style: %{gap: 0} do
      [text("No report queue workflow is available in v1.1.", fg: theme.dim.fg)]
    end
  end

  defp status_line(%{loading?: true}, theme),
    do: text("Loading moderation workspace…", fg: theme.dim.fg)

  defp status_line(%{error: nil}, _theme), do: nil

  defp status_line(%{error: error}, theme),
    do: text("Unable to load moderation workspace: #{truncate(error)}", fg: theme.error.fg)

  defp audit_rows([], theme),
    do: [text("No hide_oneliner audit records in scope.", fg: theme.dim.fg)]

  defp audit_rows(actions, theme) do
    actions
    |> Enum.take(@max_rows)
    |> Enum.map(fn action ->
      moderator = action |> Map.get(:mod) |> field(:handle, "unknown")
      metadata = Map.get(action, :metadata) || %{}

      target =
        Map.get(metadata, "author_handle") || Map.get(metadata, :author_handle) ||
          target_id(action)

      body = Map.get(metadata, "body") || Map.get(metadata, :body) || ""
      reason = field(action, :reason, "")

      text(
        "#{timestamp(action)} hide_oneliner by #{truncate(moderator, 18)} -> #{truncate(target, 18)}: #{truncate(body)} | reason: #{truncate(reason)}",
        fg: theme.primary.fg
      )
    end)
  end

  defp user_rows([], theme), do: [text("No active users in scope.", fg: theme.dim.fg)]

  defp user_rows(users, theme) do
    users
    |> Enum.take(@max_rows)
    |> Enum.map(fn user ->
      handle = field(user, :handle, "unknown")
      role = field(user, :role, "user")
      status = field(user, :status, "active")

      text("#{truncate(handle, 20)} | role: #{role} | status: #{status}", fg: theme.primary.fg)
    end)
  end

  defp board_rows([], theme), do: [text("No board scopes available.", fg: theme.dim.fg)]

  defp board_rows(boards, theme) do
    boards
    |> Enum.take(@max_rows)
    |> Enum.map(fn board ->
      name = field(board, :name, "unknown")
      slug = field(board, :slug, "")
      category = field(board, :category_name, "")
      scope = board |> Map.get(:scope) |> format_scope()

      text("#{truncate(name, 24)} | #{truncate(slug, 20)} | #{truncate(category, 20)} | #{scope}",
        fg: theme.primary.fg
      )
    end)
  end

  defp format_scopes([]), do: "none"
  defp format_scopes(scopes), do: Enum.map_join(scopes, ", ", &format_scope/1)

  defp format_scope(:site), do: "site"
  defp format_scope({:board, board_id}), do: "board:#{board_id}"
  defp format_scope(scope), do: to_string(scope)

  defp timestamp(%{inserted_at: %DateTime{} = inserted_at}) do
    Calendar.strftime(inserted_at, "%Y-%m-%d %H:%M")
  end

  defp timestamp(_action), do: ""

  defp target_id(action), do: field(action, :target_id, "unknown")

  defp field(nil, _key, default), do: default

  defp field(map, key, default) when is_map(map) do
    case Map.get(map, key, default) do
      nil -> default
      value -> to_string(value)
    end
  end

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
