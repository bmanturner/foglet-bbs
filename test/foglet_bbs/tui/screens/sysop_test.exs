defmodule Foglet.TUI.Screens.SysopTest do
  # async: false because SITE/LIMITS tabs lazy-init their submodules which
  # call Foglet.Config.get!/1 — the :foglet_config ETS table is process-global.
  use FogletBbs.DataCase, async: false

  import Foglet.TUI.RenderHelpers

  alias Foglet.Config
  alias Foglet.Config.Schema
  alias Foglet.TUI.Screens.Sysop
  alias Foglet.TUI.Screens.Sysop.State, as: SysopState

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

  describe "render/1" do
    setup %{state: state} do
      state = put_in(state, [:screen_state, :sysop], Sysop.init_screen_state())
      %{state: state}
    end

    test "does not crash with default screen state", %{state: state} do
      assert _ = Sysop.render(state)
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
        ss = Sysop.init_screen_state(current_user: state.current_user, session_context: state.session_context)

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
        ss = Sysop.init_screen_state(current_user: state.current_user, session_context: state.session_context)

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

    test "advances through all five tabs with Right arrow (0→1→2→3→4, then wraps)", %{
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

      # Past the last tab, the Raxol Tabs widget wraps back to 0; handle_key
      # simply reflects that (WR-03: no wrap-detection heuristic). Accept either
      # clamp-at-4 or wrap-to-0 so this test survives a future widget-behavior
      # change without silently re-introducing the "lie about :no_match" hack.
      {_state5, tab5} =
        case Sysop.handle_key(%{key: :right}, state4) do
          {:update, s, _} -> {s, s.screen_state.sysop.active_tab}
          :no_match -> {state4, state4.screen_state.sysop.active_tab}
        end

      assert tab1 == 1
      assert tab2 == 2
      assert tab3 == 3
      assert tab4 == 4
      assert tab5 in [0, 4]
    end

    test "digit '5' jumps to USERS tab (index 4)", %{state: state} do
      {:update, new_state, _cmds} = Sysop.handle_key(%{key: :char, char: "5"}, state)
      assert new_state.screen_state.sysop.active_tab == 4
    end

    test "digit '6' jumps to INVITES tab when visible", %{state: state} do
      state = with_invite_policy(state, "sysop_only")
      ss = Sysop.init_screen_state(current_user: state.current_user, session_context: state.session_context)
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
      state =
        state
        |> put_in([:screen_state, :sysop], Sysop.init_screen_state(active: 2))

      %{state: state}
    end

    test "renders every @limits_keys description", %{state: state} do
      {:update, state, _} = Sysop.handle_key(%{key: :tab}, state)

      flat = Sysop.render(state) |> collect_text_values() |> Enum.join("\n")

      for key <- Foglet.TUI.Screens.Sysop.LimitsForm.limits_keys() do
        {:ok, spec} = Schema.fetch_spec(key)

        assert String.contains?(flat, spec.description),
               "Expected description for #{inspect(key)} in LIMITS render output"
      end
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
  defp put_boards_view(state, bv) do
    ss = state.screen_state.sysop
    new_ss = %{ss | boards_view: bv}
    %{state | screen_state: Map.put(state.screen_state, :sysop, new_ss)}
  end

  defp activate_boards_tab(state, sysop) do
    # BOARDS is index 1.
    state = %{state | current_user: sysop}
    state = put_in(state, [:screen_state, :sysop], Sysop.init_screen_state(active: 1))
    # Lazy-init BoardsView via a :down event (which BoardsView handles as
    # selection-index rotate — ensures apply_submodule_result sees a state
    # delta and writes the freshly-initialized submodule back).
    {:update, state, _} = Sysop.handle_key(%{key: :down}, state)
    # Rewind the rotation we just caused so tests see selection_index == 0.
    ss = state.screen_state.sysop
    bv = ss.boards_view
    bv = %{bv | selection_index: 0}
    new_ss = %{ss | boards_view: bv}
    %{state | screen_state: Map.put(state.screen_state, :sysop, new_ss)}
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

      bv = state.screen_state.sysop.boards_view
      assert %ModalForm{} = bv.modal
      field_names = Enum.map(bv.modal.fields, & &1.name)

      assert field_names == [
               :slug,
               :name,
               :description,
               :category_id,
               :postable_by,
               :default_subscription
             ]

      assert bv.modal_kind == :create_board
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
      bv = state.screen_state.sysop.boards_view

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
      bv = state.screen_state.sysop.boards_view
      bv = %{bv | modal: %{bv.modal | focus_index: n - 1}}
      state = put_boards_view(state, bv)

      {:update, new_state, _} = Sysop.handle_key(%{key: :enter}, state)

      new_bv = new_state.screen_state.sysop.boards_view
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
      bv = state.screen_state.sysop.boards_view

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

      new_bv = new_state.screen_state.sysop.boards_view
      assert %ModalForm{} = new_bv.modal, "Modal must stay open on validation error"

      assert Map.has_key?(new_bv.modal.errors, :name),
             "Errors must include :name — got #{inspect(new_bv.modal.errors)}"
    end

    test "Pitfall 5 — j/k navigation no-op while modal open", %{state: state, sysop: sysop} do
      state = activate_boards_tab(state, sysop)
      {:update, state, _} = Sysop.handle_key(%{key: :char, char: "n"}, state)

      bv_before = state.screen_state.sysop.boards_view
      idx_before = bv_before.selection_index

      # j while a Modal.Form is open must not advance the selection.
      result = Sysop.handle_key(%{key: :char, char: "j"}, state)

      new_state =
        case result do
          {:update, s, _} -> s
          :no_match -> state
        end

      new_bv = new_state.screen_state.sysop.boards_view
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

      bv = state.screen_state.sysop.boards_view
      assert %Foglet.TUI.Modal{type: :confirm} = bv.modal
      assert bv.modal_kind == :archive_board

      {:update, new_state, _} = Sysop.handle_key(%{key: :char, char: "Y"}, state)

      new_bv = new_state.screen_state.sysop.boards_view
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

      bv = state.screen_state.sysop.boards_view
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

      new_bv = new_state.screen_state.sysop.boards_view
      assert new_bv.modal == nil
      assert Enum.any?(new_bv.categories, &(&1.name == "Announcements"))
    end
  end

  # =========================================================================
  # SYSTEM tab tests (Plan 02-05, SYSO-04)
  # =========================================================================

  alias Foglet.TUI.Screens.Sysop.SystemSnapshot

  defp activate_system_tab(state) do
    ss = Sysop.init_screen_state(active: 3)
    ss = %{ss | system_snapshot: SystemSnapshot.init([])}
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

    test "r refreshes the snapshot", %{state: state} do
      state = activate_system_tab(state)
      old = state.screen_state.sysop.system_snapshot
      # Sleep a touch so uptime_ms strictly advances.
      Process.sleep(5)
      {:update, state2, _} = Sysop.handle_key(%{key: :char, char: "r"}, state)
      new = state2.screen_state.sysop.system_snapshot

      assert new.snapshot.uptime_ms >= old.snapshot.uptime_ms,
             "Refreshed uptime must not regress"
    end

    test "non-r keys do not mutate the snapshot", %{state: state} do
      state = activate_system_tab(state)
      old = state.screen_state.sysop.system_snapshot

      # `j` is not a tab-nav key; Tabs widget ignores it; delegated to
      # SystemSnapshot which is a no-op for non-`r` chars.
      result = Sysop.handle_key(%{key: :char, char: "j"}, state)

      new_state =
        case result do
          {:update, s, _} -> s
          :no_match -> state
        end

      new = new_state.screen_state.sysop.system_snapshot
      assert new == old
    end
  end

  describe "BOARDS tab forbidden routing (SYSO-03, D-24)" do
    setup [:seed_category_and_board]

    test ":forbidden from create_board routes to error modal + :main_menu", %{
      state: state,
      category: category
    } do
      # Non-sysop actor (nil trips authorization immediately).
      state = %{state | current_user: nil}
      state = put_in(state, [:screen_state, :sysop], Sysop.init_screen_state(active: 1))
      {:update, state, _} = Sysop.handle_key(%{key: :down}, state)

      bv = state.screen_state.sysop.boards_view

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
  end
end
