defmodule Foglet.Accounts.UserTest do
  use FogletBbs.DataCase, async: true

  alias Foglet.Accounts.User
  alias FogletBbs.AccountsFixtures

  describe "registration_changeset/2 (IDNT-01)" do
    test "hashes password with Argon2 and clears :password virtual field" do
      attrs = AccountsFixtures.valid_user_attributes(%{password: "correct horse battery"})
      changeset = User.registration_changeset(%User{}, attrs)

      assert changeset.valid?
      hash = get_change(changeset, :password_hash)
      assert is_binary(hash)
      assert String.starts_with?(hash, "$argon2")
      assert Argon2.verify_pass("correct horse battery", hash)
      # :password virtual field must be cleared after hashing
      refute get_change(changeset, :password)
    end

    test "requires handle, email, password" do
      changeset = User.registration_changeset(%User{}, %{})
      refute changeset.valid?

      assert %{
               handle: ["can't be blank"],
               email: ["can't be blank"],
               password: ["can't be blank"]
             } =
               errors_on(changeset)
    end

    test "rejects duplicate email case-insensitively (citext)" do
      attrs = AccountsFixtures.valid_user_attributes(%{email: "Alice@example.com"})
      {:ok, _first} = %User{} |> User.registration_changeset(attrs) |> Repo.insert()

      dup_attrs =
        AccountsFixtures.valid_user_attributes(%{
          email: "alice@EXAMPLE.com",
          handle: "different_handle"
        })

      assert {:error, changeset} =
               %User{} |> User.registration_changeset(dup_attrs) |> Repo.insert()

      assert "has already been taken" in errors_on(changeset).email
    end
  end

  describe "handle uniqueness and validation (IDNT-03)" do
    test "rejects duplicate handle case-insensitively" do
      attrs = AccountsFixtures.valid_user_attributes(%{handle: "Bman"})
      {:ok, _first} = %User{} |> User.registration_changeset(attrs) |> Repo.insert()

      dup =
        AccountsFixtures.valid_user_attributes(%{
          handle: "bman",
          email: "different@example.com"
        })

      assert {:error, changeset} =
               %User{} |> User.registration_changeset(dup) |> Repo.insert()

      assert "has already been taken" in errors_on(changeset).handle
    end

    test "rejects handle with invalid characters" do
      for bad <- ["has space", "has.dot", "has!bang"] do
        attrs = AccountsFixtures.valid_user_attributes(%{handle: bad})
        changeset = User.registration_changeset(%User{}, attrs)
        refute changeset.valid?, "expected #{inspect(bad)} to be rejected"
        assert Map.has_key?(errors_on(changeset), :handle)
      end
    end

    test "rejects handle that is too short or too long" do
      short =
        User.registration_changeset(
          %User{},
          AccountsFixtures.valid_user_attributes(%{handle: "a"})
        )

      long =
        User.registration_changeset(
          %User{},
          AccountsFixtures.valid_user_attributes(%{handle: String.duplicate("a", 21)})
        )

      refute short.valid?
      refute long.valid?
    end

    test "preserves display case of handle in stored value" do
      attrs = AccountsFixtures.valid_user_attributes(%{handle: "CamelCase"})
      {:ok, user} = %User{} |> User.registration_changeset(attrs) |> Repo.insert()
      reloaded = Repo.get!(User, user.id)
      assert reloaded.handle == "CamelCase"
    end
  end

  describe "password_changeset/2 (IDNT-08)" do
    test "re-hashes password and clears :password virtual field" do
      {:ok, user} =
        %User{}
        |> User.registration_changeset(AccountsFixtures.valid_user_attributes())
        |> Repo.insert()

      original_hash = user.password_hash
      changeset = User.password_changeset(user, %{password: "newnewnewnew"})
      assert changeset.valid?
      new_hash = get_change(changeset, :password_hash)
      assert is_binary(new_hash)
      assert new_hash != original_hash
      refute get_change(changeset, :password)
    end
  end

  describe "role_changeset/2 (IDNT-06 support)" do
    test "accepts :user, :mod, :sysop" do
      for role <- [:user, :mod, :sysop] do
        cs = User.role_changeset(%User{}, %{role: role})
        assert cs.valid?
      end
    end

    test "rejects unknown role" do
      cs = User.role_changeset(%User{}, %{role: :admin})
      refute cs.valid?
    end
  end

  describe "deletion_changeset/1 (IDNT-07 support)" do
    test "clears PII fields and sets deleted_at" do
      {:ok, user} =
        %User{}
        |> User.registration_changeset(
          AccountsFixtures.valid_user_attributes(%{
            email: "victim@example.com"
          })
        )
        |> Repo.insert()

      user = %{user | location: "Neverland", tagline: "ahoy", real_name: "Victim"}
      changeset = User.deletion_changeset(user)
      assert changeset.valid?
      changes = changeset.changes
      assert changes.deleted_at
      assert changes.location == nil
      assert changes.tagline == nil
      assert changes.real_name == nil
      assert changes.email == "deleted-#{user.id}@localhost"
      assert changes.password_hash == "invalid-deleted"
      assert changes.show_in_last_callers == false
    end
  end
end
