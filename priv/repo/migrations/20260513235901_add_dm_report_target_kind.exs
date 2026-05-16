defmodule FogletBbs.Repo.Migrations.AddDmReportTargetKind do
  use Ecto.Migration

  def up do
    drop constraint(:reports, :reports_target_kind_must_be_supported)

    create constraint(:reports, :reports_target_kind_must_be_supported,
             check: "target_kind IN ('post', 'oneliner', 'user', 'dm')"
           )
  end

  def down do
    drop constraint(:reports, :reports_target_kind_must_be_supported)

    create constraint(:reports, :reports_target_kind_must_be_supported,
             check: "target_kind IN ('post', 'oneliner', 'user')"
           )
  end
end
