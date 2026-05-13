defmodule FogletBbs.Repo.Migrations.CreateIdentityPolicyRules do
  use Ecto.Migration

  def change do
    create table(:identity_policy_rules, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :kind, :string, null: false
      add :value, :string, null: false
      add :normalized_value, :string, null: false
      add :enabled, :boolean, null: false, default: true
      add :reason, :string, null: false
      add :comment, :text
      add :created_by_id, references(:users, type: :uuid, on_delete: :nilify_all)
      add :updated_by_id, references(:users, type: :uuid, on_delete: :nilify_all)

      timestamps(type: :utc_datetime_usec)
    end

    create constraint(:identity_policy_rules, :identity_policy_rules_kind_check,
             check:
               "kind in ('reserved_handle', 'banned_handle', 'banned_email', 'banned_email_domain')"
           )

    create unique_index(:identity_policy_rules, [:kind, :normalized_value])
    create index(:identity_policy_rules, [:enabled, :kind])
    create index(:identity_policy_rules, [:created_by_id])
    create index(:identity_policy_rules, [:updated_by_id])
  end
end
