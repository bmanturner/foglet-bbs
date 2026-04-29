defmodule FogletBbs.Repo.Migrations.AddAccountBoardContractBaseline do
  use Ecto.Migration

  @moduledoc """
  Forward:
  - Add canonical account handle and board slug columns.
  - Backfill canonical values from existing display values.
  - Enforce canonical uniqueness with unique indexes.
  - Add board membership role to board_subscriptions.

  Rollback:
  - Drop the canonical unique indexes.
  - Drop the canonical columns and membership role column.

  This rollback preserves user-authored handle/slug text and board membership
  rows; only derived canonical values and role metadata are removed.
  """

  def up do
    alter table(:users) do
      add :handle_canonical, :string
    end

    alter table(:boards) do
      add :slug_canonical, :string
    end

    alter table(:board_subscriptions) do
      add :role, :string, null: false, default: "reader"
    end

    execute("UPDATE users SET handle_canonical = lower(trim(handle::text))")
    execute("UPDATE boards SET slug_canonical = lower(trim(slug))")

    alter table(:users) do
      modify :handle_canonical, :string, null: false
    end

    alter table(:boards) do
      modify :slug_canonical, :string, null: false
    end

    create unique_index(:users, [:handle_canonical])
    create unique_index(:boards, [:slug_canonical])

    create constraint(:board_subscriptions, :board_subscriptions_role_valid,
             check: "role IN ('reader', 'poster', 'moderator', 'owner')"
           )
  end

  def down do
    drop constraint(:board_subscriptions, :board_subscriptions_role_valid)
    drop index(:boards, [:slug_canonical])
    drop index(:users, [:handle_canonical])

    alter table(:board_subscriptions) do
      remove :role
    end

    alter table(:boards) do
      remove :slug_canonical
    end

    alter table(:users) do
      remove :handle_canonical
    end
  end
end
