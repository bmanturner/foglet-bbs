defmodule FogletBbs.Repo.Migrations.CreateModActions do
  use Ecto.Migration

  def change do
    create table(:mod_actions, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :kind, :string, null: false
      add :target_kind, :string, null: false
      add :target_id, :uuid, null: false
      add :reason, :text, null: false
      add :metadata, :map, null: false, default: %{}

      add :mod_id, references(:users, type: :uuid, on_delete: :nilify_all)

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create constraint(:mod_actions, :kind_must_be_hide_oneliner, check: "kind = 'hide_oneliner'")

    create constraint(:mod_actions, :target_kind_must_be_oneliner,
             check: "target_kind = 'oneliner'"
           )

    create constraint(:mod_actions, :reason_must_not_be_blank, check: "btrim(reason) <> ''")

    create index(:mod_actions, [:inserted_at])
    create index(:mod_actions, [:mod_id, :inserted_at])
  end
end
