defmodule FogletBbs.Repo.Migrations.AddStructuredKindToBoardChatMessages do
  use Ecto.Migration

  def change do
    alter table(:board_chat_messages) do
      add :kind, :string, null: false, default: "text"
      add :metadata, :map, null: false, default: %{}
    end

    create constraint(:board_chat_messages, :board_chat_messages_kind_check,
             check: "kind in ('text', 'action')"
           )
  end
end
