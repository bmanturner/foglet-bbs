defmodule Foglet.Accounts.UserStatusTest do
  use FogletBbs.DataCase, async: true

  alias Foglet.Accounts.User
  alias FogletBbs.AccountsFixtures

  describe "status_changeset/2" do
    test "accepts rejected status" do
      changeset = User.status_changeset(%User{}, %{status: :rejected})

      assert changeset.valid?
    end

    test "rejects unknown status" do
      changeset = User.status_changeset(%User{}, %{status: :banned})

      refute changeset.valid?
      assert "is invalid" in errors_on(changeset).status
    end
  end

  describe "rejected persistence" do
    test "inserts and reloads a non-deleted rejected user" do
      attrs = AccountsFixtures.valid_user_attributes()

      {:ok, user} =
        %User{}
        |> User.registration_changeset(attrs)
        |> Ecto.Changeset.put_change(:status, :rejected)
        |> Repo.insert()

      assert %User{status: :rejected, deleted_at: nil} = Repo.get!(User, user.id)
    end
  end
end
