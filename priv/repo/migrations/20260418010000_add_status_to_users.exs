defmodule FogletBbs.Repo.Migrations.AddStatusToUsers do
  use Ecto.Migration

  def up do
    # Use a text column with a CHECK constraint rather than a PG enum, to stay consistent
    # with Ecto.Enum on the schema side (stores strings). Default 'active' so existing
    # rows backfill cleanly.
    alter table(:users) do
      add :status, :string, null: false, default: "active"
    end

    create constraint(:users, :status_must_be_valid,
             check: "status IN ('active', 'pending', 'suspended')"
           )

    create index(:users, [:status])
  end

  def down do
    drop constraint(:users, :status_must_be_valid)
    drop index(:users, [:status])

    alter table(:users) do
      remove :status
    end
  end
end
