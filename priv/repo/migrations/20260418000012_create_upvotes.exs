defmodule FogletBbs.Repo.Migrations.CreateUpvotes do
  use Ecto.Migration

  def change do
    create table(:upvotes, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :post_id, references(:posts, type: :binary_id, on_delete: :delete_all), null: false
      add :inserted_at, :utc_datetime_usec, null: false
    end

    create unique_index(:upvotes, [:user_id, :post_id])
    create index(:upvotes, [:post_id])
  end
end
