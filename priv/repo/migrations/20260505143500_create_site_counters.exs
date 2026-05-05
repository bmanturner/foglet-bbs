defmodule FogletBbs.Repo.Migrations.CreateSiteCounters do
  use Ecto.Migration

  def change do
    create table(:site_counters, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :value, :bigint, null: false, default: 0

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:site_counters, [:name])

    create constraint(:site_counters, :site_counters_value_non_negative, check: "value >= 0")
  end
end
