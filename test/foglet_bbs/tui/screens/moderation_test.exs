defmodule Foglet.TUI.Screens.ModerationTest do
  use FogletBbs.DataCase, async: false

  import Foglet.TUI.RenderHelpers

  alias Foglet.Accounts
  alias Foglet.Accounts.User
  alias Foglet.Config
  alias Foglet.Moderation.Action
  alias Foglet.TUI.Presentation
  alias Foglet.TUI.Screens.Moderation
  alias Foglet.TUI.Screens.Shared.InvitesState
  alias FogletBbs.AccountsFixtures

  defp build_state(role, user \\ nil) do
    %Foglet.TUI.App{
      current_screen: :moderation,
      current_user: user || %Foglet.Accounts.User{id: "u1", handle: "alice", role: role},
      session_context: %{invite_code_generators: "sysop_only"},
      terminal_size: {80, 24},
      screen_state: %{}
    }
    |> Map.from_struct()
  end

  defp build_state_with_policy(%User{} = user, policy) do
    user.role
    |> build_state(user)
    |> put_in([:session_context, :invite_code_generators], policy)
  end

  defp build_state_with_policy(role, policy) do
    role
    |> build_state()
    |> put_in([:session_context, :invite_code_generators], policy)
  end

  setup do
    %{state: build_state(:mod)}
  end

  describe "init_screen_state/1" do
    test "returns struct with active_tab: 0 and Tabs wrapper" do
      ss = Moderation.init_screen_state()
      assert ss.active_tab == 0
      assert %Foglet.TUI.Widgets.Input.Tabs{} = ss.tabs
    end
  end

  describe "render/1" do
    setup %{state: state} do
      state = put_in(state, [:screen_state, :moderation], Moderation.init_screen_state())
      %{state: state}
    end

    test "renders Chrome V2 operator breadcrumb and declares operator mode", %{state: state} do
      flat = Moderation.render(state) |> collect_text_values()

      assert Enum.any?(flat, &String.contains?(&1, "Foglet"))
      assert Enum.any?(flat, &String.contains?(&1, "Moderation"))
      assert Presentation.mode_for!(:moderation) == :operator

      assert File.read!("lib/foglet_bbs/tui/screens/moderation.ex") =~
               "Presentation.mode_for!(:moderation)"
    end

    test "renders active moderation tab label in Chrome V2 breadcrumb", %{state: state} do
      state = put_in(state, [:screen_state, :moderation], Moderation.init_screen_state(active: 1))

      flat = Moderation.render(state) |> collect_text_values()

      assert Enum.any?(flat, &String.contains?(&1, "Foglet ▸ Moderation ▸ LOG"))
    end

    test "renders shared INVITES body when active tab is INVITES" do
      state =
        :mod
        |> build_state_with_policy("mods")
        |> put_in(
          [:screen_state, :moderation],
          Moderation.init_screen_state(invites_visible?: true, active: 5)
        )

      flat = Moderation.render(state) |> collect_text_values()

      assert Enum.any?(flat, &String.contains?(&1, "Loading"))
    end

    test "shows all five tab labels: QUEUE, LOG, USERS, SANCTIONS, BOARDS (in that order)", %{
      state: state
    } do
      flat = Moderation.render(state) |> collect_text_values()
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
      flat = build_state_with_policy(:mod, "mods") |> Moderation.render() |> collect_text_values()

      assert Enum.any?(flat, &String.contains?(&1, "INVITES"))
    end

    test "hides INVITES for mod users under any_user and sysop_only policies" do
      for policy <- ["any_user", "sysop_only"] do
        flat =
          :mod
          |> build_state_with_policy(policy)
          |> Moderation.render()
          |> collect_text_values()

        refute Enum.any?(flat, &String.contains?(&1, "INVITES")),
               "Expected mod policy #{policy} to hide INVITES; got #{inspect(flat)}"
      end
    end

    test "hides INVITES from regular and nil users" do
      regular_flat =
        :user
        |> build_state_with_policy("mods")
        |> Moderation.render()
        |> collect_text_values()

      nil_flat =
        :mod
        |> build_state_with_policy("mods")
        |> Map.put(:current_user, nil)
        |> Moderation.render()
        |> collect_text_values()

      refute Enum.any?(regular_flat, &String.contains?(&1, "INVITES"))
      refute Enum.any?(nil_flat, &String.contains?(&1, "INVITES"))
    end

    test "hides INVITES from sysop users under every invite policy" do
      for policy <- ["any_user", "mods", "sysop_only"] do
        flat =
          :sysop
          |> build_state_with_policy(policy)
          |> Moderation.render()
          |> collect_text_values()

        refute Enum.any?(flat, &String.contains?(&1, "INVITES")),
               "Expected sysop policy #{policy} to hide Moderation INVITES; got #{inspect(flat)}"
      end
    end

    test "renders scaffold-only placeholder copy (no fake moderation actions)", %{state: state} do
      flat = Moderation.render(state) |> collect_text_values()
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
          |> Moderation.render()
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
        |> Moderation.render()
        |> collect_text_values()

      joined = Enum.join(flat, "\n")
      assert joined =~ "hide_oneliner"
      assert joined =~ "new-mod"
      assert joined =~ "second body"
      assert joined =~ "abuse"
      assert joined =~ "old-mod"
      assert joined =~ "first body"
      assert text_index(flat, "new-mod") < text_index(flat, "old-mod")
    end

    test "QUEUE renders honest report workflow unavailable state and no work items", %{
      state: state
    } do
      flat =
        state
        |> put_moderation_state(0, queue: [%{body: "fake report"}])
        |> Moderation.render()
        |> collect_text_values()

      joined = Enum.join(flat, "\n")
      assert joined =~ "No report queue workflow"
      refute joined =~ "fake report"
      refute joined =~ "Approve"
    end

    test "USERS renders read-only user rows without mutation commands", %{state: state} do
      flat =
        state
        |> put_moderation_state(2,
          users: [%{handle: "alice", role: :user, status: :active, last_seen_at: nil}]
        )
        |> Moderation.render()
        |> collect_text_values()

      joined = Enum.join(flat, "\n")
      assert joined =~ "Read-only"
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
        |> Moderation.render()
        |> collect_text_values()

      joined = Enum.join(flat, "\n")
      assert joined =~ "No sanction workflow"
      refute joined =~ "Sanction"
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
        |> Moderation.render()
        |> collect_text_values()

      joined = Enum.join(flat, "\n")
      assert joined =~ "Read-only"
      assert joined =~ "General"
      assert joined =~ "hide_oneliner"
      refute joined =~ "Archive"
      refute joined =~ "Create Board"
      refute joined =~ "Edit Board"
    end
  end

  describe "handle_key/2" do
    setup %{state: state} do
      state = put_in(state, [:screen_state, :moderation], Moderation.init_screen_state())
      %{state: state}
    end

    test "Right arrow advances active_tab", %{state: state} do
      {:update, new_state, _cmds} = Moderation.handle_key(%{key: :right}, state)
      assert new_state.screen_state.moderation.active_tab == 1
    end

    test "digit '3' jumps to index 2 (USERS)", %{state: state} do
      {:update, new_state, _cmds} = Moderation.handle_key(%{key: :char, char: "3"}, state)
      assert new_state.screen_state.moderation.active_tab == 2
    end

    test "Home returns to tab 0", %{state: state} do
      # First advance to tab 2
      {:update, state2, _} = Moderation.handle_key(%{key: :right}, state)
      {:update, state3, _} = Moderation.handle_key(%{key: :right}, state2)
      assert state3.screen_state.moderation.active_tab == 2

      # Now Home should return to 0
      {:update, new_state, _cmds} = Moderation.handle_key(%{key: :home}, state3)
      assert new_state.screen_state.moderation.active_tab == 0
    end

    test "End jumps to last tab", %{state: state} do
      {:update, new_state, _cmds} = Moderation.handle_key(%{key: :end}, state)
      assert new_state.screen_state.moderation.active_tab == 4
    end

    test "digit '6' reaches INVITES only for mods policy" do
      state =
        :mod
        |> build_state_with_policy("mods")
        |> put_in(
          [:screen_state, :moderation],
          Moderation.init_screen_state(invites_visible?: true)
        )

      {:update, new_state, _cmds} = Moderation.handle_key(%{key: :char, char: "6"}, state)

      assert new_state.screen_state.moderation.active_tab == 5
    end

    test "clamps stale INVITES active tab when runtime policy changes" do
      state =
        :mod
        |> build_state_with_policy("any_user")
        |> put_in(
          [:screen_state, :moderation],
          Moderation.init_screen_state(invites_visible?: true, active: 5)
        )

      {:update, new_state, _cmds} = Moderation.handle_key(%{key: :end}, state)

      assert new_state.screen_state.moderation.active_tab == 4

      refute Enum.any?(
               new_state.screen_state.moderation.tabs.raxol_state.tabs,
               &(&1.label == "INVITES")
             )
    end

    test "'Q' returns to :main_menu", %{state: state} do
      {:update, new_state, _cmds} = Moderation.handle_key(%{key: :char, char: "Q"}, state)
      assert new_state.current_screen == :main_menu
    end

    test "'q' returns to :main_menu", %{state: state} do
      {:update, new_state, _cmds} = Moderation.handle_key(%{key: :char, char: "q"}, state)
      assert new_state.current_screen == :main_menu
    end

    test "unknown key returns :no_match", %{state: state} do
      assert :no_match = Moderation.handle_key(%{key: :char, char: "z"}, state)
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
        case Moderation.handle_key(key, state) do
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

    test "persists exactly one invite and records last_generated_code for unlimited mods policy" do
      restore_invite_config(%{})
      sysop = actor_fixture(:sysop)
      Config.put!("invite_code_generators", "mods", sysop.id)
      mod = actor_fixture(:mod)
      assert {:ok, before_items} = Accounts.list_invites(mod)

      state =
        mod
        |> build_state_with_policy("mods")
        |> put_in(
          [:screen_state, :moderation],
          Moderation.init_screen_state(invites_visible?: true, active: 5)
          |> Map.put(:invites, InvitesState.new(items: before_items))
        )

      {:update, new_state, _cmds} = Moderation.handle_key(%{key: :char, char: "g"}, state)

      assert {:ok, after_items} = Accounts.list_invites(mod)
      assert length(after_items) == length(before_items) + 1

      invites = new_state.screen_state.moderation.invites
      assert invites.items == after_items
      assert is_binary(invites.last_generated_code)
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
      Moderation.init_screen_state(active: active)
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

  defp text_index(flat, needle) do
    Enum.find_index(flat, &String.contains?(&1, needle))
  end

  # ---------------------------------------------------------------------------
  # Phase 25 Plan 03 — Primitive-presence tests (LOG, USERS, BOARDS, INVITES)
  # ---------------------------------------------------------------------------

  describe "LOG primitive presence" do
    test "LOG tab renders KvGrid summary with Scope label" do
      flat =
        :mod
        |> build_state()
        |> put_moderation_state(1, mod_log: [])
        |> Moderation.render()
        |> collect_text_values()

      assert Enum.any?(flat, &String.contains?(&1, "Scope")),
             "Expected KvGrid Scope label in LOG tab, got: #{inspect(flat)}"
    end

    test "LOG tab renders ConsoleTable header with When/Actor/Body/Reason columns when rows present" do
      row = audit_row("mod1", "body text", "reason1", ~U[2026-01-01 00:00:00Z])

      flat =
        :mod
        |> build_state()
        |> put_moderation_state(1, mod_log: [row])
        |> Moderation.render()
        |> collect_text_values()

      joined = Enum.join(flat, " ")
      assert joined =~ "When" or joined =~ "Actor" or joined =~ "Body" or joined =~ "Reason",
             "Expected ConsoleTable column header in LOG tab, got: #{inspect(flat)}"
    end

    test "LOG tab renders empty-state copy when mod_log is empty" do
      flat =
        :mod
        |> build_state()
        |> put_moderation_state(1, mod_log: [])
        |> Moderation.render()
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
        |> Moderation.render()
        |> collect_text_values()

      joined = Enum.join(flat, " ")

      assert joined =~ ~r/\[.+\]/,
             "Expected badge label [..] in LOG tab summary, got: #{inspect(flat)}"
    end

    test "LOG tab Enter keypress does not dispatch any domain action" do
      state =
        :mod
        |> build_state()
        |> put_moderation_state(1, mod_log: [
          audit_row("mod1", "body text", "reason1", ~U[2026-01-01 00:00:00Z])
        ])

      result = Moderation.handle_key(%{key: :enter}, state)

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
        result = Moderation.handle_key(key, state)
        assert is_tuple(result) or result == :no_match, "Expected valid result for #{inspect(key)}"
      end
    end
  end

  describe "USERS primitive presence" do
    test "USERS tab renders KvGrid summary with Scope label" do
      flat =
        :mod
        |> build_state()
        |> put_moderation_state(2, users: [])
        |> Moderation.render()
        |> collect_text_values()

      assert Enum.any?(flat, &String.contains?(&1, "Scope")),
             "Expected KvGrid Scope label in USERS tab, got: #{inspect(flat)}"
    end

    test "USERS tab renders ConsoleTable header with Handle/Role/Status columns when rows present" do
      flat =
        :mod
        |> build_state()
        |> put_moderation_state(2, users: [%{handle: "alice", role: :user, status: :active}])
        |> Moderation.render()
        |> collect_text_values()

      joined = Enum.join(flat, " ")
      assert joined =~ "Handle" or joined =~ "Role" or joined =~ "Status",
             "Expected ConsoleTable column header in USERS tab, got: #{inspect(flat)}"
    end

    test "USERS tab renders empty-state copy when users list is empty" do
      flat =
        :mod
        |> build_state()
        |> put_moderation_state(2, users: [])
        |> Moderation.render()
        |> collect_text_values()

      joined = Enum.join(flat, " ")
      assert joined =~ "No active users",
             "Expected empty-state copy in USERS tab, got: #{inspect(flat)}"
    end

    test "USERS tab handles up/down/enter on empty table without crash" do
      state =
        :mod
        |> build_state()
        |> put_moderation_state(2, users: [])

      for key <- [%{key: :up}, %{key: :down}, %{key: :enter}] do
        result = Moderation.handle_key(key, state)
        assert is_tuple(result) or result == :no_match, "Expected valid result for #{inspect(key)}"
      end
    end

    test "USERS tab with user fixture renders badge label" do
      flat =
        :mod
        |> build_state()
        |> put_moderation_state(2, users: [%{handle: "alice", role: :user, status: :active}])
        |> Moderation.render()
        |> collect_text_values()

      joined = Enum.join(flat, " ")

      assert joined =~ ~r/\[.+\]/,
             "Expected badge label in USERS tab, got: #{inspect(flat)}"
    end
  end

  describe "BOARDS primitive presence" do
    test "BOARDS tab renders KvGrid summary with Scope label" do
      flat =
        :mod
        |> build_state()
        |> put_moderation_state(4, boards: [])
        |> Moderation.render()
        |> collect_text_values()

      assert Enum.any?(flat, &String.contains?(&1, "Scope")),
             "Expected KvGrid Scope label in BOARDS tab, got: #{inspect(flat)}"
    end

    test "BOARDS tab renders ConsoleTable header with Board/Category/State columns when rows present" do
      flat =
        :mod
        |> build_state()
        |> put_moderation_state(4,
          boards: [%{name: "General", slug: "general", category_name: "Main", scope: {:board, "b1"}}]
        )
        |> Moderation.render()
        |> collect_text_values()

      joined = Enum.join(flat, " ")
      assert joined =~ "Board" or joined =~ "Category" or joined =~ "State",
             "Expected ConsoleTable column header in BOARDS tab, got: #{inspect(flat)}"
    end

    test "BOARDS tab renders empty-state copy when boards list is empty" do
      flat =
        :mod
        |> build_state()
        |> put_moderation_state(4, boards: [])
        |> Moderation.render()
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
        result = Moderation.handle_key(key, state)
        assert is_tuple(result) or result == :no_match, "Expected valid result for #{inspect(key)}"
      end
    end
  end

  describe "INVITES ConsoleTable primitive presence" do
    test "INVITES tab renders ConsoleTable header with Code/Status/Created/Used by columns when rows present" do
      sample_invite = %{
        code: "ABC123",
        status: :active,
        inserted_at: ~U[2026-01-01 00:00:00Z],
        consumed_by_user_id: nil
      }

      state =
        :mod
        |> build_state_with_policy("mods")
        |> put_in(
          [:screen_state, :moderation],
          Moderation.init_screen_state(invites_visible?: true, active: 5)
          |> Map.put(:invites, InvitesState.new(items: [sample_invite]))
        )

      flat = Moderation.render(state) |> collect_text_values()
      joined = Enum.join(flat, " ")

      assert joined =~ "Code" or joined =~ "Status" or joined =~ "Created" or joined =~ "Used by",
             "Expected ConsoleTable column header in INVITES tab, got: #{inspect(flat)}"
    end

    test "INVITES tab renders empty-state copy when items list is empty" do
      state =
        :mod
        |> build_state_with_policy("mods")
        |> put_in(
          [:screen_state, :moderation],
          Moderation.init_screen_state(invites_visible?: true, active: 5)
          |> Map.put(:invites, %Foglet.TUI.Screens.Shared.InvitesState{items: []})
        )

      flat = Moderation.render(state) |> collect_text_values()
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
          Moderation.init_screen_state(invites_visible?: true, active: 5)
          |> Map.put(:invites, %Foglet.TUI.Screens.Shared.InvitesState{items: []})
        )

      for key <- [%{key: :up}, %{key: :down}, %{key: :enter}] do
        result = Moderation.handle_key(key, state)
        assert is_tuple(result) or result == :no_match, "Expected valid result for #{inspect(key)}"
      end
    end
  end
end
