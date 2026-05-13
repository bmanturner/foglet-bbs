defmodule FogletBbs.Repo.Migrations.CreateSshAccessRulesAndLastCallers do
  use Ecto.Migration

  def change do
    create table(:ssh_access_rules, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :mode, :string, null: false
      add :address, :string, null: false
      add :enabled, :boolean, null: false, default: true
      add :reason, :string, null: false
      add :comment, :text
      add :created_by_id, references(:users, type: :uuid, on_delete: :nilify_all)

      timestamps(type: :utc_datetime_usec)
    end

    create constraint(:ssh_access_rules, :ssh_access_rules_mode_check,
             check: "mode in ('allow', 'deny')"
           )

    create index(:ssh_access_rules, [:enabled, :mode])
    create index(:ssh_access_rules, [:created_by_id])

    create table(:last_callers, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :interface, :string, null: false
      add :peer_ip, :string
      add :peer_port, :integer
      add :user_id, references(:users, type: :uuid, on_delete: :nilify_all)
      add :outcome, :string, null: false
      add :reason, :string
      add :policy_key, :string
      add :session_id, :string
      add :public_visible, :boolean, null: false, default: false
      add :occurred_at, :utc_datetime_usec, null: false
      add :disconnected_at, :utc_datetime_usec
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create constraint(:last_callers, :last_callers_interface_check,
             check: "interface in ('ssh', 'cli', 'telnet')"
           )

    create constraint(:last_callers, :last_callers_outcome_check,
             check:
               "outcome in ('accepted', 'denied', 'rate_limited', 'over_global_limit', 'auth_gate_denied', 'failed')"
           )

    create constraint(:last_callers, :last_callers_peer_port_check,
             check: "peer_port is null or (peer_port >= 0 and peer_port <= 65535)"
           )

    create index(:last_callers, [:occurred_at], name: :last_callers_occurred_at_all_index)
    create index(:last_callers, [:user_id, :occurred_at])

    create index(:last_callers, [:occurred_at],
             name: :last_callers_public_accepted_occurred_at_index,
             where: "public_visible = true and outcome = 'accepted'"
           )

    create index(:last_callers, [:outcome, :occurred_at])
  end
end
