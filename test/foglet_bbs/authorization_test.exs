defmodule Foglet.AuthorizationTest do
  use FogletBbs.DataCase, async: true

  import ExUnit.CaptureLog

  alias Foglet.Accounts.User
  alias Foglet.Authorization

  # Shared fixture board id for {:board, _} scope tests.
  @board_id "11111111-1111-1111-1111-111111111111"

  # --- Actor fixtures (return plain structs; no DB) ---
  defp actor(:sysop), do: %User{role: :sysop, status: :active, deleted_at: nil}
  defp actor(:mod), do: %User{role: :mod, status: :active, deleted_at: nil}
  defp actor(:user), do: %User{role: :user, status: :active, deleted_at: nil}
  defp actor(:suspended), do: %User{role: :mod, status: :suspended, deleted_at: nil}
  defp actor(:pending), do: %User{role: :mod, status: :pending, deleted_at: nil}
  defp actor(:rejected), do: %User{role: :sysop, status: :rejected, deleted_at: nil}

  defp actor(:deleted),
    do: %User{role: :mod, status: :active, deleted_at: ~U[2026-01-01 00:00:00Z]}

  defp actor(:nil_actor), do: nil

  # --- Policy matrix: {actor_key, action, scope, expected} ---
  @matrix [
    # Sysop — permitted everywhere
    {:sysop, :edit_config, :site, :ok},
    {:sysop, :create_board, :site, :ok},
    {:sysop, :update_board, :site, :ok},
    {:sysop, :archive_board, :site, :ok},
    {:sysop, :create_category, :site, :ok},
    {:sysop, :update_category, :site, :ok},
    {:sysop, :archive_category, :site, :ok},
    {:sysop, :generate_invite, :site, :ok},
    {:sysop, :revoke_invite, :site, :ok},
    {:sysop, :manage_user_status, :site, :ok},
    {:sysop, :hide_oneliner, :site, :ok},
    {:sysop, :lock_thread, :site, :ok},
    {:sysop, :delete_post, :site, :ok},
    {:sysop, :lock_thread, {:board, @board_id}, :ok},
    {:sysop, :delete_post, {:board, @board_id}, :ok},
    # Sysop — also permitted for site-only actions at {:board, _} scope.
    # Guards against a future regression that accidentally adds a scope
    # check before the sysop catch-all clause.
    {:sysop, :create_board, {:board, @board_id}, :ok},
    {:sysop, :edit_config, {:board, @board_id}, :ok},
    # Mod — permitted moderation actions at :site
    {:mod, :lock_thread, :site, :ok},
    {:mod, :unlock_thread, :site, :ok},
    {:mod, :sticky_thread, :site, :ok},
    {:mod, :unsticky_thread, :site, :ok},
    {:mod, :move_thread, :site, :ok},
    {:mod, :delete_thread, :site, :ok},
    {:mod, :delete_post, :site, :ok},
    {:mod, :edit_post_as_mod, :site, :ok},
    {:mod, :hide_oneliner, :site, :ok},
    {:mod, :generate_invite, :site, :ok},
    {:mod, :revoke_invite, :site, :ok},
    # Mod — permitted moderation actions at {:board, _}
    {:mod, :lock_thread, {:board, @board_id}, :ok},
    {:mod, :delete_post, {:board, @board_id}, :ok},
    {:mod, :hide_oneliner, {:board, @board_id}, :ok},
    # Mod — forbidden sysop-only actions
    {:mod, :edit_config, :site, {:error, :forbidden}},
    {:mod, :create_board, :site, {:error, :forbidden}},
    {:mod, :update_board, :site, {:error, :forbidden}},
    {:mod, :archive_board, :site, {:error, :forbidden}},
    {:mod, :create_category, :site, {:error, :forbidden}},
    {:mod, :update_category, :site, {:error, :forbidden}},
    {:mod, :archive_category, :site, {:error, :forbidden}},
    {:mod, :manage_user_status, :site, {:error, :forbidden}},
    # Regular user — can pass only the coarse invite generation gate.
    # Runtime invite policy and caps are enforced by Foglet.Accounts.create_invite/1.
    {:user, :create_board, :site, {:error, :forbidden}},
    {:user, :lock_thread, :site, {:error, :forbidden}},
    {:user, :generate_invite, :site, :ok},
    {:user, :hide_oneliner, :site, {:error, :forbidden}},
    # Invalid actor states (D-24)
    {:nil_actor, :create_board, :site, {:error, :forbidden}},
    {:suspended, :create_board, :site, {:error, :forbidden}},
    {:suspended, :lock_thread, :site, {:error, :forbidden}},
    {:pending, :create_board, :site, {:error, :forbidden}},
    {:rejected, :manage_user_status, :site, {:error, :forbidden}},
    {:deleted, :create_board, :site, {:error, :forbidden}}
  ]

  describe "Bodyguard.permit/4 policy matrix (MODR-03)" do
    for {actor_key, action, scope, expected} <- @matrix do
      @tag actor_key: actor_key, action: action, scope: scope, expected: expected
      test "#{actor_key} #{action} #{inspect(scope)} -> #{inspect(expected)}", %{
        actor_key: actor_key,
        action: action,
        scope: scope,
        expected: expected
      } do
        actor = actor(actor_key)
        assert Bodyguard.permit(Authorization, action, actor, scope) == expected
      end
    end
  end

  describe "Bodyguard.permit/4 unknown action (D-13)" do
    test "returns {:error, :forbidden} and emits a Logger.warning" do
      log =
        capture_log(fn ->
          assert Bodyguard.permit(
                   Authorization,
                   :definitely_not_a_real_action,
                   actor(:sysop),
                   :site
                 ) ==
                   {:error, :forbidden}
        end)

      assert log =~ "Unknown action atom"
    end
  end

  describe "Bodyguard.permit?/4 boolean wrapper" do
    test "returns true when permit/4 returns :ok" do
      assert Bodyguard.permit?(Authorization, :create_board, actor(:sysop), :site) == true
    end

    test "returns false when permit/4 returns {:error, :forbidden}" do
      assert Bodyguard.permit?(Authorization, :create_board, nil, :site) == false
    end
  end

  describe "scopes_for/2 (MODR-02)" do
    test "sysop returns [:site]" do
      assert Authorization.scopes_for(actor(:sysop), :create_board) == [:site]
    end

    test "mod returns [:site] in v1.1 (D-21)" do
      assert Authorization.scopes_for(actor(:mod), :lock_thread) == [:site]
    end

    test "regular user returns []" do
      assert Authorization.scopes_for(actor(:user), :create_board) == []
    end

    test "nil actor returns []" do
      assert Authorization.scopes_for(nil, :create_board) == []
    end

    test "suspended mod returns []" do
      assert Authorization.scopes_for(actor(:suspended), :lock_thread) == []
    end

    test "pending mod returns []" do
      assert Authorization.scopes_for(actor(:pending), :lock_thread) == []
    end

    test "rejected sysop returns []" do
      assert Authorization.scopes_for(actor(:rejected), :manage_user_status) == []
    end

    test "deleted mod returns []" do
      assert Authorization.scopes_for(actor(:deleted), :lock_thread) == []
    end
  end
end
