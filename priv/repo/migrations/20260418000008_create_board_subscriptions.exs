defmodule FogletBbs.Repo.Migrations.CreateBoardSubscriptions do
  use Ecto.Migration

  def change do
    create table(:board_subscriptions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :board_id, references(:boards, type: :binary_id, on_delete: :delete_all), null: false
      add :subscribed_at, :utc_datetime_usec
      add :inserted_at, :utc_datetime_usec, null: false
    end

    create unique_index(:board_subscriptions, [:user_id, :board_id])
    create index(:board_subscriptions, [:board_id])
  end
end
