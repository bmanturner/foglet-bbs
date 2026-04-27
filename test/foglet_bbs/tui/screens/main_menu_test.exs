defmodule Foglet.TUI.Screens.MainMenuTest do
  use ExUnit.Case, async: true

  import Foglet.TUI.RenderHelpers

  alias Foglet.TUI.Screens.{MainMenu, ShellVisibility}

  defp build_state(nil) do
    %Foglet.TUI.App{
      current_screen: :main_menu,
      current_user: nil,
      session_context: %{},
      terminal_size: {80, 24}
    }
    |> Map.from_struct()
  end

  defp build_state(role) do
    %Foglet.TUI.App{
      current_screen: :main_menu,
      current_user: %Foglet.Accounts.User{id: "u1", handle: "alice", role: role},
      session_context: %{},
      terminal_size: {80, 24}
    }
    |> Map.from_struct()
  end

  defp with_oneliners(state, recent_oneliners) do
    Map.put(state, :recent_oneliners, recent_oneliners)
  end

  defp with_selected_oneliner(state, index) do
    Map.put(state, :selected_oneliner_index, index)
  end

  defp oneliner(handle, body, attrs \\ %{}) do
    Map.merge(
      %{
        id: "ol-#{handle}",
        body: body,
        user: %{handle: handle}
      },
      attrs
    )
  end

  defp role_cases do
    [
      {:user, :account, "A", "Account", "Account", &ShellVisibility.account_visible?/1},
      {:user, :moderation, "M", "Moderation", "Mod", &ShellVisibility.moderation_visible?/1},
      {:user, :sysop, "S", "Sysop", "Sysop", &ShellVisibility.sysop_visible?/1},
      {:mod, :account, "A", "Account", "Account", &ShellVisibility.account_visible?/1},
      {:mod, :moderation, "M", "Moderation", "Mod", &ShellVisibility.moderation_visible?/1},
      {:mod, :sysop, "S", "Sysop", "Sysop", &ShellVisibility.sysop_visible?/1},
      {:sysop, :account, "A", "Account", "Account", &ShellVisibility.account_visible?/1},
      {:sysop, :moderation, "M", "Moderation", "Mod", &ShellVisibility.moderation_visible?/1},
      {:sysop, :sysop, "S", "Sysop", "Sysop", &ShellVisibility.sysop_visible?/1}
    ]
  end

  defp rendered_text(state), do: MainMenu.render(state) |> collect_text_values()

  defp handle_key_result(state, key) do
    MainMenu.handle_key(%{key: :char, char: key}, state)
  end

  setup do
    %{state: build_state(:user)}
  end

  test "render/1 includes Chrome V2 home breadcrumb", %{state: state} do
    text = MainMenu.render(state) |> collect_text_values() |> Enum.join("\n")

    assert text =~ "Foglet"
    assert text =~ "Home"
  end

  test "MainMenu has no public init_screen_state/1" do
    refute function_exported?(MainMenu, :init_screen_state, 1)
  end

  describe "oneliners strip" do
    test "nil recent_oneliners renders panel title and empty state", %{state: state} do
      texts = state |> with_oneliners(nil) |> rendered_text()

      assert "Oneliners" in texts
      assert "No oneliners yet." in texts
    end

    test "empty recent_oneliners renders panel title and empty state", %{state: state} do
      texts = state |> with_oneliners([]) |> rendered_text()

      assert "Oneliners" in texts
      assert "No oneliners yet." in texts
    end

    test "one oneliner renders as handle body without timestamp", %{state: state} do
      texts =
        state
        |> with_oneliners([oneliner("alice", "hello", %{inserted_at: ~U[2026-04-24 12:00:00Z]})])
        |> rendered_text()

      assert "> @alice  hello" in texts

      row = Enum.find(texts, &String.contains?(&1, "@alice  hello"))
      refute row =~ "2026-"
      refute row =~ "AM"
      refute row =~ "PM"
    end

    test "many oneliners render no more than five rows", %{state: state} do
      entries =
        for index <- 1..7 do
          oneliner("user#{index}", "line #{index}")
        end

      rows =
        state
        |> with_oneliners(entries)
        |> rendered_text()
        |> Enum.filter(&String.contains?(&1, "@user"))

      assert length(rows) == 5
      assert "> @user1  line 1" in rows
      refute Enum.any?(rows, &String.contains?(&1, "line 6"))
    end

    test "long handle and body are clipped to one presentation row", %{state: state} do
      texts =
        state
        |> with_oneliners([oneliner("averyverylonghandle", String.duplicate("body ", 30))])
        |> rendered_text()

      row = Enum.find(texts, &String.contains?(&1, "@averyverylo"))

      assert row
      assert String.starts_with?(row, "> @averyverylon")
      assert Foglet.TUI.TextWidth.display_width(row) <= 39
      refute String.contains?(row, "\n")
      refute String.contains?(row, "body body body body body body body body body body")
    end

    test "Up and Down change app-owned selected_oneliner_index without screen-local state", %{
      state: state
    } do
      state =
        state
        |> with_oneliners([
          oneliner("alice", "first", %{id: "ol1"}),
          oneliner("bob", "second", %{id: "ol2"})
        ])
        |> with_selected_oneliner(0)

      {:update, down_state, []} = MainMenu.handle_key(%{key: :down}, state)
      assert down_state.selected_oneliner_index == 1
      refute Map.has_key?(down_state.screen_state, :main_menu)

      {:update, clamped_down_state, []} = MainMenu.handle_key(%{key: :down}, down_state)
      assert clamped_down_state.selected_oneliner_index == 1

      {:update, up_state, []} = MainMenu.handle_key(%{key: :up}, clamped_down_state)
      assert up_state.selected_oneliner_index == 0

      {:update, clamped_up_state, []} = MainMenu.handle_key(%{key: :up}, up_state)
      assert clamped_up_state.selected_oneliner_index == 0
    end

    test "all authenticated roles render a visible marker on the selected oneliner" do
      for role <- [:user, :mod, :sysop] do
        texts =
          role
          |> build_state()
          |> with_oneliners([
            oneliner("alice", "selected", %{id: "ol1"}),
            oneliner("bob", "not selected", %{id: "ol2"})
          ])
          |> with_selected_oneliner(0)
          |> rendered_text()

        assert "> @alice  selected" in texts
        assert "  @bob  not selected" in texts
      end
    end

    test "regular users do not see Hide oneliner and H returns no match", %{state: state} do
      state =
        state
        |> with_oneliners([oneliner("alice", "visible", %{id: "ol1"})])
        |> with_selected_oneliner(0)

      texts = rendered_text(state)

      refute Enum.any?(texts, &String.contains?(&1, "Hide oneliner"))
      assert :no_match = MainMenu.handle_key(%{key: :char, char: "H"}, state)
      assert :no_match = MainMenu.handle_key(%{key: :char, char: "h"}, state)
    end

    test "mods and sysops see Hide oneliner only for authorized selected rows with ids" do
      for role <- [:mod, :sysop] do
        hideable_state =
          role
          |> build_state()
          |> with_oneliners([oneliner("alice", "hideable", %{id: "ol1"})])
          |> with_selected_oneliner(0)

        assert Enum.any?(rendered_text(hideable_state), &String.contains?(&1, "Hide oneliner"))

        assert {:update, ^hideable_state, [{:open_hide_oneliner_modal, "ol1"}]} =
                 MainMenu.handle_key(%{key: :char, char: "H"}, hideable_state)

        assert {:update, ^hideable_state, [{:open_hide_oneliner_modal, "ol1"}]} =
                 MainMenu.handle_key(%{key: :char, char: "h"}, hideable_state)

        missing_id_state =
          role
          |> build_state()
          |> with_oneliners([oneliner("alice", "no id", %{id: nil})])
          |> with_selected_oneliner(0)

        refute Enum.any?(rendered_text(missing_id_state), &String.contains?(&1, "Hide oneliner"))
        assert :no_match = MainMenu.handle_key(%{key: :char, char: "H"}, missing_id_state)
      end
    end

    test "Enter on a selected oneliner is reserved and performs no Profile navigation", %{
      state: state
    } do
      state =
        state
        |> with_oneliners([oneliner("alice", "profile later", %{id: "ol1"})])
        |> with_selected_oneliner(0)

      assert :no_match = MainMenu.handle_key(%{key: :enter}, state)

      refute inspect(MainMenu.handle_key(%{key: :enter}, state)) =~ "Profile"
      refute inspect(MainMenu.handle_key(%{key: :enter}, state)) =~ "profile"
    end
  end

  test "render includes main menu owned text rows", %{state: state} do
    texts = MainMenu.render(state) |> collect_text_values()

    # D-11: Welcome line removed.
    refute Enum.any?(texts, &String.starts_with?(&1, "Welcome back")),
           "Phase 19 D-11 removes the welcome line; got: #{inspect(texts)}"

    # D-07: boxed Navigation panel header replaces it.
    assert "Navigation" in texts

    # D-08: glyph + label + right-aligned key rows.
    assert Enum.any?(texts, &(&1 =~ ~r/●\s+Boards\s+B$/)),
           "expected '● Boards    B' shaped row; got: #{inspect(texts)}"

    assert Enum.any?(texts, &(&1 =~ ~r/✎\s+Compose\s+C$/)),
           "expected '✎ Compose    C' shaped row; got: #{inspect(texts)}"

    assert Enum.any?(texts, &(&1 =~ ~r/↯\s+Logout\s+Q$/)),
           "expected '↯ Logout    Q' shaped row; got: #{inspect(texts)}"
  end

  test "'B'/'b' navigates to :board_list with {:load_boards} command", %{state: state} do
    {:update, s, cmds} = MainMenu.handle_key(%{key: :char, char: "B"}, state)
    assert s.current_screen == :board_list
    assert {:load_boards} in cmds

    {:update, s2, cmds2} = MainMenu.handle_key(%{key: :char, char: "b"}, state)
    assert s2.current_screen == :board_list
    assert {:load_boards} in cmds2
  end

  test "'C'/'c' navigates to :new_thread and seeds compose screen state", %{state: state} do
    {:update, s, cmds} = MainMenu.handle_key(%{key: :char, char: "C"}, state)
    assert s.current_screen == :new_thread
    assert {:load_boards_for_new_thread} in cmds
    assert s.screen_state.new_thread.step == :board
    assert s.screen_state.new_thread.origin == :main_menu

    {:update, s2, cmds2} = MainMenu.handle_key(%{key: :char, char: "c"}, state)
    assert s2.current_screen == :new_thread
    assert {:load_boards_for_new_thread} in cmds2
    assert s2.screen_state.new_thread.step == :board
    assert s2.screen_state.new_thread.origin == :main_menu
  end

  test "'Q'/'q' emits {:terminate, :logout} command", %{state: state} do
    {:update, _, cmds} = MainMenu.handle_key(%{key: :char, char: "Q"}, state)
    assert {:terminate, :logout} in cmds

    {:update, _, cmds2} = MainMenu.handle_key(%{key: :char, char: "q"}, state)
    assert {:terminate, :logout} in cmds2
  end

  test "'O'/'o' emits open oneliner composer command", %{state: state} do
    {:update, s, cmds} = MainMenu.handle_key(%{key: :char, char: "O"}, state)
    assert s == state
    assert [{:open_oneliner_composer}] = cmds

    {:update, s2, cmds2} = MainMenu.handle_key(%{key: :char, char: "o"}, state)
    assert s2 == state
    assert [{:open_oneliner_composer}] = cmds2
  end

  test "unknown key returns :no_match", %{state: state} do
    assert :no_match = MainMenu.handle_key(%{key: :char, char: "z"}, state)
  end

  describe "Phase 0 shell entry points" do
    test "authenticated user with role :user sees Account menu entry" do
      state = build_state(:user)
      flat = MainMenu.render(state) |> collect_text_values()
      assert Enum.any?(flat, &String.contains?(&1, "Account"))
      # Phase 19: glyph row shape replaces [A] bracket format
      assert Enum.any?(flat, &(&1 =~ ~r/◇\s+Account\s+A$/))
    end

    test "role :user does NOT see Moderation menu entry" do
      state = build_state(:user)
      flat = MainMenu.render(state) |> collect_text_values()
      refute Enum.any?(flat, &String.contains?(&1, "Moderation"))
    end

    test "role :user does NOT see Sysop menu entry" do
      state = build_state(:user)
      flat = MainMenu.render(state) |> collect_text_values()
      refute Enum.any?(flat, &String.contains?(&1, "Sysop"))
    end

    test "role :mod sees Account AND Moderation entries but NOT Sysop" do
      state = build_state(:mod)
      flat = MainMenu.render(state) |> collect_text_values()
      assert Enum.any?(flat, &String.contains?(&1, "Account"))
      assert Enum.any?(flat, &String.contains?(&1, "Moderation"))
      refute Enum.any?(flat, &String.contains?(&1, "Sysop"))
    end

    test "role :sysop sees Account AND Moderation AND Sysop entries" do
      state = build_state(:sysop)
      flat = MainMenu.render(state) |> collect_text_values()
      assert Enum.any?(flat, &String.contains?(&1, "Account"))
      assert Enum.any?(flat, &String.contains?(&1, "Moderation"))
      assert Enum.any?(flat, &String.contains?(&1, "Sysop"))
    end

    test "'A'/'a' navigates to :account and seeds screen_state" do
      state = build_state(:user)
      {:update, s, _cmds} = MainMenu.handle_key(%{key: :char, char: "A"}, state)
      assert s.current_screen == :account
      assert s.screen_state[:account] != nil

      {:update, s2, _cmds2} = MainMenu.handle_key(%{key: :char, char: "a"}, state)
      assert s2.current_screen == :account
      assert s2.screen_state[:account] != nil
    end

    test "'M'/'m' navigates to :moderation for role :mod" do
      state = build_state(:mod)
      {:update, s, _cmds} = MainMenu.handle_key(%{key: :char, char: "M"}, state)
      assert s.current_screen == :moderation

      {:update, s2, _cmds2} = MainMenu.handle_key(%{key: :char, char: "m"}, state)
      assert s2.current_screen == :moderation
    end

    test "'M'/'m' returns :no_match for role :user (key bound guarded per D-02)" do
      state = build_state(:user)
      assert :no_match = MainMenu.handle_key(%{key: :char, char: "M"}, state)
      assert :no_match = MainMenu.handle_key(%{key: :char, char: "m"}, state)
    end

    test "'S'/'s' navigates to :sysop for role :sysop" do
      state = build_state(:sysop)
      {:update, s, _cmds} = MainMenu.handle_key(%{key: :char, char: "S"}, state)
      assert s.current_screen == :sysop

      {:update, s2, _cmds2} = MainMenu.handle_key(%{key: :char, char: "s"}, state)
      assert s2.current_screen == :sysop
    end

    test "'S'/'s' returns :no_match for role :mod" do
      state = build_state(:mod)
      assert :no_match = MainMenu.handle_key(%{key: :char, char: "S"}, state)
      assert :no_match = MainMenu.handle_key(%{key: :char, char: "s"}, state)
    end

    test "'S'/'s' returns :no_match for role :user" do
      state = build_state(:user)
      assert :no_match = MainMenu.handle_key(%{key: :char, char: "S"}, state)
      assert :no_match = MainMenu.handle_key(%{key: :char, char: "s"}, state)
    end

    test "rendered shell rows follow ShellVisibility for every role" do
      # Phase 19 (Plan 01): A, M, S are now pure destinations (body rows only).
      # Phase 19 (Plan 02): rows are now glyph + label + right-aligned key shape.
      # D-01 single-source-of-truth split — this test checks menu row visibility only.
      for {role, _screen, _key, menu_label, _key_label, predicate} <- role_cases() do
        state = build_state(role)
        user = state.current_user
        visible? = predicate.(user)
        texts = rendered_text(state)

        # Phase 19: rows are now glyph + label + right-aligned key. Look for label presence in any row.
        menu_row? = Enum.any?(texts, &String.contains?(&1, menu_label))

        # Phase 19: destinations are NOT in the command bar; A/M/S key letters should not appear as bare command tokens.
        command_in_bar? = Enum.any?(texts, &(String.trim(&1) == menu_label))

        assert menu_row? == visible?,
               "expected #{menu_label} body row visibility for #{role} to be #{visible?}; got: #{inspect(texts)}"

        refute command_in_bar?,
               "destination #{menu_label} should NOT appear as bare token in command bar (Phase 19 D-01/D-04); got: #{inspect(texts)}"
      end
    end

    test "A, M, and S key handling follows ShellVisibility for every role" do
      for {role, screen, key, _menu_label, _key_label, predicate} <- role_cases() do
        state = build_state(role)
        user = state.current_user
        visible? = predicate.(user)

        assert_key_visibility(state, key, screen, visible?)
        assert_key_visibility(state, String.downcase(key), screen, visible?)
      end
    end
  end

  defp assert_key_visibility(state, key, screen, true) do
    assert {:update, new_state, _cmds} = handle_key_result(state, key)
    assert new_state.current_screen == screen
  end

  defp assert_key_visibility(state, key, _screen, false) do
    assert :no_match = handle_key_result(state, key)
  end

  describe "Phase 19 body visual" do
    test "every Navigation row fits within the computed panel inner width budget at every canonical size" do
      for {width, height} <- [{64, 22}, {80, 24}, {132, 50}] do
        for role <- [:user, :mod, :sysop] do
          state =
            role
            |> build_state()
            |> Map.put(:terminal_size, {width, height})

          texts = rendered_text(state)

          nav_rows =
            texts
            |> Enum.filter(fn row ->
              Enum.any?(["●", "✎", "◇", "⚑", "▣", "↯"], &String.contains?(row, &1))
            end)

          assert nav_rows != [],
                 "expected at least one nav row for role=#{role} at #{inspect({width, height})}; got: #{inspect(texts)}"

          inner_width = MainMenu.__nav_panel_inner_width__(state)

          for row <- nav_rows do
            assert Foglet.TUI.TextWidth.display_width(row) <= inner_width,
                   "nav row '#{row}' exceeds computed inner_width=#{inner_width} for role=#{role} at #{inspect({width, height})}"
          end
        end
      end
    end
  end

  describe "Phase 19 destinations vs. actions split" do
    test "visible_destinations/1 anonymous returns B, C, Q only (anonymous still sees Compose)" do
      # Anonymous-C: destination row is present even when authenticated; handle_key/2's
      # anonymous-C route to login is unchanged from pre-Phase-19 contract.
      assert MainMenu.visible_destinations(nil) == [
               {"B", "Boards"},
               {"C", "Compose"},
               {"Q", "Logout"}
             ]
    end

    test "visible_destinations/1 :user adds A but not M or S" do
      user = %{role: :user}

      assert MainMenu.visible_destinations(user) == [
               {"B", "Boards"},
               {"C", "Compose"},
               {"A", "Account"},
               {"Q", "Logout"}
             ]
    end

    test "visible_destinations/1 :mod adds M but not S" do
      user = %{role: :mod}

      assert MainMenu.visible_destinations(user) ==
               [
                 {"B", "Boards"},
                 {"C", "Compose"},
                 {"A", "Account"},
                 {"M", "Moderation"},
                 {"Q", "Logout"}
               ]
    end

    test "visible_destinations/1 :sysop adds A, M, AND S" do
      user = %{role: :sysop}

      assert MainMenu.visible_destinations(user) ==
               [
                 {"B", "Boards"},
                 {"C", "Compose"},
                 {"A", "Account"},
                 {"M", "Moderation"},
                 {"S", "Sysop"},
                 {"Q", "Logout"}
               ]
    end

    test "visible_actions/1 with no oneliners returns Post Oneliner only" do
      state = build_state(:user) |> with_oneliners([])

      keys =
        state |> MainMenu.visible_actions() |> Enum.flat_map(& &1.commands) |> Enum.map(& &1.key)

      assert keys == ["O"]
    end

    test "visible_actions/1 with oneliners surfaces ↑/↓ Select for any user" do
      state =
        build_state(:user)
        |> with_oneliners([oneliner("alice", "hi")])
        |> with_selected_oneliner(0)

      keys =
        state |> MainMenu.visible_actions() |> Enum.flat_map(& &1.commands) |> Enum.map(& &1.key)

      assert "↑/↓" in keys
      assert "O" in keys
      refute "H" in keys
    end

    test "visible_actions/1 surfaces H for :mod with hideable oneliner selected" do
      state =
        build_state(:mod)
        |> with_oneliners([oneliner("alice", "hi", %{id: "ol1"})])
        |> with_selected_oneliner(0)

      keys =
        state |> MainMenu.visible_actions() |> Enum.flat_map(& &1.commands) |> Enum.map(& &1.key)

      assert "H" in keys
      assert "O" in keys
    end

    test "visible_actions/1 surfaces H for :sysop with hideable oneliner selected" do
      state =
        build_state(:sysop)
        |> with_oneliners([oneliner("alice", "hi", %{id: "ol1"})])
        |> with_selected_oneliner(0)

      keys =
        state |> MainMenu.visible_actions() |> Enum.flat_map(& &1.commands) |> Enum.map(& &1.key)

      assert "H" in keys
    end

    test "visible_actions/1 hides H for :user even with hideable oneliner selected" do
      state =
        build_state(:user)
        |> with_oneliners([oneliner("alice", "hi", %{id: "ol1"})])
        |> with_selected_oneliner(0)

      keys =
        state |> MainMenu.visible_actions() |> Enum.flat_map(& &1.commands) |> Enum.map(& &1.key)

      refute "H" in keys
    end

    test "command bar non-duplication: B/C/A/M/S/Q never appear in any visible_actions group for any role (literal-keys sweep)" do
      for role <- [:user, :mod, :sysop] do
        for oneliners <- [[], [oneliner("alice", "hi", %{id: "ol1"})]] do
          state = build_state(role) |> with_oneliners(oneliners) |> with_selected_oneliner(0)

          keys =
            state
            |> MainMenu.visible_actions()
            |> Enum.flat_map(& &1.commands)
            |> Enum.map(& &1.key)

          for forbidden <- ["B", "C", "A", "M", "S", "Q"] do
            refute forbidden in keys,
                   "destination key #{forbidden} leaked into command bar for role=#{role}, oneliners=#{length(oneliners)}"
          end
        end
      end
    end

    test "destinations and actions are disjoint as a DATA property for every role x oneliner state" do
      # Structural disjointness: derives from the shared @main_menu_commands list.
      # If someone adds a new entry without setting :kind correctly, this fails
      # before the literal-keys sweep above does.
      roles_and_users = [
        {:anonymous, nil, nil},
        {:user, :user, %{role: :user}},
        {:mod, :mod, %{role: :mod}},
        {:sysop, :sysop, %{role: :sysop}}
      ]

      oneliner_states = [
        {:empty, []},
        {:hideable, [oneliner("alice", "hi", %{id: "ol1"})]}
      ]

      for {role_label, state_role, user} <- roles_and_users do
        for {oneliner_label, oneliners} <- oneliner_states do
          state =
            build_state(state_role)
            |> Map.put(:current_user, user)
            |> with_oneliners(oneliners)
            |> with_selected_oneliner(if oneliners == [], do: nil, else: 0)

          destination_keys =
            user
            |> MainMenu.visible_destinations()
            |> Enum.map(&elem(&1, 0))
            |> MapSet.new()

          action_keys =
            state
            |> MainMenu.visible_actions()
            |> Enum.flat_map(& &1.commands)
            |> Enum.map(& &1.key)
            |> MapSet.new()

          assert MapSet.disjoint?(destination_keys, action_keys),
                 "destinations and actions overlap for role=#{role_label}, oneliners=#{oneliner_label}: " <>
                   "destinations=#{inspect(MapSet.to_list(destination_keys))}, " <>
                   "actions=#{inspect(MapSet.to_list(action_keys))}"
        end
      end
    end
  end
end
