defmodule Foglet.AccountsTest do
  use FogletBbs.DataCase, async: true

  alias Foglet.Accounts
  alias Foglet.Accounts.{SSHKey, User, UserToken}
  alias FogletBbs.AccountsFixtures

  describe "register_user/1 (IDNT-01)" do
    test "creates a user with hashed password" do
      attrs = AccountsFixtures.valid_user_attributes(%{password: "opensesame"})
      assert {:ok, %User{} = user} = Accounts.register_user(attrs)
      assert user.password_hash != "opensesame"
      assert Argon2.verify_pass("opensesame", user.password_hash)
    end

    test "returns {:error, changeset} on invalid attrs" do
      assert {:error, cs} = Accounts.register_user(%{})
      refute cs.valid?
    end
  end

  describe "authenticate_by_password/2 (IDNT-01)" do
    test "returns {:ok, user} on valid credentials" do
      user = AccountsFixtures.user_fixture(%{password: "letmein12"})
      assert {:ok, %User{id: id}} = Accounts.authenticate_by_password(user.handle, "letmein12")
      assert id == user.id
    end

    test "case-insensitive handle lookup via citext" do
      _user = AccountsFixtures.user_fixture(%{handle: "CamelCase", password: "letmein12"})

      assert {:ok, %User{handle: "CamelCase"}} =
               Accounts.authenticate_by_password("camelcase", "letmein12")

      assert {:ok, %User{handle: "CamelCase"}} =
               Accounts.authenticate_by_password("CAMELCASE", "letmein12")
    end

    test "returns {:error, :invalid_credentials} on invalid password" do
      user = AccountsFixtures.user_fixture(%{password: "letmein12"})

      assert {:error, :invalid_credentials} =
               Accounts.authenticate_by_password(user.handle, "wrong")
    end

    test "returns {:error, :invalid_credentials} on unknown handle (timing-safe)" do
      assert {:error, :invalid_credentials} =
               Accounts.authenticate_by_password("no_such_user", "anything")
    end

    test "rejects authentication for deleted users" do
      user = AccountsFixtures.user_fixture(%{password: "letmein12"})
      {:ok, _} = Accounts.delete_user(user)

      assert {:error, :invalid_credentials} =
               Accounts.authenticate_by_password(user.handle, "letmein12")
    end
  end

  describe "update_role/2 (IDNT-06 support)" do
    test "promotes a user to sysop" do
      user = AccountsFixtures.user_fixture()
      assert {:ok, updated} = Accounts.update_role(user, :sysop)
      assert updated.role == :sysop
    end

    test "accepts string role from Mix task input" do
      user = AccountsFixtures.user_fixture()
      assert {:ok, updated} = Accounts.update_role(user, "mod")
      assert updated.role == :mod
    end

    test "rejects invalid role" do
      user = AccountsFixtures.user_fixture()
      assert {:error, cs} = Accounts.update_role(user, :admin)
      refute cs.valid?
    end
  end

  describe "register_ssh_key/2 (IDNT-04)" do
    test "stores key with computed fingerprint" do
      user = AccountsFixtures.user_fixture()
      key = AccountsFixtures.ssh_key_fixture(user)
      assert key.user_id == user.id
      assert String.starts_with?(key.fingerprint, "SHA256:")
    end

    test "returns {:error, changeset} for invalid key text" do
      user = AccountsFixtures.user_fixture()

      assert {:error, cs} =
               Accounts.register_ssh_key(user, %{label: "bad", public_key: "nope"})

      refute cs.valid?
    end

    test "list_ssh_keys/1 returns user's keys ordered by inserted_at" do
      user = AccountsFixtures.user_fixture()
      k1 = AccountsFixtures.ssh_key_fixture(user)
      assert [%SSHKey{id: found_id}] = Accounts.list_ssh_keys(user)
      assert found_id == k1.id
    end
  end

  describe "get_user_by_public_key/1 (IDNT-04, Phase 3 consumer)" do
    test "finds the registered user by fingerprint" do
      user = AccountsFixtures.user_fixture()
      default_key = AccountsFixtures.default_ssh_public_key()
      _ = AccountsFixtures.ssh_key_fixture(user, %{public_key: default_key})
      assert {:ok, %User{id: id}} = Accounts.get_user_by_public_key(default_key)
      assert id == user.id
    end

    test "returns {:error, :not_found} for unregistered key" do
      other_key =
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBp8Yt7rf3YpZ8eR+3KEBLQnUlsMHfK4VwCaZJmjs4Cq other@ex"

      assert {:error, :not_found} = Accounts.get_user_by_public_key(other_key)
    end

    test "returns {:error, :not_found} for invalid key text" do
      assert {:error, :not_found} = Accounts.get_user_by_public_key("not a key at all")
    end

    test "returns {:error, :not_found} when owning user is deleted" do
      user = AccountsFixtures.user_fixture()
      default_key = AccountsFixtures.default_ssh_public_key()
      _ = AccountsFixtures.ssh_key_fixture(user, %{public_key: default_key})
      {:ok, _} = Accounts.delete_user(user)
      # delete_user removes ssh_keys — we expect :not_found
      assert {:error, :not_found} = Accounts.get_user_by_public_key(default_key)
    end
  end

  describe "deliver_user_confirmation_instructions/2 (IDNT-02)" do
    test "persists a confirm token and returns the URL" do
      user = AccountsFixtures.user_fixture()
      url_fn = fn raw -> "https://example.test/confirm/#{raw}" end
      assert {:ok, url} = Accounts.deliver_user_confirmation_instructions(user, url_fn)
      assert String.starts_with?(url, "https://example.test/confirm/")

      assert Repo.exists?(
               from t in UserToken,
                 where: t.user_id == ^user.id and t.context == "confirm"
             )
    end

    test "returns {:error, :already_confirmed} if user already confirmed" do
      user = AccountsFixtures.user_fixture()
      {:ok, confirmed} = Accounts.confirm_user(user)

      assert {:error, :already_confirmed} =
               Accounts.deliver_user_confirmation_instructions(confirmed, fn _ -> "x" end)
    end
  end

  describe "deliver_user_reset_password_instructions/2 (IDNT-08)" do
    test "persists a reset_password token and returns the URL" do
      user = AccountsFixtures.user_fixture()
      url_fn = fn raw -> "https://example.test/reset/#{raw}" end
      assert {:ok, url} = Accounts.deliver_user_reset_password_instructions(user, url_fn)
      assert String.contains?(url, "reset/")

      assert Repo.exists?(
               from t in UserToken,
                 where: t.user_id == ^user.id and t.context == "reset_password"
             )
    end
  end

  describe "reset_user_password/2 (IDNT-08)" do
    test "updates password and invalidates outstanding reset tokens" do
      user = AccountsFixtures.user_fixture(%{password: "original1"})
      {_raw, _} = AccountsFixtures.user_token_fixture(user, "reset_password")

      assert Repo.exists?(
               from t in UserToken,
                 where: t.user_id == ^user.id and t.context == "reset_password"
             )

      assert {:ok, updated} = Accounts.reset_user_password(user, %{password: "brandnew1"})
      assert Argon2.verify_pass("brandnew1", updated.password_hash)
      refute Argon2.verify_pass("original1", updated.password_hash)

      refute Repo.exists?(
               from t in UserToken,
                 where: t.user_id == ^user.id and t.context == "reset_password"
             )
    end
  end

  describe "delete_user/1 (IDNT-07)" do
    test "clears PII on the user row and preserves the row for FK integrity" do
      user =
        AccountsFixtures.user_fixture(%{
          email: "victim@example.com"
        })

      # seed some profile fields that must be cleared
      {:ok, user} = Accounts.update_profile(user, %{location: "Nowhere", tagline: "ahoy"})

      assert {:ok, anonymized} = Accounts.delete_user(user)
      assert anonymized.deleted_at
      refute anonymized.location
      refute anonymized.tagline
      refute anonymized.real_name
      assert anonymized.email == "deleted-#{user.id}@localhost"
      assert anonymized.password_hash == "invalid-deleted"

      # Row still exists (preserved for FK integrity)
      assert Repo.get(User, user.id)
    end

    test "deletes all ssh_keys and user_tokens for the deleted user" do
      user = AccountsFixtures.user_fixture()
      _ = AccountsFixtures.ssh_key_fixture(user)

      {_raw, _} = AccountsFixtures.user_token_fixture(user, "confirm")
      {_raw, _} = AccountsFixtures.user_token_fixture(user, "reset_password")

      assert Repo.aggregate(from(k in SSHKey, where: k.user_id == ^user.id), :count) == 1
      assert Repo.aggregate(from(t in UserToken, where: t.user_id == ^user.id), :count) == 2

      {:ok, _} = Accounts.delete_user(user)

      assert Repo.aggregate(from(k in SSHKey, where: k.user_id == ^user.id), :count) == 0
      assert Repo.aggregate(from(t in UserToken, where: t.user_id == ^user.id), :count) == 0
    end
  end

  describe "tombstone_user_id/0" do
    test "returns a fixed UUID string" do
      assert Accounts.tombstone_user_id() == "00000000-0000-0000-0000-000000000001"
    end
  end
end
