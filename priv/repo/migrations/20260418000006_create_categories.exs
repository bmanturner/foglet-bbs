defmodule FogletBbs.Repo.Migrations.CreateCategories do
  use Ecto.Migration

  def change do
    create table(:categories, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :description, :string
      add :display_order, :integer, null: false, default: 0
      add :archived, :boolean, null: false, default: false
      timestamps(type: :utc_datetime_usec)
    end
  end
end
