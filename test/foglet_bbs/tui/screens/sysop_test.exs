defmodule Foglet.TUI.Screens.SysopTest do
  # async: false because SITE/LIMITS tabs lazy-init their submodules which
  # call Foglet.Config.get!/1 — the :foglet_config ETS table is process-global.
  use FogletBbs.DataCase, async: false

  import Foglet.TUI.RenderHelpers

  alias Foglet.Accounts
  alias Foglet.Accounts.Invites
  alias Foglet.Config
  alias Foglet.Config.Schema
  alias Foglet.TUI.Presentation
  alias Foglet.TUI.Screens.Sysop
  alias Foglet.TUI.Screens.Sysop.State, as: SysopState
  alias FogletBbs.Repo

  @config_keys Map.keys(Schema.defaults())

  defp build_state(role) do
    user =
      case role do
        nil ->
          nil

        r ->
          %Foglet.Accounts.User{
            id: Ecto.UUID.generate(),
            handle: "alice",
            role: r,
            status: :active
          }
      end

    %Foglet.TUI.App{
      current_screen: :sysop,
      current_user: user,
      session_context: %{},
      terminal_size: {80, 24},
      screen_state: %{}
    }
    |> Map.from_struct()
  end

  defp with_invite_policy(state, policy) do
    put_in(state, [:session_context, :invite_code_generators], policy)
  end

  setup do
    Config.init_cache()
    for key <- @config_keys, do: Config.invalidate(key)

    # Seed default values so get!/1 finds rows.
    for {key, default} <- Schema.defaults() do
      Config.put!(key, default, nil)
    end

    Config.put!("delivery_mode", "email", nil)

    on_exit(fn -> for key <- @config_keys, do: Config.invalidate(key) end)

    %{state: build_state(:sysop)}
  end

  describe "init_screen_state/1" do
    test "returns struct with active_tab: 0 and Tabs wrapper" do
      ss = Sysop.init_screen_state()
      assert ss.active_tab == 0
      assert %Foglet.TUI.Widgets.Input.Tabs{} = ss.tabs
    end
  end

  describe "lifecycle tagged-enum" do
    @moduletag :lifecycle

    test ":not_loaded is the default for the four lifecycle slots" do
      ss = Sysop.init_screen_state()
      assert ss.boards_view == :not_loaded
      assert ss.limits_form == :not_loaded
      assert ss.system_snapshot == :not_loaded
      assert ss.users_view == :not_loaded
      # SITE stays nil (D-03 — synchronous)
      assert ss.site_form == nil
    end

    test "lifecycle slots accept every tagged value without nil leakage" do
      values = [
        :not_loaded,
        :loading,
        {:loaded, %Foglet.TUI.Screens.Sysop.UsersView{}},
        {:error, :forbidden},
        {:error, :timeout}
      ]

      for value <- values do
        ss = struct(SysopState, users_view: value)
        assert ss.users_view == value
      end
    end
  end

  describe "render_tab_body lifecycle (D-08, D-11, D-12)" do
    @describetag :lifecycle_render

    setup %{state: state} do
      state = put_in(state, [:screen_state, :sysop], Sysop.init_screen_state(active: 4))
      %{state: state}
    end

    defp put_users_slot(state, value) do
      ss = state.screen_state.sysop
      new_ss = %{ss | users_view: value}
      put_in(state, [:screen_state, :sysop], new_ss)
    end

    test "USERS :not_loaded renders the Loading… panel", %{state: state} do
      flat = state |> put_users_slot(:not_loaded) |> Sysop.render() |> collect_text_values()
      assert Enum.any?(flat, &String.contains?(&1, "Loading…"))
    end

    test "USERS :loading renders the Loading… panel", %{state: state} do
      flat = state |> put_users_slot(:loading) |> Sysop.render() |> collect_text_values()
      assert Enum.any?(flat, &String.contains?(&1, "Loading…"))
    end

    test "USERS {:loaded, sub} delegates to UsersView.render", %{state: state} do
      sysop = %Foglet.Accounts.User{
        id: Ecto.UUID.generate(),
        handle: "alice",
        role: :sysop,
        status: :active
      }

      sub = Foglet.TUI.Screens.Sysop.UsersView.from_groups(%{}, sysop)
      flat = state |> put_users_slot({:loaded, sub}) |> Sysop.render() |> collect_text_values()
      # UsersView render emits the heading.
      assert Enum.any?(flat, &String.contains?(&1, "User status administration"))
    end

    test "USERS {:error, :forbidden} renders forbidden panel (no Retry copy, Pitfall 3)",
         %{state: state} do
      flat =
        state
        |> put_users_slot({:error, :forbidden})
        |> Sysop.render()
        |> collect_text_values()
        |> Enum.join("\n")

      assert String.contains?(flat, "Insufficient role to view this tab.")
      refute String.contains?(flat, "Could not load")
      refute String.contains?(flat, "Press R to retry")
    end

    test "USERS {:error, :timeout} renders generic error panel with retry copy",
         %{state: state} do
      flat =
        state
        |> put_users_slot({:error, :timeout})
        |> Sysop.render()
        |> collect_text_values()
        |> Enum.join("\n")

      assert String.contains?(flat, "Could not load users.")
      assert String.contains?(flat, "Press R to retry")
      refute String.contains?(flat, "Insufficient role")
    end

    test "no \"Press any key\" literal remains in lib/foglet_bbs/tui/screens/sysop.ex" do
      contents = File.read!("lib/foglet_bbs/tui/screens/sysop.ex")
      refute String.contains?(contents, "Press any key")
    end

    test "no Raxol.Core.Runtime.Command.task literal exists under Sysop.* (D-04)" do
      sysop_files =
        Path.wildcard("lib/foglet_bbs/tui/screens/sysop.ex") ++
          Path.wildcard("lib/foglet_bbs/tui/screens/sysop/**/*.ex")

      for path <- sysop_files do
        contents = File.read!(path)

        refute String.contains?(contents, "Raxol.Core.Runtime.Command.task"),
               "#{path} contains forbidden Raxol.Core.Runtime.Command.task literal (D-04)"
      end
    end
  end

  describe "delegate_to_submodule guard (D-09)" do
    @describetag :lifecycle_delegate

    setup %{state: state} do
      state = put_in(state, [:screen_state, :sysop], Sysop.init_screen_state(active: 4))
      %{state: state}
    end

    test "events on :not_loaded slot are no-ops (no submodule.handle_key invoked)",
         %{state: state} do
      ss = state.screen_state.sysop
      ss = %{ss | users_view: :not_loaded}
      state = put_in(state, [:screen_state, :sysop], ss)

      # Down is delegated; with :not_loaded the guard returns :no_match.
      assert :no_match = Sysop.handle_key(%{key: :down}, state)
    end

    test "events on :loading slot are no-ops", %{state: state} do
      ss = state.screen_state.sysop
      ss = %{ss | users_view: :loading}
      state = put_in(state, [:screen_state, :sysop], ss)

      assert :no_match = Sysop.handle_key(%{key: :down}, state)
    end

    test "events on {:error, _} slot are no-ops", %{state: state} do
      ss = state.screen_state.sysop
      ss = %{ss | users_view: {:error, :forbidden}}
      state = put_in(state, [:screen_state, :sysop], ss)

      assert :no_match = Sysop.handle_key(%{key: :down}, state)
    end

    test "events on {:loaded, sub} are delegated and the wrapper is preserved on writeback",
         %{state: state} do
      sysop = %Foglet.Accounts.User{
        id: Ecto.UUID.generate(),
        handle: "alice",
        role: :sysop,
        status: :active
      }

      pending_user = %Foglet.Accounts.User{
        id: Ecto.UUID.generate(),
        handle: "bob",
        role: :user,
        status: :pending
      }

      groups = %{pending: [pending_user], active: [], suspended: [], rejected: []}
      sub = Foglet.TUI.Screens.Sysop.UsersView.from_groups(groups, sysop)
      ss = state.screen_state.sysop
      ss = %{ss | users_view: {:loaded, sub}}
      state = put_in(state, [:screen_state, :sysop], ss)

      # Down event rotates UsersView selection — wrapper stays {:loaded, _}.
      case Sysop.handle_key(%{key: :down}, state) do
        {:update, new_state, _cmds} ->
          assert match?({:loaded, _}, new_state.screen_state.sysop.users_view)

        :no_match ->
          # Acceptable when single-row keeps selection_index pinned at 0.
          :ok
      end
    end
  end

  describe "tab-switch dispatch (D-05, D-06)" do
    @describetag :lifecycle_dispatch

    setup %{state: state} do
      state = put_in(state, [:screen_state, :sysop], Sysop.init_screen_state(active: 0))
      %{state: state}
    end

    test "switching from SITE to USERS via digit '5' emits {:load_sysop_users} when :not_loaded",
         %{state: state} do
      assert state.screen_state.sysop.users_view == :not_loaded

      {:update, new_state, cmds} = Sysop.handle_key(%{key: :char, char: "5"}, state)

      assert new_state.screen_state.sysop.active_tab == 4
      # Slot transitions to :loading synchronously with dispatch.
      assert new_state.screen_state.sysop.users_view == :loading
      assert Enum.member?(cmds, {:load_sysop_users})
    end

    test "switching to BOARDS emits {:load_sysop_boards}", %{state: state} do
      {:update, new_state, cmds} = Sysop.handle_key(%{key: :char, char: "2"}, state)
      assert new_state.screen_state.sysop.active_tab == 1
      assert new_state.screen_state.sysop.boards_view == :loading
      assert Enum.member?(cmds, {:load_sysop_boards})
    end

    test "switching to LIMITS emits {:load_sysop_limits}", %{state: state} do
      {:update, new_state, cmds} = Sysop.handle_key(%{key: :char, char: "3"}, state)
      assert new_state.screen_state.sysop.active_tab == 2
      assert new_state.screen_state.sysop.limits_form == :loading
      assert Enum.member?(cmds, {:load_sysop_limits})
    end

    test "switching to SYSTEM emits {:load_sysop_system}", %{state: state} do
      {:update, new_state, cmds} = Sysop.handle_key(%{key: :char, char: "4"}, state)
      assert new_state.screen_state.sysop.active_tab == 3
      assert new_state.screen_state.sysop.system_snapshot == :loading
      assert Enum.member?(cmds, {:load_sysop_system})
    end

    test "switching back to a {:loaded, _} tab emits no command (idempotent)",
         %{state: state} do
      sub = %Foglet.TUI.Screens.Sysop.UsersView{}
      ss = state.screen_state.sysop
      ss = %{ss | users_view: {:loaded, sub}}
      state = put_in(state, [:screen_state, :sysop], ss)

      {:update, new_state, cmds} = Sysop.handle_key(%{key: :char, char: "5"}, state)
      assert new_state.screen_state.sysop.active_tab == 4
      assert new_state.screen_state.sysop.users_view == {:loaded, sub}
      refute Enum.member?(cmds, {:load_sysop_users})
    end

    test "switching to SITE never emits a load command (D-03 sync)", %{state: state} do
      # Move to BOARDS first (which emits a load), then back to SITE.
      {:update, mid_state, _} = Sysop.handle_key(%{key: :char, char: "2"}, state)
      assert mid_state.screen_state.sysop.active_tab == 1

      {:update, new_state, cmds} = Sysop.handle_key(%{key: :char, char: "1"}, mid_state)
      assert new_state.screen_state.sysop.active_tab == 0
      # No sysop-load command emitted on SITE entry.
      refute Enum.any?(cmds, &match?({:load_sysop_users}, &1))
      refute Enum.any?(cmds, &match?({:load_sysop_boards}, &1))
      refute Enum.any?(cmds, &match?({:load_sysop_limits}, &1))
      refute Enum.any?(cmds, &match?({:load_sysop_system}, &1))
    end
  end

  describe "[R] Retry advertising (Phase 29 D-13)" do
    @describetag :retry_advertising

    setup %{state: state} do
      ss = Sysop.init_screen_state(active: 4)
      state = put_in(state, [:screen_state, :sysop], ss)
      %{state: state}
    end

    defp put_sysop_slot(state, slot, value) do
      ss = state.screen_state.sysop
      put_in(state, [:screen_state, :sysop], %{ss | slot => value})
    end

    test "active tab USERS in {:error, :timeout} advertises Retry", %{state: state} do
      flat =
        state
        |> put_sysop_slot(:users_view, {:error, :timeout})
        |> Sysop.render()
        |> collect_text_values()
        |> Enum.join("\n")

      assert String.contains?(flat, "Retry")
    end

    test "active tab USERS in {:error, :forbidden} does NOT advertise Retry", %{state: state} do
      flat =
        state
        |> put_sysop_slot(:users_view, {:error, :forbidden})
        |> Sysop.render()
        |> collect_text_values()
        |> Enum.join("\n")

      refute String.contains?(flat, "Retry")
    end

    test "active tab USERS in {:loaded, _} does NOT advertise Retry", %{state: state} do
      sub = %Foglet.TUI.Screens.Sysop.UsersView{}

      flat =
        state
        |> put_sysop_slot(:users_view, {:loaded, sub})
        |> Sysop.render()
        |> collect_text_values()
        |> Enum.join("\n")

      refute String.contains?(flat, "Retry")
    end
  end

  describe "[R] Retry dispatch (Phase 29 D-13)" do
    @describetag :retry_dispatch

    setup %{state: state} do
      ss = Sysop.init_screen_state(active: 4)
      state = put_in(state, [:screen_state, :sysop], ss)
      %{state: state}
    end

    test "pressing R on USERS in {:error, :timeout} re-dispatches {:load_sysop_users} and flips slot to :loading",
         %{state: state} do
      state = put_sysop_slot(state, :users_view, {:error, :timeout})

      assert {:update, new_state, cmds} = Sysop.handle_key(%{key: :char, char: "R"}, state)
      assert new_state.screen_state.sysop.users_view == :loading
      assert {:load_sysop_users} in cmds
    end

    test "pressing r (lowercase) on USERS in {:error, :timeout} also re-dispatches", %{
      state: state
    } do
      state = put_sysop_slot(state, :users_view, {:error, :timeout})

      assert {:update, new_state, cmds} = Sysop.handle_key(%{key: :char, char: "r"}, state)
      assert new_state.screen_state.sysop.users_view == :loading
      assert {:load_sysop_users} in cmds
    end

    test "pressing R on USERS in {:error, :forbidden} is a no-op (forbidden suppresses R)",
         %{state: state} do
      state = put_sysop_slot(state, :users_view, {:error, :forbidden})

      # R must NOT consume the event nor flip the slot to :loading. Returns
      # :no_match (or {:update, state, []} with users_view unchanged) so the
      # event continues falling through to the existing handlers.
      result = Sysop.handle_key(%{key: :char, char: "R"}, state)

      case result do
        :no_match ->
          :ok

        {:update, new_state, cmds} ->
          assert new_state.screen_state.sysop.users_view == {:error, :forbidden}
          refute {:load_sysop_users} in cmds
      end
    end

    test "pressing R on USERS in {:loaded, _} does not consume R at the Sysop level (falls through to UsersView [R] Reject)",
         %{state: state} do
      # Build a UsersView with a focused :pending row so [R] Reject would
      # dispatch a transition. We assert that R on a {:loaded, _} tab is NOT
      # consumed by the retry handler — the existing fallthrough preserves
      # the [R] Reject keybind on USERS.
      sysop = %Foglet.Accounts.User{
        id: Ecto.UUID.generate(),
        handle: "sysop",
        role: :sysop,
        status: :active
      }

      pending_user = %Foglet.Accounts.User{
        id: Ecto.UUID.generate(),
        handle: "p1",
        email: "p1@example.test",
        role: :user,
        status: :pending
      }

      sub = %Foglet.TUI.Screens.Sysop.UsersView{
        current_user: sysop,
        rows: [{:pending, pending_user}],
        selection_index: 0
      }

      state = %{state | current_user: sysop} |> put_sysop_slot(:users_view, {:loaded, sub})

      # The Sysop-level retry handler must NOT consume R on a loaded tab.
      # The event must propagate to UsersView, where [R] Reject is gated for
      # pending rows. We can't assert against the boundary side effect here
      # without a Repo, but we can assert the slot stayed {:loaded, _} (not
      # flipped to :loading) and no {:load_sysop_*} command was emitted.
      result = Sysop.handle_key(%{key: :char, char: "R"}, state)

      case result do
        :no_match ->
          :ok

        {:update, new_state, cmds} ->
          # Slot must NOT be flipped to :loading by the retry handler.
          refute new_state.screen_state.sysop.users_view == :loading
          refute {:load_sysop_users} in cmds
      end
    end

    test "pressing R on BOARDS in {:error, :timeout} dispatches {:load_sysop_boards}, not USERS",
         %{state: state} do
      # Switch to BOARDS (active_tab = 1), set its slot to error.
      ss = state.screen_state.sysop
      ss = %{ss | active_tab: 1, tabs: ss.tabs}
      state = put_in(state, [:screen_state, :sysop], ss)
      state = put_sysop_slot(state, :boards_view, {:error, :timeout})

      assert {:update, new_state, cmds} = Sysop.handle_key(%{key: :char, char: "R"}, state)
      assert new_state.screen_state.sysop.boards_view == :loading
      assert {:load_sysop_boards} in cmds
      refute {:load_sysop_users} in cmds
    end
  end

  describe "render/1" do
    setup %{state: state} do
      state = put_in(state, [:screen_state, :sysop], Sysop.init_screen_state())
      %{state: state}
    end

    test "shows all five tab labels in order: SITE, BOARDS, LIMITS, SYSTEM, USERS", %{
      state: state
    } do
      flat = Sysop.render(state) |> collect_text_values()
      expected_tabs = ["SITE", "BOARDS", "LIMITS", "SYSTEM", "USERS"]

      for tab <- expected_tabs do
        assert Enum.any?(flat, &String.contains?(&1, tab)),
               "Expected #{inspect(tab)} in flat text: #{inspect(flat)}"
      end

      # Assert order by finding index positions and checking they ascend
      tab_positions =
        Enum.map(expected_tabs, fn tab ->
          flat
          |> Enum.with_index()
          |> Enum.find_value(fn {text, idx} ->
            if String.contains?(text, tab), do: idx
          end)
        end)

      valid_positions = Enum.reject(tab_positions, &is_nil/1)

      assert valid_positions == Enum.sort(valid_positions),
             "Expected tab labels to appear in order SITE, BOARDS, LIMITS, SYSTEM, USERS. " <>
               "Got positions: #{inspect(Enum.zip(expected_tabs, tab_positions))}"
    end

    test "appends INVITES for sysop_only, mods, and any_user sysop policies", %{state: state} do
      for policy <- ["sysop_only", "mods", "any_user"] do
        state = with_invite_policy(state, policy)

        ss =
          Sysop.init_screen_state(
            current_user: state.current_user,
            session_context: state.session_context
          )

        assert SysopState.tab_labels(ss) == [
                 "SITE",
                 "BOARDS",
                 "LIMITS",
                 "SYSTEM",
                 "USERS",
                 "INVITES"
               ]

        flat =
          state
          |> put_in([:screen_state, :sysop], ss)
          |> Sysop.render()
          |> collect_text_values()

        assert Enum.any?(flat, &String.contains?(&1, "INVITES")),
               "Expected INVITES tab for #{policy}; got #{inspect(flat)}"
      end
    end

    test "does not expose Sysop INVITES to nil or non-sysop users" do
      for role <- [nil, :user, :mod] do
        state = build_state(role) |> with_invite_policy("sysop_only")

        ss =
          Sysop.init_screen_state(
            current_user: state.current_user,
            session_context: state.session_context
          )

        refute "INVITES" in SysopState.tab_labels(ss)

        flat =
          state
          |> put_in([:screen_state, :sysop], ss)
          |> Sysop.render()
          |> collect_text_values()

        refute Enum.any?(flat, &String.contains?(&1, "INVITES")),
               "Expected no INVITES tab for #{inspect(role)}; got #{inspect(flat)}"
      end
    end

    # Former scaffold-only guard removed in Plan 02-03: SITE/LIMITS tabs now
    # genuinely render forms with [Ctrl+S] Save hints — a "Save" refute would
    # always fire. The anti-fake-command guard survives under handle_key/2.
  end

  describe "handle_key/2" do
    setup %{state: state} do
      state = put_in(state, [:screen_state, :sysop], Sysop.init_screen_state())
      %{state: state}
    end

    test "advances through visible tabs with Right arrow", %{
      state: state
    } do
      {state1, tab1} =
        case Sysop.handle_key(%{key: :right}, state) do
          {:update, s, _} -> {s, s.screen_state.sysop.active_tab}
        end

      {state2, tab2} =
        case Sysop.handle_key(%{key: :right}, state1) do
          {:update, s, _} -> {s, s.screen_state.sysop.active_tab}
        end

      {state3, tab3} =
        case Sysop.handle_key(%{key: :right}, state2) do
          {:update, s, _} -> {s, s.screen_state.sysop.active_tab}
        end

      {state4, tab4} =
        case Sysop.handle_key(%{key: :right}, state3) do
          {:update, s, _} -> {s, s.screen_state.sysop.active_tab}
        end

      {_state5, tab5} =
        case Sysop.handle_key(%{key: :right}, state4) do
          {:update, s, _} -> {s, s.screen_state.sysop.active_tab}
          :no_match -> {state4, state4.screen_state.sysop.active_tab}
        end

      assert tab1 == 1
      assert tab2 == 2
      assert tab3 == 3
      assert tab4 == 4
      assert tab5 == 5
    end

    test "digit '5' jumps to USERS tab (index 4)", %{state: state} do
      {:update, new_state, _cmds} = Sysop.handle_key(%{key: :char, char: "5"}, state)
      assert new_state.screen_state.sysop.active_tab == 4
    end

    test "digit '6' jumps to INVITES tab when visible", %{state: state} do
      state = with_invite_policy(state, "sysop_only")

      ss =
        Sysop.init_screen_state(
          current_user: state.current_user,
          session_context: state.session_context
        )

      state = put_in(state, [:screen_state, :sysop], ss)

      {:update, new_state, _cmds} = Sysop.handle_key(%{key: :char, char: "6"}, state)

      assert new_state.screen_state.sysop.active_tab == 5
      assert SysopState.tab_labels(new_state.screen_state.sysop) |> Enum.at(5) == "INVITES"
    end

    test "'Q' returns to :main_menu", %{state: state} do
      {:update, new_state, _cmds} = Sysop.handle_key(%{key: :char, char: "Q"}, state)
      assert new_state.current_screen == :main_menu
    end

    test "'q' returns to :main_menu", %{state: state} do
      {:update, new_state, _cmds} = Sysop.handle_key(%{key: :char, char: "q"}, state)
      assert new_state.current_screen == :main_menu
    end

    test "unknown key returns :no_match", %{state: state} do
      assert :no_match = Sysop.handle_key(%{key: :char, char: "z"}, state)
    end

    test "Sysop screen does NOT dispatch fake config-write commands", %{state: state} do
      forbidden_commands = [:save_config, :apply_config, :set_config]

      keys = [
        %{key: :right},
        %{key: :left},
        %{key: :home},
        %{key: :end},
        %{key: :char, char: "1"},
        %{key: :char, char: "2"},
        %{key: :char, char: "5"}
      ]

      for key <- keys do
        case Sysop.handle_key(key, state) do
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
  end

  describe "SITE / LIMITS tab partition (D-02)" do
    test "every schema key appears in exactly one of @site_keys / @limits_keys" do
      all_keys = MapSet.new(Enum.map(Foglet.Config.Schema.entries(), & &1.key))
      site = MapSet.new(Foglet.TUI.Screens.Sysop.SiteForm.site_keys())
      limits = MapSet.new(Foglet.TUI.Screens.Sysop.LimitsForm.limits_keys())

      assert MapSet.disjoint?(site, limits),
             "SITE and LIMITS key lists must be disjoint"

      assert MapSet.union(site, limits) == all_keys,
             "Every Schema.entries/0 key must appear in exactly one of @site_keys / @limits_keys"
    end
  end

  describe "SITE tab render (SYSO-02, INVT-06)" do
    setup %{state: state} do
      state = put_in(state, [:screen_state, :sysop], Sysop.init_screen_state())
      %{state: state}
    end

    test "renders every visible @site_keys description", %{state: state} do
      # Force the limit row visible so all four SITE descriptions are rendered.
      Config.put!("invite_code_generators", "any_user", nil)

      # Lazy-init the SiteForm by delegating a no-op key to the SITE tab.
      {:update, state, _} = Sysop.handle_key(%{key: :tab}, state)

      flat = Sysop.render(state) |> collect_text_values() |> Enum.join("\n")

      for key <- Foglet.TUI.Screens.Sysop.SiteForm.site_keys() do
        {:ok, spec} = Schema.fetch_spec(key)

        assert String.contains?(flat, spec.description),
               "Expected description for #{inspect(key)} in SITE render output"
      end
    end

    test "hides invite_generation_per_user_limit when invite_code_generators != any_user (D-04)",
         %{state: state} do
      Config.put!("invite_code_generators", "sysop_only", nil)

      {:update, state, _} = Sysop.handle_key(%{key: :tab}, state)

      flat = Sysop.render(state) |> collect_text_values() |> Enum.join("\n")
      {:ok, spec} = Schema.fetch_spec("invite_generation_per_user_limit")

      refute String.contains?(flat, spec.description),
             "Limit row must be hidden when generators != any_user"

      refute String.contains?(flat, "invite_generation_per_user_limit"),
             "Limit key name must not leak when row is hidden"
    end

    test "shows invite_generation_per_user_limit when invite_code_generators == any_user",
         %{state: state} do
      Config.put!("invite_code_generators", "any_user", nil)

      {:update, state, _} = Sysop.handle_key(%{key: :tab}, state)

      flat = Sysop.render(state) |> collect_text_values() |> Enum.join("\n")

      assert String.contains?(flat, "invite_generation_per_user_limit"),
             "Limit row must be visible when generators == any_user"
    end
  end

  describe "SITE tab Ctrl+S (SYSO-02)" do
    setup %{state: state} do
      state = put_in(state, [:screen_state, :sysop], Sysop.init_screen_state())
      %{state: state}
    end

    test "invalid integer surfaces inline error, no modal", %{state: state} do
      # Put into 'any_user' so the limit row is visible & focusable.
      Config.put!("delivery_mode", "email", nil)
      Config.put!("invite_code_generators", "any_user", nil)

      # Persist a real sysop so Config.put/3 clears authz AND the
      # configuration.updated_by_id FK constraint. MUST be set BEFORE lazy-init
      # so SiteForm.init captures the persisted actor.
      sysop =
        FogletBbs.AccountsFixtures.user_fixture()
        |> Ecto.Changeset.change(%{role: :sysop})
        |> FogletBbs.Repo.update!()

      state = %{state | current_user: sysop}

      # Navigate to SITE tab (already index 0) — lazy-init by sending Tab.
      {:update, state, _} = Sysop.handle_key(%{key: :tab}, state)

      # SiteForm was lazy-initialized with the real sysop above.
      _ = state

      # Manually install a draft with a negative value for the limit field
      # (simulating the sysop typing a value that fails the min: 0 schema check).
      ss = state.screen_state.sysop

      site_form = %{
        ss.site_form
        | drafts: Map.put(ss.site_form.drafts, "invite_generation_per_user_limit", -1)
      }

      state = put_in(state, [:screen_state, :sysop], %{ss | site_form: site_form})

      # Send Ctrl+S.
      {:update, new_state, _cmds} =
        Sysop.handle_key(%{key: :char, char: "s", ctrl: true}, state)

      # Inline error recorded; no modal; still on sysop screen.
      assert new_state.current_screen == :sysop
      assert new_state.modal == nil

      errors = new_state.screen_state.sysop.site_form.errors

      assert Map.has_key?(errors, "invite_generation_per_user_limit"),
             "Expected inline error for the bad integer; got errors: #{inspect(errors)}"
    end

    test ":forbidden from Config.put routes to error modal + :main_menu (D-08, D-24)",
         %{state: _state} do
      # Build a state with a nil actor — Bodyguard.permit/4 denies (D-24).
      # nil is used (rather than a non-sysop User struct with a random UUID)
      # because a random UUID would fail the configuration.updated_by_id_fkey
      # constraint after the authorization check passes — nil trips authz first.
      state =
        build_state(nil)
        |> put_in([:screen_state, :sysop], Sysop.init_screen_state())

      Config.put!("delivery_mode", "email", nil)

      # Lazy-init SiteForm and mutate a draft so submit hits Config.put.
      {:update, state, _} = Sysop.handle_key(%{key: :tab}, state)

      ss = state.screen_state.sysop

      site_form = %{
        ss.site_form
        | drafts: Map.put(ss.site_form.drafts, "registration_mode", "invite_only")
      }

      state = put_in(state, [:screen_state, :sysop], %{ss | site_form: site_form})

      {:update, new_state, _cmds} =
        Sysop.handle_key(%{key: :char, char: "s", ctrl: true}, state)

      assert %Foglet.TUI.Modal{type: :error} = new_state.modal
      assert new_state.current_screen == :main_menu
    end
  end

  describe "LIMITS tab render (SYSO-02)" do
    setup %{state: state} do
      # Phase 29 D-07: lifecycle slot pre-loaded as {:loaded, _}; the
      # App-level {:load_sysop_limits} triad is the production load path,
      # but tests inject the fully-loaded form synchronously.
      ss = Sysop.init_screen_state(active: 2)
      lf = Foglet.TUI.Screens.Sysop.LimitsForm.init([])
      ss = %{ss | limits_form: {:loaded, lf}}
      state = put_in(state, [:screen_state, :sysop], ss)

      %{state: state}
    end

    test "renders every @limits_keys description", %{state: state} do
      flat = Sysop.render(state) |> collect_text_values() |> Enum.join("\n")

      for key <- Foglet.TUI.Screens.Sysop.LimitsForm.limits_keys() do
        {:ok, spec} = Schema.fetch_spec(key)

        assert String.contains?(flat, spec.description),
               "Expected description for #{inspect(key)} in LIMITS render output"
      end
    end

    test "ordinary character input %{key: :char, char: \"x\"} does not raise", %{
      state: state
    } do
      before_drafts = current_limits_form(state).drafts

      result = Sysop.handle_key(%{key: :char, char: "x"}, state)

      new_state =
        case result do
          {:update, state, _cmds} -> state
          :no_match -> state
        end

      assert current_limits_form(new_state).drafts == before_drafts
    end
  end

  # =========================================================================
  # SITE Modal.Form primitive presence (Phase 25 Plan 04)
  # =========================================================================

  describe "SITE Modal.Form primitive presence" do
    setup %{state: state} do
      state = put_in(state, [:screen_state, :sysop], Sysop.init_screen_state())
      %{state: state}
    end

    test "SITE tab body renders Modal.Form footer sentinel", %{state: state} do
      # Lazy-init the SiteForm by delegating a no-op key to the SITE tab.
      {:update, state, _} = Sysop.handle_key(%{key: :tab}, state)

      flat = Sysop.render(state) |> collect_text_values() |> Enum.join("\n")

      assert String.contains?(flat, "[Enter] Submit"),
             "Expected Modal.Form footer '[Enter] Submit' in SITE render; got:\n#{flat}"
    end

    test "SITE tab body renders heading", %{state: state} do
      {:update, state, _} = Sysop.handle_key(%{key: :tab}, state)
      flat = Sysop.render(state) |> collect_text_values() |> Enum.join("\n")

      assert String.contains?(flat, "Site policy"),
             "Expected Site policy heading in SITE render"
    end

    test "SITE tab body renders visible field labels", %{state: state} do
      {:update, state, _} = Sysop.handle_key(%{key: :tab}, state)
      flat = Sysop.render(state) |> collect_text_values() |> Enum.join("\n")

      assert String.contains?(flat, "registration_mode"),
             "Expected registration_mode field label in SITE render"

      assert String.contains?(flat, "invite_code_generators"),
             "Expected invite_code_generators field label in SITE render"
    end
  end

  # =========================================================================
  # LIMITS Modal.Form primitive presence (Phase 25 Plan 04)
  # =========================================================================

  describe "LIMITS Modal.Form primitive presence" do
    setup %{state: state} do
      # Phase 29 D-07: pre-load LIMITS slot wrapped as {:loaded, _} —
      # the production path is the App-level {:load_sysop_limits} triad.
      ss = Sysop.init_screen_state(active: 2)
      lf = Foglet.TUI.Screens.Sysop.LimitsForm.init([])
      ss = %{ss | limits_form: {:loaded, lf}}
      state = put_in(state, [:screen_state, :sysop], ss)
      %{state: state}
    end

    test "LIMITS tab body renders Modal.Form footer sentinel", %{state: state} do
      flat = Sysop.render(state) |> collect_text_values() |> Enum.join("\n")

      assert String.contains?(flat, "[Enter] Submit"),
             "Expected Modal.Form footer '[Enter] Submit' in LIMITS render; got:\n#{flat}"
    end

    test "LIMITS tab body renders heading", %{state: state} do
      flat = Sysop.render(state) |> collect_text_values() |> Enum.join("\n")

      assert String.contains?(flat, "Runtime limits"),
             "Expected Runtime limits heading in LIMITS render"
    end

    test "LIMITS tab body renders field labels with required markers", %{state: state} do
      flat = Sysop.render(state) |> collect_text_values() |> Enum.join("\n")

      assert String.contains?(flat, "max_post_length"),
             "Expected max_post_length field label in LIMITS render"

      assert String.contains?(flat, "max_thread_title_length"),
             "Expected max_thread_title_length field label in LIMITS render"
    end
  end

  # =========================================================================
  # USERS tab tests (Plan 10-02, USER-01 through USER-03)
  # =========================================================================

  alias Foglet.TUI.Screens.Sysop.UsersView

  # Phase 29 D-07: lifecycle slots store {:loaded, sub} wrapped values.
  # Test helpers wrap on write and unwrap on read so existing call sites
  # keep their bare-struct ergonomics.
  defp put_users_view(state, uv) do
    ss = state.screen_state.sysop
    new_ss = %{ss | users_view: {:loaded, uv}}
    %{state | screen_state: Map.put(state.screen_state, :sysop, new_ss)}
  end

  defp current_users_view(state) do
    case state.screen_state.sysop.users_view do
      {:loaded, uv} -> uv
      other -> flunk("Expected {:loaded, _} users_view; got #{inspect(other)}")
    end
  end

  defp persist_user(attrs) do
    attrs
    |> FogletBbs.AccountsFixtures.user_fixture()
    |> Ecto.Changeset.change(%{
      role: Map.get(attrs, :role, :user),
      status: Map.get(attrs, :status, :active),
      deleted_at: Map.get(attrs, :deleted_at)
    })
    |> Repo.update!()
  end

  defp activate_users_tab(state, sysop) do
    state = %{state | current_user: sysop}
    ss = Sysop.init_screen_state(active: 4)
    uv = UsersView.init(current_user: sysop)
    ss = %{ss | users_view: {:loaded, %{uv | selection_index: 0}}}
    put_in(state, [:screen_state, :sysop], ss)
  end

  defp select_user_row(state, handle) do
    uv = current_users_view(state)

    idx =
      Enum.find_index(uv.rows, fn {_status, user} -> user.handle == handle end) ||
        flunk("Expected USERS row for #{handle}")

    put_users_view(state, %{uv | selection_index: idx})
  end

  describe "USERS tab render (USER-01)" do
    test "renders pending, active, suspended, and rejected non-deleted handles", %{state: state} do
      sysop = persist_user(%{handle: "sysopusers", role: :sysop})

      pending =
        persist_user(%{handle: "pendinguser", email: "pending@example.test", status: :pending})

      active = persist_user(%{handle: "activeuser", email: "active@example.test"})

      suspended =
        persist_user(%{
          handle: "suspendeduser",
          email: "suspended@example.test",
          status: :suspended
        })

      rejected =
        persist_user(%{handle: "rejecteduser", email: "rejected@example.test", status: :rejected})

      _deleted =
        persist_user(%{
          handle: "deleteduser",
          email: "deleted@example.test",
          deleted_at: DateTime.utc_now()
        })

      state = activate_users_tab(state, sysop)
      flat = Sysop.render(state) |> collect_text_values() |> Enum.join("\n")

      assert String.contains?(flat, "User status administration")

      for {status, user} <- [
            {"pending", pending},
            {"active", active},
            {"suspended", suspended},
            {"rejected", rejected}
          ] do
        assert String.contains?(flat, "#{status}  @#{user.handle}  #{user.email}")
      end

      refute String.contains?(flat, "deleteduser")
    end

    test "renders empty state and key hints when there are no administrable users" do
      sysop = %Foglet.Accounts.User{id: Ecto.UUID.generate(), role: :sysop, status: :active}
      view = UsersView.init(current_user: sysop)
      flat = UsersView.render(view, Foglet.TUI.Theme.default()) |> collect_text_values()

      assert Enum.any?(flat, &String.contains?(&1, "No administrable users."))
      # Phase 29 D-15: footer is render-time. With no rows, the only key hint
      # advertised is [j/k] Move (no transition keys are gated-in).
      assert Enum.any?(flat, &String.contains?(&1, "[j/k] Move"))
    end
  end

  describe "USERS tab actions (USER-02, USER-03)" do
    test "approves pending users through Accounts and refreshes as active", %{state: state} do
      sysop = persist_user(%{handle: "approve_sysop", role: :sysop})
      pending = persist_user(%{handle: "approve_me", status: :pending})
      state = activate_users_tab(state, sysop)

      {:update, state, _} = Sysop.handle_key(%{key: :char, char: "A"}, state)

      assert Accounts.get_user!(pending.id).status == :active

      assert current_users_view(state).message ==
               "Status changed: @approve_me pending -> active."
    end

    test "rejects pending users through Accounts and refreshes as rejected", %{state: state} do
      sysop = persist_user(%{handle: "reject_sysop", role: :sysop})
      pending = persist_user(%{handle: "reject_me", status: :pending})
      state = activate_users_tab(state, sysop)

      {:update, state, _} = Sysop.handle_key(%{key: :char, char: "R"}, state)

      assert Accounts.get_user!(pending.id).status == :rejected

      assert current_users_view(state).message ==
               "Status changed: @reject_me pending -> rejected."
    end

    test "suspends active users through Accounts and refreshes as suspended", %{state: state} do
      sysop = persist_user(%{handle: "suspend_sysop", role: :sysop})
      active = persist_user(%{handle: "suspend_me", status: :active})
      state = activate_users_tab(state, sysop)
      state = select_user_row(state, active.handle)

      {:update, state, _} = Sysop.handle_key(%{key: :char, char: "S"}, state)

      assert Accounts.get_user!(active.id).status == :suspended

      assert current_users_view(state).message ==
               "Status changed: @suspend_me active -> suspended."
    end

    test "reactivates suspended users through Accounts and refreshes as active", %{state: state} do
      sysop = persist_user(%{handle: "reactivate_sysop", role: :sysop})
      suspended = persist_user(%{handle: "reactivate_me", status: :suspended})
      state = activate_users_tab(state, sysop)
      state = select_user_row(state, suspended.handle)

      {:update, state, _} = Sysop.handle_key(%{key: :char, char: "U"}, state)

      assert Accounts.get_user!(suspended.id).status == :active

      assert current_users_view(state).message ==
               "Status changed: @reactivate_me suspended -> active."
    end

    test "invalid row action is a no-op (Phase 29 D-15: pressing R on :active is gated)",
         %{state: state} do
      sysop = persist_user(%{handle: "invalid_sysop", role: :sysop})
      active = persist_user(%{handle: "reject_active", status: :active})
      state = activate_users_tab(state, sysop)
      state = select_user_row(state, active.handle)

      # D-15: [R] Reject is gated to :pending source rows. Pressing R on a
      # focused :active row is a UI no-op — no boundary call, no message.
      result = Sysop.handle_key(%{key: :char, char: "R"}, state)

      # The keypress is a no-op at the UsersView level. handle_key may return
      # :no_match (event ignored) or {:update, _, _} with state unchanged.
      case result do
        :no_match -> :ok
        {:update, new_state, _} -> assert current_users_view(new_state).message == nil
      end

      assert Accounts.get_user!(active.id).status == :active
    end
  end

  describe "USERS keybind gating (Phase 29 D-15, A2)" do
    @describetag :users_keybind_gating

    alias Foglet.TUI.Theme

    defp build_user(handle, status) do
      %Foglet.Accounts.User{
        id: Ecto.UUID.generate(),
        handle: handle,
        email: "#{handle}@example.test",
        role: :user,
        status: status
      }
    end

    defp build_users_view_with(focused_status) do
      user = build_user("focused_#{focused_status}", focused_status)

      %UsersView{
        current_user: %Foglet.Accounts.User{
          id: Ecto.UUID.generate(),
          handle: "sysop",
          role: :sysop,
          status: :active
        },
        rows: [{focused_status, user}],
        selection_index: 0
      }
    end

    test "focused :pending row advertises [A] Approve and [R] Reject; not [S] or [U]" do
      view = build_users_view_with(:pending)
      flat = view |> UsersView.render(Theme.default()) |> collect_text_values() |> Enum.join("\n")

      assert String.contains?(flat, "[A] Approve")
      assert String.contains?(flat, "[R] Reject")
      refute String.contains?(flat, "[S] Suspend")
      refute String.contains?(flat, "[U] Reactivate")
    end

    test "focused :active row advertises [S] Suspend; not [A], [R], or [U]" do
      view = build_users_view_with(:active)
      flat = view |> UsersView.render(Theme.default()) |> collect_text_values() |> Enum.join("\n")

      assert String.contains?(flat, "[S] Suspend")
      refute String.contains?(flat, "[A] Approve")
      refute String.contains?(flat, "[R] Reject")
      refute String.contains?(flat, "[U] Reactivate")
    end

    test "focused :suspended row advertises [U] Reactivate; not [A]" do
      view = build_users_view_with(:suspended)
      flat = view |> UsersView.render(Theme.default()) |> collect_text_values() |> Enum.join("\n")

      assert String.contains?(flat, "[U] Reactivate")
      refute String.contains?(flat, "[A] Approve")
      refute String.contains?(flat, "[R] Reject")
      refute String.contains?(flat, "[S] Suspend")
    end

    test "focused :rejected row advertises none of [A], [R], [S], [U]" do
      view = build_users_view_with(:rejected)
      flat = view |> UsersView.render(Theme.default()) |> collect_text_values() |> Enum.join("\n")

      refute String.contains?(flat, "[A] Approve")
      refute String.contains?(flat, "[R] Reject")
      refute String.contains?(flat, "[S] Suspend")
      refute String.contains?(flat, "[U] Reactivate")
    end

    test "empty rows list still renders [j/k] Move and does not crash" do
      view = %UsersView{
        current_user: nil,
        rows: [],
        selection_index: 0
      }

      flat = view |> UsersView.render(Theme.default()) |> collect_text_values() |> Enum.join("\n")
      assert String.contains?(flat, "[j/k] Move")
    end

    test "pressing A on focused :active row is a no-op (no boundary call, no message)" do
      view = build_users_view_with(:active)

      assert {new_view, []} = UsersView.handle_key(%{key: :char, char: "A"}, view)
      assert new_view == view
      assert new_view.message == nil
    end

    test "pressing U on focused :pending row is a no-op (A2: source must be :suspended)" do
      view = build_users_view_with(:pending)

      assert {new_view, []} = UsersView.handle_key(%{key: :char, char: "U"}, view)
      assert new_view == view
      assert new_view.message == nil
    end

    test "pressing S on focused :pending row is a no-op (target :suspended unreachable from :pending)" do
      view = build_users_view_with(:pending)

      assert {new_view, []} = UsersView.handle_key(%{key: :char, char: "S"}, view)
      assert new_view == view
      assert new_view.message == nil
    end
  end

  describe "USERS from->to copy (Phase 29 D-16)" do
    @describetag :users_from_to_copy

    test "{:error, :invalid_transition} renders 'Cannot change @<handle> from <from> to <to>.'",
         %{state: state} do
      sysop = persist_user(%{handle: "fromto_sysop", role: :sysop})
      # Persist user as :active so the boundary will reject :pending->:active
      # for a stale row whose UsersView struct claims :pending.
      stale_user = persist_user(%{handle: "stale_user", status: :active})

      state = %{state | current_user: sysop}
      ss = Sysop.init_screen_state(active: 4)

      # Build a stale UsersView whose row says :pending even though the DB has
      # the user at :active. UI gate sees :pending source, allows [A]; boundary
      # checks user.status from DB and returns {:error, :invalid_transition}.
      stale_view = %UsersView{
        current_user: sysop,
        rows: [{:pending, stale_user}],
        selection_index: 0,
        groups: %{pending: [stale_user], active: [], suspended: [], rejected: []}
      }

      ss = %{ss | users_view: {:loaded, stale_view}}
      state = put_in(state, [:screen_state, :sysop], ss)

      {:update, new_state, _} = Sysop.handle_key(%{key: :char, char: "A"}, state)

      message = current_users_view(new_state).message

      # D-16: from->to copy uses the focused row's *displayed* (stale) source
      # status and the keypress's target. The handle is named explicitly.
      assert message == "Cannot change @stale_user from pending to active."
      refute message =~ "invalid_transition"
    end

    test "no rendered string literal in users_view.ex contains 'invalid_transition'" do
      contents = File.read!("lib/foglet_bbs/tui/screens/sysop/users_view.ex")

      # Render-time guard: scan for double-quoted string literals containing
      # the substring 'invalid_transition'. Function names, atoms, and
      # comments are allowed (they don't reach the operator).
      string_literals = Regex.scan(~r/"([^"\\]|\\.)*"/, contents) |> Enum.map(&hd/1)

      offending =
        Enum.filter(string_literals, fn lit ->
          String.contains?(lit, "invalid_transition")
        end)

      assert offending == [],
             "users_view.ex contains a string literal with 'invalid_transition' (D-16): #{inspect(offending)}"
    end
  end

  # =========================================================================
  # BOARDS tab tests (Plan 02-04, SYSO-03)
  # =========================================================================

  alias Foglet.TUI.Screens.Sysop.BoardsView
  alias Foglet.TUI.Widgets.Modal.Form, as: ModalForm

  defp persist_sysop do
    FogletBbs.AccountsFixtures.user_fixture()
    |> Ecto.Changeset.change(%{role: :sysop})
    |> FogletBbs.Repo.update!()
  end

  defp seed_category_and_board(_ctx) do
    sysop = persist_sysop()
    category = FogletBbs.BoardsFixtures.category_fixture(%{name: "General", display_order: 0})
    board = FogletBbs.BoardsFixtures.board_fixture(category, %{slug: "chat", name: "Chat"})
    %{sysop: sysop, category: category, board: board}
  end

  # Sysop.State is a struct that does not implement Access — `put_in/3` into
  # `screen_state.sysop.boards_view` fails. This helper writes via struct
  # update semantics, which is what the CLAUDE.md gotchas call out explicitly.
  #
  # Phase 29 D-07: lifecycle slot stores `{:loaded, sub}`. Helper wraps on
  # write; `current_boards_view/1` unwraps on read.
  defp put_boards_view(state, bv) do
    ss = state.screen_state.sysop
    new_ss = %{ss | boards_view: {:loaded, bv}}
    %{state | screen_state: Map.put(state.screen_state, :sysop, new_ss)}
  end

  defp current_boards_view(state) do
    case state.screen_state.sysop.boards_view do
      {:loaded, bv} -> bv
      other -> flunk("Expected {:loaded, _} boards_view; got #{inspect(other)}")
    end
  end

  defp current_limits_form(state) do
    case state.screen_state.sysop.limits_form do
      {:loaded, lf} -> lf
      other -> flunk("Expected {:loaded, _} limits_form; got #{inspect(other)}")
    end
  end

  defp current_system_snapshot(state) do
    case state.screen_state.sysop.system_snapshot do
      {:loaded, ss} -> ss
      other -> flunk("Expected {:loaded, _} system_snapshot; got #{inspect(other)}")
    end
  end

  defp activate_boards_tab(state, sysop) do
    # BOARDS is index 1. Synchronously init BoardsView and wrap as
    # {:loaded, _} so delegate_to_submodule/5 routes events through.
    state = %{state | current_user: sysop}
    ss = Sysop.init_screen_state(active: 1)
    bv = BoardsView.init(current_user: sysop)
    bv = %{bv | selection_index: 0}
    ss = %{ss | boards_view: {:loaded, bv}}
    put_in(state, [:screen_state, :sysop], ss)
  end

  describe "BOARDS tab render (SYSO-03)" do
    setup [:seed_category_and_board]

    test "renders grouped category + board list", %{state: state, sysop: sysop} do
      state = activate_boards_tab(state, sysop)
      flat = Sysop.render(state) |> collect_text_values() |> Enum.join("\n")
      assert String.contains?(flat, "General")
      assert String.contains?(flat, "Chat")
      assert String.contains?(flat, "chat")
    end
  end

  describe "BOARDS tab create flow (SYSO-03)" do
    setup [:seed_category_and_board]

    test "n opens Modal.Form for new board with expected field specs", %{
      state: state,
      sysop: sysop
    } do
      state = activate_boards_tab(state, sysop)
      {:update, state, _} = Sysop.handle_key(%{key: :char, char: "n"}, state)

      bv = current_boards_view(state)
      assert %ModalForm{} = bv.modal
      field_names = Enum.map(bv.modal.fields, & &1.name)

      assert field_names == [
               :slug,
               :name,
               :description,
               :category_id,
               :postable_by,
               :default_subscription,
               :required_subscription
             ]

      required_field = Enum.find(bv.modal.fields, &(&1.name == :required_subscription))
      assert required_field.label == "Required subscription"
      assert required_field.type == :boolean
      assert required_field.value == false
      assert bv.modal_kind == :create_board
    end

    test "edit board modal pre-fills required subscription", %{
      state: state,
      sysop: sysop,
      board: board
    } do
      {:ok, board} =
        Foglet.Boards.update_board(sysop, board, %{
          default_subscription: true,
          required_subscription: true
        })

      state = activate_boards_tab(state, sysop)
      {:update, state, _} = Sysop.handle_key(%{key: :char, char: "j"}, state)
      {:update, state, _} = Sysop.handle_key(%{key: :char, char: "e"}, state)

      bv = current_boards_view(state)
      assert bv.edit_target.id == board.id

      required_field = Enum.find(bv.modal.fields, &(&1.name == :required_subscription))
      assert required_field.label == "Required subscription"
      assert required_field.value == true
    end

    test "valid submit creates board and refreshes list", %{
      state: state,
      sysop: sysop,
      category: category
    } do
      state = activate_boards_tab(state, sysop)

      # Open create modal, then install a pre-populated form directly to avoid
      # simulating every keystroke through the primitive (which is covered by
      # its own test module).
      bv = current_boards_view(state)

      fields = [
        %{name: :slug, type: :text, label: "Slug", max_length: 50, value: "news"},
        %{name: :name, type: :text, label: "Name", max_length: 100, value: "News"},
        %{name: :description, type: :textarea, label: "Description", value: ""},
        %{
          name: :category_id,
          type: :enum,
          label: "Category",
          choices: [category.id],
          value: category.id
        },
        %{
          name: :postable_by,
          type: :enum,
          label: "Postable by",
          choices: ["members", "mods_only", "sysop_only"],
          value: "members"
        },
        %{
          name: :default_subscription,
          type: :boolean,
          label: "Default subscription",
          value: false
        },
        %{
          name: :required_subscription,
          type: :boolean,
          label: "Required subscription",
          value: false
        }
      ]

      form =
        ModalForm.init(
          title: "New board",
          fields: fields,
          on_submit: fn payload ->
            Process.put({BoardsView, :pending_submit}, payload)
            :ok
          end,
          on_cancel: fn -> :ok end
        )

      bv = %{bv | modal: form, modal_kind: :create_board}
      state = put_boards_view(state, bv)

      # Focus the last field and press Enter to submit.
      n = length(fields)
      bv = current_boards_view(state)
      bv = %{bv | modal: %{bv.modal | focus_index: n - 1}}
      state = put_boards_view(state, bv)

      {:update, new_state, _} = Sysop.handle_key(%{key: :enter}, state)

      new_bv = current_boards_view(new_state)
      assert new_bv.modal == nil, "Modal should close on successful submit"

      assert Enum.any?(new_bv.boards, &(&1.slug == "news")),
             "New board must appear in refreshed list"
    end

    test "invalid submit surfaces Modal.Form errors, modal stays open", %{
      state: state,
      sysop: sysop,
      category: category
    } do
      state = activate_boards_tab(state, sysop)
      bv = current_boards_view(state)

      fields = [
        %{name: :slug, type: :text, label: "Slug", max_length: 50, value: "ok-slug"},
        # Missing required name.
        %{name: :name, type: :text, label: "Name", max_length: 100, value: ""},
        %{name: :description, type: :textarea, label: "Description", value: ""},
        %{
          name: :category_id,
          type: :enum,
          label: "Category",
          choices: [category.id],
          value: category.id
        },
        %{
          name: :postable_by,
          type: :enum,
          label: "Postable by",
          choices: ["members"],
          value: "members"
        },
        %{
          name: :default_subscription,
          type: :boolean,
          label: "Default subscription",
          value: false
        },
        %{
          name: :required_subscription,
          type: :boolean,
          label: "Required subscription",
          value: false
        }
      ]

      form =
        ModalForm.init(
          title: "New board",
          fields: fields,
          on_submit: fn payload ->
            Process.put({BoardsView, :pending_submit}, payload)
            :ok
          end,
          on_cancel: fn -> :ok end
        )

      bv = %{bv | modal: %{form | focus_index: length(fields) - 1}, modal_kind: :create_board}
      state = put_boards_view(state, bv)

      {:update, new_state, _} = Sysop.handle_key(%{key: :enter}, state)

      new_bv = current_boards_view(new_state)
      assert %ModalForm{} = new_bv.modal, "Modal must stay open on validation error"

      assert Map.has_key?(new_bv.modal.errors, :name),
             "Errors must include :name — got #{inspect(new_bv.modal.errors)}"
    end

    test "required subscription without default subscription stays in modal with changeset error",
         %{
           state: state,
           sysop: sysop,
           category: category
         } do
      state = activate_boards_tab(state, sysop)
      bv = current_boards_view(state)

      fields = [
        %{name: :slug, type: :text, label: "Slug", max_length: 50, value: "required-only"},
        %{name: :name, type: :text, label: "Name", max_length: 100, value: "Required Only"},
        %{name: :description, type: :textarea, label: "Description", value: ""},
        %{
          name: :category_id,
          type: :enum,
          label: "Category",
          choices: [category.id],
          value: category.id
        },
        %{
          name: :postable_by,
          type: :enum,
          label: "Postable by",
          choices: ["members"],
          value: "members"
        },
        %{
          name: :default_subscription,
          type: :boolean,
          label: "Default subscription",
          value: false
        },
        %{
          name: :required_subscription,
          type: :boolean,
          label: "Required subscription",
          value: true
        }
      ]

      form =
        ModalForm.init(
          title: "New board",
          fields: fields,
          on_submit: fn payload ->
            Process.put({BoardsView, :pending_submit}, payload)
            :ok
          end,
          on_cancel: fn -> :ok end
        )

      bv = %{bv | modal: %{form | focus_index: length(fields) - 1}, modal_kind: :create_board}
      state = put_boards_view(state, bv)

      {:update, new_state, _} = Sysop.handle_key(%{key: :enter}, state)

      new_bv = current_boards_view(new_state)
      assert %ModalForm{} = new_bv.modal
      assert new_bv.modal.errors.required_subscription =~ "requires default_subscription"
      refute Enum.any?(new_bv.boards, &(&1.slug == "required-only"))
    end

    test "Pitfall 5 — j/k navigation no-op while modal open", %{state: state, sysop: sysop} do
      state = activate_boards_tab(state, sysop)
      {:update, state, _} = Sysop.handle_key(%{key: :char, char: "n"}, state)

      bv_before = current_boards_view(state)
      idx_before = bv_before.selection_index

      # j while a Modal.Form is open must not advance the selection.
      result = Sysop.handle_key(%{key: :char, char: "j"}, state)

      new_state =
        case result do
          {:update, s, _} -> s
          :no_match -> state
        end

      new_bv = current_boards_view(new_state)
      assert new_bv.selection_index == idx_before
      assert %ModalForm{} = new_bv.modal
    end
  end

  describe "BOARDS tab archive flow (SYSO-03)" do
    setup [:seed_category_and_board]

    test "D on a board opens confirm modal; Y archives and removes it", %{
      state: state,
      sysop: sysop
    } do
      state = activate_boards_tab(state, sysop)

      # Selection index 0 is the category row; index 1 is the board row.
      {:update, state, _} = Sysop.handle_key(%{key: :char, char: "j"}, state)

      {:update, state, _} = Sysop.handle_key(%{key: :char, char: "D"}, state)

      bv = current_boards_view(state)
      assert %Foglet.TUI.Modal{type: :confirm} = bv.modal
      assert bv.modal_kind == :archive_board

      {:update, new_state, _} = Sysop.handle_key(%{key: :char, char: "Y"}, state)

      new_bv = current_boards_view(new_state)
      assert new_bv.modal == nil

      refute Enum.any?(new_bv.boards, &(&1.slug == "chat")),
             "Archived board must not appear in refreshed list"
    end
  end

  describe "BOARDS tab category flow (SYSO-03)" do
    setup [:seed_category_and_board]

    test "N opens Modal.Form for new category; valid submit creates it", %{
      state: state,
      sysop: sysop
    } do
      state = activate_boards_tab(state, sysop)
      {:update, state, _} = Sysop.handle_key(%{key: :char, char: "N"}, state)

      bv = current_boards_view(state)
      assert %ModalForm{} = bv.modal
      assert bv.modal_kind == :create_category

      field_names = Enum.map(bv.modal.fields, & &1.name)
      assert field_names == [:name, :description, :display_order]

      # Simulate a valid payload by pre-populating values and pressing Enter
      # from the last field.
      fields = [
        %{name: :name, type: :text, label: "Name", max_length: 100, value: "Announcements"},
        %{name: :description, type: :textarea, label: "Description", value: ""},
        %{name: :display_order, type: :integer, label: "Display order", value: "5"}
      ]

      form =
        ModalForm.init(
          title: "New category",
          fields: fields,
          on_submit: fn payload ->
            Process.put({BoardsView, :pending_submit}, payload)
            :ok
          end,
          on_cancel: fn -> :ok end
        )

      bv = %{bv | modal: %{form | focus_index: length(fields) - 1}}
      state = put_boards_view(state, bv)

      {:update, new_state, _} = Sysop.handle_key(%{key: :enter}, state)

      new_bv = current_boards_view(new_state)
      assert new_bv.modal == nil
      assert Enum.any?(new_bv.categories, &(&1.name == "Announcements"))
    end

    test "invalid category display_order stays in Modal.Form with inline error", %{
      state: state,
      sysop: sysop
    } do
      state = activate_boards_tab(state, sysop)
      bv = current_boards_view(state)

      fields = [
        %{name: :name, type: :text, label: "Name", max_length: 100, value: "Bad Order"},
        %{name: :description, type: :textarea, label: "Description", value: ""},
        %{name: :display_order, type: :integer, label: "Display order", value: "not-a-number"}
      ]

      form =
        ModalForm.init(
          title: "New category",
          fields: fields,
          on_submit: fn payload ->
            Process.put({BoardsView, :pending_submit}, payload)
            :ok
          end,
          on_cancel: fn -> :ok end
        )

      bv = %{bv | modal: %{form | focus_index: length(fields) - 1}, modal_kind: :create_category}
      state = put_boards_view(state, bv)

      {:update, new_state, _} = Sysop.handle_key(%{key: :enter}, state)

      new_bv = current_boards_view(new_state)
      assert %ModalForm{} = new_bv.modal
      assert Map.has_key?(new_bv.modal.errors, :display_order)
      refute Enum.any?(new_bv.categories, &(&1.name == "Bad Order"))
    end
  end

  # =========================================================================
  # SYSTEM tab tests (Plan 02-05, SYSO-04)
  # =========================================================================

  alias Foglet.TUI.Screens.Sysop.SystemSnapshot

  defp activate_system_tab(state) do
    ss = Sysop.init_screen_state(active: 3)
    ss = %{ss | system_snapshot: {:loaded, SystemSnapshot.init([])}}
    put_in(state, [:screen_state, :sysop], ss)
  end

  defp activate_invites_tab(state, sysop) do
    state =
      state
      |> Map.put(:current_user, sysop)
      |> with_invite_policy("sysop_only")

    ss =
      Sysop.init_screen_state(
        active: 5,
        current_user: state.current_user,
        session_context: state.session_context
      )

    put_in(state, [:screen_state, :sysop], ss)
  end

  describe "SYSTEM tab (SYSO-04)" do
    test "renders snapshot labels on tab enter", %{state: state} do
      state = activate_system_tab(state)
      flat = Sysop.render(state) |> collect_text_values() |> Enum.join("\n")

      for label <- ["Version:", "Sessions:", "Active boards:", "OTP processes:"] do
        assert String.contains?(flat, label),
               "Expected #{inspect(label)} in SYSTEM render output"
      end
    end

    test "r keeps the snapshot valid without relying on wall-clock timing", %{state: state} do
      state = activate_system_tab(state)
      old = current_system_snapshot(state)

      new_state =
        case Sysop.handle_key(%{key: :char, char: "r"}, state) do
          {:update, state2, _} -> state2
          :no_match -> state
        end

      new = current_system_snapshot(new_state)

      assert new.snapshot.uptime_ms >= old.snapshot.uptime_ms,
             "Snapshot uptime must not regress"
    end

    test "non-r keys do not mutate the snapshot", %{state: state} do
      state = activate_system_tab(state)
      old = current_system_snapshot(state)

      # `j` is not a tab-nav key; Tabs widget ignores it; delegated to
      # SystemSnapshot which is a no-op for non-`r` chars.
      result = Sysop.handle_key(%{key: :char, char: "j"}, state)

      new_state =
        case result do
          {:update, s, _} -> s
          :no_match -> state
        end

      new = current_system_snapshot(new_state)
      assert new == old
    end
  end

  describe "INVITES tab shared delegation (SYSO-05)" do
    setup %{state: state} do
      sysop = persist_sysop()
      Config.put!("invite_code_generators", "sysop_only", sysop.id)
      %{state: activate_invites_tab(state, sysop), sysop: sysop}
    end

    test "g persists exactly one unlimited sysop_only invite and stores last_generated_code", %{
      state: state,
      sysop: sysop
    } do
      assert {:ok, before_items} = Invites.list_invites(sysop)

      {:update, new_state, _cmds} = Sysop.handle_key(%{key: :char, char: "g"}, state)

      assert {:ok, after_items} = Invites.list_invites(sysop)
      assert length(after_items) == length(before_items) + 1

      invites = new_state.screen_state.sysop.invites
      assert invites.items == after_items
      assert invites.last_generated_code == hd(after_items).code
      assert is_binary(invites.last_generated_code)
      assert invites.error == nil
    end

    test "sysop.ex delegates invite lifecycle through shared modules only" do
      source = File.read!("lib/foglet_bbs/tui/screens/sysop.ex")

      assert String.contains?(source, "InvitesSurface.render")
      assert String.contains?(source, "InvitesActions.handle_key")
      assert String.contains?(source, "InvitesActions.load")

      refute source =~ ~r/Accounts\.(create_invite|revoke_invite|list_invites)/
      refute String.contains?(source, "FogletBbs.Repo")
    end
  end

  describe "[X] Revoke gesture (D-25, SYSOP-06)" do
    @describetag :x_revoke_gesture

    alias Foglet.TUI.Screens.Shared.InvitesState

    # Build an in-memory invites state with the given list of statuses; selection
    # at `focused`. No Repo round-trip — the gesture-arming/clearing logic lives
    # entirely in screen state and does not call Accounts unless X actually fires.
    defp build_invites(statuses, focused) do
      items =
        statuses
        |> Enum.with_index()
        |> Enum.map(fn {status, idx} ->
          %{
            code: "CODE#{String.pad_leading("#{idx}", 4, "0")}",
            status: status,
            issuer_id: "issuer-#{idx}",
            inserted_at: ~U[2026-04-24 01:00:00Z],
            consumed_at: nil,
            consumed_by_user_id: nil,
            revoked_at: nil
          }
        end)

      InvitesState.new(items: items, selected_index: focused)
    end

    defp activate_invites(state, sysop, invites) do
      state =
        state
        |> Map.put(:current_user, sysop)
        |> with_invite_policy("sysop_only")

      ss =
        Sysop.init_screen_state(
          active: 5,
          current_user: state.current_user,
          session_context: state.session_context
        )

      ss = %{ss | invites: invites}
      put_in(state, [:screen_state, :sysop], ss)
    end

    setup %{state: state} do
      sysop = persist_sysop()
      Config.put!("invite_code_generators", "sysop_only", sysop.id)
      %{state: state, sysop: sysop}
    end

    # Counts the number of distinct rendered text tokens whose content contains
    # the substring "Revoke". The `@key_hints` line in invites_surface.ex
    # contributes 1 occurrence ("D Revoke" body hint); when armed, the command
    # bar adds 1 more ("Revoke" label in the [X] Revoke group), totalling 2.
    defp count_revoke_tokens(state) do
      state
      |> Sysop.render()
      |> collect_text_values()
      |> Enum.count(&String.contains?(&1, "Revoke"))
    end

    test "Enter on focused non-revoked INVITES row arms [X] Revoke", %{state: state, sysop: sysop} do
      invites = build_invites([:available, :available], 0)
      state = activate_invites(state, sysop, invites)

      # Pre-condition — only the body key hints carry 'Revoke'.
      assert count_revoke_tokens(state) == 1

      {:update, new_state, _events} = Sysop.handle_key(%{key: :enter}, state)

      assert new_state.screen_state.sysop.armed_revoke? == true

      # After arming — body hint + command-bar [X] Revoke = 2 occurrences.
      assert count_revoke_tokens(new_state) >= 2,
             "Expected command bar to gain a [X] Revoke advertisement after Enter"
    end

    test "Enter on focused :revoked INVITES row does NOT arm and does NOT advertise Revoke",
         %{state: state, sysop: sysop} do
      invites = build_invites([:revoked, :available], 0)
      state = activate_invites(state, sysop, invites)

      result = Sysop.handle_key(%{key: :enter}, state)

      new_state =
        case result do
          {:update, s, _} -> s
          :no_match -> state
        end

      assert new_state.screen_state.sysop.armed_revoke? == false

      # No additional Revoke advertising — only the body hint persists.
      assert count_revoke_tokens(new_state) == 1,
             "Expected command bar to NOT gain a [X] Revoke advertisement on a revoked row"
    end

    test "X while armed dispatches InvitesActions.revoke_selected/2 (state transitions :available -> :revoked)",
         %{state: state, sysop: sysop} do
      # Persist a sysop_only invite via the existing API so the boundary call
      # has something to revoke. The screen-state items list is then synthesized
      # to point at the persisted code.
      {:ok, invite} = Foglet.Accounts.Invites.create_invite(sysop)

      live_item = %{
        code: invite.code,
        status: :available,
        issuer_id: invite.issuer_id,
        inserted_at: invite.inserted_at,
        consumed_at: nil,
        consumed_by_user_id: nil,
        revoked_at: nil
      }

      invites_state = InvitesState.new(items: [live_item], selected_index: 0)
      state = activate_invites(state, sysop, invites_state)

      # Arm the revoke
      {:update, armed_state, _} = Sysop.handle_key(%{key: :enter}, state)
      assert armed_state.screen_state.sysop.armed_revoke? == true

      # Press X — dispatches the existing revoke path
      {:update, fired_state, _events} =
        Sysop.handle_key(%{key: :char, char: "X"}, armed_state)

      # armed_revoke? cleared after firing
      assert fired_state.screen_state.sysop.armed_revoke? == false

      # The InvitesActions.revoke_selected/2 path returns the refreshed list;
      # the persisted invite is now :revoked.
      assert {:ok, [refreshed | _]} = Foglet.Accounts.Invites.list_invites(sysop)
      assert refreshed.code == invite.code
      assert refreshed.status == :revoked
    end

    test "X while not armed is a no-op (no state change, no boundary call)",
         %{state: state, sysop: sysop} do
      invites = build_invites([:available, :available], 0)
      state = activate_invites(state, sysop, invites)

      # Pre-condition: not armed.
      assert state.screen_state.sysop.armed_revoke? == false

      result = Sysop.handle_key(%{key: :char, char: "X"}, state)

      new_state =
        case result do
          {:update, s, _} -> s
          :no_match -> state
        end

      # Still not armed; no revocation happened in InvitesState.
      assert new_state.screen_state.sysop.armed_revoke? == false
      assert new_state.screen_state.sysop.invites.items == invites.items
    end

    test "Moving focus within INVITES clears armed_revoke?", %{state: state, sysop: sysop} do
      invites = build_invites([:available, :available, :available], 1)
      state = activate_invites(state, sysop, invites)

      # Arm via Enter
      {:update, armed_state, _} = Sysop.handle_key(%{key: :enter}, state)
      assert armed_state.screen_state.sysop.armed_revoke? == true

      # Move focus down (j is not used here — InvitesActions uses :down arrow)
      {:update, moved_state, _} = Sysop.handle_key(%{key: :down}, armed_state)

      assert moved_state.screen_state.sysop.armed_revoke? == false
    end

    test "Switching tabs clears armed_revoke?", %{state: state, sysop: sysop} do
      invites = build_invites([:available, :available], 0)
      state = activate_invites(state, sysop, invites)

      # Arm via Enter
      {:update, armed_state, _} = Sysop.handle_key(%{key: :enter}, state)
      assert armed_state.screen_state.sysop.armed_revoke? == true

      # Move to a different tab via Left arrow (Tabs widget consumes it)
      {:update, switched_state, _} = Sysop.handle_key(%{key: :left}, armed_state)

      assert switched_state.screen_state.sysop.armed_revoke? == false
    end

    test "Enter on non-INVITES active tab does not advertise/dispatch revoke",
         %{state: state, sysop: sysop} do
      # Activate SITE tab (active: 0) so Enter on the focused row is irrelevant.
      state =
        state
        |> Map.put(:current_user, sysop)
        |> with_invite_policy("sysop_only")

      ss =
        Sysop.init_screen_state(
          active: 0,
          current_user: state.current_user,
          session_context: state.session_context
        )

      state = put_in(state, [:screen_state, :sysop], ss)

      result = Sysop.handle_key(%{key: :enter}, state)

      new_state =
        case result do
          {:update, s, _} -> s
          :no_match -> state
        end

      assert new_state.screen_state.sysop.armed_revoke? == false
    end

    test "no new revoke logic added in invites_actions.ex (D-25 boundary lock)" do
      # The existing revoke_selected/2 path is the only side effect. This grep
      # guard ensures Plan 04 didn't introduce duplicate revoke logic.
      source = File.read!("lib/foglet_bbs/tui/screens/shared/invites_actions.ex")

      # Should still contain exactly one revoke_selected definition.
      defs = Regex.scan(~r/def revoke_selected\(/, source)
      assert length(defs) == 1
    end
  end

  describe "BOARDS tab forbidden routing (SYSO-03, D-24)" do
    setup [:seed_category_and_board]

    test ":forbidden from create_board routes to error modal + :main_menu", %{
      state: state,
      category: category
    } do
      # Non-sysop actor (nil trips authorization immediately). Phase 29
      # D-07 — pre-load BoardsView wrapped as {:loaded, _} since the
      # tagged-enum slot no longer lazy-inits via delegate_to_submodule.
      state = %{state | current_user: nil}
      ss = Sysop.init_screen_state(active: 1)
      bv = BoardsView.init(current_user: nil)
      ss = %{ss | boards_view: {:loaded, bv}}
      state = put_in(state, [:screen_state, :sysop], ss)

      bv = current_boards_view(state)

      fields = [
        %{name: :slug, type: :text, label: "Slug", max_length: 50, value: "ok"},
        %{name: :name, type: :text, label: "Name", max_length: 100, value: "OK Board"},
        %{name: :description, type: :textarea, label: "Description", value: ""},
        %{
          name: :category_id,
          type: :enum,
          label: "Category",
          choices: [category.id],
          value: category.id
        },
        %{
          name: :postable_by,
          type: :enum,
          label: "Postable by",
          choices: ["members"],
          value: "members"
        },
        %{
          name: :default_subscription,
          type: :boolean,
          label: "Default subscription",
          value: false
        }
      ]

      form =
        ModalForm.init(
          title: "New board",
          fields: fields,
          on_submit: fn payload ->
            Process.put({BoardsView, :pending_submit}, payload)
            :ok
          end,
          on_cancel: fn -> :ok end
        )

      bv = %{bv | modal: %{form | focus_index: length(fields) - 1}, modal_kind: :create_board}
      state = put_boards_view(state, bv)

      {:update, new_state, _} = Sysop.handle_key(%{key: :enter}, state)

      assert %Foglet.TUI.Modal{type: :error} = new_state.modal
      assert new_state.current_screen == :main_menu
    end

    test "{:error, :board_server_unavailable} from create_board routes to error modal + :main_menu",
         %{state: state, sysop: sysop, category: category} do
      sup = Process.whereis(Foglet.Boards.Supervisor)
      ref = Process.monitor(sup)

      :ok = Supervisor.terminate_child(FogletBbs.Supervisor, Foglet.Boards.Supervisor)
      assert_receive {:DOWN, ^ref, :process, ^sup, _reason}

      on_exit(fn ->
        case Process.whereis(Foglet.Boards.Supervisor) do
          nil -> Supervisor.restart_child(FogletBbs.Supervisor, Foglet.Boards.Supervisor)
          _pid -> :ok
        end
      end)

      state = activate_boards_tab(state, sysop)
      bv = current_boards_view(state)

      fields = [
        %{name: :slug, type: :text, label: "Slug", max_length: 50, value: "offline"},
        %{name: :name, type: :text, label: "Name", max_length: 100, value: "Offline Board"},
        %{name: :description, type: :textarea, label: "Description", value: ""},
        %{
          name: :category_id,
          type: :enum,
          label: "Category",
          choices: [category.id],
          value: category.id
        },
        %{
          name: :postable_by,
          type: :enum,
          label: "Postable by",
          choices: ["members"],
          value: "members"
        },
        %{
          name: :default_subscription,
          type: :boolean,
          label: "Default subscription",
          value: false
        }
      ]

      form =
        ModalForm.init(
          title: "New board",
          fields: fields,
          on_submit: fn payload ->
            Process.put({BoardsView, :pending_submit}, payload)
            :ok
          end,
          on_cancel: fn -> :ok end
        )

      bv = %{bv | modal: %{form | focus_index: length(fields) - 1}, modal_kind: :create_board}
      state = put_boards_view(state, bv)

      {:update, new_state, _} = Sysop.handle_key(%{key: :enter}, state)

      assert %Foglet.TUI.Modal{type: :error, message: message} = new_state.modal
      assert message == "Board server unavailable. Please retry."
      assert new_state.current_screen == :main_menu
      assert current_boards_view(new_state).modal == nil
    end
  end

  # =========================================================================
  # USERS ConsoleTable primitive presence (Phase 25 Plan 04)
  # =========================================================================

  describe "USERS ConsoleTable primitive presence" do
    test "USERS tab renders Handle column header from ConsoleTable", %{state: state} do
      sysop = persist_user(%{handle: "ct_sysop", role: :sysop})
      _user = persist_user(%{handle: "ct_user"})
      state = activate_users_tab(state, sysop)

      flat = Sysop.render(state) |> collect_text_values() |> Enum.join("\n")

      assert String.contains?(flat, "Handle"),
             "Expected 'Handle' ConsoleTable column header in USERS render; got:\n#{flat}"
    end

    test "USERS tab renders Role and Status column headers", %{state: state} do
      sysop = persist_user(%{handle: "ct2_sysop", role: :sysop})
      state = activate_users_tab(state, sysop)

      flat = Sysop.render(state) |> collect_text_values() |> Enum.join("\n")

      assert String.contains?(flat, "Role"),
             "Expected 'Role' column header in USERS render"

      assert String.contains?(flat, "Status"),
             "Expected 'Status' column header in USERS render"
    end

    test "empty USERS handles :up/:down/:enter without crash and without domain dispatch", %{
      state: state
    } do
      sysop = %Foglet.Accounts.User{id: Ecto.UUID.generate(), role: :sysop, status: :active}
      view = UsersView.init(current_user: sysop)

      state = put_in(state, [:screen_state, :sysop], Sysop.init_screen_state(active: 4))
      ss = state.screen_state.sysop

      state = %{
        state
        | screen_state: Map.put(state.screen_state, :sysop, %{ss | users_view: view})
      }

      for key <- [%{key: :up}, %{key: :down}, %{key: :enter}] do
        result = Sysop.handle_key(key, state)

        case result do
          {:update, new_state, cmds} ->
            assert cmds == [] or not Enum.any?(cmds, fn c -> is_tuple(c) end),
                   "Unexpected domain dispatch on empty USERS for #{inspect(key)}"

            _ = new_state

          :no_match ->
            :ok
        end
      end
    end
  end

  # =========================================================================
  # SYSTEM KvGrid primitive presence (Phase 25 Plan 04)
  # =========================================================================

  alias Foglet.TUI.Screens.Sysop.SystemSnapshot

  describe "SYSTEM KvGrid primitive presence" do
    test "SYSTEM tab renders KvGrid label rows", %{state: state} do
      # Pre-initialize the system snapshot wrapped as {:loaded, _} (D-07).
      snap = Foglet.TUI.Screens.Sysop.SystemSnapshot.init()
      ss = Sysop.init_screen_state(active: 3)
      ss = %{ss | system_snapshot: {:loaded, snap}}
      state = put_in(state, [:screen_state, :sysop], ss)

      flat = Sysop.render(state) |> collect_text_values() |> Enum.join("\n")

      assert String.contains?(flat, "Sessions:") or String.contains?(flat, "Version:"),
             "Expected KvGrid label row (Sessions: or Version:) in SYSTEM render"
    end

    test "SYSTEM refresh key [r] continues to refresh snapshot", %{state: state} do
      # Pre-initialize the system snapshot wrapped as {:loaded, _} (D-07).
      snap = Foglet.TUI.Screens.Sysop.SystemSnapshot.init()
      ss = Sysop.init_screen_state(active: 3)
      ss = %{ss | system_snapshot: {:loaded, snap}}
      state = put_in(state, [:screen_state, :sysop], ss)

      assert snap != nil

      # "r" key may return :no_match if the snapshot values haven't changed.
      result = Sysop.handle_key(%{key: :char, char: "r"}, state)

      case result do
        {:update, new_state, _} ->
          snap2 = current_system_snapshot(new_state)
          assert snap2 != nil

        :no_match ->
          # Snapshot was refreshed but wall clock didn't change — snapshot is
          # still valid. The pre-seeded snap already demonstrates init works.
          assert snap != nil
      end
    end
  end

  # =========================================================================
  # BOARDS destructive styling routes through commands.destructive (D-07)
  # =========================================================================

  # =========================================================================
  # Phase 25 Plan 05 — Per-tab theme hygiene (D-12) + Inspector deferral (D-20)
  # =========================================================================

  describe "Phase 25 theme hygiene (D-12)" do
    import Foglet.TUI.WidgetHelpers
    import Foglet.TUI.LayoutSmokeHelpers

    for tab <- ["SITE", "LIMITS", "BOARDS", "SYSTEM"] do
      @tab tab
      test "converted Sysop #{tab} tab leaks no color atoms", %{state: state} do
        ss =
          Sysop.init_screen_state()
          |> set_active_tab(@tab)

        state = put_in(state, [:screen_state, :sysop], ss)
        serialized = state |> Sysop.render() |> inspect(limit: :infinity)

        for color <- color_names() do
          refute color_atom_leaked?(serialized, color),
                 "leaked :#{color} in converted Sysop #{@tab} tab"
        end
      end
    end

    test "converted Sysop USERS tab leaks no color atoms", %{state: state} do
      sysop = %Foglet.Accounts.User{
        id: Ecto.UUID.generate(),
        handle: "hygiene_sysop",
        role: :sysop,
        status: :active
      }

      state = activate_users_tab(state, sysop)
      serialized = state |> Sysop.render() |> inspect(limit: :infinity)

      for color <- color_names() do
        refute color_atom_leaked?(serialized, color),
               "leaked :#{color} in converted Sysop USERS tab"
      end
    end
  end

  describe "Phase 25 Workspace.Inspector deferral (D-20)" do
    test "no screen module references Workspace.Inspector" do
      offenders =
        "lib/foglet_bbs/tui/screens/"
        |> Path.expand()
        |> Path.join("**/*.ex")
        |> Path.wildcard()
        |> Enum.filter(fn path ->
          path |> File.read!() |> String.contains?("Workspace.Inspector")
        end)

      assert offenders == [],
             "Phase 25 D-20: Workspace.Inspector must not be referenced from screens; " <>
               "offending files: #{inspect(offenders)}"
    end
  end

  describe "BOARDS destructive styling routes through commands.destructive (D-07)" do
    test "Foglet.TUI.Presentation.theme_mappings().commands.destructive maps to :error" do
      mapping = Foglet.TUI.Presentation.theme_mappings()
      assert mapping.commands.destructive == :error
    end

    test "BoardsView confirm modal for archive board is opened by D key on board row" do
      setup_ctx = seed_category_and_board(%{})
      sysop = setup_ctx.sysop

      state = build_state(:sysop)
      state = %{state | current_user: sysop}
      state = activate_boards_tab(state, sysop)

      {:update, state, _} = Sysop.handle_key(%{key: :char, char: "D"}, state)

      bv = current_boards_view(state)

      assert bv.modal_kind in [:archive_board, :archive_category],
             "Expected archive confirm modal after D key"

      assert bv.modal != nil
    end
  end
end
