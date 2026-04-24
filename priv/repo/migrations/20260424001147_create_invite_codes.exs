defmodule FogletBbs.Repo.Migrations.CreateInviteCodes do
  use Ecto.Migration

  def change do
    create table(:invite_codes, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :code, :string, null: false

      add :issuer_id, references(:users, type: :uuid, on_delete: :restrict), null: false
      add :consumed_at, :utc_datetime_usec

      add :consumed_by_user_id,
          references(:users, type: :uuid, on_delete: :nilify_all)

      add :revoked_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:invite_codes, [:code])
    create index(:invite_codes, [:issuer_id, :inserted_at])
    create index(:invite_codes, [:consumed_at])
    create index(:invite_codes, [:revoked_at])
  end
end
