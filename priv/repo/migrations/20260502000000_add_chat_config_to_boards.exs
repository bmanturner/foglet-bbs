defmodule FogletBbs.Repo.Migrations.AddChatConfigToBoards do
  use Ecto.Migration

  def change do
    alter table(:boards) do
      add :chat_enabled, :boolean, null: false, default: false
      add :chat_storage_mode, :string, null: false, default: "ephemeral"
      add :chat_message_ttl_seconds, :integer, null: false, default: 7200
    end

    create constraint(:boards, :boards_chat_storage_mode_allowed,
             check: "chat_storage_mode IN ('ephemeral', 'permanent')"
           )

    create constraint(:boards, :boards_chat_message_ttl_seconds_range,
             check:
               "chat_enabled = false OR chat_storage_mode <> 'ephemeral' OR (chat_message_ttl_seconds >= 60 AND chat_message_ttl_seconds <= 86400)"
           )
  end
end
