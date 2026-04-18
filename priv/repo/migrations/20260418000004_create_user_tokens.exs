defmodule FogletBbs.Repo.Migrations.CreateUserTokens do
  use Ecto.Migration

  def change do
    create table(:user_tokens, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :token, :binary, null: false
      add :context, :string, null: false
      add :sent_to, :string

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      add :inserted_at, :utc_datetime_usec, null: false
    end

    create unique_index(:user_tokens, [:context, :token])
    create index(:user_tokens, [:user_id])
  end
end
