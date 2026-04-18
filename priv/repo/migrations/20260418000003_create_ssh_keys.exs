defmodule FogletBbs.Repo.Migrations.CreateSshKeys do
  use Ecto.Migration

  def change do
    create table(:ssh_keys, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :label, :string, null: false
      add :public_key, :text, null: false
      add :fingerprint, :string, null: false
      add :last_used_at, :utc_datetime_usec

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:ssh_keys, [:fingerprint])
    create unique_index(:ssh_keys, [:user_id, :label])
    create index(:ssh_keys, [:user_id])
  end
end
