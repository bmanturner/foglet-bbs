defmodule Foglet.SSH.KeyCBTest do
  use FogletBbs.DataCase, async: true

  alias Foglet.SSH.KeyCB

  import FogletBbs.AccountsFixtures

  # A real ed25519 public key used as the default fixture (shared with AccountsFixtures).
  @static_openssh_key FogletBbs.AccountsFixtures.default_ssh_public_key()

  describe "Foglet.SSH.KeyCB.is_auth_key/3 (SSH-03, Option A)" do
    # With Option A the function always returns true — its role is to stash the
    # offered pubkey for CLIHandler to pick up, not to gate connection acceptance
    # (that's handled by no_auth_needed: true at the daemon level).

    test "returns true for any key — even one not registered to any user" do
      user = user_fixture()
      [{public_key, _}] = :ssh_file.decode(@static_openssh_key, :public_key)
      assert KeyCB.is_auth_key(public_key, String.to_charlist(user.handle), []) == true
    end

    test "accepts a binary username (not only charlist) — Pitfall 2" do
      user = user_fixture()
      [{public_key, _}] = :ssh_file.decode(@static_openssh_key, :public_key)
      assert KeyCB.is_auth_key(public_key, user.handle, []) == true
    end

    test "stashes the offered pubkey in PubkeyStash keyed by peer" do
      [{public_key, _}] = :ssh_file.decode(@static_openssh_key, :public_key)
      peer = {{127, 0, 0, 1}, 54_321}
      opts = [peer: {peer, :fake_socket}]

      KeyCB.is_auth_key(public_key, "anyuser", opts)

      assert {:ok, ^public_key} = Foglet.SSH.PubkeyStash.pop(peer)
    end
  end
end
