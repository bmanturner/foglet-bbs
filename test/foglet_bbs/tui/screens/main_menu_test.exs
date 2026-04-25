defmodule Foglet.TUI.Screens.MainMenuTest do
  use ExUnit.Case, async: true

  import Foglet.TUI.RenderHelpers

  alias Foglet.TUI.Screens.{MainMenu, ShellVisibility}

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
      assert String.length(row) <= 39
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

    assert "Welcome back, alice." in texts
    assert "  [B] Browse Boards" in texts
    assert "  [C] Compose New Thread" in texts
    assert "  [Q] Logout" in texts
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
      assert Enum.any?(flat, &String.contains?(&1, "[A]"))
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

    test "rendered shell rows and command labels follow ShellVisibility for every role" do
      for {role, _screen, key, menu_label, key_label, predicate} <- role_cases() do
        state = build_state(role)
        user = state.current_user
        visible? = predicate.(user)
        texts = rendered_text(state)

        menu_row? = "  [#{key}] #{menu_label}" in texts
        command? = key in texts and Enum.any?(texts, &(String.trim(&1) == key_label))

        assert menu_row? == visible?,
               "expected #{menu_label} menu row visibility for #{role} to be #{visible?}"

        assert command? == visible?,
               "expected #{key_label} command visibility for #{role} to be #{visible?}"
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
end
