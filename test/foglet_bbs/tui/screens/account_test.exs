defmodule Foglet.TUI.Screens.AccountTest do
  use FogletBbs.DataCase, async: false

  import Foglet.TUI.RenderHelpers

  alias Foglet.Accounts
  alias Foglet.Accounts.Invites
  alias Foglet.Config
  alias Foglet.Sessions.Session
  alias Foglet.TUI.App
  alias Foglet.TUI.Presentation
  alias Foglet.TUI.Screens.Account
  alias Foglet.TUI.Screens.Account.SSHKeysState
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

  describe "render/1 (Account.render/1 traceability)" do
    test "renders Chrome V2 operator breadcrumb and declares operator mode", %{state: state} do
      state = put_in(state, [:screen_state, :account], Account.init_screen_state())
      flat = Account.render(state) |> collect_text_values()

      assert Enum.any?(flat, &String.contains?(&1, "Foglet"))
      assert Enum.any?(flat, &String.contains?(&1, "Account"))
      assert Presentation.mode_for!(:account) == :operator

      assert File.read!("lib/foglet_bbs/tui/screens/account.ex") =~
               "Presentation.mode_for!(:account)"
    end

    test "KEYS-01 shows PROFILE, PREFS, and SSH KEYS tab labels by default", %{state: state} do
      state = put_in(state, [:screen_state, :account], Account.init_screen_state())
      flat = Account.render(state) |> collect_text_values()
      assert Enum.any?(flat, &String.contains?(&1, "PROFILE"))
      assert Enum.any?(flat, &String.contains?(&1, "PREFS"))
      assert Enum.any?(flat, &String.contains?(&1, "SSH KEYS"))
    end

    test "KEYS-01 SSH KEYS tab renders an empty key-list state", %{state: state} do
      account_state =
        Account.init_screen_state()
        |> Map.put(:active_tab, 2)
        |> Map.put(:ssh_keys, SSHKeysState.loaded(SSHKeysState.new(), []))

      state = put_in(state, [:screen_state, :account], account_state)
      flat = Account.render(state) |> collect_text_values()

      assert Enum.any?(flat, &String.contains?(&1, "No SSH keys registered yet."))
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

  describe "handle_key/2 (Account.handle_key/2 traceability)" do
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

      {:update, new_state, _cmds} = Account.handle_key(%{key: :char, char: "4"}, state)

      assert new_state.screen_state.account.active_tab == 3
      flat = Account.render(new_state) |> collect_text_values()
      assert Enum.any?(flat, &String.contains?(&1, "INVITES"))
    end

    test "digit '2' jumps to second tab (index 1)", %{state: state} do
      {:update, new_state, _cmds} = Account.handle_key(%{key: :char, char: "2"}, state)
      assert new_state.screen_state.account.active_tab == 1
    end

    test "KEYS-01 digit '3' selects SSH KEYS when invites are hidden", %{state: state} do
      {:update, new_state, _cmds} = Account.handle_key(%{key: :char, char: "3"}, state)
      assert new_state.screen_state.account.active_tab == 2

      flat = Account.render(new_state) |> collect_text_values()
      assert Enum.any?(flat, &String.contains?(&1, "SSH KEYS"))
    end

    test "Ctrl+Q returns to :main_menu", %{state: state} do
      {:update, new_state, _cmds} =
        Account.handle_key(%{key: :char, char: "Q", ctrl: true}, state)

      assert new_state.current_screen == :main_menu
    end

    test "'q' is delegated to the active form", %{state: state} do
      {:update, new_state, _cmds} = Account.handle_key(%{key: :char, char: "q"}, state)
      assert new_state.current_screen == :account
      assert new_state.screen_state.account.profile_dirty?
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

      assert {:ok, []} = Invites.list_invites(user)

      {:update, state, []} = Account.handle_key(%{key: :char, char: "4"}, state)
      {:update, state, []} = Account.handle_key(%{key: :char, char: "g"}, state)

      assert {:ok, [invite]} = Invites.list_invites(user)
      assert state.screen_state.account.invites.last_generated_code == invite.code
      assert [%{code: code, status: :available}] = state.screen_state.account.invites.items
      assert code == invite.code

      flat = Account.render(state) |> collect_text_values()
      assert Enum.any?(flat, &String.contains?(&1, "New invite code: #{invite.code}"))
    end

    test "refresh, select, and revoke delegate through shared Account INVITES actions" do
      user = AccountsFixtures.user_fixture()
      state = build_state(user, %{invite_code_generators: "any_user"})

      {:ok, first} = Invites.create_invite(user)
      {:ok, second} = Invites.create_invite(user)

      {:update, state, []} = Account.handle_key(%{key: :char, char: "4"}, state)
      assert Enum.count(state.screen_state.account.invites.items) == 2

      {:update, state, []} = Account.handle_key(%{key: :down}, state)
      assert state.screen_state.account.invites.selected_index == 1
      selected_code = Enum.at(state.screen_state.account.invites.items, 1).code
      other_code = Enum.find([first.code, second.code], &(&1 != selected_code))

      {:update, state, []} = Account.handle_key(%{key: :char, char: "d"}, state)
      assert state.screen_state.account.invites.error == "You are not allowed to manage invites."
      assert {:ok, %{status: :available}} = Invites.get_invite_status(selected_code)
      assert {:ok, %{status: :available}} = Invites.get_invite_status(other_code)

      {:update, state, []} = Account.handle_key(%{key: :char, char: "r"}, state)
      assert Enum.any?(state.screen_state.account.invites.items, &(&1.code == selected_code))
      assert state.screen_state.account.invites.error == nil
    end

    test "hidden INVITES tab leaves generate unavailable for disallowed Account policy" do
      user = AccountsFixtures.user_fixture()
      state = build_state(user, %{invite_code_generators: "sysop_only"})

      assert {:update, _state, []} = Account.handle_key(%{key: :char, char: "g"}, state)
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

      {:update, state, []} = Account.handle_key(%{key: :char, char: "3"}, state)

      assert [%{id: key_id, label: "laptop"}] = state.screen_state.account.ssh_keys.items
      assert key_id == own_key.id

      {:update, state, []} = Account.handle_key(%{key: :char, char: "r"}, state)
      assert [%{id: ^key_id}] = state.screen_state.account.ssh_keys.items

      flat = Account.render(state) |> collect_text_values()
      assert Enum.any?(flat, &String.contains?(&1, "Refresh"))
      assert Enum.any?(flat, &String.contains?(&1, "Revoke"))
    end

    test "KEYS-02 add flow stores a valid key, refreshes list, and shows status" do
      user = AccountsFixtures.user_fixture()
      state = build_state(user, %{})

      {:update, state, []} = Account.handle_key(%{key: :char, char: "3"}, state)
      {:update, state, []} = Account.handle_key(%{key: :char, char: "a"}, state)

      account_state =
        put_ssh_key_form(state.screen_state.account, %{
          label: "workstation",
          public_key: @alternate_ssh_public_key
        })

      state = put_in(state, [:screen_state, :account], account_state)

      {:update, state, []} = Account.handle_key(%{key: :enter}, state)

      assert [%{label: "workstation", fingerprint: "SHA256:" <> _}] = Accounts.list_ssh_keys(user)
      assert state.screen_state.account.ssh_keys.status_message == "SSH key added."
      assert [%{label: "workstation"}] = state.screen_state.account.ssh_keys.items
    end

    test "KEYS-02 add flow shows terminal-visible validation errors" do
      user = AccountsFixtures.user_fixture()
      _existing = AccountsFixtures.ssh_key_fixture(user, %{label: "laptop"})
      state = build_state(user, %{})

      {:update, state, []} = Account.handle_key(%{key: :char, char: "3"}, state)
      {:update, state, []} = Account.handle_key(%{key: :char, char: "a"}, state)
      {:update, blank_state, []} = Account.handle_key(%{key: :enter}, state)

      blank_flat = Account.render(blank_state) |> collect_text_values()
      assert Enum.any?(blank_flat, &String.contains?(&1, "label"))
      assert Enum.any?(blank_flat, &String.contains?(&1, "public_key"))

      account_state =
        put_ssh_key_form(blank_state.screen_state.account, %{
          label: "bad",
          public_key: "invalid OpenSSH material"
        })

      invalid_state = put_in(blank_state, [:screen_state, :account], account_state)

      {:update, invalid_state, []} = Account.handle_key(%{key: :enter}, invalid_state)
      invalid_flat = Account.render(invalid_state) |> collect_text_values()
      assert Enum.any?(invalid_flat, &String.contains?(&1, "invalid OpenSSH"))

      account_state =
        put_ssh_key_form(invalid_state.screen_state.account, %{
          label: "other",
          public_key: AccountsFixtures.default_ssh_public_key()
        })

      duplicate_fingerprint_state =
        put_in(invalid_state, [:screen_state, :account], account_state)

      {:update, duplicate_fingerprint_state, []} =
        Account.handle_key(%{key: :enter}, duplicate_fingerprint_state)

      duplicate_fingerprint_flat =
        duplicate_fingerprint_state |> Account.render() |> collect_text_values()

      assert Enum.any?(duplicate_fingerprint_flat, &String.contains?(&1, "already been taken"))

      account_state =
        put_ssh_key_form(duplicate_fingerprint_state.screen_state.account, %{
          label: "laptop",
          public_key: @alternate_ssh_public_key
        })

      duplicate_label_state =
        put_in(duplicate_fingerprint_state, [:screen_state, :account], account_state)

      {:update, duplicate_label_state, []} =
        Account.handle_key(%{key: :enter}, duplicate_label_state)

      duplicate_label_flat = duplicate_label_state |> Account.render() |> collect_text_values()
      assert Enum.any?(duplicate_label_flat, &String.contains?(&1, "already been taken"))
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

      {:update, state, []} = Account.handle_key(%{key: :char, char: "3"}, state)
      {:update, state, []} = Account.handle_key(%{key: :down}, state)
      assert state.screen_state.account.ssh_keys.selected_index == 1

      {:update, state, []} = Account.handle_key(%{key: :char, char: "d"}, state)

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

      {:update, empty_state, []} = Account.handle_key(%{key: :char, char: "d"}, empty_state)
      assert empty_state.screen_state.account.ssh_keys.errors.general == "No SSH key is selected."
    end

    test "KEYS-04 revoke handles not found without crashing" do
      user = AccountsFixtures.user_fixture()
      key = AccountsFixtures.ssh_key_fixture(user)
      state = build_state(user, %{})

      {:update, state, []} = Account.handle_key(%{key: :char, char: "3"}, state)
      {:ok, _revoked} = Accounts.revoke_ssh_key(user, key.id)

      {:update, state, []} = Account.handle_key(%{key: :char, char: "d"}, state)

      assert state.screen_state.account.ssh_keys.errors.general ==
               "That SSH key could not be found."
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
          Account.init_screen_state()
          |> set_active_tab(@tab)

        state =
          build_state_for_role(:user)
          |> put_in([:screen_state, :account], ss)

        serialized = state |> Account.render() |> inspect(limit: :infinity)

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

  # ---------------------------------------------------------------------------
  # Phase 25 Plan 02 — Primitive-presence tests (TDD RED)
  # ---------------------------------------------------------------------------

  describe "PROFILE Modal.Form primitive presence" do
    test "renders Modal.Form footer sentinel and form heading" do
      state =
        build_state_for_role(:user)
        |> put_in([:screen_state, :account], Account.init_screen_state())

      flat = Account.render(state) |> collect_text_values()

      assert Enum.any?(flat, &String.contains?(&1, "[Enter] Submit")),
             "expected Modal.Form footer sentinel '[Enter] Submit' in profile tab, got: #{inspect(flat)}"

      assert Enum.any?(flat, &String.contains?(&1, "Profile")),
             "expected form heading 'Profile' in profile tab"
    end

    test "renders labeled field rows for each profile field" do
      state =
        build_state_for_role(:user)
        |> put_in([:screen_state, :account], Account.init_screen_state())

      flat = Account.render(state) |> collect_text_values()

      assert Enum.any?(flat, &String.contains?(&1, "Location")),
             "expected 'Location' field label in profile tab"

      assert Enum.any?(flat, &String.contains?(&1, "Tagline")),
             "expected 'Tagline' field label in profile tab"

      assert Enum.any?(flat, &String.contains?(&1, "Real name")),
             "expected 'Real name' field label in profile tab"
    end

    test "renders required marker glyph for required fields" do
      state =
        build_state_for_role(:user)
        |> put_in([:screen_state, :account], Account.init_screen_state())

      flat = Account.render(state) |> collect_text_values()

      assert Enum.any?(flat, &String.contains?(&1, "*")),
             "expected required marker '*' in profile tab form"
    end

    test "renders inline error text when set_errors is applied" do
      ss = Account.init_screen_state()

      alias Foglet.TUI.Widgets.Modal.Form, as: ModalForm

      ss_with_error = %{
        ss
        | profile_form: ModalForm.set_errors(ss.profile_form, %{location: "is too short"})
      }

      state =
        build_state_for_role(:user)
        |> put_in([:screen_state, :account], ss_with_error)

      flat = Account.render(state) |> collect_text_values()

      assert Enum.any?(flat, &String.contains?(&1, "is too short")),
             "expected inline error 'is too short' in profile tab render"
    end
  end

  describe "PREFS Modal.Form primitive presence" do
    setup %{state: state} do
      {:update, prefs_state, []} = Account.handle_key(%{key: :char, char: "2"}, state)
      %{state: prefs_state}
    end

    test "renders Modal.Form footer sentinel", %{state: state} do
      flat = Account.render(state) |> collect_text_values()

      assert Enum.any?(flat, &String.contains?(&1, "[Enter] Submit")),
             "expected Modal.Form footer sentinel in prefs tab"
    end

    test "renders enum field for theme selection", %{state: state} do
      flat = Account.render(state) |> collect_text_values()

      assert Enum.any?(flat, &String.contains?(&1, "Theme")),
             "expected 'Theme' enum field label in prefs tab"
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
        |> put_in([:screen_state, :account], Account.init_screen_state(current_user: user))

      {:update, state, []} = Account.handle_key(%{key: :char, char: "2"}, state)

      account_state = %{state.screen_state.account | prefs_focus: :theme}
      state = put_in(state, [:screen_state, :account], account_state)

      {:update, preview_state, []} = Account.handle_key(%{key: :down}, state)

      assert preview_state.screen_state.account.candidate_theme_id != nil,
             "expected candidate_theme_id to be set after cycling theme enum field down"
    end
  end

  describe "SSH_KEYS ConsoleTable primitive presence" do
    setup %{state: state} do
      inserted_at = ~U[2026-04-24 10:11:12.123456Z]

      account_state =
        Account.init_screen_state()
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

    test "renders ConsoleTable header row with column labels", %{state: state} do
      flat = Account.render(state) |> collect_text_values()

      assert Enum.any?(flat, &String.contains?(&1, "Label")),
             "expected 'Label' column header in SSH KEYS tab"

      assert Enum.any?(flat, &String.contains?(&1, "Fingerprint")),
             "expected 'Fingerprint' column header in SSH KEYS tab"

      assert Enum.any?(flat, &String.contains?(&1, "Created")),
             "expected 'Created' column header in SSH KEYS tab"
    end

    test "renders empty state copy with empty list" do
      state =
        build_state_for_role(:user)
        |> put_in(
          [:screen_state, :account],
          Account.init_screen_state()
          |> Map.put(:active_tab, 2)
          |> Map.put(:ssh_keys, SSHKeysState.loaded(SSHKeysState.new(), []))
        )

      flat = Account.render(state) |> collect_text_values()

      assert Enum.any?(flat, &String.contains?(&1, "No SSH keys registered yet.")),
             "expected empty state copy in SSH KEYS tab"
    end

    test "pressing down on non-empty list advances cursor without crash", %{state: state} do
      result = Account.handle_key(%{key: :down}, state)
      assert match?({:update, _, _}, result) or result == :no_match
    end

    test "pressing up, down, enter on empty list does not crash" do
      state =
        build_state_for_role(:user)
        |> put_in(
          [:screen_state, :account],
          Account.init_screen_state()
          |> Map.put(:active_tab, 2)
          |> Map.put(:ssh_keys, SSHKeysState.loaded(SSHKeysState.new(), []))
        )

      for key <- [%{key: :up}, %{key: :down}, %{key: :enter}] do
        result = Account.handle_key(key, state)

        assert match?({:update, _, _}, result) or result == :no_match,
               "expected no crash for key #{inspect(key)} on empty SSH KEYS list"
      end
    end
  end
end
