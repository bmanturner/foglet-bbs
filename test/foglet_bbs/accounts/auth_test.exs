defmodule Foglet.Accounts.AuthTest do
  use FogletBbs.DataCase, async: true

  alias Foglet.Accounts
  alias Foglet.Accounts.{Auth, SSHKey, User}
  alias FogletBbs.AccountsFixtures

  @alternate_ssh_public_key "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBp8Yt7rf3YpZ8eR+3KEBLQnUlsMHfK4VwCaZJmjs4Cq other@example"

  describe "authenticate_by_password/2 (IDNT-01)" do
    test "returns {:ok, user} on valid credentials" do
      user = AccountsFixtures.user_fixture(%{password: "letmein12"})
      assert {:ok, %User{id: id}} = Auth.authenticate_by_password(user.handle, "letmein12")
      assert id == user.id
    end

    test "case-insensitive handle lookup via citext" do
      _user = AccountsFixtures.user_fixture(%{handle: "CamelCase", password: "letmein12"})

      assert {:ok, %User{handle: "CamelCase"}} =
               Auth.authenticate_by_password("camelcase", "letmein12")

      assert {:ok, %User{handle: "CamelCase"}} =
               Auth.authenticate_by_password("CAMELCASE", "letmein12")
    end

    test "returns {:error, :invalid_credentials} on invalid password" do
      user = AccountsFixtures.user_fixture(%{password: "letmein12"})

      assert {:error, :invalid_credentials} =
               Auth.authenticate_by_password(user.handle, "wrong")
    end

    test "returns {:error, :invalid_credentials} on unknown handle (timing-safe)" do
      assert {:error, :invalid_credentials} =
               Auth.authenticate_by_password("no_such_user", "anything")
    end

    test "rejects authentication for deleted users" do
      user = AccountsFixtures.user_fixture(%{password: "letmein12"})
      {:ok, _} = Accounts.delete_user(user)

      assert {:error, :invalid_credentials} =
               Auth.authenticate_by_password(user.handle, "letmein12")
    end
  end

  describe "get_user_by_public_key/1 (IDNT-04, Phase 3 consumer)" do
    test "finds the registered user by fingerprint" do
      user = AccountsFixtures.user_fixture()
      default_key = AccountsFixtures.default_ssh_public_key()
      _ = AccountsFixtures.ssh_key_fixture(user, %{public_key: default_key})
      assert {:ok, %User{id: id}} = Auth.get_user_by_public_key(default_key)
      assert id == user.id
    end

    test "returns {:error, :not_found} for unregistered key" do
      other_key =
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBp8Yt7rf3YpZ8eR+3KEBLQnUlsMHfK4VwCaZJmjs4Cq other@ex"

      assert {:error, :not_found} = Auth.get_user_by_public_key(other_key)
    end

    test "returns {:error, :not_found} for invalid key text" do
      assert {:error, :not_found} = Auth.get_user_by_public_key("not a key at all")
    end

    test "returns {:error, :not_found} when owning user is deleted" do
      user = AccountsFixtures.user_fixture()
      default_key = AccountsFixtures.default_ssh_public_key()
      _ = AccountsFixtures.ssh_key_fixture(user, %{public_key: default_key})
      {:ok, _} = Accounts.delete_user(user)
      # delete_user removes ssh_keys — we expect :not_found
      assert {:error, :not_found} = Auth.get_user_by_public_key(default_key)
    end
  end

  describe "authenticate_by_public_key/1 (KEYS-05)" do
    test "finds a registered active user and records last_used_at only on the matched key" do
      {:ok, user} = AccountsFixtures.user_fixture() |> Accounts.confirm_user()
      default_key = AccountsFixtures.default_ssh_public_key()
      other_key = @alternate_ssh_public_key
      registered = AccountsFixtures.ssh_key_fixture(user, %{public_key: default_key})
      untouched = AccountsFixtures.ssh_key_fixture(user, %{public_key: other_key})

      assert registered.last_used_at == nil
      assert untouched.last_used_at == nil

      assert {:ok, %User{id: user_id}} = Auth.authenticate_by_public_key(default_key)
      assert user_id == user.id

      assert %SSHKey{last_used_at: %DateTime{} = last_used_at} = Repo.get(SSHKey, registered.id)
      assert last_used_at == DateTime.truncate(last_used_at, :microsecond)
      assert %SSHKey{last_used_at: nil} = Repo.get(SSHKey, untouched.id)
    end

    test "invalid, unregistered, revoked, and deleted-user keys return not_found without writes" do
      {:ok, user} = AccountsFixtures.user_fixture() |> Accounts.confirm_user()
      default_key = AccountsFixtures.default_ssh_public_key()
      unregistered_key = @alternate_ssh_public_key
      registered = AccountsFixtures.ssh_key_fixture(user, %{public_key: default_key})

      assert {:error, :not_found} = Auth.authenticate_by_public_key("not a key at all")
      assert {:error, :not_found} = Auth.authenticate_by_public_key(unregistered_key)
      assert %SSHKey{last_used_at: nil} = Repo.get(SSHKey, registered.id)

      assert {:ok, _revoked} = Accounts.revoke_ssh_key(user, registered.id)
      assert {:error, :not_found} = Auth.authenticate_by_public_key(default_key)

      deleted_owner = AccountsFixtures.user_fixture()
      deleted_owner_key_text = @alternate_ssh_public_key

      deleted_owner_key =
        AccountsFixtures.ssh_key_fixture(deleted_owner, %{public_key: deleted_owner_key_text})

      {:ok, deleted_owner} =
        deleted_owner
        |> User.deletion_changeset()
        |> Repo.update()

      assert deleted_owner.deleted_at
      assert {:error, :not_found} = Auth.authenticate_by_public_key(deleted_owner_key_text)
      assert %SSHKey{last_used_at: nil} = Repo.get(SSHKey, deleted_owner_key.id)
    end

    test "inactive account statuses return not_found without last_used_at writes" do
      for status <- [:pending, :suspended, :rejected] do
        user = user_with_status(status, "pubkey#{status}")
        key = AccountsFixtures.ssh_key_fixture(user, %{public_key: public_key_for(status)})

        assert {:error, :not_found} = Auth.authenticate_by_public_key(key.public_key)
        assert %SSHKey{last_used_at: nil} = Repo.get(SSHKey, key.id)
      end
    end

    test "password authentication does not update SSH key last_used_at" do
      user = AccountsFixtures.user_fixture(%{password: "letmein12"})
      key = AccountsFixtures.ssh_key_fixture(user)

      assert {:ok, %User{id: user_id}} =
               Auth.authenticate_by_password(user.handle, "letmein12")

      assert user_id == user.id
      assert %SSHKey{last_used_at: nil} = Repo.get(SSHKey, key.id)
    end
  end

  describe "lookup_by_public_key/1 and authorize_session/1 (FOG-116)" do
    test "active confirmed user is authorized and records key use only through authentication" do
      {:ok, user} = AccountsFixtures.user_fixture() |> Accounts.confirm_user()
      key = AccountsFixtures.ssh_key_fixture(user)

      assert {:ok, %{user: %User{id: user_id}, ssh_key: %SSHKey{id: key_id}}} =
               Auth.lookup_by_public_key(key.public_key)

      assert user_id == user.id
      assert key_id == key.id
      assert {:ok, :authorized, %User{id: ^user_id}} = Auth.authorize_session(user)
      assert %SSHKey{last_used_at: nil} = Repo.get(SSHKey, key.id)

      assert {:ok, %User{id: ^user_id}} = Auth.authenticate_by_public_key(key.public_key)
      assert %SSHKey{last_used_at: %DateTime{}} = Repo.get(SSHKey, key.id)
    end

    test "active unconfirmed user is a matched verification gate without last_used_at writes" do
      user = AccountsFixtures.user_fixture()
      key = AccountsFixtures.ssh_key_fixture(user)

      assert {:ok, %{user: %User{id: user_id}}} = Auth.lookup_by_public_key(key.public_key)
      assert user_id == user.id
      assert {:ok, :verify, %User{id: ^user_id}} = Auth.authorize_session(user)
      assert {:error, :not_found} = Auth.authenticate_by_public_key(key.public_key)
      assert %SSHKey{last_used_at: nil} = Repo.get(SSHKey, key.id)
    end

    test "pending user is matched but not authorized and does not record key use" do
      user = user_with_status(:pending, "pubkeypendinglookup")
      key = AccountsFixtures.ssh_key_fixture(user)

      assert {:ok, %{user: %User{id: user_id}}} = Auth.lookup_by_public_key(key.public_key)
      assert user_id == user.id
      assert {:error, :pending} = Auth.authorize_session(user)
      assert {:error, :not_found} = Auth.authenticate_by_public_key(key.public_key)
      assert %SSHKey{last_used_at: nil} = Repo.get(SSHKey, key.id)
    end

    test "suspended and rejected users are explicit blocked outcomes without key-use writes" do
      for {status, key_text} <- [
            {:suspended, @alternate_ssh_public_key},
            {:rejected, public_key_for(:rejected)}
          ] do
        user = user_with_status(status, "pk#{status}lookup")
        key = AccountsFixtures.ssh_key_fixture(user, %{public_key: key_text})

        assert {:ok, %{user: %User{id: user_id}}} = Auth.lookup_by_public_key(key.public_key)
        assert user_id == user.id
        assert {:error, ^status} = Auth.authorize_session(user)
        assert {:error, :not_found} = Auth.authenticate_by_public_key(key.public_key)
        assert %SSHKey{last_used_at: nil} = Repo.get(SSHKey, key.id)
      end
    end

    test "deleted user keys and unknown fingerprints do not return a matched identity" do
      user = AccountsFixtures.user_fixture()
      key = AccountsFixtures.ssh_key_fixture(user)
      _deleted = user |> User.deletion_changeset() |> Repo.update!()

      assert {:error, :not_found} = Auth.lookup_by_public_key(key.public_key)
      assert {:error, :not_found} = Auth.lookup_by_public_key(@alternate_ssh_public_key)
      assert {:error, :not_found} = Auth.authenticate_by_public_key(key.public_key)
      assert %SSHKey{last_used_at: nil} = Repo.get(SSHKey, key.id)
    end
  end

  defp user_with_status(status, handle, role \\ :user) do
    {:ok, user} =
      AccountsFixtures.user_fixture(%{handle: handle})
      |> Accounts.update_role(role)

    user
    |> User.status_changeset(%{status: status})
    |> Repo.update!()
  end

  defp public_key_for(:pending), do: AccountsFixtures.default_ssh_public_key()
  defp public_key_for(:suspended), do: @alternate_ssh_public_key

  defp public_key_for(:rejected),
    do:
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIP3YzupUUO1ytFJEzTWUf46vEQ0g5yWmK5IE6fCyEbDH rejected@example"
end
