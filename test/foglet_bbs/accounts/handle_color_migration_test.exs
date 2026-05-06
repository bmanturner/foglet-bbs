defmodule Foglet.Accounts.HandleColorMigrationTest do
  use FogletBbs.DataCase, async: true

  alias Foglet.Accounts
  alias FogletBbs.{AccountsFixtures, Repo}

  @migration_path "priv/repo/migrations/20260506140000_add_handle_color_to_users.exs"

  setup_all do
    Code.require_file(@migration_path)
    :ok
  end

  test "database default persists #FFFFFF for direct inserts" do
    attrs = AccountsFixtures.valid_user_attributes()
    changeset = Foglet.Accounts.User.registration_changeset(%Foglet.Accounts.User{}, attrs)
    changeset = Ecto.Changeset.delete_change(changeset, :handle_color)

    {:ok, user} = Repo.insert(changeset)

    assert Accounts.get_user!(user.id).handle_color == "#FFFFFF"
  end

  test "backfill is idempotent and does not clobber valid custom values" do
    defaulted = AccountsFixtures.user_fixture()
    custom = AccountsFixtures.user_fixture()

    {:ok, defaulted_id} = Ecto.UUID.dump(defaulted.id)
    {:ok, custom_id} = Ecto.UUID.dump(custom.id)

    Repo.query!("UPDATE users SET handle_color = NULL WHERE id = $1", [defaulted_id])
    Repo.query!("UPDATE users SET handle_color = '#ff8800' WHERE id = $1", [custom_id])

    sql = FogletBbs.Repo.Migrations.AddHandleColorToUsers.backfill_handle_color_sql()
    Repo.query!(sql)
    Repo.query!(sql)

    assert Accounts.get_user!(defaulted.id).handle_color == "#FFFFFF"
    assert Accounts.get_user!(custom.id).handle_color == "#ff8800"
  end
end
