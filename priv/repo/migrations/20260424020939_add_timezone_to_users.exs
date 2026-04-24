defmodule FogletBbs.Repo.Migrations.AddTimezoneToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :timezone, :string, null: false, default: "Etc/UTC"
    end
  end
end
