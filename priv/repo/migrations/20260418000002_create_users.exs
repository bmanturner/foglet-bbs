defmodule FogletBbs.Repo.Migrations.CreateUsers do
  use Ecto.Migration

  def up do
    create table(:users, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :handle, :citext, null: false
      add :email, :citext, null: false
      add :password_hash, :string, null: false
      add :confirmed_at, :utc_datetime_usec

      add :role, :user_role, null: false, default: "user"

      add :location, :string
      add :tagline, :string
      add :real_name, :string

      add :post_count, :integer, null: false, default: 0
      add :last_seen_at, :utc_datetime_usec

      add :theme, :string, null: false, default: "default"
      add :show_in_last_callers, :boolean, null: false, default: true
      add :email_digest, :string, null: false, default: "off"
      add :preferences, :map, null: false, default: %{}

      add :deleted_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:users, [:handle])
    create unique_index(:users, [:email])

    create index(:users, [:last_seen_at],
             where: "deleted_at IS NULL",
             name: :users_last_seen_at_active_idx
           )
  end

  def down do
    drop table(:users)
  end
end
