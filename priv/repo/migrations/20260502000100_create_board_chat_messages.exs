defmodule FogletBbs.Repo.Migrations.CreateBoardChatMessages do
  use Ecto.Migration

  def change do
    create table(:board_chat_messages, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :body, :text, null: false

      add :board_id, references(:boards, type: :binary_id, on_delete: :delete_all), null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :nilify_all), null: false

      timestamps(type: :utc_datetime_usec)
    end

    create index(:board_chat_messages, [:board_id])

    # Composite index for the recent-messages query:
    # SELECT ... WHERE board_id = $1 ORDER BY inserted_at DESC LIMIT $2
    create index(:board_chat_messages, [:board_id, :inserted_at],
             name: :board_chat_messages_board_id_inserted_at_desc_idx
           )
  end
end
