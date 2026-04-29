defmodule Foglet.TUI.Screens.MainMenuTest do
  use ExUnit.Case, async: true

  import Foglet.TUI.RenderHelpers

  alias Foglet.TUI.Context
  alias Foglet.TUI.Effect
  alias Foglet.TUI.Screens.{MainMenu, ShellVisibility}
  alias Foglet.TUI.Screens.MainMenu.State, as: MainMenuState

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

  defp context_from_app(state) do
    Context.new(
      current_user: state.current_user,
      session_context: state.session_context,
      session_pid: state.session_pid,
      terminal_size: state.terminal_size,
      route: state.current_screen,
      route_params: Map.get(state, :route_params, %{}),
      domain: Map.get(state.session_context || %{}, :domain, %{})
    )
  end

  defp local_from_app(state) do
    %MainMenuState{
      recent_oneliners: Map.get(state, :recent_oneliners, []),
      selected_oneliner_index: Map.get(state, :selected_oneliner_index, 0),
      pending_hide_oneliner_id: Map.get(state, :pending_hide_oneliner_id)
    }
  end

  defp rendered_text(state) do
    MainMenu.render(local_from_app(state), context_from_app(state)) |> collect_text_values()
  end

  defp handle_key_result(state, key) do
    MainMenu.update(
      {:key, %{key: :char, char: key}},
      local_from_app(state),
      context_from_app(state)
    )
  end

  defp handle_special_key_result(state, key) do
    MainMenu.update({:key, %{key: key}}, local_from_app(state), context_from_app(state))
  end

  defp assert_navigate_effect(effects, screen) do
    assert Enum.any?(effects, &match?(%Effect{type: :navigate, payload: %{screen: ^screen}}, &1))
  end

  defp assert_dispatch_effect(effects, message) do
    assert %Effect{type: :session, payload: {:dispatch, message}} in effects
  end

  defp assert_board_list_load_task(effects) do
    assert Enum.any?(
             effects,
             &match?(
               %Effect{type: :task, payload: %{op: :load_boards, screen_key: :board_list}},
               &1
             )
           )
  end

  defp only_task_fun(effects, op) do
    assert [%Effect{type: :task, payload: %{op: ^op, screen_key: :main_menu, fun: fun}}] = effects
    fun
  end

  setup do
    %{state: build_state(:user)}
  end

  test "MainMenu has no public init_screen_state/1" do
    refute function_exported?(MainMenu, :init_screen_state, 1)
  end

  describe "oneliners strip" do
    test "nil recent_oneliners renders panel title and empty state", %{state: state} do
      texts = state |> with_oneliners(nil) |> rendered_text()

      # Phase 32 / MENU-01: panel title is embedded in the box top border via
      # Raxol's `:panel` element type — it lives in `attrs.title`, not in a
      # `:text` child node, so collect_text_values/1 (which walks `:text`
      # children only) never sees it. The body-row "Oneliners" title is gone;
      # the layout_smoke test asserts the embedded " Oneliners " overlay at
      # the positioned-render layer.
      refute "Oneliners" in texts
      assert "No oneliners yet." in texts
    end

    test "empty recent_oneliners renders panel title and empty state", %{state: state} do
      texts = state |> with_oneliners([]) |> rendered_text()

      # Phase 32 / MENU-01: see note above — title is embedded in the box top
      # border, not a `:text` child, so collect_text_values does not surface it.
      refute "Oneliners" in texts
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

    test "Up and Down change MainMenu.State selected_oneliner_index", %{
      state: state
    } do
      state =
        state
        |> with_oneliners([
          oneliner("alice", "first", %{id: "ol1"}),
          oneliner("bob", "second", %{id: "ol2"})
        ])
        |> with_selected_oneliner(0)

      {down_state, []} = handle_special_key_result(state, :down)
      assert down_state.selected_oneliner_index == 1
      assert %MainMenuState{} = down_state

      {clamped_down_state, []} =
        MainMenu.update({:key, %{key: :down}}, down_state, context_from_app(state))

      assert clamped_down_state.selected_oneliner_index == 1

      {up_state, []} =
        MainMenu.update({:key, %{key: :up}}, clamped_down_state, context_from_app(state))

      assert up_state.selected_oneliner_index == 0

      {clamped_up_state, []} =
        MainMenu.update({:key, %{key: :up}}, up_state, context_from_app(state))

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
      {local_state, []} = handle_key_result(state, "H")
      assert local_state == local_from_app(state)

      {local_state, []} = handle_key_result(state, "h")
      assert local_state == local_from_app(state)
    end

    test "mods and sysops see Hide oneliner only for authorized selected rows with ids" do
      for role <- [:mod, :sysop] do
        hideable_state =
          role
          |> build_state()
          |> with_oneliners([oneliner("alice", "hideable", %{id: "ol1"})])
          |> with_selected_oneliner(0)

        assert Enum.any?(rendered_text(hideable_state), &String.contains?(&1, "Hide oneliner"))

        {local_state, effects} = handle_key_result(hideable_state, "H")
        assert local_state.pending_hide_oneliner_id == "ol1"

        assert [
                 %Effect{
                   type: :modal,
                   payload: {:open, %Foglet.TUI.Modal{title: "Hide Oneliner"}}
                 }
               ] = effects

        {local_state, effects} = handle_key_result(hideable_state, "h")
        assert local_state.pending_hide_oneliner_id == "ol1"

        assert [
                 %Effect{
                   type: :modal,
                   payload: {:open, %Foglet.TUI.Modal{title: "Hide Oneliner"}}
                 }
               ] = effects

        missing_id_state =
          role
          |> build_state()
          |> with_oneliners([oneliner("alice", "no id", %{id: nil})])
          |> with_selected_oneliner(0)

        refute Enum.any?(rendered_text(missing_id_state), &String.contains?(&1, "Hide oneliner"))
        {local_state, []} = handle_key_result(missing_id_state, "H")
        assert local_state == local_from_app(missing_id_state)
      end
    end

    test "Enter on a selected oneliner is reserved and performs no Profile navigation", %{
      state: state
    } do
      state =
        state
        |> with_oneliners([oneliner("alice", "profile later", %{id: "ol1"})])
        |> with_selected_oneliner(0)

      {local_state, effects} = handle_special_key_result(state, :enter)
      assert local_state == local_from_app(state)
      assert effects == []
    end
  end

  describe "oneliner modal submit reducer messages" do
    setup %{state: state} do
      Process.put(:fake_oneliners_owner, self())

      state =
        put_in(state.session_context[:domain], %{oneliners: Foglet.TUI.FakeOneliners})

      %{state: state}
    end

    test "composer submit emits a screen-tagged create task", %{state: state} do
      {local_state, effects} =
        MainMenu.update(
          {:modal_submit, :oneliner_composer, %{body: "ship it"}},
          local_from_app(state),
          context_from_app(state)
        )

      assert local_state.oneliner_status == :submitting
      task = only_task_fun(effects, :submit_oneliner)
      assert {:ok, %{id: "ol-new", body: "ship it"}} = task.()
      assert_received {:create_entry, _user, %{body: "ship it"}}
    end

    test "hide submit trims reason and emits a screen-tagged hide task", %{state: state} do
      local =
        state
        |> with_oneliners([oneliner("alice", "hideable", %{id: "ol1"})])
        |> with_selected_oneliner(0)
        |> local_from_app()
        |> MainMenuState.set_pending_hide("ol1")

      {local_state, effects} =
        MainMenu.update(
          {:modal_submit, :hide_oneliner, %{reason: "  abuse  "}},
          local,
          context_from_app(state)
        )

      assert local_state.oneliner_status == :hiding
      task = only_task_fun(effects, :submit_hide_oneliner)
      assert {:ok, %{id: "ol1"}} = task.()
      assert_received {:hide_entry, _user, "ol1", "abuse"}
    end

    test "hide submit validates blank reason before task creation", %{state: state} do
      local = local_from_app(state) |> MainMenuState.set_pending_hide("ol1")

      {local_state, effects} =
        MainMenu.update(
          {:modal_submit, :hide_oneliner, %{reason: "   "}},
          local,
          context_from_app(state)
        )

      assert local_state.oneliner_errors.reason == "Reason is required."

      assert [%Effect{type: :modal, payload: {:open, %Foglet.TUI.Modal{title: "Hide Oneliner"}}}] =
               effects

      refute_received {:hide_entry, _user, _entry_id, _reason}
    end

    test "create success dismisses composer and requests oneliner refresh", %{state: state} do
      local = local_from_app(state)

      {local_state, effects} =
        MainMenu.update(
          {:task_result, :submit_oneliner, {:ok, {:ok, %{id: "ol2"}}}},
          local,
          context_from_app(state)
        )

      assert local_state.oneliner_status == :loading
      assert %Effect{type: :modal, payload: :dismiss} in effects

      assert Enum.any?(
               effects,
               &match?(%Effect{type: :task, payload: %{op: :load_oneliners}}, &1)
             )
    end

    test "create duplicate user error stays in local form errors", %{state: state} do
      {local_state, effects} =
        MainMenu.update(
          {:task_result, :submit_oneliner, {:ok, {:error, :same_user_latest_visible}}},
          local_from_app(state),
          context_from_app(state)
        )

      assert local_state.oneliner_errors.base == "Let someone else post before posting again."

      assert [%Effect{type: :modal, payload: {:open, %Foglet.TUI.Modal{title: "Post Oneliner"}}}] =
               effects
    end

    test "hide success removes hidden row and clears pending target", %{state: state} do
      local =
        state
        |> with_oneliners([
          oneliner("alice", "hideable", %{id: "ol1"}),
          oneliner("bob", "keep", %{id: "ol2"})
        ])
        |> with_selected_oneliner(1)
        |> local_from_app()
        |> MainMenuState.set_pending_hide("ol1")

      {local_state, effects} =
        MainMenu.update(
          {:task_result, :submit_hide_oneliner, {:ok, {:ok, %{id: "ol1"}}}},
          local,
          context_from_app(state)
        )

      assert [%{id: "ol2"}] = local_state.recent_oneliners
      assert local_state.pending_hide_oneliner_id == nil
      assert local_state.selected_oneliner_index == 0
      assert [%Effect{type: :modal, payload: :dismiss}] = effects
    end

    test "hide forbidden stores local form error and keeps pending target", %{state: state} do
      local = local_from_app(state) |> MainMenuState.set_pending_hide("ol1")

      {local_state, effects} =
        MainMenu.update(
          {:task_result, :submit_hide_oneliner, {:ok, {:error, :forbidden}}},
          local,
          context_from_app(state)
        )

      assert local_state.pending_hide_oneliner_id == "ol1"
      assert local_state.oneliner_errors.base == "You are not allowed to hide this oneliner."

      assert [%Effect{type: :modal, payload: {:open, %Foglet.TUI.Modal{title: "Hide Oneliner"}}}] =
               effects
    end
  end

  test "render includes main menu owned text rows", %{state: state} do
    texts = rendered_text(state)

    # D-11: Welcome line removed.
    refute Enum.any?(texts, &String.starts_with?(&1, "Welcome back")),
           "Phase 19 D-11 removes the welcome line; got: #{inspect(texts)}"

    # Phase 32 / MENU-01: Navigation panel title is now embedded in the box
    # top border via Raxol's `:panel` (lives in `attrs.title`, not a `:text`
    # child), so collect_text_values does not surface it. Layout-smoke tests
    # assert the embedded " Navigation " overlay at the positioned-render
    # layer; here we just confirm the body-row title is gone.
    refute "Navigation" in texts

    # Phase 32 / MENU-03: each nav row is now composed of TWO text nodes —
    # a primary-color leading segment (glyph + label + right-align padding,
    # with one-column inner indent per MENU-04) and an accent-color
    # bracketed-key segment "[X]". collect_text_values flattens children, so
    # both halves appear as separate entries in `texts`.
    assert Enum.any?(texts, &(&1 =~ ~r/^\s+●\s+Boards/)),
           "expected ' ● Boards ...' leading segment; got: #{inspect(texts)}"

    assert "[B]" in texts,
           "expected '[B]' bracketed-key segment; got: #{inspect(texts)}"

    assert Enum.any?(texts, &(&1 =~ ~r/^\s+✎\s+Compose/)),
           "expected ' ✎ Compose ...' leading segment; got: #{inspect(texts)}"

    assert "[C]" in texts,
           "expected '[C]' bracketed-key segment; got: #{inspect(texts)}"

    assert Enum.any?(texts, &(&1 =~ ~r/^\s+↯\s+Logout/)),
           "expected ' ↯ Logout ...' leading segment; got: #{inspect(texts)}"

    assert "[Q]" in texts,
           "expected '[Q]' bracketed-key segment; got: #{inspect(texts)}"
  end

  test "'B'/'b' navigates to :board_list with BoardList-owned load task", %{state: state} do
    {_local, effects} = handle_key_result(state, "B")
    assert_navigate_effect(effects, :board_list)
    assert_board_list_load_task(effects)

    {_local, effects} = handle_key_result(state, "b")
    assert_navigate_effect(effects, :board_list)
    assert_board_list_load_task(effects)
  end

  test "'C'/'c' navigates to :new_thread and seeds compose screen state", %{state: state} do
    {_local, effects} = handle_key_result(state, "C")
    assert_navigate_effect(effects, :new_thread)
    assert_dispatch_effect(effects, {:load_boards_for_new_thread})

    {_local, effects} = handle_key_result(state, "c")
    assert_navigate_effect(effects, :new_thread)
    assert_dispatch_effect(effects, {:load_boards_for_new_thread})
  end

  test "'Q'/'q' emits {:terminate, :logout} command", %{state: state} do
    {_local, effects} = handle_key_result(state, "Q")
    assert [%Effect{type: :quit}] = effects

    {_local, effects} = handle_key_result(state, "q")
    assert [%Effect{type: :quit}] = effects
  end

  test "'O'/'o' emits open oneliner composer command", %{state: state} do
    {local, effects} = handle_key_result(state, "O")
    assert local == local_from_app(state)

    assert [%Effect{type: :modal, payload: {:open, %Foglet.TUI.Modal{title: "Post Oneliner"}}}] =
             effects

    {local, effects} = handle_key_result(state, "o")
    assert local == local_from_app(state)

    assert [%Effect{type: :modal, payload: {:open, %Foglet.TUI.Modal{title: "Post Oneliner"}}}] =
             effects
  end

  test "unknown key returns :no_match", %{state: state} do
    assert {local_from_app(state), []} == handle_key_result(state, "z")
  end

  describe "Phase 0 shell entry points" do
    test "authenticated user with role :user sees Account menu entry" do
      state = build_state(:user)
      flat = rendered_text(state)
      assert Enum.any?(flat, &String.contains?(&1, "Account"))
      # Phase 32 / MENU-03 + MENU-04: nav row is now two text nodes — leading
      # segment with one-column indent + glyph + label, and a separate
      # bracketed-key "[A]" segment in accent color.
      assert Enum.any?(flat, &(&1 =~ ~r/^\s+◇\s+Account/)),
             "expected ' ◇ Account ...' leading segment; got: #{inspect(flat)}"

      assert "[A]" in flat,
             "expected '[A]' bracketed-key segment; got: #{inspect(flat)}"
    end

    test "role :user does NOT see Moderation menu entry" do
      state = build_state(:user)
      flat = rendered_text(state)
      refute Enum.any?(flat, &String.contains?(&1, "Moderation"))
    end

    test "role :user does NOT see Sysop menu entry" do
      state = build_state(:user)
      flat = rendered_text(state)
      refute Enum.any?(flat, &String.contains?(&1, "Sysop"))
    end

    test "role :mod sees Account AND Moderation entries but NOT Sysop" do
      state = build_state(:mod)
      flat = rendered_text(state)
      assert Enum.any?(flat, &String.contains?(&1, "Account"))
      assert Enum.any?(flat, &String.contains?(&1, "Moderation"))
      refute Enum.any?(flat, &String.contains?(&1, "Sysop"))
    end

    test "role :sysop sees Account AND Moderation AND Sysop entries" do
      state = build_state(:sysop)
      flat = rendered_text(state)
      assert Enum.any?(flat, &String.contains?(&1, "Account"))
      assert Enum.any?(flat, &String.contains?(&1, "Moderation"))
      assert Enum.any?(flat, &String.contains?(&1, "Sysop"))
    end

    test "'A'/'a' navigates to :account and seeds screen_state" do
      state = build_state(:user)
      {_local, effects} = handle_key_result(state, "A")

      assert Enum.any?(
               effects,
               &match?(%Effect{type: :navigate, payload: %{screen: :account}}, &1)
             )

      {_local, effects} = handle_key_result(state, "a")

      assert Enum.any?(
               effects,
               &match?(%Effect{type: :navigate, payload: %{screen: :account}}, &1)
             )
    end

    test "'M'/'m' navigates to :moderation for role :mod" do
      state = build_state(:mod)
      {_local, effects} = handle_key_result(state, "M")

      assert Enum.any?(
               effects,
               &match?(%Effect{type: :navigate, payload: %{screen: :moderation}}, &1)
             )

      {_local, effects} = handle_key_result(state, "m")

      assert Enum.any?(
               effects,
               &match?(%Effect{type: :navigate, payload: %{screen: :moderation}}, &1)
             )
    end

    test "'M'/'m' returns :no_match for role :user (key bound guarded per D-02)" do
      state = build_state(:user)
      assert {local_from_app(state), []} == handle_key_result(state, "M")
      assert {local_from_app(state), []} == handle_key_result(state, "m")
    end

    test "'S'/'s' navigates to :sysop for role :sysop" do
      state = build_state(:sysop)
      {_local, effects} = handle_key_result(state, "S")
      assert Enum.any?(effects, &match?(%Effect{type: :navigate, payload: %{screen: :sysop}}, &1))

      {_local, effects} = handle_key_result(state, "s")
      assert Enum.any?(effects, &match?(%Effect{type: :navigate, payload: %{screen: :sysop}}, &1))
    end

    test "'S'/'s' returns :no_match for role :mod" do
      state = build_state(:mod)
      assert {local_from_app(state), []} == handle_key_result(state, "S")
      assert {local_from_app(state), []} == handle_key_result(state, "s")
    end

    test "'S'/'s' returns :no_match for role :user" do
      state = build_state(:user)
      assert {local_from_app(state), []} == handle_key_result(state, "S")
      assert {local_from_app(state), []} == handle_key_result(state, "s")
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
    {_local_state, effects} = handle_key_result(state, key)
    assert_navigate_effect(effects, screen)
  end

  defp assert_key_visibility(state, key, _screen, false) do
    assert {local_from_app(state), []} == handle_key_result(state, key)
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

          # Phase 32 / MENU-03: each nav row is now two text nodes — leading
          # segment (glyph + label + right-align padding) and a separate
          # bracketed-key "[X]" segment. collect_text_values surfaces both as
          # standalone entries; only the leading segment carries the glyph.
          nav_leading_rows =
            texts
            |> Enum.filter(fn row ->
              Enum.any?(["●", "✎", "◇", "⚑", "▣", "↯"], &String.contains?(row, &1))
            end)

          bracketed_keys = Enum.filter(texts, &(&1 =~ ~r/^\[[A-Z]\]$/))

          assert nav_leading_rows != [],
                 "expected at least one nav leading segment for role=#{role} at #{inspect({width, height})}; got: #{inspect(texts)}"

          assert bracketed_keys != [],
                 "expected at least one bracketed-key segment for role=#{role} at #{inspect({width, height})}; got: #{inspect(texts)}"

          inner_width = MainMenu.__nav_panel_inner_width__(state)

          # Leading segment + a 3-cell "[X]" bracketed key must fit within
          # inner_width when their display_widths are summed. The leading
          # segment already includes its right-align padding sized to leave
          # exactly room for "[X]" (and at least one extra padding cell), so
          # `leading_width + 3 <= inner_width` is the load-bearing invariant.
          for row <- nav_leading_rows do
            assert Foglet.TUI.TextWidth.display_width(row) + 3 <= inner_width,
                   "nav row '#{row}' + bracketed-key budget exceeds inner_width=#{inner_width} for role=#{role} at #{inspect({width, height})}"
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

  describe "update(:on_route_enter, …) — Phase 39 Plan 04" do
    # These reducer pins document the screen-side ownership of the route-entry
    # signal. They preserve the user-conditional load semantics of the App's
    # `maybe_dispatch_route_entry/3` clause for `:main_menu` (`app.ex:810-816`):
    # when a current_user is present, dispatch :load_oneliners; otherwise
    # no-op. Plan 39-05 will collapse the App-side per-screen clauses into a
    # single generic dispatch, relying on these screen-side clauses.

    test "with current_user set delegates to :load_oneliners (loads + emits task effect)" do
      user = %Foglet.Accounts.User{id: "u1", handle: "alice", role: :user}

      context =
        Context.new(
          current_user: user,
          route: :main_menu,
          terminal_size: {80, 24}
        )

      local = MainMenu.init(context)

      {state_via_on_enter, effects_via_on_enter} =
        MainMenu.update(:on_route_enter, local, context)

      {state_via_load, effects_via_load} =
        MainMenu.update(:load_oneliners, local, context)

      assert state_via_on_enter == state_via_load
      assert state_via_on_enter.oneliner_status == :loading

      assert Enum.any?(
               effects_via_on_enter,
               &match?(%Effect{type: :task, payload: %{op: :load_oneliners}}, &1)
             )

      assert effects_via_on_enter == effects_via_load
    end

    test "with no current_user no-ops (no effects, normalized state)" do
      context = Context.new(current_user: nil, route: :main_menu, terminal_size: {80, 24})
      local = MainMenu.init(context)

      {new_local, effects} = MainMenu.update(:on_route_enter, local, context)

      assert effects == []
      assert %MainMenuState{} = new_local
    end

    test "with nil local_state and no user normalizes without crashing" do
      context = Context.new(current_user: nil, route: :main_menu, terminal_size: {80, 24})

      {new_local, effects} = MainMenu.update(:on_route_enter, nil, context)

      assert effects == []
      assert %MainMenuState{} = new_local
    end
  end
end
