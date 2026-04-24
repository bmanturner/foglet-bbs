defmodule Foglet.Accounts.SSHKeyTest do
  use FogletBbs.DataCase, async: true

  alias Foglet.Accounts.{SSHKey, User}
  alias FogletBbs.AccountsFixtures

  # Two distinct valid Ed25519 public keys (deterministic test fixtures).
  @key_a "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGk+NU3dUxm5p8e2fMAKw1Z0p+4rM7q2DnGkgpTsvc0A test_a@example"
  @key_b "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBp8Yt7rf3YpZ8eR+3KEBLQnUlsMHfK4VwCaZJmjs4Cq test_b@example"

  defp insert_user!(overrides \\ %{}) do
    {:ok, u} =
      %User{}
      |> User.registration_changeset(AccountsFixtures.valid_user_attributes(overrides))
      |> Repo.insert()

    u
  end

  defp key_changeset(user, attrs) do
    %SSHKey{user_id: user.id}
    |> SSHKey.changeset(attrs)
  end

  describe "SSHKey changeset (IDNT-04)" do
    test "computes fingerprint from public_key at insert time" do
      user = insert_user!()

      {:ok, key} =
        user
        |> key_changeset(%{label: "laptop", public_key: @key_a})
        |> Repo.insert()

      assert key.fingerprint
      assert String.starts_with?(key.fingerprint, "SHA256:")
    end

    test "rejects duplicate fingerprint across users" do
      user_a = insert_user!(%{handle: "user_a", email: "a@example.com"})
      user_b = insert_user!(%{handle: "user_b", email: "b@example.com"})

      {:ok, _} =
        user_a |> key_changeset(%{label: "laptop", public_key: @key_a}) |> Repo.insert()

      assert {:error, changeset} =
               user_b |> key_changeset(%{label: "laptop", public_key: @key_a}) |> Repo.insert()

      assert "has already been taken" in errors_on(changeset).fingerprint
    end

    test "rejects duplicate label per user" do
      user = insert_user!()

      {:ok, _} =
        user |> key_changeset(%{label: "laptop", public_key: @key_a}) |> Repo.insert()

      assert {:error, changeset} =
               user |> key_changeset(%{label: "laptop", public_key: @key_b}) |> Repo.insert()

      assert "has already been taken" in errors_on(changeset).label
    end

    test "rejects invalid public key text" do
      user = insert_user!()
      changeset = key_changeset(user, %{label: "bogus", public_key: "this is not a key"})
      refute changeset.valid?
      assert Map.has_key?(errors_on(changeset), :public_key)
    end

    test "requires label and public_key" do
      user = insert_user!()
      changeset = key_changeset(user, %{})
      refute changeset.valid?
      assert %{label: ["can't be blank"], public_key: ["can't be blank"]} = errors_on(changeset)
    end
  end
end
