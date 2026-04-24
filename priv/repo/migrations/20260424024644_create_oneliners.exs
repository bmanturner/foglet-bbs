defmodule FogletBbs.Repo.Migrations.CreateOneliners do
  use Ecto.Migration

  def change do
    create table(:oneliners, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :body, :string, null: false
      add :hidden, :boolean, null: false, default: false
      add :hidden_reason, :string

      add :user_id, references(:users, type: :uuid, on_delete: :delete_all), null: false
      add :hidden_by_id, references(:users, type: :uuid, on_delete: :nilify_all)

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:oneliners, [:inserted_at], where: "hidden = false")
  end
end
