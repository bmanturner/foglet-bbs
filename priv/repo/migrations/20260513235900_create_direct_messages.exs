defmodule FogletBbs.Repo.Migrations.CreateDirectMessages do
  use Ecto.Migration

  def change do
    create table(:direct_messages, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :body, :text, null: false
      add :read_at, :utc_datetime_usec
      add :deleted_by_sender_at, :utc_datetime_usec
      add :deleted_by_recipient_at, :utc_datetime_usec

      add :sender_id, references(:users, type: :binary_id, on_delete: :nilify_all), null: false

      add :recipient_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime_usec)
    end

    create constraint(:direct_messages, :direct_messages_body_must_not_be_blank,
             check: "btrim(body) <> ''"
           )

    create constraint(:direct_messages, :direct_messages_sender_recipient_must_differ,
             check: "sender_id <> recipient_id"
           )

    create index(:direct_messages, [:recipient_id, :inserted_at],
             name: :direct_messages_recipient_id_inserted_at_idx
           )

    create index(:direct_messages, [:sender_id, :inserted_at],
             name: :direct_messages_sender_id_inserted_at_idx
           )

    create index(:direct_messages, [:recipient_id],
             where: "read_at IS NULL AND deleted_by_recipient_at IS NULL",
             name: :direct_messages_recipient_id_unread_idx
           )

    create index(:direct_messages, [:sender_id, :recipient_id, :inserted_at],
             name: :direct_messages_sender_recipient_inserted_at_idx
           )
  end
end
