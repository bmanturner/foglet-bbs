defmodule FogletBbs.Repo.Migrations.CreateReports do
  use Ecto.Migration

  def change do
    create table(:reports, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :target_kind, :string, null: false
      add :target_id, :uuid, null: false
      add :reason, :text, null: false
      add :notes, :text
      add :status, :string, null: false, default: "open"
      add :resolved_at, :utc_datetime_usec
      add :resolution_note, :text

      add :reporter_id, references(:users, type: :uuid, on_delete: :nilify_all), null: false
      add :resolved_by_id, references(:users, type: :uuid, on_delete: :nilify_all)

      timestamps(type: :utc_datetime_usec)
    end

    create constraint(:reports, :reports_target_kind_must_be_supported,
             check: "target_kind IN ('post', 'oneliner', 'user')"
           )

    create constraint(:reports, :reports_status_must_be_supported,
             check: "status IN ('open', 'resolved', 'dismissed')"
           )

    create constraint(:reports, :reports_reason_must_not_be_blank, check: "btrim(reason) <> ''")

    create constraint(:reports, :reports_resolution_state_consistency,
             check: """
             (
               status = 'open' AND
               resolved_at IS NULL AND
               resolved_by_id IS NULL AND
               resolution_note IS NULL
             ) OR (
               status IN ('resolved', 'dismissed') AND
               resolved_at IS NOT NULL AND
               resolved_by_id IS NOT NULL AND
               resolution_note IS NOT NULL AND
               btrim(resolution_note) <> ''
             )
             """
           )

    create index(:reports, [:status], where: "status = 'open'", name: :reports_open_status_index)
    create index(:reports, [:reporter_id, :inserted_at])
  end
end
