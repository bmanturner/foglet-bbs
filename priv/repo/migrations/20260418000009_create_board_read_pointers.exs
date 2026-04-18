defmodule FogletBbs.Repo.Migrations.CreateBoardReadPointers do
  use Ecto.Migration

  def change do
    create table(:board_read_pointers, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :last_read_message_number, :integer, null: false, default: 0
      add :last_read_at, :utc_datetime_usec
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :board_id, references(:boards, type: :binary_id, on_delete: :delete_all), null: false
      add :inserted_at, :utc_datetime_usec, null: false
    end

    create unique_index(:board_read_pointers, [:user_id, :board_id])
  end
end
