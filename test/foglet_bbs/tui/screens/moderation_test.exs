defmodule Foglet.TUI.Screens.ModerationTest do
  use FogletBbs.DataCase, async: false

  import Foglet.TUI.RenderHelpers

  alias Foglet.Accounts
  alias Foglet.Accounts.{Invites, User}
  alias Foglet.Config
  alias Foglet.Moderation.{Action, Report}
  alias Foglet.TUI.Context
  alias Foglet.TUI.Effect
  alias Foglet.TUI.Presentation
  alias Foglet.TUI.Screens.Moderation
  alias Foglet.TUI.Screens.Moderation.State, as: ModerationState
  alias Foglet.TUI.Screens.Shared.InvitesState
  alias Foglet.TUI.Theme
  alias Foglet.TUI.Widgets.Display.ConsoleTable
  alias Foglet.TUI.Widgets.Modal.Form, as: ModalForm
  alias FogletBbs.AccountsFixtures

  defp build_state(role, user \\ nil) do
    %Foglet.TUI.App{
      current_screen: :moderation,
      current_user: user || %Foglet.Accounts.User{id: "u1", handle: "alice", role: role},
      session_context: %{
        invite_code_generators: "sysop_only",
        registration_mode: "invite_only"
      },
      terminal_size: {80, 24},
      screen_state: %{}
    }
    |> Map.from_struct()
  end

  defp build_state_with_policy(role_or_user, policy, registration_mode \\ "invite_only")

  defp build_state_with_policy(%User{} = user, policy, registration_mode) do
    user.role
    |> build_state(user)
    |> put_in([:session_context, :invite_code_generators], policy)
    |> put_in([:session_context, :registration_mode], registration_mode)
  end

  defp build_state_with_policy(role, policy, registration_mode) do
    role
    |> build_state()
    |> put_in([:session_context, :invite_code_generators], policy)
    |> put_in([:session_context, :registration_mode], registration_mode)
  end

  defp moderation_context(state) do
    app = struct!(Foglet.TUI.App, Map.take(state, Map.keys(%Foglet.TUI.App{})))
    Foglet.TUI.App.build_context(app)
  end

  defp render_moderation(state) do
    context = moderation_context(state)
    local_state = get_in(state, [:screen_state, :moderation]) || Moderation.init(context)

    Moderation.render(local_state, context)
  end

  defp handle_moderation_key(event, state) do
    context = moderation_context(state)
    local_state = get_in(state, [:screen_state, :moderation]) || Moderation.init(context)
    {new_local_state, effects} = Moderation.update({:key, event}, local_state, context)
    state = put_in(state, [:screen_state, :moderation], new_local_state)

    if new_local_state == local_state and effects == [] do
      :no_match
    else
      apply_moderation_effects(state, effects)
    end
  end

  defp apply_moderation_effects(state, effects) do
    Enum.reduce(effects, {:update, state, []}, fn
      %Effect{type: :navigate, payload: %{screen: screen, params: params}},
      {:update, state, cmds} ->
        {:update, %{state | current_screen: screen, route_params: params || %{}}, cmds}

      %Effect{type: :task, payload: %{op: op, fun: fun}}, {:update, state, cmds} ->
        result = fun.()
        local_state = get_in(state, [:screen_state, :moderation])

        {new_local_state, followup} =
          Moderation.update(
            {:task_result, op, {:ok, result}},
            local_state,
            moderation_context(state)
          )

        state
        |> put_in([:screen_state, :moderation], new_local_state)
        |> apply_moderation_effects(followup)
        |> append_cmds(cmds)

      _effect, acc ->
        acc
    end)
  end

  defp append_cmds({:update, state, new_cmds}, cmds), do: {:update, state, cmds ++ new_cmds}

  setup do
    %{state: build_state(:mod)}
  end

  defmodule FakeModeration do
    def workspace_snapshot(_user) do
      {:ok,
       %{
         scopes: [:site],
         queue: [],
         log: [],
         users: [%{handle: "alice", role: :user, status: :active}],
         boards: [%{name: "General", category_name: "Main", state: :active}]
       }}
    end

    def resolve_report(_user, report_id, attrs) do
      {:ok,
       %Report{
         id: report_id,
         status: :resolved,
         resolution_note: Map.get(attrs, :resolution_note),
         target_kind: :post,
         target_id: Ecto.UUID.generate(),
         reason: "spam"
       }}
    end

    def dismiss_report(_user, report_id, attrs) do
      {:ok,
       %Report{
         id: report_id,
         status: :dismissed,
         resolution_note: Map.get(attrs, :resolution_note),
         target_kind: :post,
         target_id: Ecto.UUID.generate(),
         reason: "spam"
       }}
    end
  end

  describe "Moderation.State.new/1" do
    test "returns struct with active_tab: 0 and Tabs wrapper" do
      ss = ModerationState.new()
      assert ss.active_tab == 0
      assert %Foglet.TUI.Widgets.Input.Tabs{} = ss.tabs
    end
  end

  describe "new screen contract" do
    test "LOG tab uses enhanced width for operator context next to the event table" do
      user = %User{id: "u1", handle: "mod", role: :mod}
      context = Context.new(current_user: user, route: :moderation, terminal_size: {120, 36})

      state =
        ModerationState.new(
          active: 1,
          scopes: [:site],
          mod_log: [
            %{
              kind: :resolved,
              reason: "spam",
              metadata: %{body: "Removed obvious spam"},
              mod: %{handle: "alice"},
              inserted_at: DateTime.utc_now()
            }
          ]
        )

      flat = Moderation.render(state, context) |> Foglet.TUI.WidgetHelpers.flatten_text()

      assert flat =~ "Operator context"
      assert flat =~ "Events"
      assert flat =~ "Rows are read-only"
    end

    test "Moderation.update(:load) emits a workspace task effect" do
      user = %User{id: "u1", handle: "mod", role: :mod}

      context =
        Context.new(
          current_user: user,
          route: :moderation,
          domain: %{moderation: FakeModeration}
        )

      {state, effects} = Moderation.update(:load, Moderation.init(context), context)

      assert state.loading?

      assert [
               %Effect{
                 type: :task,
                 payload: %{op: :load_moderation_workspace, screen_key: :moderation}
               }
             ] =
               effects
    end

    test "Moderation task result stores workspace rows locally" do
      user = %User{id: "u1", handle: "mod", role: :mod}
      context = Context.new(current_user: user, route: :moderation)
      state = Moderation.init(context)

      snapshot = %{
        scopes: [:site],
        queue: [],
        log: [],
        users: [%{handle: "alice", role: :user, status: :active}],
        boards: [%{name: "General", category_name: "Main", state: :active}]
      }

      {state, effects} =
        Moderation.update(
          {:task_result, :load_moderation_workspace, {:ok, {:ok, snapshot}}},
          state,
          context
        )

      refute state.loading?
      assert state.error == nil
      assert [%{handle: "alice"}] = state.users
      assert effects == []
    end

    test "read-only table tabs update table state without effects" do
      context = Context.new(current_user: %User{id: "u1", role: :mod}, route: :moderation)
      state = ModerationState.new(active: 1, mod_log: [])

      {state, effects} = Moderation.update({:key, %{key: :down}}, state, context)

      assert %ModerationState{} = state
      assert effects == []
    end

    test "Moderation.update(:load) does not crash when session_context is a SessionContext struct (FOG-168)" do
      # Regression: `domain_module/3` previously called `get_in(sc, [:domain, key])`
      # against `context.session_context`. When that field is a real
      # `%Foglet.TUI.SessionContext{}` struct (the live SSH path), `get_in/2`
      # raises `UndefinedFunctionError: SessionContext.fetch/2` because structs
      # do not implement Access. This test locks in the safe `Map.get` traversal.
      user = %User{id: "u1", handle: "mod", role: :mod}

      context =
        Context.new(
          current_user: user,
          route: :moderation,
          session_context: %Foglet.TUI.SessionContext{}
        )

      assert {state, effects} = Moderation.update(:load, Moderation.init(context), context)
      assert state.loading?

      assert [
               %Effect{
                 type: :task,
                 payload: %{op: :load_moderation_workspace, screen_key: :moderation}
               }
             ] = effects
    end

    test "moderator INVITES tab requests task-backed generate" do
      user = %User{id: "u1", handle: "mod", role: :mod}

      context =
        Context.new(
          current_user: user,
          route: :moderation,
          session_context: %{invite_code_generators: "mods", registration_mode: "invite_only"}
        )

      state = ModerationState.new(invites_visible?: true, active: 5)

      {state, effects} =
        Moderation.update({:key, %{key: :char, char: "g"}}, state, context)

      assert state.active_tab == 5

      assert [%Effect{payload: %{op: :moderation_generate_invite, screen_key: :moderation}}] =
               effects
    end

    # FOG-173: regression — pressing G after a prior tab-jump (e.g. "6")
    # leaves `tabs.last_action == {:tab_changed, _}`. The earlier dispatch
    # condition `new_tabs == ss.tabs` would treat the G keypress as a tab
    # event because `Tabs.handle_event/2` rewrites `last_action` to nil,
    # and bypass `handle_active_key`, silently dropping G/D in live SSH.
    test "INVITES G still dispatches generate after a prior tab-jump keypress" do
      user = %User{id: "u1", handle: "mod", role: :mod}

      context =
        Context.new(
          current_user: user,
          route: :moderation,
          session_context: %{invite_code_generators: "mods", registration_mode: "invite_only"}
        )

      state = ModerationState.new(invites_visible?: true, active: 0)

      # Jump to INVITES (tab 6) — this seeds tabs.last_action with {:tab_changed, 5}.
      {state, _effects} =
        Moderation.update({:key, %{key: :char, char: "6"}}, state, context)

      assert state.active_tab == 5
      assert state.tabs.last_action == {:tab_changed, 5}

      # Now press G — must reach handle_invites_update and emit a generate effect.
      {state, effects} =
        Moderation.update({:key, %{key: :char, char: "g"}}, state, context)

      assert state.active_tab == 5

      assert [%Effect{payload: %{op: :moderation_generate_invite, screen_key: :moderation}}] =
               effects
    end

    test "INVITES D arms confirm_revoke after a prior tab-jump keypress" do
      user = %User{id: "u1", handle: "mod", role: :mod}

      context =
        Context.new(
          current_user: user,
          route: :moderation,
          session_context: %{invite_code_generators: "mods", registration_mode: "invite_only"}
        )

      items = [%{code: "ABC", status: :available, inserted_at: ~U[2026-01-01 00:00:00Z]}]
      invites = InvitesState.loaded(InvitesState.new(), items)
      state = %{ModerationState.new(invites_visible?: true, active: 0) | invites: invites}

      {state, _} = Moderation.update({:key, %{key: :char, char: "6"}}, state, context)
      {state, effects} = Moderation.update({:key, %{key: :char, char: "d"}}, state, context)

      assert state.invites.mode == :confirm_revoke
      assert effects == []
    end
  end

  describe "render/1" do
    setup %{state: state} do
      state = put_in(state, [:screen_state, :moderation], ModerationState.new())
      %{state: state}
    end

    test "declares operator mode through Presentation", %{state: state} do
      # Behavioural assertion: rendering succeeds AND the canonical
      # Presentation lookup returns :operator for the :moderation screen.
      # The previous source-string grep was redundant with the runtime
      # assertion above and pinned the implementation to a literal call
      # shape, violating AGENTS.md's "no text-presence tests" rule.
      assert _ = render_moderation(state)
      assert Presentation.mode_for!(:moderation) == :operator
    end

    test "renders shared INVITES body when active tab is INVITES" do
      state =
        :mod
        |> build_state_with_policy("mods")
        |> put_in(
          [:screen_state, :moderation],
          ModerationState.new(invites_visible?: true, active: 5)
        )

      flat = render_moderation(state) |> collect_text_values()

      assert Enum.any?(flat, &String.contains?(&1, "Loading"))
    end

    test "shows all five tab labels: QUEUE, LOG, USERS, SANCTIONS, BOARDS (in that order)", %{
      state: state
    } do
      flat = render_moderation(state) |> collect_text_values()
      expected_tabs = ["QUEUE", "LOG", "USERS", "SANCTIONS", "BOARDS"]

      for tab <- expected_tabs do
        assert Enum.any?(flat, &String.contains?(&1, tab)),
               "Expected #{inspect(tab)} in flat text: #{inspect(flat)}"
      end

      # Assert order by finding index positions of first occurrence and checking they ascend
      tab_positions =
        Enum.map(expected_tabs, fn tab ->
          flat
          |> Enum.with_index()
          |> Enum.find_value(fn {text, idx} ->
            if String.contains?(text, tab), do: idx
          end)
        end)

      # Filter out nils and check ascending
      valid_positions = Enum.reject(tab_positions, &is_nil/1)

      assert valid_positions == Enum.sort(valid_positions),
             "Expected tab labels to appear in order QUEUE, LOG, USERS, SANCTIONS, BOARDS. " <>
               "Got positions: #{inspect(Enum.zip(expected_tabs, tab_positions))}"
    end

    test "shows INVITES for mod users only under mods runtime policy" do
      flat = build_state_with_policy(:mod, "mods") |> render_moderation() |> collect_text_values()

      assert Enum.any?(flat, &String.contains?(&1, "INVITES"))
    end

    test "hides INVITES for mod users under any_user and sysop_only policies" do
      for policy <- ["any_user", "sysop_only"] do
        flat =
          :mod
          |> build_state_with_policy(policy)
          |> render_moderation()
          |> collect_text_values()

        refute Enum.any?(flat, &String.contains?(&1, "INVITES")),
               "Expected mod policy #{policy} to hide INVITES; got #{inspect(flat)}"
      end
    end

    test "hides INVITES from regular and nil users" do
      regular_flat =
        :user
        |> build_state_with_policy("mods")
        |> render_moderation()
        |> collect_text_values()

      nil_flat =
        :mod
        |> build_state_with_policy("mods")
        |> Map.put(:current_user, nil)
        |> render_moderation()
        |> collect_text_values()

      refute Enum.any?(regular_flat, &String.contains?(&1, "INVITES"))
      refute Enum.any?(nil_flat, &String.contains?(&1, "INVITES"))
    end

    test "hides INVITES from sysop users under every invite policy" do
      for policy <- ["any_user", "mods", "sysop_only"] do
        flat =
          :sysop
          |> build_state_with_policy(policy)
          |> render_moderation()
          |> collect_text_values()

        refute Enum.any?(flat, &String.contains?(&1, "INVITES")),
               "Expected sysop policy #{policy} to hide Moderation INVITES; got #{inspect(flat)}"
      end
    end

    test "renders scaffold-only placeholder copy (no fake moderation actions)", %{state: state} do
      flat = render_moderation(state) |> collect_text_values()
      # Forbidden substrings that would indicate fake operator actions in key-bar or buttons
      forbidden = ["Ban", "Unban", "Sanction", "Approve", "Remove", "Delete"]

      for word <- forbidden do
        refute Enum.any?(flat, &String.contains?(&1, word)),
               "Expected #{inspect(word)} not to appear in Moderation render output. " <>
                 "Found in: #{inspect(Enum.filter(flat, &String.contains?(&1, word)))}"
      end
    end

    test "base tabs render without Phase 8 placeholder copy", %{state: state} do
      for active <- 0..4 do
        flat =
          state
          |> put_moderation_state(active)
          |> render_moderation()
          |> collect_text_values()

        refute Enum.any?(flat, &String.contains?(&1, "will arrive in Phase 8"))
        refute Enum.any?(flat, &String.contains?(&1, "Phase 8"))
      end
    end

    test "LOG renders newest hide_oneliner audit rows with moderator, target, and reason", %{
      state: state
    } do
      older = audit_row("old-mod", "first body", "spam", ~U[2026-04-24 12:00:00Z])
      newer = audit_row("new-mod", "second body", "abuse", ~U[2026-04-24 13:00:00Z])

      flat =
        state
        |> put_moderation_state(1, mod_log: [newer, older])
        |> render_moderation()
        |> collect_text_values()

      joined = Enum.join(flat, "\n")
      # FOG-164: Type label is "Oneliner moderation log"; the per-row action
      # column truncates `:hide_oneliner` to "hide_on…" (8-char width).
      assert joined =~ "Oneliner"
      assert joined =~ "hide_on"
      assert joined =~ "new-mod"
      assert joined =~ "second body"
      assert joined =~ "abuse"
      assert joined =~ "old-mod"
      assert joined =~ "first body"
      assert text_index(flat, "new-mod") < text_index(flat, "old-mod")
    end

    test "LOG renders compact timestamps in the current user's timezone and time format",
         %{state: state} do
      row = audit_row("mod", "timezone body", "reason", ~U[2026-04-24 13:05:00Z])

      user = %{
        state.current_user
        | timezone: "America/Chicago",
          preferences: %{"time_format" => "12h"}
      }

      flat =
        %{state | current_user: user}
        |> put_moderation_state(1, mod_log: [row])
        |> render_moderation()
        |> collect_text_values()

      joined = Enum.join(flat, "\n")

      assert joined =~ "04-24 08:05 AM"
      refute joined =~ "2026-04-24"
    end

    test "QUEUE renders wide table + inspector workspace with approved action copy", %{
      state: state
    } do
      report =
        report_row(%{id: "rep-1", target_kind: :post, reason: "spam", notes: "needs review"})
        |> Map.from_struct()
        |> Map.put(:target_label, "post #42 in general")

      flat =
        state
        |> Map.put(:terminal_size, {120, 30})
        |> put_moderation_state(0, queue: [report])
        |> render_moderation()
        |> collect_text_values()

      joined = Enum.join(flat, "\n")

      assert joined =~ "Open reports"
      assert joined =~ "Target"
      assert joined =~ "Reason"
      assert joined =~ "Reporter"
      assert joined =~ "Selected report"
      assert joined =~ "post #42 in general"
      assert joined =~ "needs review"
      assert joined =~ "V View target"
      assert joined =~ "E Resolve"
      assert joined =~ "D Dismiss"
      assert joined =~ "R Refresh"
    end

    test "QUEUE wide render tree survives Raxol preparer at 120x36", %{
      state: state
    } do
      report =
        report_row(%{id: "rep-1", target_kind: :post, reason: "spam", notes: "needs review"})
        |> Map.from_struct()
        |> Map.put(:target_label, "post #42 in general")

      tree =
        state
        |> Map.put(:terminal_size, {120, 36})
        |> put_moderation_state(0, queue: [report])
        |> render_moderation()

      assert %{} = Raxol.UI.Layout.Preparer.prepare(tree)
    end

    test "QUEUE stacks table and selected report details below the wide breakpoint", %{
      state: state
    } do
      report =
        report_row(%{id: "rep-1", target_kind: :post, reason: "spam", notes: "needs review"})
        |> Map.from_struct()
        |> Map.put(:target_label, "post #42 in general")

      flat =
        state
        |> Map.put(:terminal_size, {90, 24})
        |> put_moderation_state(0, queue: [report])
        |> render_moderation()
        |> collect_text_values()

      joined = Enum.join(flat, "\n")

      assert joined =~ "Open reports"
      assert joined =~ "Selected report"
      assert joined =~ "post #42 in general"
      assert joined =~ "needs review"
    end

    test "USERS renders read-only user rows without mutation commands", %{state: state} do
      flat =
        state
        |> put_moderation_state(2,
          users: [%{handle: "alice", role: :user, status: :active, last_seen_at: nil}]
        )
        |> render_moderation()
        |> collect_text_values()

      joined = Enum.join(flat, "\n")
      assert joined =~ "Viewing only"
      assert joined =~ "alice"
      refute joined =~ "Promote"
      refute joined =~ "Suspend"
      refute joined =~ "Delete"
      refute joined =~ "Edit"
    end

    test "SANCTIONS renders unavailable copy and no sanction command", %{state: state} do
      flat =
        state
        |> put_moderation_state(3)
        |> render_moderation()
        |> collect_text_values()

      joined = Enum.join(flat, "\n")
      assert joined =~ "Sanctions are not available"
      refute joined =~ "Ban"
    end

    test "BOARDS renders read-only scope context without board lifecycle commands", %{
      state: state
    } do
      flat =
        state
        |> put_moderation_state(4,
          scopes: [:site],
          boards: [
            %{name: "General", slug: "general", category_name: "Main", scope: {:board, "b1"}}
          ]
        )
        |> render_moderation()
        |> collect_text_values()

      joined = Enum.join(flat, "\n")
      assert joined =~ "Viewing only"
      assert joined =~ "General"
      assert joined =~ "Visible boards:"
      refute joined =~ "Archive"
      refute joined =~ "Create Board"
      refute joined =~ "Edit Board"
    end
  end

  describe "handle_key/2" do
    setup %{state: state} do
      state = put_in(state, [:screen_state, :moderation], ModerationState.new())
      %{state: state}
    end

    test "Right arrow advances active_tab", %{state: state} do
      {:update, new_state, _cmds} = handle_moderation_key(%{key: :right}, state)
      assert new_state.screen_state.moderation.active_tab == 1
    end

    test "digit '3' jumps to index 2 (USERS)", %{state: state} do
      {:update, new_state, _cmds} = handle_moderation_key(%{key: :char, char: "3"}, state)
      assert new_state.screen_state.moderation.active_tab == 2
    end

    test "Home returns to tab 0", %{state: state} do
      # First advance to tab 2
      {:update, state2, _} = handle_moderation_key(%{key: :right}, state)
      {:update, state3, _} = handle_moderation_key(%{key: :right}, state2)
      assert state3.screen_state.moderation.active_tab == 2

      # Now Home should return to 0
      {:update, new_state, _cmds} = handle_moderation_key(%{key: :home}, state3)
      assert new_state.screen_state.moderation.active_tab == 0
    end

    test "End jumps to last tab", %{state: state} do
      {:update, new_state, _cmds} = handle_moderation_key(%{key: :end}, state)
      assert new_state.screen_state.moderation.active_tab == 4
    end

    test "digit '6' reaches INVITES only for mods policy" do
      state =
        :mod
        |> build_state_with_policy("mods")
        |> put_in(
          [:screen_state, :moderation],
          ModerationState.new(invites_visible?: true)
        )

      {:update, new_state, _cmds} = handle_moderation_key(%{key: :char, char: "6"}, state)

      assert new_state.screen_state.moderation.active_tab == 5
    end

    test "clamps stale INVITES active tab when runtime policy changes" do
      state =
        :mod
        |> build_state_with_policy("any_user")
        |> put_in(
          [:screen_state, :moderation],
          ModerationState.new(invites_visible?: true, active: 5)
        )

      {:update, new_state, _cmds} = handle_moderation_key(%{key: :end}, state)

      assert new_state.screen_state.moderation.active_tab == 4

      refute Enum.any?(
               new_state.screen_state.moderation.tabs.raxol_state.tabs,
               &(&1.label == "INVITES")
             )
    end

    test "'Q' returns to :main_menu", %{state: state} do
      {:update, new_state, _cmds} = handle_moderation_key(%{key: :char, char: "Q"}, state)
      assert new_state.current_screen == :main_menu
    end

    test "'q' returns to :main_menu", %{state: state} do
      {:update, new_state, _cmds} = handle_moderation_key(%{key: :char, char: "q"}, state)
      assert new_state.current_screen == :main_menu
    end

    test "unknown key returns :no_match", %{state: state} do
      assert :no_match = handle_moderation_key(%{key: :char, char: "z"}, state)
    end

    test "QUEUE j/k changes the selected report", %{state: state} do
      reports = [
        report_row(%{id: "rep-1", reason: "spam"}),
        report_row(%{id: "rep-2", reason: "abuse"})
      ]

      state = put_moderation_state(state, 0, queue: reports)

      {:update, state, _} = handle_moderation_key(%{key: :char, char: "j"}, state)
      assert state.screen_state.moderation.queue_selected_index == 1

      {:update, state, _} = handle_moderation_key(%{key: :char, char: "k"}, state)
      assert state.screen_state.moderation.queue_selected_index == 0
    end

    test "QUEUE E opens a resolution modal with report summary context" do
      user = %User{id: "u1", handle: "mod", role: :mod}

      context =
        Context.new(
          current_user: user,
          route: :moderation,
          domain: %{moderation: FakeModeration}
        )

      state =
        ModerationState.new(
          queue: [
            report_row(%{id: "rep-1", reason: "spam"})
            |> Map.from_struct()
            |> Map.put(:target_label, "post #42 in general")
          ]
        )

      {state, effects} = Moderation.update({:key, %{key: :char, char: "e"}}, state, context)

      assert state.queue_selected_index == 0

      assert [
               %Effect{
                 type: :modal,
                 payload:
                   {:open,
                    %Foglet.TUI.Modal{
                      title: "Resolve Report",
                      message: %{form: %ModalForm{}, summary_lines: summary_lines}
                    }}
               }
             ] = effects

      assert Enum.any?(summary_lines, &String.contains?(&1, "post #42 in general"))
      assert Enum.any?(summary_lines, &String.contains?(&1, "spam"))
    end

    test "QUEUE D opens a dismissal modal for the selected report" do
      user = %User{id: "u1", handle: "mod", role: :mod}

      context =
        Context.new(
          current_user: user,
          route: :moderation,
          domain: %{moderation: FakeModeration}
        )

      state = ModerationState.new(queue: [report_row(%{id: "rep-1", reason: "spam"})])

      {_state, effects} = Moderation.update({:key, %{key: :char, char: "d"}}, state, context)

      assert [%Effect{type: :modal, payload: {:open, %{title: "Dismiss Report"}}}] = effects
    end

    test "Moderation screen does NOT dispatch fake moderation commands", %{state: state} do
      forbidden_commands = [:ban_user, :approve_queue_item, :remove_post, :issue_sanction]

      keys = [
        %{key: :right},
        %{key: :left},
        %{key: :home},
        %{key: :end},
        %{key: :char, char: "1"},
        %{key: :char, char: "2"},
        %{key: :char, char: "3"}
      ]

      for key <- keys do
        case handle_moderation_key(key, state) do
          {:update, _new_state, cmds} ->
            for cmd <- cmds do
              if is_tuple(cmd) do
                refute elem(cmd, 0) in forbidden_commands,
                       "Unexpected command #{inspect(cmd)} from key #{inspect(key)}"
              end
            end

          :no_match ->
            :ok
        end
      end
    end

    # FOG-164: D arms a confirm sub-mode; Enter dispatches the revoke; Esc
    # cancels and keeps the invite. Mirrors the Account confirm pattern so
    # the destructive INVITES action always requires a deliberate follow-up.
    test "INVITES D opens confirm_revoke mode without dispatching revoke" do
      mod = actor_fixture(:mod)
      Config.put!("invite_code_generators", "mods", actor_fixture(:sysop).id)
      AccountsFixtures.invite_fixture(mod, %{code: "Cnf001"})
      {:ok, items} = Invites.list_invites(mod)

      state =
        mod
        |> build_state_with_policy("mods")
        |> put_in(
          [:screen_state, :moderation],
          ModerationState.new(invites_visible?: true, active: 5)
          |> Map.put(:invites, InvitesState.new(items: items))
        )

      {:update, new_state, _} = handle_moderation_key(%{key: :char, char: "d"}, state)

      invites = new_state.screen_state.moderation.invites
      assert invites.mode == :confirm_revoke
      assert invites.confirm_target.code == "Cnf001"
      assert {:ok, %{status: :available}} = Invites.get_invite_status("Cnf001")
    end

    test "INVITES Enter from confirm_revoke dispatches revoke and clears mode" do
      sysop = actor_fixture(:sysop)
      Config.put!("invite_code_generators", "mods", sysop.id)
      mod = actor_fixture(:mod)
      AccountsFixtures.invite_fixture(mod, %{code: "Rvk001"})
      {:ok, items} = Invites.list_invites(mod)

      state =
        mod
        |> build_state_with_policy("mods")
        |> put_in(
          [:screen_state, :moderation],
          ModerationState.new(invites_visible?: true, active: 5)
          |> Map.put(:invites, InvitesState.new(items: items))
        )

      {:update, armed, _} = handle_moderation_key(%{key: :char, char: "d"}, state)
      {:update, after_enter, _} = handle_moderation_key(%{key: :enter}, armed)

      invites = after_enter.screen_state.moderation.invites
      assert invites.mode == :list
      assert invites.confirm_target == nil
      assert {:ok, %{status: :revoked}} = Invites.get_invite_status("Rvk001")
    end

    test "INVITES Esc from confirm_revoke cancels and keeps the invite" do
      sysop = actor_fixture(:sysop)
      Config.put!("invite_code_generators", "mods", sysop.id)
      mod = actor_fixture(:mod)
      AccountsFixtures.invite_fixture(mod, %{code: "Kep001"})
      {:ok, items} = Invites.list_invites(mod)

      state =
        mod
        |> build_state_with_policy("mods")
        |> put_in(
          [:screen_state, :moderation],
          ModerationState.new(invites_visible?: true, active: 5)
          |> Map.put(:invites, InvitesState.new(items: items))
        )

      {:update, armed, _} = handle_moderation_key(%{key: :char, char: "d"}, state)
      {:update, after_esc, _} = handle_moderation_key(%{key: :escape}, armed)

      invites = after_esc.screen_state.moderation.invites
      assert invites.mode == :list
      assert invites.confirm_target == nil
      assert {:ok, %{status: :available}} = Invites.get_invite_status("Kep001")
    end

    test "INVITES confirm_revoke surface renders title/body/keybar with code" do
      mod = actor_fixture(:mod)
      Config.put!("invite_code_generators", "mods", actor_fixture(:sysop).id)

      invites =
        InvitesState.new(items: [%{code: "Shw001", status: :available}])
        |> InvitesState.start_confirm_revoke()

      state =
        mod
        |> build_state_with_policy("mods")
        |> put_in(
          [:screen_state, :moderation],
          ModerationState.new(invites_visible?: true, active: 5)
          |> Map.put(:invites, invites)
        )

      flat = render_moderation(state) |> collect_text_values()
      joined = Enum.join(flat, "\n")

      assert joined =~ "Revoke invite Shw001?"
      assert joined =~ "Code Shw001 will stop working. Existing accounts stay intact."
      assert joined =~ "Enter Revoke invite"
      assert joined =~ "Esc Keep invite"
    end

    test "persists exactly one invite and records last_generated_code for unlimited mods policy" do
      restore_invite_config(%{})
      sysop = actor_fixture(:sysop)
      Config.put!("invite_code_generators", "mods", sysop.id)
      mod = actor_fixture(:mod)
      assert {:ok, before_items} = Invites.list_invites(mod)

      state =
        mod
        |> build_state_with_policy("mods")
        |> put_in(
          [:screen_state, :moderation],
          ModerationState.new(invites_visible?: true, active: 5)
          |> Map.put(:invites, InvitesState.new(items: before_items))
        )

      {:update, new_state, _cmds} = handle_moderation_key(%{key: :char, char: "g"}, state)

      assert {:ok, after_items} = Invites.list_invites(mod)
      assert length(after_items) == length(before_items) + 1

      invites = new_state.screen_state.moderation.invites
      assert invites.items == after_items
      assert is_binary(invites.last_generated_code)
    end
  end

  describe "queue moderation actions" do
    test "modal submit resolve_report dispatches moderation task" do
      user = %User{id: "u1", handle: "mod", role: :mod}

      context =
        Context.new(
          current_user: user,
          route: :moderation,
          domain: %{moderation: FakeModeration}
        )

      state = ModerationState.new(queue: [report_row(%{id: "rep-1", reason: "spam"})])

      {_state, effects} =
        Moderation.update(
          {:modal_submit, :resolve_report, %{report_id: "rep-1", resolution_note: "handled"}},
          state,
          context
        )

      assert [%Effect{type: :task, payload: %{op: :resolve_report, screen_key: :moderation}}] =
               effects
    end
  end

  # ---------------------------------------------------------------------------
  # Phase 25 Plan 05 — Per-tab theme hygiene (D-12)
  # ---------------------------------------------------------------------------

  describe "Phase 25 theme hygiene (D-12)" do
    import Foglet.TUI.WidgetHelpers
    import Foglet.TUI.LayoutSmokeHelpers

    for tab <- ["LOG", "USERS", "BOARDS"] do
      @tab tab
      test "converted Moderation #{tab} tab leaks no color atoms" do
        ss =
          ModerationState.new()
          |> set_active_tab(@tab)

        state =
          build_state(:mod)
          |> put_in([:screen_state, :moderation], ss)

        serialized = state |> render_moderation() |> inspect(limit: :infinity)

        for color <- color_names() do
          refute color_atom_leaked?(serialized, color),
                 "leaked :#{color} in converted Moderation #{@tab} tab"
        end
      end
    end

    test "converted Moderation INVITES tab leaks no color atoms" do
      ss =
        ModerationState.new(invites_visible?: true)
        |> set_active_tab("INVITES")

      state =
        :mod
        |> build_state_with_policy("mods")
        |> put_in([:screen_state, :moderation], ss)

      serialized = state |> render_moderation() |> inspect(limit: :infinity)

      for color <- color_names() do
        refute color_atom_leaked?(serialized, color),
               "leaked :#{color} in converted Moderation INVITES tab"
      end
    end
  end

  defp restore_invite_config(_context) do
    Config.init_cache()
    current_generators = Config.get("invite_code_generators", "sysops")
    current_limit = Config.get("invite_generation_per_user_limit", 0)

    on_exit(fn ->
      Config.put!("invite_code_generators", current_generators)
      Config.put!("invite_generation_per_user_limit", current_limit)
      Config.invalidate("invite_code_generators")
      Config.invalidate("invite_generation_per_user_limit")
    end)

    :ok
  end

  defp actor_fixture(role) do
    user = AccountsFixtures.user_fixture()
    {:ok, actor} = Accounts.update_role(user, role)
    actor
  end

  defp put_moderation_state(state, active, attrs \\ []) do
    ss =
      ModerationState.new(active: active)
      |> struct!(attrs)

    put_in(state, [:screen_state, :moderation], ss)
  end

  defp audit_row(handle, body, reason, inserted_at) do
    %Action{
      kind: :hide_oneliner,
      target_kind: :oneliner,
      target_id: Ecto.UUID.generate(),
      reason: reason,
      metadata: %{"body" => body, "author_handle" => "target"},
      mod: %User{handle: handle},
      inserted_at: inserted_at
    }
  end

  defp report_row(attrs) do
    defaults = %{
      id: Ecto.UUID.generate(),
      target_kind: :post,
      target_id: Ecto.UUID.generate(),
      reason: "spam",
      notes: "needs review",
      status: :open,
      reporter: %User{handle: "reporter"},
      inserted_at: ~U[2026-04-24 13:00:00Z]
    }

    struct!(Report, Map.merge(defaults, attrs))
  end

  defp text_index(flat, needle) do
    Enum.find_index(flat, &String.contains?(&1, needle))
  end

  describe "LOG table behavior" do
    test "LOG tab renders empty-state copy when mod_log is empty" do
      flat =
        :mod
        |> build_state()
        |> put_moderation_state(1, mod_log: [])
        |> render_moderation()
        |> collect_text_values()

      joined = Enum.join(flat, " ")

      assert joined =~ "No moderation events",
             "Expected empty-state copy in LOG tab, got: #{inspect(flat)}"
    end

    test "LOG tab status summary contains a badge-style label" do
      flat =
        :mod
        |> build_state()
        |> put_moderation_state(1, mod_log: [])
        |> render_moderation()
        |> collect_text_values()

      joined = Enum.join(flat, " ")

      assert joined =~ ~r/\[.+\]/,
             "Expected badge label [..] in LOG tab summary, got: #{inspect(flat)}"
    end

    test "LOG tab Enter keypress does not dispatch any domain action" do
      state =
        :mod
        |> build_state()
        |> put_moderation_state(1,
          mod_log: [
            audit_row("mod1", "body text", "reason1", ~U[2026-01-01 00:00:00Z])
          ]
        )

      result = handle_moderation_key(%{key: :enter}, state)

      case result do
        {:update, _new_state, cmds} ->
          refute Enum.any?(cmds, fn
                   {:ban_user, _} -> true
                   {:remove_post, _} -> true
                   _ -> false
                 end),
                 "Expected no domain dispatch from LOG Enter, got: #{inspect(cmds)}"

        :no_match ->
          :ok
      end
    end

    test "LOG tab empty-table handles up/down/enter without crash" do
      state =
        :mod
        |> build_state()
        |> put_moderation_state(1, mod_log: [])

      for key <- [%{key: :up}, %{key: :down}, %{key: :enter}] do
        result = handle_moderation_key(key, state)

        assert is_tuple(result) or result == :no_match,
               "Expected valid result for #{inspect(key)}"
      end
    end

    test "LOG table keeps ConsoleTable default page size when not provided" do
      table = ModerationState.build_log_table([])

      assert table.table.raxol_state.options.page_size == 10
    end
  end

  describe "USERS table behavior" do
    test "USERS tab renders empty-state copy when users list is empty" do
      flat =
        :mod
        |> build_state()
        |> put_moderation_state(2, users: [])
        |> render_moderation()
        |> collect_text_values()

      joined = Enum.join(flat, " ")

      assert joined =~ "No users found",
             "Expected empty-state copy in USERS tab, got: #{inspect(flat)}"
    end

    test "USERS tab handles up/down/enter on empty table without crash" do
      state =
        :mod
        |> build_state()
        |> put_moderation_state(2, users: [])

      for key <- [%{key: :up}, %{key: :down}, %{key: :enter}] do
        result = handle_moderation_key(key, state)

        assert is_tuple(result) or result == :no_match,
               "Expected valid result for #{inspect(key)}"
      end
    end

    test "USERS tab with user fixture renders badge label" do
      flat =
        :mod
        |> build_state()
        |> put_moderation_state(2, users: [%{handle: "alice", role: :user, status: :active}])
        |> render_moderation()
        |> collect_text_values()

      joined = Enum.join(flat, " ")

      assert joined =~ ~r/\[.+\]/,
             "Expected badge label in USERS tab, got: #{inspect(flat)}"
    end

    test "USERS table keeps ConsoleTable default page size when not provided" do
      table = ModerationState.build_users_table([])

      assert table.table.raxol_state.options.page_size == 10
    end
  end

  describe "BOARDS table behavior" do
    test "BOARDS tab renders empty-state copy when boards list is empty" do
      flat =
        :mod
        |> build_state()
        |> put_moderation_state(4, boards: [])
        |> render_moderation()
        |> collect_text_values()

      joined = Enum.join(flat, " ")

      assert joined =~ "No boards",
             "Expected empty-state copy in BOARDS tab, got: #{inspect(flat)}"
    end

    test "BOARDS tab handles up/down/enter on empty table without crash" do
      state =
        :mod
        |> build_state()
        |> put_moderation_state(4, boards: [])

      for key <- [%{key: :up}, %{key: :down}, %{key: :enter}] do
        result = handle_moderation_key(key, state)

        assert is_tuple(result) or result == :no_match,
               "Expected valid result for #{inspect(key)}"
      end
    end

    test "BOARDS table keeps ConsoleTable default page size when not provided" do
      table = ModerationState.build_boards_table([])

      assert table.table.raxol_state.options.page_size == 10
    end
  end

  describe "INVITES ConsoleTable behavior" do
    test "shared invite table keeps all headers visible at compact width" do
      sample_invite = %{
        code: "AbC123",
        status: :available,
        inserted_at: ~U[2026-01-01 00:00:00Z],
        consumed_by_user_id: "user-123"
      }

      table = InvitesState.build_table([sample_invite], width: 60)
      flat = table |> ConsoleTable.render(theme: Theme.default()) |> collect_text_values()
      joined = Enum.join(flat, " ")

      for header <- ["Code", "Status", "Issued", "Used by"] do
        assert joined =~ header,
               "Expected #{header} to render at compact width, got: #{inspect(flat)}"
      end
    end

    test "INVITES tab renders empty-state copy when items list is empty" do
      state =
        :mod
        |> build_state_with_policy("mods")
        |> put_in(
          [:screen_state, :moderation],
          ModerationState.new(invites_visible?: true, active: 5)
          |> Map.put(:invites, %Foglet.TUI.Screens.Shared.InvitesState{items: []})
        )

      flat = render_moderation(state) |> collect_text_values()
      joined = Enum.join(flat, " ")

      assert joined =~ "No invites",
             "Expected empty-state copy in INVITES tab, got: #{inspect(flat)}"
    end

    test "INVITES tab handles up/down/enter on empty table without crash" do
      state =
        :mod
        |> build_state_with_policy("mods")
        |> put_in(
          [:screen_state, :moderation],
          ModerationState.new(invites_visible?: true, active: 5)
          |> Map.put(:invites, %Foglet.TUI.Screens.Shared.InvitesState{items: []})
        )

      for key <- [%{key: :up}, %{key: :down}, %{key: :enter}] do
        result = handle_moderation_key(key, state)

        assert is_tuple(result) or result == :no_match,
               "Expected valid result for #{inspect(key)}"
      end
    end
  end

  describe "update(:on_route_enter, …) — Phase 39 Plan 04" do
    # These reducer pins preserve the user-conditional semantics of App's
    # `maybe_dispatch_route_entry/3` clause for `:moderation` (`app.ex:818-824`):
    # when current_user is set, dispatch :load; otherwise no-op. Plan 39-05
    # will collapse the App-side clause into a generic dispatch.

    test "with current_user set delegates to :load (sets loading? and emits workspace task)" do
      user = %User{id: "u1", handle: "mod", role: :mod}

      context =
        Context.new(
          current_user: user,
          route: :moderation,
          domain: %{moderation: FakeModeration}
        )

      local = Moderation.init(context)

      {state_via_on_enter, effects_via_on_enter} =
        Moderation.update(:on_route_enter, local, context)

      {state_via_load, effects_via_load} =
        Moderation.update(:load, local, context)

      assert state_via_on_enter == state_via_load
      assert state_via_on_enter.loading?

      assert [
               %Effect{
                 type: :task,
                 payload: %{op: :load_moderation_workspace, screen_key: :moderation}
               }
             ] = effects_via_on_enter

      assert effects_via_on_enter == effects_via_load
    end

    test "with no current_user no-ops (no effects, normalized state)" do
      context = Context.new(current_user: nil, route: :moderation)
      local = Moderation.init(context)

      {new_local, effects} = Moderation.update(:on_route_enter, local, context)

      assert effects == []
      assert %ModerationState{} = new_local
    end

    test "with nil local_state and no user normalizes without crashing" do
      context = Context.new(current_user: nil, route: :moderation)

      {new_local, effects} = Moderation.update(:on_route_enter, nil, context)

      assert effects == []
      assert %ModerationState{} = new_local
    end
  end
end
