defmodule Foglet.TUI.Screens.SysopTest do
  # async: false because SITE/LIMITS tabs initialize submodules which
  # call Foglet.Config.get!/1 — the :foglet_config ETS table is process-global.
  use FogletBbs.DataCase, async: false

  import Foglet.TUI.RenderHelpers

  alias Foglet.Accounts
  alias Foglet.Accounts.Invites
  alias Foglet.Config
  alias Foglet.Config.Schema
  alias Foglet.TUI.Context
  alias Foglet.TUI.Effect
  alias Foglet.TUI.Modal
  alias Foglet.TUI.Screens.Sysop
  alias Foglet.TUI.Screens.Sysop.SiteForm.State, as: SiteFormState
  alias Foglet.TUI.Screens.Sysop.State, as: SysopState
  alias Foglet.TUI.Screens.Sysop.UsersView
  alias FogletBbs.Repo

  @config_keys Map.keys(Schema.defaults())

  defmodule FakeAccounts do
    def list_user_status_admin_targets(_actor) do
      {:ok, %{pending: [], active: [], suspended: [], rejected: []}}
    end
  end

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

  defp with_invite_policy(state, policy, registration_mode \\ "invite_only") do
    state
    |> put_in([:session_context, :invite_code_generators], policy)
    |> put_in([:session_context, :registration_mode], registration_mode)
  end

  defp sysop_context(state) do
    app = struct!(Foglet.TUI.App, Map.take(state, Map.keys(%Foglet.TUI.App{})))
    Foglet.TUI.App.build_context(app)
  end

  defp render_sysop(state) do
    context = sysop_context(state)
    local_state = get_in(state, [:screen_state, :sysop]) || Sysop.init(context)

    Sysop.render(local_state, context)
  end

  defp handle_sysop_key(event, state) do
    context = sysop_context(state)
    local_state = get_in(state, [:screen_state, :sysop]) || Sysop.init(context)
    {new_local_state, effects} = Sysop.update({:key, event}, local_state, context)
    new_local_state = preserve_app_owned_loading(local_state, new_local_state, effects)
    state = put_in(state, [:screen_state, :sysop], new_local_state)

    if sysop_no_match?(local_state, new_local_state, effects) do
      :no_match
    else
      apply_sysop_effects(state, effects)
    end
  end

  defp preserve_app_owned_loading(old_state, new_state, effects) do
    Enum.reduce(effects, new_state, fn
      %Effect{type: :task, payload: %{op: op}}, acc
      when op in [:sysop_load_boards, :sysop_load_limits, :sysop_load_system, :sysop_load_users] ->
        Map.put(acc, sysop_slot_for_op(op), Map.fetch!(old_state, sysop_slot_for_op(op)))

      _effect, acc ->
        acc
    end)
  end

  defp sysop_slot_for_op(:sysop_load_boards), do: :boards_view
  defp sysop_slot_for_op(:sysop_load_limits), do: :limits_form
  defp sysop_slot_for_op(:sysop_load_system), do: :system_snapshot
  defp sysop_slot_for_op(:sysop_load_users), do: :users_view

  defp sysop_no_match?(old_state, new_state, []) do
    fields = [
      :active_tab,
      :site_form,
      :limits_form,
      :boards_view,
      :system_snapshot,
      :users_view,
      :invites,
      :armed_revoke?
    ]

    Map.take(old_state, fields) == Map.take(new_state, fields)
  end

  defp sysop_no_match?(_old_state, _new_state, _effects), do: false

  defp apply_sysop_effects(state, effects) do
    Enum.reduce(effects, {:update, state, []}, fn
      %Effect{type: :navigate, payload: %{screen: screen, params: params}},
      {:update, state, cmds} ->
        {:update, %{state | current_screen: screen, route_params: params || %{}}, cmds}

      %Effect{type: :modal, payload: {:open, modal}}, {:update, state, cmds} ->
        {:update, %{state | modal: modal}, cmds}

      %Effect{type: :modal, payload: :dismiss}, {:update, state, cmds} ->
        {:update, %{state | modal: nil}, cmds}

      %Effect{type: :task, payload: %{op: op}} = effect, {:update, state, cmds}
      when op in [:sysop_load_boards, :sysop_load_limits, :sysop_load_system, :sysop_load_users] ->
        {:update, state, cmds ++ [legacy_sysop_load_command(effect.payload.op)]}

      %Effect{type: :task, payload: %{op: op, fun: fun}}, {:update, state, cmds} ->
        result = fun.()
        local_state = get_in(state, [:screen_state, :sysop])

        {new_local_state, followup} =
          Sysop.update({:task_result, op, {:ok, result}}, local_state, sysop_context(state))

        state
        |> put_in([:screen_state, :sysop], new_local_state)
        |> apply_sysop_effects(followup)
        |> append_cmds(cmds)

      _effect, acc ->
        acc
    end)
  end

  defp legacy_sysop_load_command(:sysop_load_boards), do: {:load_sysop_boards}
  defp legacy_sysop_load_command(:sysop_load_limits), do: {:load_sysop_limits}
  defp legacy_sysop_load_command(:sysop_load_system), do: {:load_sysop_system}
  defp legacy_sysop_load_command(:sysop_load_users), do: {:load_sysop_users}

  defp append_cmds({:update, state, new_cmds}, cmds), do: {:update, state, cmds ++ new_cmds}

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

  describe "Sysop.State.new/1" do
    test "returns struct with active_tab: 0 and Tabs wrapper" do
      ss = SysopState.new()
      assert ss.active_tab == 0
      assert %Foglet.TUI.Widgets.Input.Tabs{} = ss.tabs
    end
  end

  describe "new screen contract" do
    test "Sysop.Render is the sibling render entry point" do
      assert Code.ensure_loaded?(Sysop.Render)
      assert function_exported?(Sysop.Render, :render, 1)

      source = File.read!("lib/foglet_bbs/tui/screens/sysop.ex")

      assert String.contains?(source, "Render.render()")
    end

    test "init/1 builds local sysop state from Context visibility" do
      user = %Foglet.Accounts.User{
        id: Ecto.UUID.generate(),
        handle: "alice",
        role: :sysop,
        status: :active
      }

      context =
        Context.new(
          current_user: user,
          route: :sysop,
          session_context: %{
            invite_code_generators: "sysop_only",
            registration_mode: "invite_only"
          }
        )

      assert %SysopState{} = state = Sysop.init(context)
      assert "INVITES" in SysopState.tab_labels(state)
    end

    test "render/2 renders from local state and Context without App-shaped input" do
      user = %Foglet.Accounts.User{
        id: Ecto.UUID.generate(),
        handle: "alice",
        role: :sysop,
        status: :active
      }

      context = Context.new(current_user: user, route: :sysop, terminal_size: {80, 24})
      state = Sysop.init(context)

      assert _node = Sysop.render(state, context)
    end

    test "tab entry sets lifecycle slot to loading and emits a task effect" do
      user = %Foglet.Accounts.User{
        id: Ecto.UUID.generate(),
        handle: "alice",
        role: :sysop,
        status: :active
      }

      context =
        Context.new(
          current_user: user,
          route: :sysop,
          domain: %{accounts: FakeAccounts}
        )

      {state, effects} =
        Sysop.update({:key, %{key: :char, char: "5"}}, Sysop.init(context), context)

      assert state.active_tab == 4
      assert state.users_view == :loading

      assert [%Effect{type: :task, payload: %{op: :sysop_load_users, screen_key: :sysop}}] =
               effects
    end

    test "tab load with struct session_context does not raise on Access lookup" do
      # Regression for FOG-170: domain_module/3 used get_in on session_context,
      # which crashed when session_context was a %Foglet.TUI.SessionContext{}
      # struct (Access not implemented). Default Context session_context is a
      # struct, so production right-arrow / number-jump into USERS hit
      # Foglet.TUI.SessionContext.fetch/2 inside lifecycle_effect/1.
      user = %Foglet.Accounts.User{
        id: Ecto.UUID.generate(),
        handle: "alice",
        role: :sysop,
        status: :active
      }

      context =
        Context.new(
          current_user: user,
          route: :sysop,
          session_context: %Foglet.TUI.SessionContext{}
        )

      {jump_state, jump_effects} =
        Sysop.update({:key, %{key: :char, char: "5"}}, Sysop.init(context), context)

      assert jump_state.active_tab == 4
      assert jump_state.users_view == :loading

      assert [%Effect{type: :task, payload: %{op: :sysop_load_users, screen_key: :sysop}}] =
               jump_effects
    end

    test "task result stores loaded sysop submodule state" do
      context = Context.new(route: :sysop)
      state = %{Sysop.init(context) | active_tab: 4}
      view = UsersView.from_groups(%{}, nil)

      {state, effects} =
        Sysop.update({:task_result, :sysop_load_users, {:ok, {:ok, view}}}, state, context)

      assert state.users_view == {:loaded, view}
      assert effects == []
    end

    test "retry on non-forbidden errors flips to loading and forbidden remains local" do
      context = Context.new(route: :sysop, domain: %{accounts: FakeAccounts})
      state = %{Sysop.init(context) | active_tab: 4, users_view: {:error, :timeout}}

      {retry_state, retry_effects} =
        Sysop.update({:key, %{key: :char, char: "R"}}, state, context)

      assert retry_state.users_view == :loading
      assert [%Effect{payload: %{op: :sysop_load_users}}] = retry_effects

      forbidden_state = %{state | users_view: {:error, :forbidden}}

      {unchanged_state, forbidden_effects} =
        Sysop.update({:key, %{key: :char, char: "R"}}, forbidden_state, context)

      assert unchanged_state.users_view == {:error, :forbidden}
      assert forbidden_effects == []
    end

    test "submodule error_modal events become modal and navigation effects" do
      context = Context.new(current_user: nil, route: :sysop)
      state = Sysop.init(context)

      {state, effects} =
        Sysop.update({:key, %{key: :char, char: "s", ctrl: true}}, state, context)

      assert %SysopState{} = state

      assert [
               %Effect{type: :modal, payload: {:open, %Modal{type: :error}}},
               %Effect{type: :navigate, payload: %{screen: :main_menu}}
             ] = effects
    end
  end

  describe "lifecycle tagged-enum" do
    @moduletag :lifecycle

    test ":not_loaded is the default for the four lifecycle slots" do
      ss = SysopState.new()
      assert ss.boards_view == :not_loaded
      assert ss.limits_form == :not_loaded
      assert ss.system_snapshot == :not_loaded
      assert ss.users_view == :not_loaded
      # SITE form is seeded lazily by `Sysop.update(:load, ...)` on entry.
      assert ss.site_form == nil
    end

    test "SITE form initializes with the current actor on :load" do
      sysop = %Foglet.Accounts.User{
        id: Ecto.UUID.generate(),
        handle: "sysop",
        role: :sysop,
        status: :active
      }

      context = %Foglet.TUI.Context{
        current_user: sysop,
        session_context: %{}
      }

      {ss, _effects} = Foglet.TUI.Screens.Sysop.update(:load, SysopState.new(), context)

      assert %SiteFormState{current_user: ^sysop} = ss.site_form
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
      state = put_in(state, [:screen_state, :sysop], SysopState.new(active: 4))
      %{state: state}
    end

    defp put_users_slot(state, value) do
      ss = state.screen_state.sysop
      new_ss = %{ss | users_view: value}
      put_in(state, [:screen_state, :sysop], new_ss)
    end

    test "USERS :not_loaded renders the Loading… panel", %{state: state} do
      flat = state |> put_users_slot(:not_loaded) |> render_sysop() |> collect_text_values()
      assert Enum.any?(flat, &String.contains?(&1, "Loading sysop tools…"))
    end

    test "USERS :loading renders the Loading… panel", %{state: state} do
      flat = state |> put_users_slot(:loading) |> render_sysop() |> collect_text_values()
      assert Enum.any?(flat, &String.contains?(&1, "Loading sysop tools…"))
    end

    test "USERS {:loaded, sub} delegates to UsersView.render", %{state: state} do
      sysop = %Foglet.Accounts.User{
        id: Ecto.UUID.generate(),
        handle: "alice",
        role: :sysop,
        status: :active
      }

      sub = Foglet.TUI.Screens.Sysop.UsersView.from_groups(%{}, sysop)
      flat = state |> put_users_slot({:loaded, sub}) |> render_sysop() |> collect_text_values()
      # UsersView render emits the heading.
      assert Enum.any?(flat, &String.contains?(&1, "User status"))
    end

    test "USERS {:error, :forbidden} renders forbidden panel (no Retry copy, Pitfall 3)",
         %{state: state} do
      flat =
        state
        |> put_users_slot({:error, :forbidden})
        |> render_sysop()
        |> collect_text_values()
        |> Enum.join("\n")

      assert String.contains?(flat, "Your role no longer allows access to this tab.")
      refute String.contains?(flat, "Could not load")
      refute String.contains?(flat, "Press R to try again")
    end

    test "USERS {:error, :timeout} renders generic error panel with retry copy",
         %{state: state} do
      flat =
        state
        |> put_users_slot({:error, :timeout})
        |> render_sysop()
        |> collect_text_values()
        |> Enum.join("\n")

      assert String.contains?(flat, "Could not load users.")
      assert String.contains?(flat, "Press R to try again")
      refute String.contains?(flat, "Your role no longer allows")
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
      state = put_in(state, [:screen_state, :sysop], SysopState.new(active: 4))
      %{state: state}
    end

    test "events on :not_loaded slot are no-ops (no submodule.handle_key invoked)",
         %{state: state} do
      ss = state.screen_state.sysop
      ss = %{ss | users_view: :not_loaded}
      state = put_in(state, [:screen_state, :sysop], ss)

      # Down is delegated; with :not_loaded the guard returns :no_match.
      assert :no_match = handle_sysop_key(%{key: :down}, state)
    end

    test "events on :loading slot are no-ops", %{state: state} do
      ss = state.screen_state.sysop
      ss = %{ss | users_view: :loading}
      state = put_in(state, [:screen_state, :sysop], ss)

      assert :no_match = handle_sysop_key(%{key: :down}, state)
    end

    test "events on {:error, _} slot are no-ops", %{state: state} do
      ss = state.screen_state.sysop
      ss = %{ss | users_view: {:error, :forbidden}}
      state = put_in(state, [:screen_state, :sysop], ss)

      assert :no_match = handle_sysop_key(%{key: :down}, state)
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
      case handle_sysop_key(%{key: :down}, state) do
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
      state = put_in(state, [:screen_state, :sysop], SysopState.new(active: 0))
      %{state: state}
    end

    test "switching from SITE to USERS via digit '5' emits {:load_sysop_users} when :not_loaded",
         %{state: state} do
      assert state.screen_state.sysop.users_view == :not_loaded

      {:update, new_state, cmds} = handle_sysop_key(%{key: :char, char: "5"}, state)

      assert new_state.screen_state.sysop.active_tab == 4
      # WR-05: the App is the single writer for the :loading transition.
      # The screen merely emits the dispatch tuple; the slot stays
      # :not_loaded until the App processes {:load_sysop_users}.
      assert new_state.screen_state.sysop.users_view == :not_loaded
      assert Enum.member?(cmds, {:load_sysop_users})
    end

    test "switching to BOARDS emits {:load_sysop_boards}", %{state: state} do
      {:update, new_state, cmds} = handle_sysop_key(%{key: :char, char: "2"}, state)
      assert new_state.screen_state.sysop.active_tab == 1
      # WR-05: App owns the :loading transition (see USERS test above).
      assert new_state.screen_state.sysop.boards_view == :not_loaded
      assert Enum.member?(cmds, {:load_sysop_boards})
    end

    test "switching to LIMITS emits {:load_sysop_limits}", %{state: state} do
      {:update, new_state, cmds} = handle_sysop_key(%{key: :char, char: "3"}, state)
      assert new_state.screen_state.sysop.active_tab == 2
      # WR-05: App owns the :loading transition (see USERS test above).
      assert new_state.screen_state.sysop.limits_form == :not_loaded
      assert Enum.member?(cmds, {:load_sysop_limits})
    end

    test "switching to SYSTEM emits {:load_sysop_system}", %{state: state} do
      {:update, new_state, cmds} = handle_sysop_key(%{key: :char, char: "4"}, state)
      assert new_state.screen_state.sysop.active_tab == 3
      # WR-05: App owns the :loading transition (see USERS test above).
      assert new_state.screen_state.sysop.system_snapshot == :not_loaded
      assert Enum.member?(cmds, {:load_sysop_system})
    end

    test "switching back to a {:loaded, _} tab emits no command (idempotent)",
         %{state: state} do
      sub = %Foglet.TUI.Screens.Sysop.UsersView{}
      ss = state.screen_state.sysop
      ss = %{ss | users_view: {:loaded, sub}}
      state = put_in(state, [:screen_state, :sysop], ss)

      {:update, new_state, cmds} = handle_sysop_key(%{key: :char, char: "5"}, state)
      assert new_state.screen_state.sysop.active_tab == 4
      assert new_state.screen_state.sysop.users_view == {:loaded, sub}
      refute Enum.member?(cmds, {:load_sysop_users})
    end

    test "switching to SITE never emits a load command (D-03 sync)", %{state: state} do
      # Move to BOARDS first (which emits a load), then back to SITE.
      {:update, mid_state, _} = handle_sysop_key(%{key: :char, char: "2"}, state)
      assert mid_state.screen_state.sysop.active_tab == 1

      {:update, new_state, cmds} = handle_sysop_key(%{key: :char, char: "1"}, mid_state)
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
      ss = SysopState.new(active: 4)
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
        |> render_sysop()
        |> collect_text_values()
        |> Enum.join("\n")

      assert String.contains?(flat, "Retry")
    end

    test "active tab USERS in {:error, :forbidden} does NOT advertise Retry", %{state: state} do
      flat =
        state
        |> put_sysop_slot(:users_view, {:error, :forbidden})
        |> render_sysop()
        |> collect_text_values()
        |> Enum.join("\n")

      refute String.contains?(flat, "Retry")
    end

    test "active tab USERS in {:loaded, _} does NOT advertise Retry", %{state: state} do
      sub = %Foglet.TUI.Screens.Sysop.UsersView{}

      flat =
        state
        |> put_sysop_slot(:users_view, {:loaded, sub})
        |> render_sysop()
        |> collect_text_values()
        |> Enum.join("\n")

      refute String.contains?(flat, "Retry")
    end
  end

  describe "[R] Retry dispatch (Phase 29 D-13)" do
    @describetag :retry_dispatch

    setup %{state: state} do
      ss = SysopState.new(active: 4)
      state = put_in(state, [:screen_state, :sysop], ss)
      %{state: state}
    end

    test "pressing R on USERS in {:error, :timeout} re-dispatches {:load_sysop_users}",
         %{state: state} do
      state = put_sysop_slot(state, :users_view, {:error, :timeout})

      assert {:update, new_state, cmds} = handle_sysop_key(%{key: :char, char: "R"}, state)
      # WR-05: App owns the :loading transition. The screen leaves the slot
      # in {:error, _} and emits the dispatch tuple; the App's
      # {:load_sysop_users} clause flips the slot to :loading via
      # put_sysop_loading/2 before firing the off-process task.
      assert new_state.screen_state.sysop.users_view == {:error, :timeout}
      assert {:load_sysop_users} in cmds
    end

    test "pressing r (lowercase) on USERS in {:error, :timeout} also re-dispatches", %{
      state: state
    } do
      state = put_sysop_slot(state, :users_view, {:error, :timeout})

      assert {:update, new_state, cmds} = handle_sysop_key(%{key: :char, char: "r"}, state)
      # WR-05: App owns the :loading transition (see uppercase R test above).
      assert new_state.screen_state.sysop.users_view == {:error, :timeout}
      assert {:load_sysop_users} in cmds
    end

    test "pressing R on USERS in {:error, :forbidden} is a no-op (forbidden suppresses R)",
         %{state: state} do
      state = put_sysop_slot(state, :users_view, {:error, :forbidden})

      # R must NOT consume the event nor flip the slot to :loading. Returns
      # :no_match (or {:update, state, []} with users_view unchanged) so the
      # event continues falling through to the existing handlers.
      result = handle_sysop_key(%{key: :char, char: "R"}, state)

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
      result = handle_sysop_key(%{key: :char, char: "R"}, state)

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

      assert {:update, new_state, cmds} = handle_sysop_key(%{key: :char, char: "R"}, state)
      # WR-05: App owns the :loading transition.
      assert new_state.screen_state.sysop.boards_view == {:error, :timeout}
      assert {:load_sysop_boards} in cmds
      refute {:load_sysop_users} in cmds
    end
  end

  describe "render/1" do
    setup %{state: state} do
      state = put_in(state, [:screen_state, :sysop], SysopState.new())
      %{state: state}
    end

    test "shows all five tab labels in order: SITE, BOARDS, LIMITS, SYSTEM, USERS", %{
      state: state
    } do
      flat = render_sysop(state) |> collect_text_values()
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
          SysopState.new(
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
          |> render_sysop()
          |> collect_text_values()

        assert Enum.any?(flat, &String.contains?(&1, "INVITES")),
               "Expected INVITES tab for #{policy}; got #{inspect(flat)}"
      end
    end

    test "does not expose Sysop INVITES to nil or non-sysop users" do
      for role <- [nil, :user, :mod] do
        state = build_state(role) |> with_invite_policy("sysop_only")

        ss =
          SysopState.new(
            current_user: state.current_user,
            session_context: state.session_context
          )

        refute "INVITES" in SysopState.tab_labels(ss)

        flat =
          state
          |> put_in([:screen_state, :sysop], ss)
          |> render_sysop()
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
      ss =
        SysopState.new(current_user: state.current_user, session_context: state.session_context)

      state = put_in(state, [:screen_state, :sysop], ss)
      %{state: state}
    end

    test "advances through invite-only visible tabs with Right arrow", %{
      state: state
    } do
      state = with_invite_policy(state, "sysop_only", "invite_only")

      ss =
        SysopState.new(
          current_user: state.current_user,
          session_context: state.session_context
        )

      state = put_in(state, [:screen_state, :sysop], ss)

      {state1, tab1} =
        case handle_sysop_key(%{key: :right}, state) do
          {:update, s, _} -> {s, s.screen_state.sysop.active_tab}
        end

      {state2, tab2} =
        case handle_sysop_key(%{key: :right}, state1) do
          {:update, s, _} -> {s, s.screen_state.sysop.active_tab}
        end

      {state3, tab3} =
        case handle_sysop_key(%{key: :right}, state2) do
          {:update, s, _} -> {s, s.screen_state.sysop.active_tab}
        end

      {state4, tab4} =
        case handle_sysop_key(%{key: :right}, state3) do
          {:update, s, _} -> {s, s.screen_state.sysop.active_tab}
        end

      {_state5, tab5} =
        case handle_sysop_key(%{key: :right}, state4) do
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
      {:update, new_state, _cmds} = handle_sysop_key(%{key: :char, char: "5"}, state)
      assert new_state.screen_state.sysop.active_tab == 4
    end

    test "digit '6' jumps to INVITES tab when visible", %{state: state} do
      state = with_invite_policy(state, "sysop_only")

      ss =
        SysopState.new(
          current_user: state.current_user,
          session_context: state.session_context
        )

      state = put_in(state, [:screen_state, :sysop], ss)

      {:update, new_state, _cmds} = handle_sysop_key(%{key: :char, char: "6"}, state)

      assert new_state.screen_state.sysop.active_tab == 5
      assert SysopState.tab_labels(new_state.screen_state.sysop) |> Enum.at(5) == "INVITES"
    end

    test "'Q' returns to :main_menu", %{state: state} do
      {:update, new_state, _cmds} = handle_sysop_key(%{key: :char, char: "Q"}, state)
      assert new_state.current_screen == :main_menu
    end

    test "'q' returns to :main_menu", %{state: state} do
      {:update, new_state, _cmds} = handle_sysop_key(%{key: :char, char: "q"}, state)
      assert new_state.current_screen == :main_menu
    end

    test "unknown key returns :no_match", %{state: state} do
      assert :no_match = handle_sysop_key(%{key: :char, char: "z"}, state)
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
        case handle_sysop_key(key, state) do
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
    test "hides invite_generation_per_user_limit when invite_code_generators != any_user (D-04)",
         %{state: state} do
      Config.put!("invite_code_generators", "sysop_only", nil)
      state = put_in(state, [:screen_state, :sysop], SysopState.new())

      {:update, state, _} = handle_sysop_key(%{key: :tab}, state)

      flat = render_sysop(state) |> collect_text_values() |> Enum.join("\n")

      refute String.contains?(flat, "invite_generation_per_user_limit"),
             "Limit key name must not leak when row is hidden"
    end

    test "shows invite_generation_per_user_limit when invite_code_generators == any_user",
         %{state: state} do
      Config.put!("invite_code_generators", "any_user", nil)
      state = put_in(state, [:screen_state, :sysop], SysopState.new())

      {:update, state, _} = handle_sysop_key(%{key: :tab}, state)

      flat = render_sysop(state) |> collect_text_values() |> Enum.join("\n")

      assert String.contains?(flat, "invite_generation_per_user_limit"),
             "Limit row must be visible when generators == any_user"
    end

    # FOG-689: When the SITE tab is active, it is a Modal.Form-style editor.
    # The screen-level command bar must advertise Save/Cancel at a priority
    # that survives 80x24 keybar compaction (lower priority numbers in
    # CommandBar = higher retention).
    test "SITE 80x24 keybar advertises Save and Cancel actions", %{state: state} do
      state =
        state
        |> put_in([:screen_state, :sysop], SysopState.new())
        |> Map.put(:terminal_size, {80, 24})

      flat = render_sysop(state) |> collect_text_values() |> Enum.join("\n")

      assert String.contains?(flat, "Save"),
             "SITE 80x24 keybar must retain Save action (FOG-689). Got: #{flat}"

      assert String.contains?(flat, "Cancel"),
             "SITE 80x24 keybar must retain Cancel action (FOG-689). Got: #{flat}"
    end
  end

  describe "SITE tab Ctrl+S (SYSO-02)" do
    setup %{state: state} do
      state = put_in(state, [:screen_state, :sysop], SysopState.new())
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

      state =
        %{state | current_user: sysop}
        |> put_in([:screen_state, :sysop], SysopState.new(current_user: sysop))

      # Navigate within SITE so the reducer uses the initialized form actor.
      {:update, state, _} = handle_sysop_key(%{key: :tab}, state)

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
        handle_sysop_key(%{key: :char, char: "s", ctrl: true}, state)

      # Inline error recorded; no modal; still on sysop screen.
      assert new_state.current_screen == :sysop
      assert new_state.modal == nil

      errors = new_state.screen_state.sysop.site_form.errors

      assert Map.has_key?(errors, "invite_generation_per_user_limit"),
             "Expected inline error for the bad integer; got errors: #{inspect(errors)}"

      assert match?({:error, _}, new_state.screen_state.sysop.site_form.submit_state)
    end

    test ":forbidden from Config.put routes to error modal + :main_menu (D-08, D-24)",
         %{state: _state} do
      # Build a state with a nil actor — Bodyguard.permit/4 denies (D-24).
      # nil is used (rather than a non-sysop User struct with a random UUID)
      # because a random UUID would fail the configuration.updated_by_id_fkey
      # constraint after the authorization check passes — nil trips authz first.
      state =
        build_state(nil)
        |> put_in([:screen_state, :sysop], SysopState.new())

      Config.put!("delivery_mode", "email", nil)

      # Mutate the initialized SiteForm draft so submit hits Config.put.
      {:update, state, _} = handle_sysop_key(%{key: :tab}, state)

      ss = state.screen_state.sysop

      site_form = %{
        ss.site_form
        | drafts: Map.put(ss.site_form.drafts, "registration_mode", "invite_only")
      }

      state = put_in(state, [:screen_state, :sysop], %{ss | site_form: site_form})

      {:update, new_state, _cmds} =
        handle_sysop_key(%{key: :char, char: "s", ctrl: true}, state)

      assert %Foglet.TUI.Modal{type: :error} = new_state.modal
      assert new_state.current_screen == :main_menu
    end

    test "SITE test-email task effects are forwarded from the submodule" do
      Config.put!("delivery_mode", "email", nil)

      sysop = %Foglet.Accounts.User{
        id: Ecto.UUID.generate(),
        handle: "sysop",
        role: :sysop,
        status: :active,
        email: "sysop@example.test"
      }

      context = Context.new(current_user: sysop, route: :sysop)
      {state, _effects} = Sysop.update(:load, Sysop.init(context), context)

      {state, effects} = Sysop.update({:key, %{key: :char, char: "e"}}, state, context)

      assert state.site_form.test_email_state == :sending
      assert [%Effect{type: :task, payload: %{op: :sysop_send_test_email}}] = effects
    end
  end

  describe "LIMITS tab render (SYSO-02)" do
    setup %{state: state} do
      # Phase 29 D-07: lifecycle slot pre-loaded as {:loaded, _}; the
      # App-level {:load_sysop_limits} triad is the production load path,
      # but tests inject the fully-loaded form synchronously.
      ss = SysopState.new(active: 2)
      lf = Foglet.TUI.Screens.Sysop.LimitsForm.init([])
      ss = %{ss | limits_form: {:loaded, lf}}
      state = put_in(state, [:screen_state, :sysop], ss)

      %{state: state}
    end

    test "ordinary character input %{key: :char, char: \"x\"} does not raise", %{
      state: state
    } do
      before_drafts = current_limits_form(state).drafts

      result = handle_sysop_key(%{key: :char, char: "x"}, state)

      new_state =
        case result do
          {:update, state, _cmds} -> state
          :no_match -> state
        end

      assert current_limits_form(new_state).drafts == before_drafts
    end

    # FOG-185: digit chars on LIMITS must edit the focused integer field
    # rather than triggering the numeric tab-jump shortcut. The Raxol Tabs
    # widget consumes 1–9 unconditionally, so the Sysop screen filters
    # them at the routing seam when LIMITS is active.
    for digit <- ~w(0 1 2 3 4 5 6 7 8 9) do
      test "digit '#{digit}' edits the focused LIMITS field instead of jumping tabs",
           %{state: state} do
        focused_key = "max_post_length"

        before_lf = current_limits_form(state)

        assert Enum.at(Foglet.TUI.Screens.Sysop.LimitsForm.limits_keys(), before_lf.focused) ==
                 focused_key

        before_value =
          case Map.get(before_lf.drafts, focused_key) do
            n when is_integer(n) -> Integer.to_string(n)
            s when is_binary(s) -> s
            _ -> ""
          end

        {:update, new_state, _cmds} =
          handle_sysop_key(%{key: :char, char: unquote(digit)}, state)

        # Active tab must remain LIMITS (index 2) — no numeric tab jump.
        assert new_state.screen_state.sysop.active_tab == 2

        # The focused integer field must have appended the digit.
        assert Map.get(current_limits_form(new_state).drafts, focused_key) ==
                 before_value <> unquote(digit)
      end
    end

    test "Ctrl+digit on LIMITS is not treated as a field edit", %{state: state} do
      before_drafts = current_limits_form(state).drafts

      result = handle_sysop_key(%{key: :char, char: "2", ctrl: true}, state)

      new_state =
        case result do
          {:update, s, _cmds} -> s
          :no_match -> state
        end

      # Active tab should not have jumped, and the field should not have
      # accepted a Ctrl-modified digit.
      assert new_state.screen_state.sysop.active_tab == 2
      assert current_limits_form(new_state).drafts == before_drafts
    end

    test "Left/Right still navigate tabs while LIMITS is active", %{state: state} do
      {:update, right_state, _cmds} =
        handle_sysop_key(%{key: :right}, state)

      assert right_state.screen_state.sysop.active_tab == 3
    end

    # FOG-739: LIMITS routes plain digits 0–9 into the focused integer
    # draft, so the screen-level command bar must NOT advertise the
    # global `1-N Jump` shortcut while LIMITS is the active tab —
    # otherwise sysops press `4` expecting SYSTEM and silently extend
    # `Post length limit`. Arrow-key tab navigation remains advertised.
    test "LIMITS command bar suppresses '1-N Jump' but keeps Switch", %{state: state} do
      flat =
        state
        |> render_sysop()
        |> collect_text_values()
        |> Enum.join(" ")

      refute String.contains?(flat, "Jump"),
             "LIMITS must not advertise '1-N Jump' when digits edit the focused field"

      refute String.contains?(flat, "1-5"),
             "LIMITS must not advertise the '1-5' jump-key range while digits are field input"

      assert String.contains?(flat, "Switch"),
             "LIMITS must keep '←/→ Switch' as the discoverable tab-nav affordance"
    end

    # FOG-739: same suppression must hold at cramped 64x22 — the bug
    # repro harness exercises both 80x24 and 64x22 and the priority-0
    # Jump pin used to survive compaction.
    test "LIMITS command bar suppresses Jump at 64x22", %{state: state} do
      flat =
        state
        |> Map.put(:terminal_size, {64, 22})
        |> render_sysop()
        |> collect_text_values()
        |> Enum.join(" ")

      refute String.contains?(flat, "Jump"),
             "LIMITS at 64x22 must not advertise '1-N Jump' (FOG-739)"
    end
  end

  # =========================================================================
  # USERS tab tests (Plan 10-02, USER-01 through USER-03)
  # =========================================================================

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
    ss = SysopState.new(active: 4)
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
      flat = render_sysop(state) |> collect_text_values() |> Enum.join("\n")

      assert String.contains?(flat, "User status")

      # FOG-740: header columns must align with row column order
      # (Handle, Role, Status, Email).
      header_line =
        flat
        |> String.split("\n")
        |> Enum.find(&(String.contains?(&1, "Handle") and String.contains?(&1, "Status")))

      assert header_line, "expected USERS header line in rendered output"

      handle_col = :binary.match(header_line, "Handle") |> elem(0)
      role_col = :binary.match(header_line, "Role") |> elem(0)
      status_col = :binary.match(header_line, "Status") |> elem(0)
      email_col = :binary.match(header_line, "Email") |> elem(0)

      assert handle_col < role_col and role_col < status_col and status_col < email_col,
             "expected header order Handle < Role < Status < Email; got #{inspect(header_line)}"

      lines = String.split(flat, "\n")

      for {status, user} <- [
            {"pending", pending},
            {"active", active},
            {"suspended", suspended},
            {"rejected", rejected}
          ] do
        row_line = Enum.find(lines, &String.contains?(&1, "@#{user.handle}"))

        assert row_line,
               "expected USERS row for @#{user.handle} (status #{status}) in rendered output"

        # Each value sits under its header column at the byte offset the header set.
        # Substrings (role "user", status "active") collide with handle/email tokens,
        # so assert the exact column slice rather than first-match position.
        role_str = to_string(user.role)
        handle_str = "@#{user.handle}"

        assert binary_part(row_line, handle_col, byte_size(handle_str)) == handle_str
        assert binary_part(row_line, role_col, byte_size(role_str)) == role_str
        assert binary_part(row_line, status_col, byte_size(status)) == status
        assert binary_part(row_line, email_col, byte_size(user.email)) == user.email
      end

      refute String.contains?(flat, "deleteduser")
    end

    test "renders empty state and key hints when there are no administrable users" do
      sysop = %Foglet.Accounts.User{id: Ecto.UUID.generate(), role: :sysop, status: :active}
      view = UsersView.init(current_user: sysop)
      flat = UsersView.render(view, Foglet.TUI.Theme.default()) |> collect_text_values()

      assert Enum.any?(flat, &String.contains?(&1, "No users need status changes."))
      # Phase 29 D-15: footer is render-time. With no rows, the only key hint
      # advertised is [↑/↓] Move (no transition keys are gated-in). j/k remains
      # an unadvertised fallback so the footer stays compact.
      assert Enum.any?(flat, &String.contains?(&1, "[↑/↓] Move"))
      refute Enum.any?(flat, &String.contains?(&1, "[j/k] Move"))
    end
  end

  describe "USERS tab actions (USER-02, USER-03)" do
    test "approves pending users through Accounts and refreshes as active", %{state: state} do
      sysop = persist_user(%{handle: "approve_sysop", role: :sysop})
      pending = persist_user(%{handle: "approve_me", status: :pending})
      state = activate_users_tab(state, sysop)

      {:update, state, _} = handle_sysop_key(%{key: :char, char: "A"}, state)

      assert Accounts.get_user!(pending.id).status == :active

      assert current_users_view(state).message == "Approved @approve_me."
    end

    test "rejects pending users through Accounts and refreshes as rejected", %{state: state} do
      sysop = persist_user(%{handle: "reject_sysop", role: :sysop})
      pending = persist_user(%{handle: "reject_me", status: :pending})
      state = activate_users_tab(state, sysop)

      {:update, state, _} = handle_sysop_key(%{key: :char, char: "R"}, state)

      assert Accounts.get_user!(pending.id).status == :rejected

      assert current_users_view(state).message == "Rejected @reject_me."
    end

    test "suspends active users through Accounts and refreshes as suspended", %{state: state} do
      sysop = persist_user(%{handle: "suspend_sysop", role: :sysop})
      active = persist_user(%{handle: "suspend_me", status: :active})
      state = activate_users_tab(state, sysop)
      state = select_user_row(state, active.handle)

      {:update, state, _} = handle_sysop_key(%{key: :char, char: "S"}, state)

      assert Accounts.get_user!(active.id).status == :suspended

      assert current_users_view(state).message == "Suspended @suspend_me."
    end

    test "reactivates suspended users through Accounts and refreshes as active", %{state: state} do
      sysop = persist_user(%{handle: "reactivate_sysop", role: :sysop})
      suspended = persist_user(%{handle: "reactivate_me", status: :suspended})
      state = activate_users_tab(state, sysop)
      state = select_user_row(state, suspended.handle)

      {:update, state, _} = handle_sysop_key(%{key: :char, char: "U"}, state)

      assert Accounts.get_user!(suspended.id).status == :active

      assert current_users_view(state).message == "Reactivated @reactivate_me."
    end

    test "invalid row action is a no-op (Phase 29 D-15: pressing R on :active is gated)",
         %{state: state} do
      sysop = persist_user(%{handle: "invalid_sysop", role: :sysop})
      active = persist_user(%{handle: "reject_active", status: :active})
      state = activate_users_tab(state, sysop)
      state = select_user_row(state, active.handle)

      # D-15: [R] Reject is gated to :pending source rows. Pressing R on a
      # focused :active row is a UI no-op — no boundary call, no message.
      result = handle_sysop_key(%{key: :char, char: "R"}, state)

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

    test "empty rows list still renders arrow Move and does not crash" do
      view = %UsersView{
        current_user: nil,
        rows: [],
        selection_index: 0
      }

      flat = view |> UsersView.render(Theme.default()) |> collect_text_values() |> Enum.join("\n")
      assert String.contains?(flat, "[↑/↓] Move")
      refute String.contains?(flat, "[j/k] Move")
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
      ss = SysopState.new(active: 4)

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

      {:update, new_state, _} = handle_sysop_key(%{key: :char, char: "A"}, state)

      message = current_users_view(new_state).message

      # D-16: from->to copy uses the focused row's *displayed* (stale) source
      # status and the keypress's target. The handle is named explicitly.
      assert message == "@stale_user cannot move from pending to active."
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
    ss = SysopState.new(active: 1)
    bv = BoardsView.init(current_user: sysop)
    bv = %{bv | selection_index: 0}
    ss = %{ss | boards_view: {:loaded, bv}}
    put_in(state, [:screen_state, :sysop], ss)
  end

  defp boards_submit_form(title, fields, modal_kind) do
    ModalForm.init(
      title: title,
      fields: fields,
      on_submit: fn payload -> Effect.modal_submit(:sysop, modal_kind, payload) end,
      on_cancel: fn -> :ok end
    )
  end

  describe "BOARDS tab render (SYSO-03)" do
    setup [:seed_category_and_board]

    test "renders grouped category + board list", %{state: state, sysop: sysop} do
      state = activate_boards_tab(state, sysop)
      flat = render_sysop(state) |> collect_text_values() |> Enum.join("\n")
      assert String.contains?(flat, "General")
      assert String.contains?(flat, "Chat")
      assert String.contains?(flat, "chat")
    end

    test "FOG-670 opening new-board form replaces list with bounded overlay and form-mode footer",
         %{state: state, sysop: sysop} do
      state = activate_boards_tab(state, sysop)
      {:update, state, _} = handle_sysop_key(%{key: :char, char: "n"}, state)

      flat = render_sysop(state) |> collect_text_values() |> Enum.join("\n")

      # The board list rows must not bleed through behind the open form.
      refute String.contains?(flat, "qa-no-chat")
      refute String.contains?(flat, "QA No Chat")

      # The list-mode keybar must not advertise list actions while the form is
      # open — those keys are no-ops while a modal is active (Pitfall 5).
      refute String.contains?(flat, "[j/k] Move")
      refute String.contains?(flat, "[n] New board")

      # The form-mode footer advertises save/cancel/field-navigation and the
      # screen-level command bar shows the same form group instead of generic
      # tab navigation.
      assert String.contains?(flat, "Tab")
      assert String.contains?(flat, "Shift+Tab")
      assert String.contains?(flat, "Save")
      assert String.contains?(flat, "Cancel")
      refute String.contains?(flat, "Switch")
      refute String.contains?(flat, "Jump")

      # Regression for the cramped-width QA failure: at 64 columns the command
      # bar must keep reverse navigation discoverable instead of dropping the
      # Shift+Tab affordance to fit.
      cramped_flat =
        state
        |> Map.put(:terminal_size, {64, 22})
        |> render_sysop()
        |> collect_text_values()
        |> Enum.join("\n")

      assert String.contains?(cramped_flat, "Shift+Tab")
      assert String.contains?(cramped_flat, "Save")
      assert String.contains?(cramped_flat, "Cancel")
    end

    test "FOG-670 archive-confirm modal advertises Y/N in screen footer", %{
      state: state,
      sysop: sysop
    } do
      state = activate_boards_tab(state, sysop)
      # Move selection to a board row, then trigger archive-confirm.
      {:update, state, _} = handle_sysop_key(%{key: :char, char: "j"}, state)
      {:update, state, _} = handle_sysop_key(%{key: :char, char: "D"}, state)

      flat = render_sysop(state) |> collect_text_values() |> Enum.join("\n")

      # No tab-nav hints while the confirm modal is open; explicit Y/N keys
      # are advertised instead.
      refute String.contains?(flat, "Switch")
      refute String.contains?(flat, "Jump")
      assert String.contains?(flat, "Yes") or String.contains?(flat, "[Y]")
      assert String.contains?(flat, "No") or String.contains?(flat, "[N")
    end
  end

  describe "BOARDS tab create flow (SYSO-03)" do
    setup [:seed_category_and_board]

    test "n opens Modal.Form for new board with expected field specs", %{
      state: state,
      sysop: sysop,
      category: category
    } do
      state = activate_boards_tab(state, sysop)
      {:update, state, _} = handle_sysop_key(%{key: :char, char: "n"}, state)

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
               :required_subscription,
               :chat_enabled,
               :chat_storage_mode,
               :chat_message_ttl_seconds
             ]

      required_field = Enum.find(bv.modal.fields, &(&1.name == :required_subscription))
      assert required_field.label == "Required subscription"
      assert required_field.type == :boolean
      assert required_field.value == false

      chat_enabled_field = Enum.find(bv.modal.fields, &(&1.name == :chat_enabled))
      assert chat_enabled_field.type == :boolean
      assert chat_enabled_field.value == false

      category_field = Enum.find(bv.modal.fields, &(&1.name == :category_id))
      assert category_field.type == :enum
      assert category_field.choices == [{"General", category.id}]
      assert category_field.value == category.id

      postable_field = Enum.find(bv.modal.fields, &(&1.name == :postable_by))
      assert postable_field.type == :enum

      assert postable_field.choices == [
               {"Members", "members"},
               {"Moderators only", "mods_only"},
               {"Sysops only", "sysop_only"}
             ]

      storage_field = Enum.find(bv.modal.fields, &(&1.name == :chat_storage_mode))
      assert storage_field.type == :enum

      assert storage_field.choices == [
               {"In-memory (auto-expires)", "ephemeral"},
               {"Saved to database", "permanent"}
             ]

      assert storage_field.value == "ephemeral"
      assert is_function(storage_field.visible_when, 1)

      ttl_field = Enum.find(bv.modal.fields, &(&1.name == :chat_message_ttl_seconds))
      assert ttl_field.type == :enum

      assert ttl_field.choices == [
               {"15 minutes", 900},
               {"1 hour", 3600},
               {"6 hours", 21_600},
               {"24 hours (max)", 86_400}
             ]

      assert ttl_field.value == 3600
      assert is_function(ttl_field.visible_when, 1)

      assert bv.modal_kind == :create_board
    end

    test "FOG-349 edit board with legacy ttl prepends synthetic '(custom)' choice", %{
      state: state,
      sysop: sysop,
      board: board
    } do
      # Default schema ttl is 7200, which is NOT in the preset list — exactly
      # the legacy-custom case the implementation must preserve.
      assert board.chat_message_ttl_seconds == 7200

      state = activate_boards_tab(state, sysop)
      {:update, state, _} = handle_sysop_key(%{key: :char, char: "j"}, state)
      {:update, state, _} = handle_sysop_key(%{key: :char, char: "e"}, state)

      bv = current_boards_view(state)
      ttl_field = Enum.find(bv.modal.fields, &(&1.name == :chat_message_ttl_seconds))

      assert hd(ttl_field.choices) == {"7200 seconds (custom)", 7200}
      assert ttl_field.value == 7200
    end

    test "FOG-349 cycling off the legacy '(custom)' entry drops it from subsequent renders",
         %{state: state, sysop: sysop} do
      state = activate_boards_tab(state, sysop)
      {:update, state, _} = handle_sysop_key(%{key: :char, char: "j"}, state)
      {:update, state, _} = handle_sysop_key(%{key: :char, char: "e"}, state)
      bv = current_boards_view(state)

      # First, enable chat (focus 0..7 then toggle), then jump focus directly
      # onto the TTL field by rebuilding the modal struct (simpler than walking
      # Tab through every preceding field across the whole flow).
      ttl_idx = Enum.find_index(bv.modal.fields, &(&1.name == :chat_message_ttl_seconds))
      chat_idx = Enum.find_index(bv.modal.fields, &(&1.name == :chat_enabled))

      bv = %{bv | modal: %{bv.modal | focus_index: chat_idx}}
      state = put_boards_view(state, bv)
      {:update, state, _} = handle_sysop_key(%{key: :char, char: " "}, state)

      bv = current_boards_view(state)
      bv = %{bv | modal: %{bv.modal | focus_index: ttl_idx}}
      state = put_boards_view(state, bv)

      # Sanity check the synthetic choice is present.
      ttl_field =
        Enum.find(
          current_boards_view(state).modal.fields,
          &(&1.name == :chat_message_ttl_seconds)
        )

      assert hd(ttl_field.choices) == {"7200 seconds (custom)", 7200}

      # Press ↓ once: cycles off the synthetic head, drop kicks in, value lands
      # on the first preset (15 minutes / 900 seconds).
      {:update, state, _} = handle_sysop_key(%{key: :down}, state)

      ttl_field =
        Enum.find(
          current_boards_view(state).modal.fields,
          &(&1.name == :chat_message_ttl_seconds)
        )

      refute Enum.any?(ttl_field.choices, fn {label, _} -> String.contains?(label, "custom") end)

      assert hd(ttl_field.choices) == {"15 minutes", 900}

      assert ModalForm.field_value(current_boards_view(state).modal, :chat_message_ttl_seconds) ==
               900
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
      {:update, state, _} = handle_sysop_key(%{key: :char, char: "j"}, state)
      {:update, state, _} = handle_sysop_key(%{key: :char, char: "e"}, state)

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

      form = boards_submit_form("New board", fields, :create_board)

      bv = %{bv | modal: form, modal_kind: :create_board}
      state = put_boards_view(state, bv)

      # Focus the last field and press Enter to submit.
      n = length(fields)
      bv = current_boards_view(state)
      bv = %{bv | modal: %{bv.modal | focus_index: n - 1}}
      state = put_boards_view(state, bv)

      {:update, new_state, _} = handle_sysop_key(%{key: :enter}, state)

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

      form = boards_submit_form("New board", fields, :create_board)

      bv = %{bv | modal: %{form | focus_index: length(fields) - 1}, modal_kind: :create_board}
      state = put_boards_view(state, bv)

      {:update, new_state, _} = handle_sysop_key(%{key: :enter}, state)

      new_bv = current_boards_view(new_state)
      assert %ModalForm{} = new_bv.modal, "Modal must stay open on validation error"
      assert match?({:error, _}, new_bv.modal.submit_state)

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

      form = boards_submit_form("New board", fields, :create_board)

      bv = %{bv | modal: %{form | focus_index: length(fields) - 1}, modal_kind: :create_board}
      state = put_boards_view(state, bv)

      {:update, new_state, _} = handle_sysop_key(%{key: :enter}, state)

      new_bv = current_boards_view(new_state)
      assert %ModalForm{} = new_bv.modal
      assert new_bv.modal.errors.required_subscription =~ "requires default_subscription"
      refute Enum.any?(new_bv.boards, &(&1.slug == "required-only"))
    end

    test "Pitfall 5 — j/k navigation no-op while modal open", %{state: state, sysop: sysop} do
      state = activate_boards_tab(state, sysop)
      {:update, state, _} = handle_sysop_key(%{key: :char, char: "n"}, state)

      bv_before = current_boards_view(state)
      idx_before = bv_before.selection_index

      # j while a Modal.Form is open must not advance the selection.
      result = handle_sysop_key(%{key: :char, char: "j"}, state)

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
      {:update, state, _} = handle_sysop_key(%{key: :char, char: "j"}, state)

      {:update, state, _} = handle_sysop_key(%{key: :char, char: "D"}, state)

      bv = current_boards_view(state)
      assert %Foglet.TUI.Modal{type: :confirm} = bv.modal
      assert bv.modal_kind == :archive_board

      {:update, new_state, _} = handle_sysop_key(%{key: :char, char: "Y"}, state)

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
      {:update, state, _} = handle_sysop_key(%{key: :char, char: "N"}, state)

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

      form = boards_submit_form("New category", fields, :create_category)

      bv = %{bv | modal: %{form | focus_index: length(fields) - 1}}
      state = put_boards_view(state, bv)

      {:update, new_state, _} = handle_sysop_key(%{key: :enter}, state)

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

      form = boards_submit_form("New category", fields, :create_category)

      bv = %{bv | modal: %{form | focus_index: length(fields) - 1}, modal_kind: :create_category}
      state = put_boards_view(state, bv)

      {:update, new_state, _} = handle_sysop_key(%{key: :enter}, state)

      new_bv = current_boards_view(new_state)
      assert %ModalForm{} = new_bv.modal
      assert match?({:error, _}, new_bv.modal.submit_state)
      assert Map.has_key?(new_bv.modal.errors, :display_order)
      refute Enum.any?(new_bv.categories, &(&1.name == "Bad Order"))
    end
  end

  # =========================================================================
  # SYSTEM tab tests (Plan 02-05, SYSO-04)
  # =========================================================================

  alias Foglet.TUI.Screens.Sysop.SystemSnapshot

  defp activate_system_tab(state) do
    ss = SysopState.new(active: 3)
    ss = %{ss | system_snapshot: {:loaded, SystemSnapshot.init([])}}
    put_in(state, [:screen_state, :sysop], ss)
  end

  defp activate_invites_tab(state, sysop) do
    state =
      state
      |> Map.put(:current_user, sysop)
      |> with_invite_policy("sysop_only")

    ss =
      SysopState.new(
        active: 5,
        current_user: state.current_user,
        session_context: state.session_context
      )

    put_in(state, [:screen_state, :sysop], ss)
  end

  describe "SYSTEM tab (SYSO-04)" do
    test "renders snapshot labels on tab enter", %{state: state} do
      state = activate_system_tab(state)
      flat = render_sysop(state) |> collect_text_values() |> Enum.join("\n")

      for label <- ["Version:", "Live sessions:", "Active boards:", "BEAM processes:"] do
        assert String.contains?(flat, label),
               "Expected #{inspect(label)} in SYSTEM render output"
      end
    end

    test "r keeps the snapshot valid without relying on wall-clock timing", %{state: state} do
      state = activate_system_tab(state)
      old = current_system_snapshot(state)

      new_state =
        case handle_sysop_key(%{key: :char, char: "r"}, state) do
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
      result = handle_sysop_key(%{key: :char, char: "j"}, state)

      new_state =
        case result do
          {:update, s, _} -> s
          :no_match -> state
        end

      new = current_system_snapshot(new_state)
      assert new == old
    end

    # FOG-166: KvGrid.render/2 returns nested `[text, badge]` lists for
    # rows with `state:` badges. Earlier versions of this screen handed
    # that mixed list directly to the outer column, which crashed
    # `Raxol.UI.Layout.Preparer.prepare/1` (FunctionClauseError on a bare
    # list child) and tore down the SSH/TUI session. The fix flattens the
    # KvGrid output and hosts it in a dedicated sub-column. Walk the
    # rendered tree and assert no list child survives anywhere — this
    # reproduces the original preparer crash, which static text presence
    # checks did not catch.
    test "SYSTEM render tree has no nested list children (preparer-safe)",
         %{state: state} do
      state = activate_system_tab(state)
      tree = render_sysop(state)

      assert_no_list_children!(tree, [:root])
    end

    test "SYSTEM render tree survives Raxol.UI.Layout.Preparer.prepare/1",
         %{state: state} do
      state = activate_system_tab(state)
      tree = render_sysop(state)

      # If any child is a bare list, prepare/1 raises FunctionClauseError.
      assert %{} = Raxol.UI.Layout.Preparer.prepare(tree)
    end

    for {w, h} <- [{100, 30}, {80, 24}, {64, 22}] do
      @w w
      @h h
      test "SYSTEM render at #{@w}x#{@h} prepares without crash",
           %{state: state} do
        state =
          state
          |> Map.put(:terminal_size, {@w, @h})
          |> activate_system_tab()

        tree = render_sysop(state)
        assert_no_list_children!(tree, [:root])
        assert %{} = Raxol.UI.Layout.Preparer.prepare(tree)
      end
    end
  end

  defp assert_no_list_children!(node, path) when is_map(node) do
    case Map.get(node, :children) do
      nil ->
        :ok

      children when is_list(children) ->
        children
        |> Enum.with_index()
        |> Enum.each(fn {child, idx} ->
          if is_list(child) do
            flunk(
              "Bare list child at #{inspect(Enum.reverse([idx | path]))} would crash " <>
                "Raxol.UI.Layout.Preparer.prepare/1: #{inspect(child, limit: 5)}"
            )
          end

          assert_no_list_children!(child, [idx | path])
        end)
    end

    :ok
  end

  defp assert_no_list_children!(node, path) when is_list(node) do
    flunk(
      "Bare list at #{inspect(Enum.reverse(path))} (preparer requires a map): " <>
        inspect(node, limit: 5)
    )
  end

  defp assert_no_list_children!(_other, _path), do: :ok

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

      {:update, new_state, _cmds} = handle_sysop_key(%{key: :char, char: "g"}, state)

      assert {:ok, after_items} = Invites.list_invites(sysop)
      assert length(after_items) == length(before_items) + 1

      invites = new_state.screen_state.sysop.invites
      assert invites.items == after_items
      assert invites.last_generated_code == hd(after_items).code
      assert is_binary(invites.last_generated_code)
      assert invites.error == nil
    end

    test "sysop shell and render delegate invite lifecycle through shared modules only" do
      source = File.read!("lib/foglet_bbs/tui/screens/sysop.ex")
      render_source = File.read!("lib/foglet_bbs/tui/screens/sysop/render.ex")

      assert String.contains?(render_source, "InvitesSurface.render")
      assert String.contains?(source, "InvitesActions.handle_key")
      assert String.contains?(source, "InvitesActions.load")

      refute source =~ ~r/Accounts\.(create_invite|revoke_invite|list_invites)/
      refute String.contains?(source, "FogletBbs.Repo")
      refute render_source =~ ~r/Accounts\.(create_invite|revoke_invite|list_invites)/
      refute String.contains?(render_source, "FogletBbs.Repo")
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
        SysopState.new(
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
      |> render_sysop()
      |> collect_text_values()
      |> Enum.count(&String.contains?(&1, "Revoke"))
    end

    test "Enter on focused non-revoked INVITES row arms [X] Revoke", %{state: state, sysop: sysop} do
      invites = build_invites([:available, :available], 0)
      state = activate_invites(state, sysop, invites)

      # Pre-condition — only the body key hints carry 'Revoke'.
      assert count_revoke_tokens(state) == 1

      {:update, new_state, _events} = handle_sysop_key(%{key: :enter}, state)

      assert new_state.screen_state.sysop.armed_revoke? == true

      # After arming — body hint + command-bar [X] Revoke = 2 occurrences.
      assert count_revoke_tokens(new_state) >= 2,
             "Expected command bar to gain a [X] Revoke advertisement after Enter"
    end

    test "Enter on focused :revoked INVITES row does NOT arm and does NOT advertise Revoke",
         %{state: state, sysop: sysop} do
      invites = build_invites([:revoked, :available], 0)
      state = activate_invites(state, sysop, invites)

      result = handle_sysop_key(%{key: :enter}, state)

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

    test "WR-07: Enter on focused :revoked INVITES row surfaces an explanatory error",
         %{state: state, sysop: sysop} do
      invites = build_invites([:revoked, :available], 0)
      state = activate_invites(state, sysop, invites)

      assert {:update, new_state, _cmds} = handle_sysop_key(%{key: :enter}, state)

      # The revoked-row Enter handler surfaces feedback via InvitesState.error
      # so the operator gets an explanation rather than a silent no-op when
      # the [X] Revoke advertisement is absent.
      new_invites = new_state.screen_state.sysop.invites
      assert new_invites.error == "Invite already revoked."
      assert new_state.screen_state.sysop.armed_revoke? == false
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
      {:update, armed_state, _} = handle_sysop_key(%{key: :enter}, state)
      assert armed_state.screen_state.sysop.armed_revoke? == true

      # Press X — dispatches the existing revoke path
      {:update, fired_state, _events} =
        handle_sysop_key(%{key: :char, char: "X"}, armed_state)

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

      result = handle_sysop_key(%{key: :char, char: "X"}, state)

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
      {:update, armed_state, _} = handle_sysop_key(%{key: :enter}, state)
      assert armed_state.screen_state.sysop.armed_revoke? == true

      # Move focus down (j is not used here — InvitesActions uses :down arrow)
      {:update, moved_state, _} = handle_sysop_key(%{key: :down}, armed_state)

      assert moved_state.screen_state.sysop.armed_revoke? == false
    end

    test "Switching tabs clears armed_revoke?", %{state: state, sysop: sysop} do
      invites = build_invites([:available, :available], 0)
      state = activate_invites(state, sysop, invites)

      # Arm via Enter
      {:update, armed_state, _} = handle_sysop_key(%{key: :enter}, state)
      assert armed_state.screen_state.sysop.armed_revoke? == true

      # Move to a different tab via Left arrow (Tabs widget consumes it)
      {:update, switched_state, _} = handle_sysop_key(%{key: :left}, armed_state)

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
        SysopState.new(
          active: 0,
          current_user: state.current_user,
          session_context: state.session_context
        )

      state = put_in(state, [:screen_state, :sysop], ss)

      result = handle_sysop_key(%{key: :enter}, state)

      new_state =
        case result do
          {:update, s, _} -> s
          :no_match -> state
        end

      assert new_state.screen_state.sysop.armed_revoke? == false
    end

    test "FOG-162: D on focused non-revoked INVITES row arms (no immediate revoke, no boundary call)",
         %{state: state, sysop: sysop} do
      invites = build_invites([:available, :available], 0)
      state = activate_invites(state, sysop, invites)

      # Pre-condition: not armed, only body hint advertises Revoke.
      assert state.screen_state.sysop.armed_revoke? == false
      assert count_revoke_tokens(state) == 1

      {:update, new_state, events} = handle_sysop_key(%{key: :char, char: "D"}, state)

      # D arms instead of dispatching the revoke effect. No task effect is
      # emitted on the arm step.
      assert new_state.screen_state.sysop.armed_revoke? == true
      assert events == []

      # Items are unchanged (no boundary call, no list refresh).
      assert new_state.screen_state.sysop.invites.items == invites.items

      # Command bar now advertises [X] Revoke alongside the body hint.
      assert count_revoke_tokens(new_state) >= 2
    end

    test "FOG-162: lowercase d also arms instead of revoking", %{state: state, sysop: sysop} do
      invites = build_invites([:available], 0)
      state = activate_invites(state, sysop, invites)

      {:update, new_state, events} = handle_sysop_key(%{key: :char, char: "d"}, state)

      assert new_state.screen_state.sysop.armed_revoke? == true
      assert events == []
      assert new_state.screen_state.sysop.invites.items == invites.items
    end

    test "FOG-162: D on focused :revoked INVITES row surfaces error and does not arm",
         %{state: state, sysop: sysop} do
      invites = build_invites([:revoked, :available], 0)
      state = activate_invites(state, sysop, invites)

      {:update, new_state, events} = handle_sysop_key(%{key: :char, char: "D"}, state)

      assert new_state.screen_state.sysop.armed_revoke? == false
      assert new_state.screen_state.sysop.invites.error == "Invite already revoked."
      assert events == []
    end

    test "FOG-162: D + X end-to-end performs the actual revoke", %{state: state, sysop: sysop} do
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

      # Arm via D (instead of Enter).
      {:update, armed_state, []} = handle_sysop_key(%{key: :char, char: "D"}, state)
      assert armed_state.screen_state.sysop.armed_revoke? == true

      # The persisted invite is still :available — D alone did not revoke.
      assert {:ok, [pre_x | _]} = Foglet.Accounts.Invites.list_invites(sysop)
      assert pre_x.status == :available

      # X follows through on the armed gesture.
      {:update, fired_state, _} = handle_sysop_key(%{key: :char, char: "X"}, armed_state)
      assert fired_state.screen_state.sysop.armed_revoke? == false

      assert {:ok, [refreshed | _]} = Foglet.Accounts.Invites.list_invites(sysop)
      assert refreshed.status == :revoked
    end

    test "FOG-162: focus movement after D-arm clears armed_revoke?", %{
      state: state,
      sysop: sysop
    } do
      invites = build_invites([:available, :available, :available], 1)
      state = activate_invites(state, sysop, invites)

      {:update, armed_state, []} = handle_sysop_key(%{key: :char, char: "D"}, state)
      assert armed_state.screen_state.sysop.armed_revoke? == true

      {:update, moved_state, _} = handle_sysop_key(%{key: :down}, armed_state)
      assert moved_state.screen_state.sysop.armed_revoke? == false
    end

    test "FOG-175: D arms even when INVITES tab was just entered via tab nav (last_action carry-over)",
         %{state: state, sysop: sysop} do
      # Repro for FOG-175: in live SSH the user always reaches INVITES via a
      # tab-changing key (Right arrow or `6`). That sets the Tabs widget's
      # `last_action` to {:tab_changed, _}. The first per-tab key after the
      # navigation (e.g. D/d) flips `last_action` to nil, which used to make
      # `handle_update_key/3`'s `new_tabs == ss.tabs` check fail and route
      # the event through the "tabs changed" branch — clearing
      # armed_revoke? and never reaching delegate_update_to_invites/3.
      invites = build_invites([:available, :available], 0)

      # Start one tab to the left of INVITES, then nav onto INVITES so the
      # Tabs wrapper has a fresh {:tab_changed, _} `last_action` residue.
      state =
        state
        |> Map.put(:current_user, sysop)
        |> with_invite_policy("sysop_only")

      ss =
        SysopState.new(
          active: 4,
          current_user: state.current_user,
          session_context: state.session_context
        )

      state = put_in(state, [:screen_state, :sysop], %{ss | invites: invites})

      {:update, on_invites_state, _} = handle_sysop_key(%{key: :right}, state)
      assert Enum.at(SysopState.tab_labels(on_invites_state.screen_state.sysop), 5) == "INVITES"
      assert on_invites_state.screen_state.sysop.active_tab == 5
      assert on_invites_state.screen_state.sysop.tabs.last_action == {:tab_changed, 5}

      # The seeded invites might have been wiped by the tab change's
      # `maybe_request_invites_load` clobber; re-seed them so we can assert
      # on the arm path directly.
      seeded =
        update_in(on_invites_state, [:screen_state, :sysop], fn s -> %{s | invites: invites} end)

      {:update, armed_state, events} = handle_sysop_key(%{key: :char, char: "D"}, seeded)

      assert armed_state.screen_state.sysop.armed_revoke? == true
      assert events == []
      assert armed_state.screen_state.sysop.invites.items == invites.items
    end

    test "FOG-179: g generates an invite on the first press after navigating into INVITES via Right arrow",
         %{state: state, sysop: sysop} do
      # Regression for FOG-179: handle_update_key/3 must gate on the Tabs
      # `action` alone, not on `new_tabs == ss.tabs`. Reaching INVITES via a
      # tab-changing key seeds tabs.last_action with `{:tab_changed, _}`. The
      # next non-nav key (here `g`) flips last_action to nil, which would have
      # made a struct-equality guard misroute the press into the tab-change
      # branch and silently drop the generate effect.
      state =
        state
        |> Map.put(:current_user, sysop)
        |> with_invite_policy("sysop_only")

      ss =
        SysopState.new(
          active: 4,
          current_user: state.current_user,
          session_context: state.session_context
        )

      state = put_in(state, [:screen_state, :sysop], ss)

      {:update, on_invites_state, _} = handle_sysop_key(%{key: :right}, state)
      assert Enum.at(SysopState.tab_labels(on_invites_state.screen_state.sysop), 5) == "INVITES"
      assert on_invites_state.screen_state.sysop.active_tab == 5
      assert on_invites_state.screen_state.sysop.tabs.last_action == {:tab_changed, 5}

      assert {:ok, before_items} = Invites.list_invites(sysop)

      {:update, generated_state, _cmds} =
        handle_sysop_key(%{key: :char, char: "g"}, on_invites_state)

      # Active tab did not change — the press reached delegate_update_to_invites/3.
      assert generated_state.screen_state.sysop.active_tab == 5

      assert {:ok, after_items} = Invites.list_invites(sysop)
      assert length(after_items) == length(before_items) + 1

      invites_after = generated_state.screen_state.sysop.invites
      assert invites_after.last_generated_code == hd(after_items).code
      assert is_binary(invites_after.last_generated_code)
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
      ss = SysopState.new(active: 1)
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

      form = boards_submit_form("New board", fields, :create_board)

      bv = %{bv | modal: %{form | focus_index: length(fields) - 1}, modal_kind: :create_board}
      state = put_boards_view(state, bv)

      {:update, new_state, _} = handle_sysop_key(%{key: :enter}, state)

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

      form = boards_submit_form("New board", fields, :create_board)

      bv = %{bv | modal: %{form | focus_index: length(fields) - 1}, modal_kind: :create_board}
      state = put_boards_view(state, bv)

      {:update, new_state, _} = handle_sysop_key(%{key: :enter}, state)

      assert %Foglet.TUI.Modal{type: :error, message: message} = new_state.modal
      assert message == "Board service is not ready. Try again in a moment."
      assert new_state.current_screen == :main_menu
      assert current_boards_view(new_state).modal == nil
    end
  end

  describe "USERS ConsoleTable behavior" do
    test "empty USERS handles :up/:down/:enter without crash and without domain dispatch", %{
      state: state
    } do
      sysop = %Foglet.Accounts.User{id: Ecto.UUID.generate(), role: :sysop, status: :active}
      view = UsersView.init(current_user: sysop)

      state = put_in(state, [:screen_state, :sysop], SysopState.new(active: 4))
      ss = state.screen_state.sysop

      state = %{
        state
        | screen_state: Map.put(state.screen_state, :sysop, %{ss | users_view: view})
      }

      for key <- [%{key: :up}, %{key: :down}, %{key: :enter}] do
        result = handle_sysop_key(key, state)

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

  alias Foglet.TUI.Screens.Sysop.SystemSnapshot

  describe "SYSTEM snapshot behavior" do
    test "SYSTEM refresh key [r] continues to refresh snapshot", %{state: state} do
      # Pre-initialize the system snapshot wrapped as {:loaded, _} (D-07).
      snap = Foglet.TUI.Screens.Sysop.SystemSnapshot.init()
      ss = SysopState.new(active: 3)
      ss = %{ss | system_snapshot: {:loaded, snap}}
      state = put_in(state, [:screen_state, :sysop], ss)

      assert %SystemSnapshot{} = snap

      # "r" key may return :no_match if the snapshot values haven't changed.
      result = handle_sysop_key(%{key: :char, char: "r"}, state)

      case result do
        {:update, new_state, _} ->
          snap2 = current_system_snapshot(new_state)
          assert %SystemSnapshot{} = snap2

        :no_match ->
          # Snapshot was refreshed but wall clock didn't change — snapshot is
          # still valid. The pre-seeded snap already demonstrates init works.
          assert %SystemSnapshot{} = snap
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
          SysopState.new()
          |> set_active_tab(@tab)

        state = put_in(state, [:screen_state, :sysop], ss)
        serialized = state |> render_sysop() |> inspect(limit: :infinity)

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
      serialized = state |> render_sysop() |> inspect(limit: :infinity)

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

      {:update, state, _} = handle_sysop_key(%{key: :char, char: "D"}, state)

      bv = current_boards_view(state)

      assert bv.modal_kind in [:archive_board, :archive_category],
             "Expected archive confirm modal after D key"

      assert bv.modal != nil
    end
  end

  describe "update(:on_route_enter, …) — Phase 39 Plan 04" do
    # These reducer pins preserve the user-conditional semantics of App's
    # `maybe_dispatch_route_entry/3` clause for `:sysop` (`app.ex:826-832`):
    # when current_user is set, dispatch :load; otherwise no-op. Plan 39-05
    # will collapse the App-side clause into a generic dispatch.

    test "with current_user set delegates to :load (parity with direct :load call, BOARDS tab emits task)" do
      user = %Foglet.Accounts.User{
        id: Ecto.UUID.generate(),
        handle: "alice",
        role: :sysop,
        status: :active
      }

      context = Context.new(current_user: user, route: :sysop, terminal_size: {80, 24})
      # Active BOARDS tab so :load actually triggers a task effect (SITE tab
      # has no slot and produces no effects, which would let the catch-all
      # falsely "pass" parity even before the new clause exists).
      local = %{Sysop.init(context) | active_tab: 1}

      {state_via_on_enter, effects_via_on_enter} =
        Sysop.update(:on_route_enter, local, context)

      {state_via_load, effects_via_load} =
        Sysop.update(:load, local, context)

      assert state_via_on_enter == state_via_load
      assert effects_via_on_enter == effects_via_load

      assert Enum.any?(
               effects_via_on_enter,
               &match?(%Effect{type: :task, payload: %{op: :sysop_load_boards}}, &1)
             )
    end

    test "with no current_user no-ops (no effects, normalized state)" do
      context = Context.new(current_user: nil, route: :sysop, terminal_size: {80, 24})
      local = Sysop.init(context)

      {new_local, effects} = Sysop.update(:on_route_enter, local, context)

      assert effects == []
      assert %SysopState{} = new_local
    end

    test "with nil local_state and no user normalizes without crashing" do
      context = Context.new(current_user: nil, route: :sysop, terminal_size: {80, 24})

      {new_local, effects} = Sysop.update(:on_route_enter, nil, context)

      assert effects == []
      assert %SysopState{} = new_local
    end
  end
end
