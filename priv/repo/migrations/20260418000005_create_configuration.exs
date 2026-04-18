defmodule FogletBbs.Repo.Migrations.CreateConfiguration do
  use Ecto.Migration

  def change do
    create table(:configuration, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :key, :string, null: false
      add :value, :map, null: false
      add :description, :string

      add :updated_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:configuration, [:key])
  end
end
