defmodule Foglet.TUI.Screens.AccountTest do
  use FogletBbs.DataCase, async: false

  import Foglet.TUI.RenderHelpers

  alias Foglet.Accounts
  alias Foglet.Accounts.Invites
  alias Foglet.Config
  alias Foglet.Sessions.Session
  alias Foglet.TUI.App
  alias Foglet.TUI.Context
  alias Foglet.TUI.Effect
  alias Foglet.TUI.Presentation
  alias Foglet.TUI.Screens.Account
  alias Foglet.TUI.Screens.Account.SSHKeysState
  alias Foglet.TUI.Screens.Account.State, as: AccountState
  alias Foglet.TUI.Theme
  alias FogletBbs.AccountsFixtures

  @alternate_ssh_public_key "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBp8Yt7rf3YpZ8eR+3KEBLQnUlsMHfK4VwCaZJmjs4Cq other@example"

  defp build_state(user, session_context) do
    %Foglet.TUI.App{
      current_screen: :account,
      current_user: user,
      session_context: session_context,
      terminal_size: {80, 24},
      screen_state: %{}
    }
    |> Map.from_struct()
  end

  defp build_state_for_role(role, session_context \\ %{}) do
    build_state(
      %Foglet.Accounts.User{
        id: "00000000-0000-0000-0000-000000000001",
        handle: "alice",
        role: role
      },
      session_context
    )
  end

  defp account_context(state) do
    app = struct!(App, Map.take(state, Map.keys(%App{})))
    App.build_context(app)
  end

  defp render_account(state) do
    context = account_context(state)
    local_state = get_in(state, [:screen_state, :account]) || Account.init(context)

    Account.render(local_state, context)
  end

  defp handle_account_key(event, state) do
    context = account_context(state)
    local_state = get_in(state, [:screen_state, :account]) || Account.init(context)
    {new_local_state, effects} = Account.update({:key, event}, local_state, context)
    state = put_in(state, [:screen_state, :account], new_local_state)

    if new_local_state == local_state and effects == [] do
      :no_match
    else
      apply_account_effects(state, effects)
    end
  end

  defp apply_account_effects(state, effects) do
    Enum.reduce(effects, {:update, state, []}, fn
      %Effect{type: :navigate, payload: %{screen: screen, params: params}},
      {:update, state, cmds} ->
        {:update, %{state | current_screen: screen, route_params: params || %{}}, cmds}

      %Effect{type: :session, payload: {:set_current_user, user}}, {:update, state, cmds} ->
        {:update, %{state | current_user: user}, cmds}

      %Effect{type: :session, payload: {:update_preferences, _snapshot}}, acc ->
        acc

      %Effect{type: :task, payload: %{op: op, fun: fun}}, {:update, state, cmds} ->
        result = fun.()
        local_state = get_in(state, [:screen_state, :account])

        {new_local_state, followup} =
          Account.update({:task_result, op, {:ok, result}}, local_state, account_context(state))

        state
        |> put_in([:screen_state, :account], new_local_state)
        |> apply_account_effects(followup)
        |> append_cmds(cmds)

      _effect, acc ->
        acc
    end)
  end

  defp append_cmds({:update, state, new_cmds}, cmds), do: {:update, state, cmds ++ new_cmds}

  setup do
    %{state: build_state_for_role(:user)}
  end

  describe "Account.State.new/1" do
    test "returns a struct with active_tab: 0 and a Tabs wrapper state" do
      ss = AccountState.new()
      assert ss.active_tab == 0
      assert %Foglet.TUI.Widgets.Input.Tabs{} = ss.tabs
    end

    test "seeds profile and prefs drafts from current_user without mutating session context" do
      user = %Foglet.Accounts.User{
        id: "u1",
        handle: "alice",
        role: :user,
        location: "Mist Harbor",
        tagline: "low clouds, loud modems",
        real_name: "Alice Example",
        timezone: "America/Chicago",
        preferences: %{"time_format" => "24h"},
        theme: "amber"
      }

      ss = AccountState.new(current_user: user)

      assert ss.profile_draft == %{
               location: "Mist Harbor",
               tagline: "low clouds, loud modems",
               real_name: "Alice Example"
             }

      assert ss.prefs_draft == %{
               timezone: "America/Chicago",
               time_format: "24h",
               theme: "amber"
             }

      assert ss.profile_focus == :location
      assert ss.prefs_focus == :timezone
      assert ss.profile_errors == %{}
      assert ss.prefs_errors == %{}
      refute ss.profile_dirty?
      refute ss.prefs_dirty?
      assert ss.candidate_theme_id == nil
    end
  end

  describe "new screen contract" do
    test "Account.Render is the sibling render entry point" do
      assert Code.ensure_loaded?(Account.Render)
      assert function_exported?(Account.Render, :render, 1)

      source = File.read!("lib/foglet_bbs/tui/screens/account.ex")

      assert String.contains?(source, "Render.render()")
    end

    test "Account.init/1 seeds local state from Context" do
      user = build_user_with_profile(location: "Mist Harbor")

      state =
        Account.init(
          Context.new(
            current_user: user,
            session_context: %{invite_code_generators: "any_user"},
            route: :account
          )
        )

      assert %AccountState{} = state
      assert state.profile_draft.location == "Mist Harbor"
      assert "INVITES" in AccountState.tab_labels(true)
    end

    test "Account.render/2 renders from local state and Context without App-shaped input" do
      user = build_user_with_profile()
      context = Context.new(current_user: user, route: :account, terminal_size: {80, 24})
      state = Account.init(context)

      assert _node = Account.render(state, context)
    end

    test "profile task result reseeds Account local state and refreshes App user" do
      user = build_user_with_profile()
      context = Context.new(current_user: user, route: :account)
      state = Account.init(context)
      updated = %{user | location: "New Cove"}

      {state, effects} =
        Account.update(
          {:task_result, :account_save_profile, {:ok, {:ok, updated}}},
          state,
          context
        )

      assert %AccountState{} = state
      assert state.profile_draft.location == "New Cove"
      assert state.status_message == "Profile saved."
      assert [%Effect{type: :session, payload: {:set_current_user, ^updated}}] = effects
    end

    test "prefs task result reseeds state and emits session refresh effects" do
      user = build_user_with_profile(theme: "amber")
      context = Context.new(current_user: user, route: :account)

      state =
        Account.init(context)
        |> Map.put(:candidate_theme_id, "gray")

      {state, effects} =
        Account.update({:task_result, :account_save_prefs, {:ok, {:ok, user}}}, state, context)

      assert state.candidate_theme_id == nil
      assert state.status_message == "Preferences saved."

      assert [
               %Effect{type: :session, payload: {:set_current_user, ^user}},
               %Effect{type: :session, payload: {:update_preferences, snapshot}}
             ] = effects

      assert snapshot.theme_id == "amber"
    end

    test "profile task failure moves Modal.Form out of submitting" do
      alias Foglet.TUI.Widgets.Modal.Form, as: ModalForm

      user = build_user_with_profile()
      context = Context.new(current_user: user, route: :account)

      state =
        Account.init(context)
        |> Map.update!(:profile_form, &%{&1 | submit_state: :submitting})

      changeset = Accounts.User.profile_changeset(user, %{location: String.duplicate("x", 200)})

      {state, []} =
        Account.update(
          {:task_result, :account_save_profile, {:ok, {:error, changeset}}},
          state,
          context
        )

      assert %ModalForm{submit_state: {:error, _}} = state.profile_form
      assert %{location: message} = state.profile_form.errors
      assert String.contains?(message, "Location must be 80 characters or fewer.")
    end

    test "prefs task failure moves Modal.Form out of submitting" do
      alias Foglet.TUI.Widgets.Modal.Form, as: ModalForm

      user = build_user_with_profile()
      context = Context.new(current_user: user, route: :account)

      state =
        Account.init(context)
        |> Map.put(:active_tab, 1)
        |> Map.update!(:prefs_form, &%{&1 | submit_state: :submitting})

      changeset = Accounts.User.profile_changeset(user, %{timezone: "Not/AZone"})

      {state, []} =
        Account.update(
          {:task_result, :account_save_prefs, {:ok, {:error, changeset}}},
          state,
          context
        )

      assert %ModalForm{submit_state: {:error, _}} = state.prefs_form
      assert %{timezone: message} = state.prefs_form.errors
      assert String.contains?(message, "Timezone must be a valid IANA name")
    end

    test "SSH key and invite tabs request task-backed loads" do
      user = build_user_with_profile()

      context =
        Context.new(
          current_user: user,
          route: :account,
          session_context: %{invite_code_generators: "any_user"}
        )

      {ssh_state, ssh_effects} =
        Account.update({:key, %{key: :char, char: "3"}}, Account.init(context), context)

      assert ssh_state.active_tab == 2
      assert [%Effect{payload: %{op: :account_load_ssh_keys}}] = ssh_effects

      {invite_state, invite_effects} =
        Account.update({:key, %{key: :char, char: "4"}}, ssh_state, context)

      assert invite_state.active_tab == 3
      assert [%Effect{payload: %{op: :account_load_invites}}] = invite_effects
    end
  end

  describe "render/1 (Account.render/1 traceability)" do
    test "declares operator mode through Presentation", %{state: state} do
      state = put_in(state, [:screen_state, :account], AccountState.new())

      assert _ = render_account(state)
      assert Presentation.mode_for!(:account) == :operator

      assert File.read!("lib/foglet_bbs/tui/screens/account/render.ex") =~
               "Presentation.mode_for!(:account)"
    end

    test "KEYS-01 defines PROFILE, PREFS, and SSH KEYS tab labels by default" do
      assert AccountState.tab_labels(false) == ["PROFILE", "PREFS", "SSH KEYS"]
    end

    test "KEYS-01 SSH KEYS tab renders an empty key-list state", %{state: state} do
      account_state =
        AccountState.new()
        |> Map.put(:active_tab, 2)
        |> Map.put(:ssh_keys, SSHKeysState.loaded(SSHKeysState.new(), []))

      state = put_in(state, [:screen_state, :account], account_state)
      flat = render_account(state) |> collect_text_values()

      assert Enum.any?(
               flat,
               &String.contains?(&1, "No SSH keys yet. Add one to sign in without a password.")
             )
    end

    test "omits INVITES when InvitesSurface.visible?/2 returns false" do
      # role: :user with sysop_only policy => not visible
      state =
        :user
        |> build_state_for_role(%{invite_code_generators: "sysop_only"})
        |> put_in([:screen_state, :account], AccountState.new())

      flat = render_account(state) |> collect_text_values()
      refute Enum.any?(flat, &String.contains?(&1, "INVITES"))
    end

    test "includes INVITES when InvitesSurface.visible?/2 returns true" do
      # role: :sysop => always visible per D-07
      state = build_state_for_role(:sysop)
      state = put_in(state, [:screen_state, :account], AccountState.new(role: :sysop))
      flat = render_account(state) |> collect_text_values()
      assert Enum.any?(flat, &String.contains?(&1, "INVITES"))
    end

    test "any_user policy shows INVITES for a regular user" do
      # any_user
      state =
        :user
        |> build_state_for_role(%{invite_code_generators: "any_user"})
        |> put_in([:screen_state, :account], AccountState.new())

      flat = render_account(state) |> collect_text_values()
      assert Enum.any?(flat, &String.contains?(&1, "INVITES"))
    end

    test "mods and sysop_only policies hide INVITES for a regular user" do
      # mods sysop_only
      for policy <- ["mods", "sysop_only"] do
        state =
          :user
          |> build_state_for_role(%{invite_code_generators: policy})
          |> put_in([:screen_state, :account], AccountState.new())

        flat = render_account(state) |> collect_text_values()
        refute Enum.any?(flat, &String.contains?(&1, "INVITES"))
      end
    end

    test "nil user does not see INVITES under any_user policy" do
      # nil user
      state = build_state(nil, %{invite_code_generators: "any_user"})
      flat = render_account(state) |> collect_text_values()
      refute Enum.any?(flat, &String.contains?(&1, "INVITES"))
    end

    test "visibility changes in session_context rebuild tab list on render" do
      state =
        :user
        |> build_state_for_role(%{invite_code_generators: "sysop_only"})
        |> put_in([:screen_state, :account], AccountState.new())

      hidden_flat = render_account(state) |> collect_text_values()
      refute Enum.any?(hidden_flat, &String.contains?(&1, "INVITES"))

      visible_state = %{state | session_context: %{invite_code_generators: "any_user"}}
      visible_flat = render_account(visible_state) |> collect_text_values()
      assert Enum.any?(visible_flat, &String.contains?(&1, "INVITES"))
    end

    test "renders no fake invite or approval buttons", %{state: state} do
      state = put_in(state, [:screen_state, :account], AccountState.new())
      flat = render_account(state) |> collect_text_values()
      forbidden = ["Generate", "Revoke", "Approve"]

      for word <- forbidden do
        refute Enum.any?(flat, &String.contains?(&1, word)),
               "Expected #{inspect(word)} not to appear in Account render output"
      end
    end

    test "PROFILE and PREFS define editable field labels", %{state: state} do
      ss = AccountState.new(current_user: state.current_user)

      assert Enum.map(ss.profile_form.fields, & &1.label) == ["Location", "Tagline", "Real name"]
      assert Enum.map(ss.prefs_form.fields, & &1.label) == ["Timezone", "Time format", "Theme"]
    end

    test "unsaved theme preview changes Account render and cancel keeps session theme unchanged" do
      user = %Foglet.Accounts.User{
        id: "u1",
        handle: "alice",
        role: :user,
        timezone: "Etc/UTC",
        preferences: %{"time_format" => "12h"},
        theme: "gray"
      }

      state =
        user
        |> build_state(%{theme: Theme.resolve(:gray), theme_id: "gray"})
        |> put_in([:screen_state, :account], AccountState.new(current_user: user))

      {:update, state, []} = handle_account_key(%{key: :char, char: "2"}, state)
      before_preview = inspect(render_account(state))

      account_state = %{state.screen_state.account | prefs_focus: :theme}
      state = put_in(state, [:screen_state, :account], account_state)

      {:update, preview_state, []} = handle_account_key(%{key: :down}, state)

      assert preview_state.screen_state.account.candidate_theme_id != nil
      assert preview_state.session_context.theme == Theme.resolve(:gray)
      assert inspect(render_account(preview_state)) != before_preview

      {:update, cancelled_state, []} = handle_account_key(%{key: :escape}, preview_state)

      assert cancelled_state.screen_state.account.candidate_theme_id == nil
      assert cancelled_state.screen_state.account.prefs_draft.theme == "gray"
      assert cancelled_state.session_context.theme == Theme.resolve(:gray)
    end
  end

  describe "handle_key/2 (handle_account_key/2 traceability)" do
    setup %{state: state} do
      state = put_in(state, [:screen_state, :account], AccountState.new())
      %{state: state}
    end

    test "Right arrow advances active_tab via Tabs.handle_event/2", %{state: state} do
      {:update, new_state, _cmds} = handle_account_key(%{key: :right}, state)
      assert new_state.screen_state.account.active_tab == 1
    end

    test "visibility changes in session_context rebuild tab list on handle-key", %{state: state} do
      state = %{state | session_context: %{invite_code_generators: "any_user"}}

      {:update, new_state, _cmds} = handle_account_key(%{key: :char, char: "4"}, state)

      assert new_state.screen_state.account.active_tab == 3
      flat = render_account(new_state) |> collect_text_values()
      assert Enum.any?(flat, &String.contains?(&1, "INVITES"))
    end

    test "digit '2' jumps to second tab (index 1)", %{state: state} do
      {:update, new_state, _cmds} = handle_account_key(%{key: :char, char: "2"}, state)
      assert new_state.screen_state.account.active_tab == 1
    end

    test "KEYS-01 digit '3' selects SSH KEYS when invites are hidden", %{state: state} do
      {:update, new_state, _cmds} = handle_account_key(%{key: :char, char: "3"}, state)
      assert new_state.screen_state.account.active_tab == 2

      flat = render_account(new_state) |> collect_text_values()
      assert Enum.any?(flat, &String.contains?(&1, "SSH KEYS"))
    end

    test "Ctrl+Q returns to :main_menu", %{state: state} do
      {:update, new_state, _cmds} =
        handle_account_key(%{key: :char, char: "Q", ctrl: true}, state)

      assert new_state.current_screen == :main_menu
    end

    test "'q' is delegated to the active form", %{state: state} do
      {:update, new_state, _cmds} = handle_account_key(%{key: :char, char: "q"}, state)
      assert new_state.current_screen == :account
      assert new_state.screen_state.account.profile_dirty?
    end

    test "non-text unknown key returns :no_match", %{state: state} do
      assert :no_match = handle_account_key(%{key: :f12}, state)
    end

    test "Account screen does NOT dispatch any fake operator commands (Save/Generate/Revoke)", %{
      state: state
    } do
      forbidden_commands = [:save_profile, :generate_invite, :revoke_invite, :approve_user]

      keys = [
        %{key: :right},
        %{key: :left},
        %{key: :char, char: "1"},
        %{key: :char, char: "2"}
      ]

      for key <- keys do
        case handle_account_key(key, state) do
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

  describe "App Account reducer result handling" do
    test "successful save results refresh local state, current user, and active session snapshots" do
      user = AccountsFixtures.user_fixture()

      {:ok, session_pid} =
        start_supervised(
          {Session, [user_id: user.id, handle: user.handle, role: user.role]},
          id: :account_save_success_session
        )

      state = %App{
        current_screen: :account,
        current_user: user,
        session_context: %{
          session_pid: session_pid,
          timezone: "Etc/UTC",
          time_format: "12h",
          theme_id: "gray",
          theme: Theme.resolve(:gray)
        },
        session_pid: session_pid,
        terminal_size: {80, 24},
        screen_state: %{
          account:
            AccountState.new(current_user: user)
            |> Map.put(:profile_dirty?, true)
            |> Map.put(:prefs_dirty?, true)
            |> Map.put(:candidate_theme_id, "amber")
        }
      }

      {:ok, updated_profile} =
        Accounts.update_profile(user, %{
          location: "Mist Harbor",
          tagline: "low clouds",
          real_name: "Alice Example"
        })

      {state, []} =
        App.update(
          {:screen_task_result, :account, :account_save_profile, {:ok, {:ok, updated_profile}}},
          state
        )

      {:ok, updated_prefs} =
        Accounts.update_profile(updated_profile, %{
          timezone: "America/Chicago",
          preferences: %{"time_format" => "24h"},
          theme: "amber"
        })

      {state, []} =
        App.update(
          {:screen_task_result, :account, :account_save_prefs, {:ok, {:ok, updated_prefs}}},
          state
        )

      persisted = Accounts.get_user!(user.id)

      assert persisted.location == "Mist Harbor"
      assert persisted.tagline == "low clouds"
      assert persisted.real_name == "Alice Example"
      assert persisted.timezone == "America/Chicago"
      assert persisted.preferences["time_format"] == "24h"
      assert persisted.theme == "amber"

      assert state.current_user.id == user.id
      assert state.current_user.location == "Mist Harbor"
      assert state.current_user.timezone == "America/Chicago"
      assert state.current_user.preferences["time_format"] == "24h"
      assert state.current_user.theme == "amber"

      assert state.session_context.timezone == "America/Chicago"
      assert state.session_context.time_format == "24h"
      assert state.session_context.theme_id == "amber"
      assert state.session_context.theme == Theme.resolve(:amber)

      account_state = state.screen_state.account
      refute account_state.profile_dirty?
      refute account_state.prefs_dirty?
      assert account_state.candidate_theme_id == nil
      assert account_state.profile_errors == %{}
      assert account_state.prefs_errors == %{}

      _ = :sys.get_state(session_pid)
      session_state = Session.get_state(session_pid)
      assert session_state.timezone == "America/Chicago"
      assert session_state.time_format == "24h"
      assert session_state.theme_id == "amber"
      assert session_state.theme == Theme.resolve(:amber)
    end

    test "failed save result renders errors and leaves active snapshots unchanged" do
      user =
        AccountsFixtures.user_fixture(%{
          location: "Original Cove",
          timezone: "Etc/UTC",
          preferences: %{"time_format" => "12h"},
          theme: "gray"
        })

      {:ok, session_pid} =
        start_supervised(
          {Session, [user_id: user.id, handle: user.handle, role: user.role]},
          id: :account_save_failure_session
        )

      state = %App{
        current_screen: :account,
        current_user: user,
        session_context: %{
          session_pid: session_pid,
          timezone: "Etc/UTC",
          time_format: "12h",
          theme_id: "gray",
          theme: Theme.resolve(:gray)
        },
        session_pid: session_pid,
        terminal_size: {80, 24},
        screen_state: %{
          account:
            AccountState.new(current_user: user)
            |> Map.put(:active_tab, 1)
            |> Map.put(:prefs_dirty?, true)
        }
      }

      original_user = state.current_user
      original_context = state.session_context
      original_session = Session.get_state(session_pid)

      {:error, changeset} =
        Accounts.update_profile(user, %{
          timezone: "Not/AZone",
          preferences: %{"time_format" => "24h"},
          theme: "amber"
        })

      {new_state, []} =
        App.update(
          {:screen_task_result, :account, :account_save_prefs, {:ok, {:error, changeset}}},
          state
        )

      assert new_state.current_user == original_user
      assert new_state.session_context == original_context

      _ = :sys.get_state(session_pid)
      assert Session.get_state(session_pid).timezone == original_session.timezone
      assert Session.get_state(session_pid).time_format == original_session.time_format
      assert Session.get_state(session_pid).theme_id == original_session.theme_id

      assert %{timezone: message} = new_state.screen_state.account.prefs_errors
      assert String.contains?(message, "valid IANA")
      assert match?({:error, _}, new_state.screen_state.account.prefs_form.submit_state)

      flat = render_account(Map.from_struct(new_state)) |> collect_text_values()
      assert Enum.any?(flat, &String.contains?(&1, "Timezone must be a valid IANA name"))
    end
  end

  describe "live INVITES actions" do
    setup :restore_invite_config

    test "persists exactly one invite and displays last_generated_code under any_user" do
      # persists exactly one invite last_generated_code any_user
      user = AccountsFixtures.user_fixture()
      state = build_state(user, %{invite_code_generators: "any_user"})

      assert {:ok, []} = Invites.list_invites(user)

      {:update, state, []} = handle_account_key(%{key: :char, char: "4"}, state)
      {:update, state, []} = handle_account_key(%{key: :char, char: "g"}, state)

      assert {:ok, [invite]} = Invites.list_invites(user)
      assert state.screen_state.account.invites.last_generated_code == invite.code
      assert [%{code: code, status: :available}] = state.screen_state.account.invites.items
      assert code == invite.code

      flat = render_account(state) |> collect_text_values()
      assert Enum.any?(flat, &String.contains?(&1, "Invite code ready: #{invite.code}"))
    end

    test "refresh, select, and revoke delegate through shared Account INVITES actions" do
      user = AccountsFixtures.user_fixture()
      state = build_state(user, %{invite_code_generators: "any_user"})

      {:ok, first} = Invites.create_invite(user)
      {:ok, second} = Invites.create_invite(user)

      {:update, state, []} = handle_account_key(%{key: :char, char: "4"}, state)
      assert Enum.count(state.screen_state.account.invites.items) == 2

      {:update, state, []} = handle_account_key(%{key: :down}, state)
      assert state.screen_state.account.invites.selected_index == 1
      selected_code = Enum.at(state.screen_state.account.invites.items, 1).code
      other_code = Enum.find([first.code, second.code], &(&1 != selected_code))

      # FOG-130 Item 3: D opens the revoke confirm sub-mode; Enter actually
      # calls revoke. The shared invites action then surfaces the forbidden
      # error to the user.
      {:update, state, []} = handle_account_key(%{key: :char, char: "d"}, state)
      assert state.screen_state.account.invites.mode == :confirm_revoke
      assert state.screen_state.account.invites.confirm_target.code == selected_code

      {:update, state, []} = handle_account_key(%{key: :enter}, state)
      assert state.screen_state.account.invites.mode == :list
      assert state.screen_state.account.invites.error == "You are not allowed to manage invites."
      assert {:ok, %{status: :available}} = Invites.get_invite_status(selected_code)
      assert {:ok, %{status: :available}} = Invites.get_invite_status(other_code)

      {:update, state, []} = handle_account_key(%{key: :char, char: "r"}, state)
      assert Enum.any?(state.screen_state.account.invites.items, &(&1.code == selected_code))
      assert state.screen_state.account.invites.error == nil
    end

    test "hidden INVITES tab leaves generate unavailable for disallowed Account policy" do
      user = AccountsFixtures.user_fixture()
      state = build_state(user, %{invite_code_generators: "sysop_only"})

      assert {:update, _state, []} = handle_account_key(%{key: :char, char: "g"}, state)
      assert {:ok, []} = Invites.list_invites(user)
    end
  end

  describe "live SSH KEYS actions" do
    test "KEYS-03 entering SSH KEYS and refreshing load only the current user's keys" do
      user = AccountsFixtures.user_fixture()
      other_user = AccountsFixtures.user_fixture()
      own_key = AccountsFixtures.ssh_key_fixture(user, %{label: "laptop"})

      _other_key =
        AccountsFixtures.ssh_key_fixture(other_user, %{public_key: @alternate_ssh_public_key})

      state = build_state(user, %{})

      {:update, state, []} = handle_account_key(%{key: :char, char: "3"}, state)

      assert [%{id: key_id, label: "laptop"}] = state.screen_state.account.ssh_keys.items
      assert key_id == own_key.id

      {:update, state, []} = handle_account_key(%{key: :char, char: "r"}, state)
      assert [%{id: ^key_id}] = state.screen_state.account.ssh_keys.items

      flat = render_account(state) |> collect_text_values()
      assert Enum.any?(flat, &String.contains?(&1, "Refresh"))
      assert Enum.any?(flat, &String.contains?(&1, "Revoke"))
    end

    test "KEYS-02 add flow stores a valid key, refreshes list, and shows status" do
      user = AccountsFixtures.user_fixture()
      state = build_state(user, %{})

      {:update, state, []} = handle_account_key(%{key: :char, char: "3"}, state)
      {:update, state, []} = handle_account_key(%{key: :char, char: "a"}, state)

      account_state =
        put_ssh_key_form(state.screen_state.account, %{
          label: "workstation",
          public_key: @alternate_ssh_public_key
        })

      state = put_in(state, [:screen_state, :account], account_state)

      {:update, state, []} = handle_account_key(%{key: :enter}, state)

      assert [%{label: "workstation", fingerprint: "SHA256:" <> _}] = Accounts.list_ssh_keys(user)
      assert state.screen_state.account.ssh_keys.status_message == "SSH key added."
      assert [%{label: "workstation"}] = state.screen_state.account.ssh_keys.items
    end

    test "KEYS-02 add flow shows terminal-visible validation errors" do
      user = AccountsFixtures.user_fixture()
      _existing = AccountsFixtures.ssh_key_fixture(user, %{label: "laptop"})
      state = build_state(user, %{})

      {:update, state, []} = handle_account_key(%{key: :char, char: "3"}, state)
      {:update, state, []} = handle_account_key(%{key: :char, char: "a"}, state)
      {:update, blank_state, []} = handle_account_key(%{key: :enter}, state)

      blank_flat = render_account(blank_state) |> collect_text_values()
      assert Enum.any?(blank_flat, &String.contains?(&1, "Label is required."))
      assert Enum.any?(blank_flat, &String.contains?(&1, "Public key is required."))

      account_state =
        put_ssh_key_form(blank_state.screen_state.account, %{
          label: "bad",
          public_key: "invalid OpenSSH material"
        })

      invalid_state = put_in(blank_state, [:screen_state, :account], account_state)

      {:update, invalid_state, []} = handle_account_key(%{key: :enter}, invalid_state)
      invalid_flat = render_account(invalid_state) |> collect_text_values()
      assert Enum.any?(invalid_flat, &String.contains?(&1, "valid OpenSSH public key"))

      account_state =
        put_ssh_key_form(invalid_state.screen_state.account, %{
          label: "other",
          public_key: AccountsFixtures.default_ssh_public_key()
        })

      duplicate_fingerprint_state =
        put_in(invalid_state, [:screen_state, :account], account_state)

      {:update, duplicate_fingerprint_state, []} =
        handle_account_key(%{key: :enter}, duplicate_fingerprint_state)

      duplicate_fingerprint_flat =
        duplicate_fingerprint_state |> render_account() |> collect_text_values()

      assert Enum.any?(
               duplicate_fingerprint_flat,
               &String.contains?(&1, "That public key is already on this account.")
             )

      account_state =
        put_ssh_key_form(duplicate_fingerprint_state.screen_state.account, %{
          label: "laptop",
          public_key: @alternate_ssh_public_key
        })

      duplicate_label_state =
        put_in(duplicate_fingerprint_state, [:screen_state, :account], account_state)

      {:update, duplicate_label_state, []} =
        handle_account_key(%{key: :enter}, duplicate_label_state)

      duplicate_label_flat = duplicate_label_state |> render_account() |> collect_text_values()

      assert Enum.any?(
               duplicate_label_flat,
               &String.contains?(&1, "You already have an SSH key with that label.")
             )
    end

    test "KEYS-04 revoke selected key refreshes list and reports missing selections" do
      user = AccountsFixtures.user_fixture()
      first = AccountsFixtures.ssh_key_fixture(user, %{label: "first"})

      second =
        AccountsFixtures.ssh_key_fixture(user, %{
          label: "second",
          public_key: @alternate_ssh_public_key
        })

      state = build_state(user, %{})

      {:update, state, []} = handle_account_key(%{key: :char, char: "3"}, state)
      {:update, state, []} = handle_account_key(%{key: :down}, state)
      assert state.screen_state.account.ssh_keys.selected_index == 1

      # FOG-130 Item 2: D opens the revoke confirmation; Enter actually
      # performs the destructive action.
      {:update, state, []} = handle_account_key(%{key: :char, char: "d"}, state)
      assert state.screen_state.account.ssh_keys.mode == :confirm_revoke
      assert state.screen_state.account.ssh_keys.confirm_target.label == "second"

      {:update, state, []} = handle_account_key(%{key: :enter}, state)

      assert state.screen_state.account.ssh_keys.mode == :list
      assert state.screen_state.account.ssh_keys.status_message == "SSH key revoked."
      assert [%{id: remaining_id}] = state.screen_state.account.ssh_keys.items
      assert remaining_id == first.id
      assert [%{id: ^remaining_id}] = Accounts.list_ssh_keys(user)
      refute Enum.any?(Accounts.list_ssh_keys(user), &(&1.id == second.id))

      account_state = %{
        state.screen_state.account
        | ssh_keys: SSHKeysState.loaded(state.screen_state.account.ssh_keys, [])
      }

      empty_state = put_in(state, [:screen_state, :account], account_state)

      # On an empty list D refuses to open the confirm sub-mode and surfaces
      # the friendly selection error directly.
      {:update, empty_state, []} = handle_account_key(%{key: :char, char: "d"}, empty_state)
      assert empty_state.screen_state.account.ssh_keys.mode == :list

      assert empty_state.screen_state.account.ssh_keys.errors.general ==
               "Select an SSH key first."
    end

    test "KEYS-04 revoke handles not found without crashing" do
      user = AccountsFixtures.user_fixture()
      key = AccountsFixtures.ssh_key_fixture(user)
      state = build_state(user, %{})

      {:update, state, []} = handle_account_key(%{key: :char, char: "3"}, state)
      {:ok, _revoked} = Accounts.revoke_ssh_key(user, key.id)

      {:update, state, []} = handle_account_key(%{key: :char, char: "d"}, state)
      assert state.screen_state.account.ssh_keys.mode == :confirm_revoke

      {:update, state, []} = handle_account_key(%{key: :enter}, state)

      assert state.screen_state.account.ssh_keys.errors.general ==
               "That SSH key is no longer here. Refresh the list."
    end
  end

  # ---------------------------------------------------------------------------
  # Phase 25 Plan 05 — Per-tab theme hygiene (D-12)
  # ---------------------------------------------------------------------------

  describe "Phase 25 theme hygiene (D-12)" do
    import Foglet.TUI.WidgetHelpers
    import Foglet.TUI.LayoutSmokeHelpers

    for tab <- ["PROFILE", "PREFS", "SSH KEYS"] do
      @tab tab
      test "converted Account #{tab} tab leaks no color atoms" do
        ss =
          AccountState.new()
          |> set_active_tab(@tab)

        state =
          build_state_for_role(:user)
          |> put_in([:screen_state, :account], ss)

        serialized = state |> render_account() |> inspect(limit: :infinity)

        for color <- color_names() do
          refute color_atom_leaked?(serialized, color),
                 "leaked :#{color} in converted Account #{@tab} tab"
        end
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

    Config.put!("invite_code_generators", "any_user")
    Config.put!("invite_generation_per_user_limit", 0)
    :ok
  end

  defp put_ssh_key_form(account_state, form) do
    %{account_state | ssh_keys: %{account_state.ssh_keys | form: form}}
  end

  defp build_user_with_profile(opts \\ []) do
    %Foglet.Accounts.User{
      id: "u-honest-esc",
      handle: "alice",
      role: :user,
      location: Keyword.get(opts, :location, "Berlin"),
      tagline: Keyword.get(opts, :tagline, "hi"),
      real_name: Keyword.get(opts, :real_name, "Brendan"),
      timezone: Keyword.get(opts, :timezone, "Etc/UTC"),
      preferences: Keyword.get(opts, :preferences, %{"time_format" => "12h"}),
      theme: Keyword.get(opts, :theme, "gray")
    }
  end

  # ---------------------------------------------------------------------------
  # Phase 28 Plan 03 — FORM-06 honest Esc (D-10, D-11)
  # ---------------------------------------------------------------------------

  describe "FORM-06 honest Esc on Account Profile (Phase 28 D-10, D-11)" do
    alias Foglet.TUI.Screens.Account.ProfileForm
    alias Foglet.TUI.Widgets.Modal.Form, as: ModalForm

    test "Esc reseeds profile_draft to saved-user values, clears dirty + status_message" do
      user = build_user_with_profile()
      ss = AccountState.new(current_user: user)

      # Mutate the live form by typing a char into the focused field
      # (focus starts at :location — first field).
      {form_after_type, nil} =
        ModalForm.handle_event(%{key: :char, char: "X"}, ss.profile_form)

      # Sanity: the typing event mutated :location away from "Berlin" (we don't
      # care about cursor position — only that the live form differs from the
      # saved-user value, which is what Esc must reseed away).
      assert ModalForm.field_value(form_after_type, :location) != "Berlin"
      assert ModalForm.field_value(form_after_type, :location) =~ "X"

      ss_dirty = %{ss | profile_form: form_after_type, profile_dirty?: true}

      {:ok, after_esc, cmds} = ProfileForm.handle_key(%{key: :escape}, ss_dirty, user)

      assert after_esc.profile_draft == %{
               location: "Berlin",
               tagline: "hi",
               real_name: "Brendan"
             }

      assert after_esc.profile_dirty? == false
      assert after_esc.status_message == nil
      assert cmds == []

      # And the rendered form's first-field value reverted on the next render.
      assert ModalForm.field_value(after_esc.profile_form, :location) == "Berlin"
    end

    test "Esc on Account Profile does not produce any 'discarded' status copy" do
      user = build_user_with_profile()
      ss = AccountState.new(current_user: user)

      {form_after_type, nil} =
        ModalForm.handle_event(%{key: :char, char: "X"}, ss.profile_form)

      ss_dirty = %{ss | profile_form: form_after_type, profile_dirty?: true}

      {:ok, after_esc, []} = ProfileForm.handle_key(%{key: :escape}, ss_dirty, user)

      # No status_message, and no "discarded" text anywhere in the state map.
      assert after_esc.status_message == nil

      serialized = inspect(after_esc, limit: :infinity)
      refute serialized =~ "Profile changes discarded"
      refute serialized =~ "discarded"
    end
  end

  describe "FORM-06 honest Esc on Account Preferences (Phase 28 D-10, D-11)" do
    alias Foglet.TUI.Screens.Account.PrefsForm
    alias Foglet.TUI.Widgets.Modal.Form, as: ModalForm

    test "Esc reseeds prefs_draft to saved-user values, clears dirty + status_message" do
      user = build_user_with_profile()
      ss = AccountState.new(current_user: user)

      # Mutate the live prefs form by cycling the focused enum picker
      # (focus starts at :timezone — first field).
      {form_after_pick, nil} =
        ModalForm.handle_event(%{key: :down}, ss.prefs_form)

      # Sanity: cycling moved :timezone off the seeded "Etc/UTC".
      assert ModalForm.field_value(form_after_pick, :timezone) != "Etc/UTC"

      ss_dirty = %{
        ss
        | prefs_form: form_after_pick,
          prefs_dirty?: true,
          candidate_theme_id: "amber"
      }

      {:ok, after_esc, cmds} = PrefsForm.handle_key(%{key: :escape}, ss_dirty, user)

      assert after_esc.prefs_draft == %{
               timezone: "Etc/UTC",
               time_format: "12h",
               theme: "gray"
             }

      assert after_esc.prefs_dirty? == false
      assert after_esc.status_message == nil
      assert after_esc.candidate_theme_id == nil
      assert cmds == []

      assert ModalForm.field_value(after_esc.prefs_form, :timezone) == "Etc/UTC"
    end

    test "Esc on Account Preferences does not produce any 'discarded' status copy" do
      user = build_user_with_profile()
      ss = AccountState.new(current_user: user)

      {form_after_pick, nil} =
        ModalForm.handle_event(%{key: :down}, ss.prefs_form)

      ss_dirty = %{ss | prefs_form: form_after_pick, prefs_dirty?: true}

      {:ok, after_esc, []} = PrefsForm.handle_key(%{key: :escape}, ss_dirty, user)

      assert after_esc.status_message == nil

      serialized = inspect(after_esc, limit: :infinity)
      refute serialized =~ "Preference changes discarded"
      refute serialized =~ "discarded"
    end
  end

  describe "PROFILE Modal.Form contract" do
    test "renders form heading and suppresses Modal.Form footer (FORM-03 default-off)" do
      # Phase 28 FORM-03 / D-06: Account tab-body forms do NOT render the
      # Modal.Form footer; the global command bar is the single advertiser of
      # [Enter] Submit / [Esc] Cancel. Profile/Prefs build forms without
      # `show_footer: true`, so render must contain the form heading but NOT
      # the footer sentinel.
      state =
        build_state_for_role(:user)
        |> put_in([:screen_state, :account], AccountState.new())

      flat = render_account(state) |> collect_text_values()

      assert Enum.any?(flat, &String.contains?(&1, "Profile")),
             "expected form heading 'Profile' in profile tab"

      refute Enum.any?(flat, &String.contains?(&1, "[Enter] Submit")),
             "Modal.Form footer must NOT appear in Account tab body (Phase 28 D-06)"
    end

    test "builds labeled field rows for each profile field" do
      ss = AccountState.new()

      assert Enum.map(ss.profile_form.fields, & &1.label) == ["Location", "Tagline", "Real name"]
    end

    test "real_name is optional (FOG-130 Item 6 reconciliation with domain validation)" do
      ss = AccountState.new()

      # Real name is NOT required at the form level because
      # User.profile_changeset/2 does not require it. Domain truth wins.
      assert [] = Enum.filter(ss.profile_form.fields, &Map.get(&1, :required, false))

      assert Enum.find(ss.profile_form.fields, &(&1.name == :real_name)) ==
               %{
                 name: :real_name,
                 type: :text,
                 label: "Real name",
                 description: "For friends and the sysop; blank uses your handle.",
                 value: ""
               }
    end

    test "renders inline error text when set_errors is applied" do
      ss = AccountState.new()

      alias Foglet.TUI.Widgets.Modal.Form, as: ModalForm

      ss_with_error = %{
        ss
        | profile_form: ModalForm.set_errors(ss.profile_form, %{location: "is too short"})
      }

      state =
        build_state_for_role(:user)
        |> put_in([:screen_state, :account], ss_with_error)

      flat = render_account(state) |> collect_text_values()

      assert Enum.any?(flat, &String.contains?(&1, "is too short")),
             "expected inline error 'is too short' in profile tab render"
    end
  end

  describe "PREFS Modal.Form contract" do
    setup %{state: state} do
      {:update, prefs_state, []} = handle_account_key(%{key: :char, char: "2"}, state)
      %{state: prefs_state}
    end

    test "suppresses Modal.Form footer in prefs tab (FORM-03 default-off)", %{state: state} do
      # Phase 28 FORM-03 / D-06: Account tab-body forms do NOT render the
      # Modal.Form footer; the global command bar advertises [Enter]/[Esc].
      flat = render_account(state) |> collect_text_values()

      refute Enum.any?(flat, &String.contains?(&1, "[Enter] Submit")),
             "Modal.Form footer must NOT appear in Prefs tab body (Phase 28 D-06)"
    end

    test "defines enum field for theme selection", %{state: state} do
      form = state.screen_state.account.prefs_form

      assert Enum.any?(form.fields, &match?(%{name: :theme, type: :enum}, &1)),
             "expected theme enum field in prefs form spec"
    end

    test "FOG-131: timezone is an enum picker, not a raw text field", %{state: state} do
      form = state.screen_state.account.prefs_form
      tz = Enum.find(form.fields, &(&1.name == :timezone))

      assert tz.type == :enum, "expected :timezone field to be an enum picker (FOG-131)"
      assert is_list(tz.choices) and length(tz.choices) > 1
      assert "Etc/UTC" in tz.choices
      assert "America/Chicago" in tz.choices
    end

    test "FOG-131: cycling timezone enum changes the picker value without saving" do
      alias Foglet.TUI.Widgets.Modal.Form, as: ModalForm

      user = build_user_with_profile(timezone: "Etc/UTC")
      ss = AccountState.new(current_user: user)

      {form2, action} = ModalForm.handle_event(%{key: :down}, ss.prefs_form)

      assert action == nil, "cycling must not emit a submit action (FOG-131 save-only-on-save)"
      assert ModalForm.field_value(form2, :timezone) != "Etc/UTC"

      assert ModalForm.field_value(form2, :timezone) in Foglet.TUI.Screens.Account.Timezones.curated()
    end

    test "FOG-131: a non-curated saved timezone is preserved in picker choices" do
      user = build_user_with_profile(timezone: "Pacific/Tarawa")
      ss = AccountState.new(current_user: user)

      tz = Enum.find(ss.prefs_form.fields, &(&1.name == :timezone))

      assert "Pacific/Tarawa" in tz.choices,
             "user's saved timezone must remain selectable even if not curated"

      assert Foglet.TUI.Widgets.Modal.Form.field_value(ss.prefs_form, :timezone) ==
               "Pacific/Tarawa"
    end

    test "FOG-132: timezone enum field is configured for compact display", %{state: state} do
      tz = Enum.find(state.screen_state.account.prefs_form.fields, &(&1.name == :timezone))

      assert Map.get(tz, :display) == :compact,
             "expected :timezone field to render with display: :compact (FOG-132 — bound vertical footprint)"
    end

    test "FOG-132: PREFS render contains a single compact timezone row, not the full curated list",
         %{state: state} do
      flat = render_account(state) |> collect_text_values()

      curated = Foglet.TUI.Screens.Account.Timezones.curated()
      current = "Etc/UTC"
      others = curated -- [current]

      compact_rows =
        Enum.filter(flat, fn line ->
          is_binary(line) and String.contains?(line, "‹ #{current} ›")
        end)

      assert length(compact_rows) == 1,
             "expected exactly one compact timezone row showing the current value (FOG-132); got #{inspect(compact_rows)}"

      # No other curated zone may be painted as its own row — that is the
      # FOG-132 regression: the RadioGroup used to render every choice and
      # overlap Time format / Theme / footer at 80x24.
      leaked =
        Enum.filter(flat, fn line ->
          is_binary(line) and Enum.any?(others, &String.contains?(line, &1))
        end)

      assert leaked == [],
             "no non-current curated timezone may appear in the rendered PREFS body (FOG-132); leaked rows: #{inspect(leaked)}"

      # Time format and Theme labels must remain visible alongside the
      # bounded picker — overlap was the original symptom.
      assert Enum.any?(flat, &(is_binary(&1) and String.contains?(&1, "Time format"))),
             "Time format label must still render after the bounded timezone picker (FOG-132)"

      assert Enum.any?(flat, &(is_binary(&1) and String.contains?(&1, "Theme"))),
             "Theme label must still render after the bounded timezone picker (FOG-132)"
    end

    test "cycling down on focused theme enum field updates candidate_theme_id" do
      user = %Foglet.Accounts.User{
        id: "u1",
        handle: "alice",
        role: :user,
        timezone: "Etc/UTC",
        preferences: %{"time_format" => "12h"},
        theme: "gray"
      }

      state =
        user
        |> build_state(%{theme: Theme.resolve(:gray), theme_id: "gray"})
        |> put_in([:screen_state, :account], AccountState.new(current_user: user))

      {:update, state, []} = handle_account_key(%{key: :char, char: "2"}, state)

      account_state = %{state.screen_state.account | prefs_focus: :theme}
      state = put_in(state, [:screen_state, :account], account_state)

      {:update, preview_state, []} = handle_account_key(%{key: :down}, state)

      assert preview_state.screen_state.account.candidate_theme_id != nil,
             "expected candidate_theme_id to be set after cycling theme enum field down"
    end
  end

  describe "SSH_KEYS table contract" do
    setup %{state: state} do
      inserted_at = ~U[2026-04-24 10:11:12.123456Z]

      account_state =
        AccountState.new()
        |> Map.put(:active_tab, 2)
        |> Map.put(
          :ssh_keys,
          Foglet.TUI.Screens.Account.SSHKeysState.loaded(
            Foglet.TUI.Screens.Account.SSHKeysState.new(),
            [
              %{
                id: "k1",
                label: "laptop",
                fingerprint: "SHA256:abc123",
                inserted_at: inserted_at,
                last_used_at: nil,
                public_key: "ssh-ed25519 AAAAC3 laptop@test"
              }
            ]
          )
        )

      state = put_in(state, [:screen_state, :account], account_state)
      %{state: state}
    end

    test "builds ConsoleTable columns for SSH key rows", %{state: state} do
      table = state.screen_state.account.ssh_keys.table

      assert Enum.map(table.columns, & &1.label) == [
               "Label",
               "Fingerprint",
               "Added",
               "Last used"
             ]
    end

    test "renders empty state copy with empty list" do
      state =
        build_state_for_role(:user)
        |> put_in(
          [:screen_state, :account],
          AccountState.new()
          |> Map.put(:active_tab, 2)
          |> Map.put(:ssh_keys, SSHKeysState.loaded(SSHKeysState.new(), []))
        )

      flat = render_account(state) |> collect_text_values()

      assert Enum.any?(
               flat,
               &String.contains?(&1, "No SSH keys yet. Add one to sign in without a password.")
             ),
             "expected empty state copy in SSH KEYS tab"
    end

    test "pressing down on non-empty list advances cursor without crash", %{state: state} do
      result = handle_account_key(%{key: :down}, state)
      assert match?({:update, _, _}, result) or result == :no_match
    end

    test "pressing up, down, enter on empty list does not crash" do
      state =
        build_state_for_role(:user)
        |> put_in(
          [:screen_state, :account],
          AccountState.new()
          |> Map.put(:active_tab, 2)
          |> Map.put(:ssh_keys, SSHKeysState.loaded(SSHKeysState.new(), []))
        )

      for key <- [%{key: :up}, %{key: :down}, %{key: :enter}] do
        result = handle_account_key(key, state)

        assert match?({:update, _, _}, result) or result == :no_match,
               "expected no crash for key #{inspect(key)} on empty SSH KEYS list"
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Phase 28 Plan 05 — WR-01 :backtab on Account ProfileForm / PrefsForm
  # ---------------------------------------------------------------------------

  describe "FORM-02 :backtab on Account ProfileForm / PrefsForm (Phase 28 WR-01)" do
    alias Foglet.TUI.Screens.Account.PrefsForm
    alias Foglet.TUI.Screens.Account.ProfileForm
    alias Foglet.TUI.Widgets.Modal.Form, as: ModalForm

    test "FORM-02 :backtab on ProfileForm retreats focus by one" do
      user = build_user_with_profile()
      ss = AccountState.new(current_user: user)

      # Advance focus 0 → 1 via Tab so :backtab has somewhere to retreat to.
      {:ok, ss, []} = ProfileForm.handle_key(%{key: :tab}, ss, user)
      assert ss.profile_form.focus_index == 1

      {:ok, after_backtab, []} = ProfileForm.handle_key(%{key: :backtab}, ss, user)

      assert after_backtab.profile_form.focus_index == 0,
             "WR-01: :backtab on ProfileForm should retreat focus to 0; " <>
               "got focus_index = #{inspect(after_backtab.profile_form.focus_index)}"
    end

    test "FORM-02 :backtab on PrefsForm retreats focus by one" do
      user = build_user_with_profile()
      ss = AccountState.new(current_user: user)

      # Advance focus 0 → 1 (timezone → time_format enum).
      {:ok, ss, []} = PrefsForm.handle_key(%{key: :tab}, ss, user)
      assert ss.prefs_form.focus_index == 1

      {:ok, after_backtab, []} = PrefsForm.handle_key(%{key: :backtab}, ss, user)

      assert after_backtab.prefs_form.focus_index == 0,
             "WR-01: :backtab on PrefsForm should retreat focus to 0; " <>
               "got focus_index = #{inspect(after_backtab.prefs_form.focus_index)}"
    end

    test "WR-01 sanity: :backtab on PrefsForm preserves focused field via Modal.Form path" do
      # Equivalence check: Modal.Form treats :backtab ≡ :shift_tab. After WR-01
      # lands, ProfileForm/PrefsForm route :backtab into that path instead of
      # dropping it on the floor with :no_match.
      user = build_user_with_profile()
      ss = AccountState.new(current_user: user)

      {:ok, ss, []} = PrefsForm.handle_key(%{key: :tab}, ss, user)
      {:ok, ss, []} = PrefsForm.handle_key(%{key: :tab}, ss, user)
      assert ss.prefs_form.focus_index == 2

      {:ok, after_backtab, []} = PrefsForm.handle_key(%{key: :backtab}, ss, user)
      assert after_backtab.prefs_form.focus_index == 1

      # Verify the form's enum value was not silently mutated by routing
      # :backtab through an unintended clause.
      assert ModalForm.field_value(after_backtab.prefs_form, :time_format) ==
               ModalForm.field_value(ss.prefs_form, :time_format)
    end
  end

  # ---------------------------------------------------------------------------
  # Phase 28 Plan 05 — BL-01 :form modal lock release on async failure
  # ---------------------------------------------------------------------------

  describe "BL-01 :form modal lock release (Phase 28 FORM-05)" do
    alias Foglet.TUI.Widgets.Modal.Form, as: ModalForm

    setup do
      Process.put(:fake_oneliners_owner, self())

      user = %Foglet.Accounts.User{
        id: "u-bl01",
        handle: "alice",
        role: :mod,
        confirmed_at: DateTime.utc_now() |> DateTime.truncate(:microsecond)
      }

      {:ok, state} =
        App.init(%{
          session_context: %{
            user: user,
            user_id: user.id,
            domain: %{oneliners: Foglet.TUI.FakeOneliners}
          }
        })

      %{state: state, user: user}
    end

    defp open_oneliner_composer(state) do
      App.update({:key, %{key: :char, char: "O"}}, state)
    end

    defp open_hide_oneliner_modal(state) do
      {with_oneliner, []} =
        App.update(
          {:screen_task_result, :main_menu, :load_oneliners,
           {:ok, [%{id: "ol-bl01", body: "hello", user: %{handle: "bob"}}]}},
          state
        )

      App.update({:key, %{key: :char, char: "H"}}, with_oneliner)
    end

    test "doomed oneliner submit leaves form in {:error, _} (not :submitting)",
         %{state: state} do
      {with_modal, []} = open_oneliner_composer(state)

      # Drive the form to :submitting via the natural Enter-on-last-field path.
      {submitting, cmds} =
        App.update({:key, %{key: :enter}}, with_modal)

      assert %Foglet.TUI.Modal{type: :form, message: %ModalForm{} = form} = submitting.modal
      assert form.submit_state == :submitting
      assert [%Raxol.Core.Runtime.Command{type: :task}] = cmds

      {after_error, []} =
        App.update(
          {:screen_task_result, :main_menu, :submit_oneliner,
           {:ok, {:error, :same_user_latest_visible}}},
          submitting
        )

      assert %Foglet.TUI.Modal{type: :form, message: %ModalForm{} = form} =
               after_error.modal

      assert match?({:error, _}, form.submit_state)
    end

    test "doomed hide-oneliner submit leaves form in {:error, _} (not :submitting)",
         %{state: state} do
      {with_modal, []} = open_hide_oneliner_modal(state)

      # Type a valid reason then Enter to drive :submitting.
      {with_text, _} =
        App.update({:key, %{key: :char, char: "x"}}, with_modal)

      {submitting, cmds} =
        App.update({:key, %{key: :enter}}, with_text)

      assert %Foglet.TUI.Modal{type: :form, message: %ModalForm{} = form} = submitting.modal
      assert form.submit_state == :submitting
      assert [%Raxol.Core.Runtime.Command{type: :task}] = cmds

      {after_error, []} =
        App.update(
          {:screen_task_result, :main_menu, :submit_hide_oneliner, {:ok, {:error, :forbidden}}},
          submitting
        )

      assert %Foglet.TUI.Modal{type: :form, message: %ModalForm{} = form} =
               after_error.modal

      assert match?({:error, _}, form.submit_state)
    end

    test "after doomed oneliner error, %{key: :escape} dismisses the modal", %{state: state} do
      {with_modal, []} = open_oneliner_composer(state)
      {submitting, _cmds} = App.update({:key, %{key: :enter}}, with_modal)

      {after_error, []} =
        App.update(
          {:screen_task_result, :main_menu, :submit_oneliner,
           {:ok, {:error, :same_user_latest_visible}}},
          submitting
        )

      # Today the form is still locked at :submitting and the lock-guard
      # swallows :escape. After the BL-01 fix, set_submit_state has run, the
      # auto-reset preamble collapses {:error, _} → :idle, and the Esc cancel
      # clause fires → modal dismisses.
      {after_esc, _cmds} = App.update({:key, %{key: :escape}}, after_error)

      assert after_esc.modal == nil,
             "BL-01: Esc must dismiss modal after a doomed submit; modal still open: " <>
               inspect(after_esc.modal)
    end

    test "after doomed hide-oneliner error, %{key: :escape} dismisses the modal",
         %{state: state} do
      {with_modal, []} = open_hide_oneliner_modal(state)
      {with_text, _} = App.update({:key, %{key: :char, char: "x"}}, with_modal)
      {submitting, _cmds} = App.update({:key, %{key: :enter}}, with_text)

      {after_error, []} =
        App.update(
          {:screen_task_result, :main_menu, :submit_hide_oneliner, {:ok, {:error, :forbidden}}},
          submitting
        )

      {after_esc, _cmds} = App.update({:key, %{key: :escape}}, after_error)

      assert after_esc.modal == nil,
             "BL-01: Esc must dismiss hide-modal after a doomed submit; modal still open: " <>
               inspect(after_esc.modal)
    end
  end

  # ---------------------------------------------------------------------------
  # FOG-130 — context-aware key bar, revoke confirms, PREFS enum hint
  # ---------------------------------------------------------------------------

  describe "FOG-130 Item 1: tab-context-aware key bar" do
    # Account chrome at 80×24 is tight enough that the priority-truncating key
    # bar drops the Actions group on some tabs. We render at a wider terminal
    # so every advertised command shows up in `collect_text_values/1`.
    defp wide_terminal(state), do: %{state | terminal_size: {140, 30}}

    test "PROFILE shows form-tab cluster (Tab Next, Enter Save, Esc Cancel)" do
      state =
        build_state_for_role(:user)
        |> wide_terminal()
        |> put_in([:screen_state, :account], AccountState.new())

      joined = render_account(state) |> collect_text_values() |> Enum.join("|")

      assert String.contains?(joined, "Next"), "expected 'Next' key bar label on PROFILE"
      assert String.contains?(joined, "Save")
      assert String.contains?(joined, "Cancel")
      refute String.contains?(joined, "Add key")
      # "Generate invite" must not advertise on the PROFILE tab key bar.
      refute String.contains?(joined, "Generate invite")
    end

    test "SSH KEYS list mode advertises A Add key / R Refresh / D Revoke key, no Save/Cancel" do
      account_state =
        AccountState.new()
        |> Map.put(:active_tab, 2)
        |> Map.put(:ssh_keys, SSHKeysState.loaded(SSHKeysState.new(), []))

      state =
        build_state_for_role(:user)
        |> wide_terminal()
        |> put_in([:screen_state, :account], account_state)

      joined = render_account(state) |> collect_text_values() |> Enum.join("|")

      assert String.contains?(joined, "Add key")
      assert String.contains?(joined, "Refresh")
      assert String.contains?(joined, "Revoke key")
      # The key bar must not still advertise Save on the SSH KEYS list mode.
      assert not Enum.any?(
               render_account(state) |> collect_text_values(),
               &(&1 == "Save")
             )
    end

    test "SSH KEYS confirm-revoke mode advertises Enter Revoke key / Esc Keep key" do
      keys = SSHKeysState.new()
      keys = SSHKeysState.loaded(keys, [%{id: "k1", label: "laptop", fingerprint: "SHA256:abc"}])
      keys = SSHKeysState.start_confirm_revoke(keys)

      account_state =
        AccountState.new()
        |> Map.put(:active_tab, 2)
        |> Map.put(:ssh_keys, keys)

      state =
        build_state_for_role(:user)
        |> wide_terminal()
        |> put_in([:screen_state, :account], account_state)

      joined = render_account(state) |> collect_text_values() |> Enum.join("|")

      assert String.contains?(joined, "Revoke key")
      assert String.contains?(joined, "Keep key")
      # In confirm-revoke mode, Add key must not be advertised on the key bar.
      refute String.contains?(joined, "Add key")
    end

    test "INVITES list mode advertises G Generate invite / D Revoke invite" do
      state =
        :sysop
        |> build_state_for_role()
        |> wide_terminal()
        |> put_in(
          [:screen_state, :account],
          AccountState.new(invites_visible?: true, active: 3)
          |> Map.update!(:invites, &Foglet.TUI.Screens.Shared.InvitesState.loaded(&1, []))
        )

      joined = render_account(state) |> collect_text_values() |> Enum.join("|")

      assert String.contains?(joined, "Generate invite")
      assert String.contains?(joined, "Revoke invite")
    end

    test "PREFS adds ↑/↓ Change hint when an enum field is focused (Item 4)" do
      ss =
        AccountState.new()
        |> Map.put(:active_tab, 1)
        |> Map.put(:prefs_focus, :theme)

      state =
        build_state_for_role(:user)
        |> put_in([:screen_state, :account], ss)

      joined = render_account(state) |> collect_text_values() |> Enum.join("|")

      assert String.contains?(joined, "Change"),
             "expected ↑/↓ Change hint when Theme enum is focused"
    end

    test "PREFS does not add Change hint when a text field is focused" do
      ss =
        AccountState.new()
        |> Map.put(:active_tab, 1)
        |> Map.put(:prefs_focus, :timezone)

      state =
        build_state_for_role(:user)
        |> put_in([:screen_state, :account], ss)

      flat = render_account(state) |> collect_text_values()

      # The "Change" key-bar label only renders for enum fields. Some surface
      # copy may contain "Change", so anchor on the exact key-bar element.
      refute Enum.any?(flat, &(&1 == "Change")),
             "↑/↓ Change must not advertise when a text field is focused"
    end
  end

  describe "FOG-130 Item 2: SSH KEYS revoke confirmation flow" do
    test "D opens confirm sub-mode without performing the revoke" do
      user = AccountsFixtures.user_fixture()
      key = AccountsFixtures.ssh_key_fixture(user, %{label: "laptop"})
      state = build_state(user, %{})

      {:update, state, []} = handle_account_key(%{key: :char, char: "3"}, state)
      {:update, state, []} = handle_account_key(%{key: :char, char: "d"}, state)

      assert state.screen_state.account.ssh_keys.mode == :confirm_revoke
      assert state.screen_state.account.ssh_keys.confirm_target.label == "laptop"
      assert [%{id: still_there}] = Accounts.list_ssh_keys(user)
      assert still_there == key.id
    end

    test "Esc cancels the confirm and leaves the list unchanged" do
      user = AccountsFixtures.user_fixture()
      _ = AccountsFixtures.ssh_key_fixture(user, %{label: "laptop"})
      state = build_state(user, %{})

      {:update, state, []} = handle_account_key(%{key: :char, char: "3"}, state)
      {:update, state, []} = handle_account_key(%{key: :char, char: "d"}, state)
      assert state.screen_state.account.ssh_keys.mode == :confirm_revoke

      {:update, state, []} = handle_account_key(%{key: :escape}, state)

      assert state.screen_state.account.ssh_keys.mode == :list
      assert state.screen_state.account.ssh_keys.confirm_target == nil
      assert [_] = Accounts.list_ssh_keys(user)
    end

    test "confirm body shows label + fingerprint and never the raw public key" do
      raw_key = "ssh-ed25519 SECRET-MATERIAL-DO-NOT-LEAK alice@example"

      keys =
        SSHKeysState.loaded(SSHKeysState.new(), [
          %{id: "k1", label: "laptop", fingerprint: "SHA256:abc", public_key: raw_key}
        ])

      keys = SSHKeysState.start_confirm_revoke(keys)

      account_state =
        AccountState.new()
        |> Map.put(:active_tab, 2)
        |> Map.put(:ssh_keys, keys)

      state =
        build_state_for_role(:user)
        |> wide_terminal()
        |> put_in([:screen_state, :account], account_state)

      flat = render_account(state) |> collect_text_values()
      joined = Enum.join(flat, "\n")

      assert Enum.any?(flat, &String.contains?(&1, "Revoke SSH key?"))
      assert String.contains?(joined, "This removes laptop from your account.")
      refute String.contains?(joined, "SECRET-MATERIAL")
    end
  end

  describe "FOG-130 Item 3: INVITES revoke confirmation flow" do
    alias Foglet.TUI.Screens.Shared.InvitesState

    test "D opens confirm sub-mode and Esc cancels back to the list" do
      invites =
        InvitesState.loaded(InvitesState.new(), [
          %{code: "ABC123", status: :available, issuer_id: 1, inserted_at: nil}
        ])

      account_state =
        AccountState.new(invites_visible?: true, active: 3)
        |> Map.put(:invites, invites)

      state =
        build_state_for_role(:sysop)
        |> put_in([:screen_state, :account], account_state)

      {:update, state, []} = handle_account_key(%{key: :char, char: "d"}, state)
      assert state.screen_state.account.invites.mode == :confirm_revoke
      assert state.screen_state.account.invites.confirm_target.code == "ABC123"

      {:update, state, []} = handle_account_key(%{key: :escape}, state)
      assert state.screen_state.account.invites.mode == :list
      assert state.screen_state.account.invites.confirm_target == nil
    end

    test "confirm body advertises Revoke invite / Keep invite copy" do
      invites =
        InvitesState.start_confirm_revoke(
          InvitesState.loaded(InvitesState.new(), [
            %{code: "XYZ987", status: :available, issuer_id: 1, inserted_at: nil}
          ])
        )

      account_state =
        AccountState.new(invites_visible?: true, active: 3)
        |> Map.put(:invites, invites)

      state =
        build_state_for_role(:sysop)
        |> put_in([:screen_state, :account], account_state)

      flat = render_account(state) |> collect_text_values()
      joined = Enum.join(flat, "\n")

      assert Enum.any?(flat, &String.contains?(&1, "Revoke invite?"))
      assert String.contains?(joined, "Code XYZ987 will stop working.")
      assert Enum.any?(flat, &String.contains?(&1, "Enter Revoke invite"))
      assert Enum.any?(flat, &String.contains?(&1, "Esc Keep invite"))
    end
  end

  describe "FOG-130 Item 5/6: copy + Real name optional reconciliation" do
    test "PROFILE save success uses 'Profile saved.' (not generic Account changes saved)" do
      user = build_user_with_profile()
      context = Context.new(current_user: user, route: :account)

      {state, _} =
        Account.update(
          {:task_result, :account_save_profile, {:ok, {:ok, user}}},
          Account.init(context),
          context
        )

      assert state.status_message == "Profile saved."
    end

    test "PREFS save success uses 'Preferences saved.'" do
      user = build_user_with_profile()
      context = Context.new(current_user: user, route: :account)

      {state, _} =
        Account.update(
          {:task_result, :account_save_prefs, {:ok, {:ok, user}}},
          Account.init(context),
          context
        )

      assert state.status_message == "Preferences saved."
    end

    test "PROFILE save failure uses 'Profile was not saved.'" do
      user = build_user_with_profile()
      context = Context.new(current_user: user, route: :account)

      changeset = Accounts.User.profile_changeset(user, %{location: String.duplicate("x", 200)})

      {state, _} =
        Account.update(
          {:task_result, :account_save_profile, {:ok, {:error, changeset}}},
          Account.init(context),
          context
        )

      assert state.status_message == "Profile was not saved."
    end

    test "Submitting a Profile draft no longer flashes 'Profile ready to save.'" do
      alias Foglet.TUI.Screens.Account.ProfileForm
      alias Foglet.TUI.Widgets.Modal.Form, as: ModalForm

      user = build_user_with_profile()
      ss = AccountState.new(current_user: user)

      # Drive ProfileForm to submit by jumping focus to last field then Enter.
      {:ok, ss, []} = ProfileForm.handle_key(%{key: :tab}, ss, user)
      {:ok, ss, []} = ProfileForm.handle_key(%{key: :tab}, ss, user)
      assert ss.profile_form.focus_index == 2
      assert ModalForm.field_value(ss.profile_form, :real_name) == user.real_name

      {:ok, after_submit, cmds} = ProfileForm.handle_key(%{key: :enter}, ss, user)

      assert [{:account_save_profile, _}] = cmds
      refute after_submit.status_message == "Profile ready to save."
    end

    test "real_name field carries optional helper description" do
      ss = AccountState.new()

      real_name_field = Enum.find(ss.profile_form.fields, &(&1.name == :real_name))

      refute Map.get(real_name_field, :required, false)

      assert real_name_field.description ==
               "For friends and the sysop; blank uses your handle."
    end

    test "Timezone and Theme fields carry helper descriptions per FOG-127" do
      ss = AccountState.new()

      timezone = Enum.find(ss.prefs_form.fields, &(&1.name == :timezone))
      theme = Enum.find(ss.prefs_form.fields, &(&1.name == :theme))

      assert timezone.description == "Use ↑/↓ to pick a timezone; save to keep it."
      assert theme.description == "Preview changes here; save to keep them."
    end
  end
end
