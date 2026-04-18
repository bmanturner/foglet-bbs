defmodule FogletBbs.Repo.Migrations.CreatePostEdits do
  use Ecto.Migration

  def change do
    create table(:post_edits, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :previous_body, :string, null: false
      add :reason, :string
      add :edited_at, :utc_datetime_usec, null: false
      add :post_id, references(:posts, type: :binary_id, on_delete: :delete_all), null: false
      add :edited_by_id, references(:users, type: :binary_id, on_delete: :nilify_all), null: false
      add :inserted_at, :utc_datetime_usec, null: false
    end

    create index(:post_edits, [:post_id, :edited_at])
  end
end
