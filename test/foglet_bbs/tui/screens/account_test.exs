defmodule Foglet.TUI.Screens.AccountTest do
  use ExUnit.Case, async: true

  import Foglet.TUI.RenderHelpers

  alias Foglet.TUI.Screens.Account

  defp build_state(role \\ :user) do
    %Foglet.TUI.App{
      current_screen: :account,
      current_user: %Foglet.Accounts.User{id: "u1", handle: "alice", role: role},
      session_context: %{},
      terminal_size: {80, 24},
      screen_state: %{}
    }
    |> Map.from_struct()
  end

  setup do
    %{state: build_state(:user)}
  end

  describe "init_screen_state/1" do
    test "returns a struct with active_tab: 0 and a Tabs wrapper state" do
      ss = Account.init_screen_state()
      assert ss.active_tab == 0
      assert %Foglet.TUI.Widgets.Input.Tabs{} = ss.tabs
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

    test "omits INVITES when InvitesSurface.visible?/2 returns false", %{state: state} do
      # role: :user with sysop_only policy => not visible
      state = put_in(state, [:screen_state, :account], Account.init_screen_state())
      flat = Account.render(state) |> collect_text_values()
      refute Enum.any?(flat, &String.contains?(&1, "INVITES"))
    end

    test "includes INVITES when InvitesSurface.visible?/2 returns true" do
      # role: :sysop => always visible per D-07
      state = build_state(:sysop)
      state = put_in(state, [:screen_state, :account], Account.init_screen_state(role: :sysop))
      flat = Account.render(state) |> collect_text_values()
      assert Enum.any?(flat, &String.contains?(&1, "INVITES"))
    end

    test "renders scaffold-only placeholder copy (no fake save buttons)", %{state: state} do
      state = put_in(state, [:screen_state, :account], Account.init_screen_state())
      flat = Account.render(state) |> collect_text_values()
      forbidden = ["Save", "Generate", "Revoke", "Approve"]

      for word <- forbidden do
        refute Enum.any?(flat, &String.contains?(&1, word)),
               "Expected #{inspect(word)} not to appear in Account render output"
      end
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

    test "unknown key returns :no_match", %{state: state} do
      assert :no_match = Account.handle_key(%{key: :char, char: "z"}, state)
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
end
