defmodule FogletBbs.Repo.Migrations.CreateBoards do
  use Ecto.Migration

  def change do
    create table(:boards, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :slug, :string, null: false
      add :name, :string, null: false
      add :description, :string
      add :display_order, :integer, null: false, default: 0
      add :next_message_number, :integer, null: false, default: 1
      add :readable_by, :string, null: false, default: "public"
      add :postable_by, :string, null: false, default: "members"
      add :archived, :boolean, null: false, default: false
      add :default_subscription, :boolean, null: false, default: false
      add :category_id, references(:categories, type: :binary_id, on_delete: :restrict), null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:boards, [:slug])
    create index(:boards, [:category_id, :display_order])
  end
end
