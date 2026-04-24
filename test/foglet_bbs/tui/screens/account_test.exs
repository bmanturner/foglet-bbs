defmodule Foglet.TUI.Screens.AccountTest do
  use FogletBbs.DataCase, async: false

  import Foglet.TUI.RenderHelpers

  alias Foglet.Accounts
  alias Foglet.Config
  alias Foglet.Sessions.Session
  alias Foglet.TUI.App
  alias Foglet.TUI.Screens.Account
  alias Foglet.TUI.Theme
  alias FogletBbs.AccountsFixtures

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
    build_state(%Foglet.Accounts.User{id: "u1", handle: "alice", role: role}, session_context)
  end

  setup do
    %{state: build_state_for_role(:user)}
  end

  describe "init_screen_state/1" do
    test "returns a struct with active_tab: 0 and a Tabs wrapper state" do
      ss = Account.init_screen_state()
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

      ss = Account.init_screen_state(current_user: user)

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

  describe "render/1" do
    test "does not crash with default screen state", %{state: state} do
      state = put_in(state, [:screen_state, :account], Account.init_screen_state())
      assert _ = Account.render(state)
    end

    test "shows PROFILE and PREFS tab labels by default", %{state: state} do
      state = put_in(state, [:screen_state, :account], Account.init_screen_state())
      flat = Account.render(state) |> collect_text_values()
      assert Enum.any?(flat, &String.contains?(&1, "PROFILE"))
      assert Enum.any?(flat, &String.contains?(&1, "PREFS"))
    end

    test "omits INVITES when InvitesSurface.visible?/2 returns false" do
      # role: :user with sysop_only policy => not visible
      state =
        :user
        |> build_state_for_role(%{invite_code_generators: "sysop_only"})
        |> put_in([:screen_state, :account], Account.init_screen_state())

      flat = Account.render(state) |> collect_text_values()
      refute Enum.any?(flat, &String.contains?(&1, "INVITES"))
    end

    test "includes INVITES when InvitesSurface.visible?/2 returns true" do
      # role: :sysop => always visible per D-07
      state = build_state_for_role(:sysop)
      state = put_in(state, [:screen_state, :account], Account.init_screen_state(role: :sysop))
      flat = Account.render(state) |> collect_text_values()
      assert Enum.any?(flat, &String.contains?(&1, "INVITES"))
    end

    test "any_user policy shows INVITES for a regular user" do
      # any_user
      state =
        :user
        |> build_state_for_role(%{invite_code_generators: "any_user"})
        |> put_in([:screen_state, :account], Account.init_screen_state())

      flat = Account.render(state) |> collect_text_values()
      assert Enum.any?(flat, &String.contains?(&1, "INVITES"))
    end

    test "mods and sysop_only policies hide INVITES for a regular user" do
      # mods sysop_only
      for policy <- ["mods", "sysop_only"] do
        state =
          :user
          |> build_state_for_role(%{invite_code_generators: policy})
          |> put_in([:screen_state, :account], Account.init_screen_state())

        flat = Account.render(state) |> collect_text_values()
        refute Enum.any?(flat, &String.contains?(&1, "INVITES"))
      end
    end

    test "nil user does not see INVITES under any_user policy" do
      # nil user
      state = build_state(nil, %{invite_code_generators: "any_user"})
      flat = Account.render(state) |> collect_text_values()
      refute Enum.any?(flat, &String.contains?(&1, "INVITES"))
    end

    test "visibility changes in session_context rebuild tab list on render" do
      state =
        :user
        |> build_state_for_role(%{invite_code_generators: "sysop_only"})
        |> put_in([:screen_state, :account], Account.init_screen_state())

      hidden_flat = Account.render(state) |> collect_text_values()
      refute Enum.any?(hidden_flat, &String.contains?(&1, "INVITES"))

      visible_state = %{state | session_context: %{invite_code_generators: "any_user"}}
      visible_flat = Account.render(visible_state) |> collect_text_values()
      assert Enum.any?(visible_flat, &String.contains?(&1, "INVITES"))
    end

    test "renders no fake invite or approval buttons", %{state: state} do
      state = put_in(state, [:screen_state, :account], Account.init_screen_state())
      flat = Account.render(state) |> collect_text_values()
      forbidden = ["Generate", "Revoke", "Approve"]

      for word <- forbidden do
        refute Enum.any?(flat, &String.contains?(&1, word)),
               "Expected #{inspect(word)} not to appear in Account render output"
      end
    end

    test "PROFILE and PREFS render editable field labels", %{state: state} do
      state =
        put_in(
          state,
          [:screen_state, :account],
          Account.init_screen_state(current_user: state.current_user)
        )

      profile_flat = Account.render(state) |> collect_text_values()
      assert Enum.any?(profile_flat, &String.contains?(&1, "Location"))
      assert Enum.any?(profile_flat, &String.contains?(&1, "Tagline"))
      assert Enum.any?(profile_flat, &String.contains?(&1, "Real name"))

      {:update, prefs_state, []} = Account.handle_key(%{key: :char, char: "2"}, state)
      prefs_flat = Account.render(prefs_state) |> collect_text_values()
      assert Enum.any?(prefs_flat, &String.contains?(&1, "Timezone"))
      assert Enum.any?(prefs_flat, &String.contains?(&1, "Time format"))
      assert Enum.any?(prefs_flat, &String.contains?(&1, "Theme"))
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
        |> put_in([:screen_state, :account], Account.init_screen_state(current_user: user))

      {:update, state, []} = Account.handle_key(%{key: :char, char: "2"}, state)
      before_preview = inspect(Account.render(state))

      account_state = %{state.screen_state.account | prefs_focus: :theme}
      state = put_in(state, [:screen_state, :account], account_state)

      {:update, preview_state, []} = Account.handle_key(%{key: :down}, state)

      assert preview_state.screen_state.account.candidate_theme_id != nil
      assert preview_state.session_context.theme == Theme.resolve(:gray)
      assert inspect(Account.render(preview_state)) != before_preview

      {:update, cancelled_state, []} = Account.handle_key(%{key: :escape}, preview_state)

      assert cancelled_state.screen_state.account.candidate_theme_id == nil
      assert cancelled_state.screen_state.account.prefs_draft.theme == "gray"
      assert cancelled_state.session_context.theme == Theme.resolve(:gray)
    end
  end

  describe "handle_key/2" do
    setup %{state: state} do
      state = put_in(state, [:screen_state, :account], Account.init_screen_state())
      %{state: state}
    end

    test "Right arrow advances active_tab via Tabs.handle_event/2", %{state: state} do
      {:update, new_state, _cmds} = Account.handle_key(%{key: :right}, state)
      assert new_state.screen_state.account.active_tab == 1
    end

    test "visibility changes in session_context rebuild tab list on handle-key", %{state: state} do
      state = %{state | session_context: %{invite_code_generators: "any_user"}}

      {:update, new_state, _cmds} = Account.handle_key(%{key: :char, char: "3"}, state)

      assert new_state.screen_state.account.active_tab == 2
      flat = Account.render(new_state) |> collect_text_values()
      assert Enum.any?(flat, &String.contains?(&1, "INVITES"))
    end

    test "digit '2' jumps to second tab (index 1)", %{state: state} do
      {:update, new_state, _cmds} = Account.handle_key(%{key: :char, char: "2"}, state)
      assert new_state.screen_state.account.active_tab == 1
    end

    test "'Q' returns to :main_menu", %{state: state} do
      {:update, new_state, _cmds} = Account.handle_key(%{key: :char, char: "Q"}, state)
      assert new_state.current_screen == :main_menu
    end

    test "'q' returns to :main_menu", %{state: state} do
      {:update, new_state, _cmds} = Account.handle_key(%{key: :char, char: "q"}, state)
      assert new_state.current_screen == :main_menu
    end

    test "non-text unknown key returns :no_match", %{state: state} do
      assert :no_match = Account.handle_key(%{key: :f12}, state)
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
        case Account.handle_key(key, state) do
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

  describe "App Account save command handling" do
    test "successful save persists profile and preferences and refreshes active session snapshots" do
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
            Account.init_screen_state(current_user: user)
            |> Map.put(:profile_dirty?, true)
            |> Map.put(:prefs_dirty?, true)
            |> Map.put(:candidate_theme_id, "amber")
        }
      }

      {state, []} =
        App.update(
          {:account_save_profile,
           %{location: "Mist Harbor", tagline: "low clouds", real_name: "Alice Example"}},
          state
        )

      {state, []} =
        App.update(
          {:account_save_prefs,
           %{
             timezone: "America/Chicago",
             preferences: %{"time_format" => "24h"},
             theme: "amber"
           }},
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

    test "failed save renders errors and leaves active snapshots unchanged" do
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
            Account.init_screen_state(current_user: user)
            |> Map.put(:active_tab, 1)
            |> Map.put(:prefs_dirty?, true)
        }
      }

      original_user = state.current_user
      original_context = state.session_context
      original_session = Session.get_state(session_pid)

      {new_state, []} =
        App.update(
          {:account_save_prefs,
           %{
             timezone: "Not/AZone",
             preferences: %{"time_format" => "24h"},
             theme: "amber"
           }},
          state
        )

      assert new_state.current_user == original_user
      assert new_state.session_context == original_context

      _ = :sys.get_state(session_pid)
      assert Session.get_state(session_pid).timezone == original_session.timezone
      assert Session.get_state(session_pid).time_format == original_session.time_format
      assert Session.get_state(session_pid).theme_id == original_session.theme_id

      assert %{timezone: message} = new_state.screen_state.account.prefs_errors
      assert String.contains?(message, "valid IANA timezone")

      flat = Account.render(Map.from_struct(new_state)) |> collect_text_values()
      assert Enum.any?(flat, &String.contains?(&1, "Timezone error:"))
    end
  end

  describe "live INVITES actions" do
    setup :restore_invite_config

    test "persists exactly one invite and displays last_generated_code under any_user" do
      # persists exactly one invite last_generated_code any_user
      user = AccountsFixtures.user_fixture()
      state = build_state(user, %{invite_code_generators: "any_user"})

      assert {:ok, []} = Accounts.list_invites(user)

      {:update, state, []} = Account.handle_key(%{key: :char, char: "3"}, state)
      {:update, state, []} = Account.handle_key(%{key: :char, char: "g"}, state)

      assert {:ok, [invite]} = Accounts.list_invites(user)
      assert state.screen_state.account.invites.last_generated_code == invite.code
      assert [%{code: code, status: :available}] = state.screen_state.account.invites.items
      assert code == invite.code

      flat = Account.render(state) |> collect_text_values()
      assert Enum.any?(flat, &String.contains?(&1, "New invite code: #{invite.code}"))
    end

    test "refresh, select, and revoke delegate through shared Account INVITES actions" do
      user = AccountsFixtures.user_fixture()
      state = build_state(user, %{invite_code_generators: "any_user"})

      {:ok, first} = Accounts.create_invite(user)
      {:ok, second} = Accounts.create_invite(user)

      {:update, state, []} = Account.handle_key(%{key: :char, char: "3"}, state)
      assert Enum.count(state.screen_state.account.invites.items) == 2

      {:update, state, []} = Account.handle_key(%{key: :down}, state)
      assert state.screen_state.account.invites.selected_index == 1
      selected_code = Enum.at(state.screen_state.account.invites.items, 1).code
      other_code = Enum.find([first.code, second.code], &(&1 != selected_code))

      {:update, state, []} = Account.handle_key(%{key: :char, char: "d"}, state)
      assert state.screen_state.account.invites.error == "You are not allowed to manage invites."
      assert {:ok, %{status: :available}} = Accounts.get_invite_status(selected_code)
      assert {:ok, %{status: :available}} = Accounts.get_invite_status(other_code)

      {:update, state, []} = Account.handle_key(%{key: :char, char: "r"}, state)
      assert Enum.any?(state.screen_state.account.invites.items, &(&1.code == selected_code))
      assert state.screen_state.account.invites.error == nil
    end

    test "hidden INVITES tab leaves generate unavailable for disallowed Account policy" do
      user = AccountsFixtures.user_fixture()
      state = build_state(user, %{invite_code_generators: "sysop_only"})

      assert {:update, _state, []} = Account.handle_key(%{key: :char, char: "g"}, state)
      assert {:ok, []} = Accounts.list_invites(user)
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
end
