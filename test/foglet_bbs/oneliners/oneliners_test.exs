defmodule Foglet.OnelinersTest do
  use FogletBbs.DataCase, async: false

  alias Foglet.Oneliners.Entry
  alias FogletBbs.AccountsFixtures

  describe "Entry schema and create_changeset/2" do
    test "defines the locked persistence fields without updated_at" do
      fields = Entry.__schema__(:fields)

      assert :body in fields
      assert :hidden in fields
      assert :hidden_reason in fields
      assert :user_id in fields
      assert :hidden_by_id in fields
      assert :inserted_at in fields
      refute :updated_at in fields
    end

    test "validates and trims a valid body" do
      user = AccountsFixtures.user_fixture()

      changeset = Entry.create_changeset(%Entry{user_id: user.id}, %{body: "  hello  "})

      assert changeset.valid?
      assert Ecto.Changeset.get_change(changeset, :body) == "hello"
    end

    test "rejects blank and overlong bodies while accepting 120 characters" do
      user = AccountsFixtures.user_fixture()

      blank_changeset = Entry.create_changeset(%Entry{user_id: user.id}, %{body: "   "})
      overlong_changeset = Entry.create_changeset(%Entry{user_id: user.id}, %{body: String.duplicate("x", 121)})
      max_changeset = Entry.create_changeset(%Entry{user_id: user.id}, %{body: String.duplicate("x", 120)})

      refute blank_changeset.valid?
      assert {"can't be blank", _} = Keyword.fetch!(blank_changeset.errors, :body)

      refute overlong_changeset.valid?
      assert {"should be at most %{count} character(s)", _} = Keyword.fetch!(overlong_changeset.errors, :body)

      assert max_changeset.valid?
    end
  end
end
