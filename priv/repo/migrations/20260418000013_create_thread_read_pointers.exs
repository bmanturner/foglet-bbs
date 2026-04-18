defmodule FogletBbs.Repo.Migrations.CreateThreadReadPointers do
  use Ecto.Migration

  def change do
    create table(:thread_read_pointers, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :last_read_at, :utc_datetime_usec
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :thread_id, references(:threads, type: :binary_id, on_delete: :delete_all), null: false
      add :last_read_post_id, references(:posts, type: :binary_id, on_delete: :nilify_all)
      add :inserted_at, :utc_datetime_usec, null: false
    end

    create unique_index(:thread_read_pointers, [:user_id, :thread_id])
  end
end
