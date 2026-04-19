defmodule Foglet.SSH.CLIHandlerTest do
  @moduledoc """
  Unit tests for CLIHandler context-building logic.

  Full SSH channel event handling requires a real SSH harness (D-21 — out of
  scope). These tests exercise the pubkey correlation and context-building paths
  using dependency injection via PubkeyStash.
  """

  use FogletBbs.DataCase, async: true

  import FogletBbs.AccountsFixtures

  alias Foglet.Accounts
  alias Foglet.SSH.PubkeyStash

  @static_openssh_key FogletBbs.AccountsFixtures.default_ssh_public_key()

  describe "PubkeyStash correlation" do
    test "pop returns :miss when no key was stashed for that peer" do
      peer = {{10, 0, 0, 1}, 11_111}
      assert PubkeyStash.pop(peer) == :miss
    end

    test "pop returns {:ok, key} after put and removes the entry" do
      peer = {{10, 0, 0, 2}, 22_222}
      [{public_key, _}] = :ssh_file.decode(@static_openssh_key, :public_key)

      PubkeyStash.put(peer, public_key)

      assert {:ok, ^public_key} = PubkeyStash.pop(peer)
      # Second pop should be a miss (entry deleted)
      assert PubkeyStash.pop(peer) == :miss
    end

    test "pop(:unknown) always returns :miss" do
      assert PubkeyStash.pop(:unknown) == :miss
    end
  end

  describe "pubkey → user resolution (context-building logic)" do
    # These tests verify the CLIHandler's pubkey resolution path by calling
    # the domain functions the CLIHandler calls internally. We don't invoke
    # CLIHandler callbacks directly (they require live SSH infrastructure).

    test "pubkey matching a registered user returns that user" do
      user = user_fixture()

      {:ok, _ssh_key} =
        Accounts.register_ssh_key(user, %{label: "laptop", public_key: @static_openssh_key})

      assert {:ok, found_user} = Accounts.get_user_by_public_key(@static_openssh_key)
      assert found_user.id == user.id
      assert found_user.handle == user.handle
    end

    test "pubkey NOT registered returns {:error, :not_found}" do
      assert {:error, :not_found} = Accounts.get_user_by_public_key(@static_openssh_key)
    end

    test "pubkey for a deleted user returns {:error, :not_found}" do
      user = user_fixture()

      {:ok, _} =
        Accounts.register_ssh_key(user, %{label: "test", public_key: @static_openssh_key})

      {:ok, _} = Accounts.delete_user(user)

      assert {:error, :not_found} = Accounts.get_user_by_public_key(@static_openssh_key)
    end
  end

  describe "context shape" do
    # These tests verify the structure that CLIHandler.build_context/3 produces
    # by checking that TUI.App.init/1 correctly consumes a Lifecycle-style context.

    test "guest context (no pubkey match) produces login screen" do
      guest_ctx = %{
        session_context: %{
          user: nil,
          user_id: nil,
          session_pid: nil,
          pubkey_authenticated: false,
          registration_mode: "open",
          max_post_length: 8192
        },
        terminal_size: {80, 24}
      }

      {:ok, state} = Foglet.TUI.App.init(guest_ctx)
      assert state.current_screen == :login
      assert state.current_user == nil
      assert state.session_pid == nil
    end

    test "authenticated context (pubkey match) produces main_menu screen" do
      user = %Foglet.Accounts.User{id: "uid-123", handle: "pubkeyuser", role: :user}

      auth_ctx = %{
        session_context: %{
          user: user,
          user_id: user.id,
          session_pid: nil,
          pubkey_authenticated: true,
          registration_mode: "open",
          max_post_length: 8192
        },
        terminal_size: {132, 50}
      }

      {:ok, state} = Foglet.TUI.App.init(auth_ctx)
      assert state.current_screen == :main_menu
      assert state.current_user == user
      assert state.terminal_size == {132, 50}
    end
  end
end
