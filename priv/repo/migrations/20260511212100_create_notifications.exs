defmodule FogletBbs.Repo.Migrations.CreateNotifications do
  use Ecto.Migration

  def change do
    create table(:notifications, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :kind, :string, null: false
      add :payload, :map, null: false
      add :read_at, :utc_datetime_usec
      add :dedupe_key, :string

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      add :actor_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      timestamps(updated_at: false, type: :utc_datetime_usec)
    end

    create index(:notifications, [:user_id, :inserted_at],
             where: "read_at IS NULL",
             name: :notifications_user_id_unread_inserted_at_idx
           )

    create index(:notifications, [:user_id, :inserted_at],
             name: :notifications_user_id_inserted_at_idx
           )

    create unique_index(:notifications, [:user_id, :dedupe_key],
             where: "dedupe_key IS NOT NULL",
             name: :notifications_user_id_dedupe_key_idx
           )
  end
end
