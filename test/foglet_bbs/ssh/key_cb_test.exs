defmodule Foglet.SSH.KeyCBTest do
  use FogletBbs.DataCase, async: true

  describe "Foglet.SSH.KeyCB (SSH-02 / SSH-03)" do
    @tag :pending
    test "host_key/2 returns the server's private key from priv/ssh/" do
      flunk("Pending — Plan 02 implements host_key/2 delegating to :ssh_file")
    end

    @tag :pending
    test "is_auth_key/3 returns true for a registered OpenSSH public key" do
      flunk(
        "Pending — Plan 02 implements is_auth_key/3 against Accounts.get_user_by_public_key/1"
      )
    end

    @tag :pending
    test "is_auth_key/3 returns false for an unregistered key" do
      flunk("Pending — Plan 02 implements is_auth_key/3 negative case")
    end

    @tag :pending
    test "is_auth_key/3 returns false for a key belonging to a deleted user" do
      flunk("Pending — Plan 02 implements is_auth_key/3 deleted_at check")
    end

    @tag :pending
    test "pwdfun callback delegates to Foglet.Accounts.authenticate_by_password/2 (SSH-02)" do
      flunk("Pending — Plan 02 implements pwdfun in Foglet.SSH.Supervisor")
    end

    @tag :pending
    test "pwdfun converts SSH charlist username to binary via List.to_string/1 (Pitfall 2)" do
      flunk("Pending — Plan 02 implements charlist boundary conversion")
    end
  end
end
