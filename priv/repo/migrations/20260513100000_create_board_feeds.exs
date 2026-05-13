defmodule FogletBbs.Repo.Migrations.CreateBoardFeeds do
  use Ecto.Migration

  def change do
    create table(:board_feeds, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :board_id, references(:boards, type: :uuid, on_delete: :delete_all), null: false
      add :url, :text, null: false
      add :title, :string, null: false
      add :enabled, :boolean, null: false, default: true
      add :display_order, :integer, null: false, default: 0
      add :cache_ttl_seconds, :integer, null: false, default: 3600
      add :last_fetched_at, :utc_datetime_usec
      add :last_success_at, :utc_datetime_usec
      add :last_error, :text

      timestamps(type: :utc_datetime_usec)
    end

    create index(:board_feeds, [:board_id, :enabled])
    create unique_index(:board_feeds, [:board_id, :url])

    create constraint(:board_feeds, :board_feeds_cache_ttl_seconds_range,
             check: "cache_ttl_seconds BETWEEN 300 AND 86400"
           )

    create constraint(:board_feeds, :board_feeds_url_length,
             check: "char_length(url) BETWEEN 1 AND 2048"
           )

    create table(:board_feed_items, primary_key: false) do
      add :id, :uuid, primary_key: true

      add :board_feed_id, references(:board_feeds, type: :uuid, on_delete: :delete_all),
        null: false

      add :board_id, references(:boards, type: :uuid, on_delete: :delete_all), null: false
      add :external_id, :string, null: false
      add :title, :string, null: false
      add :url, :text
      add :author, :string
      add :summary, :text
      add :published_at, :utc_datetime_usec
      add :fetched_at, :utc_datetime_usec, null: false
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:board_feed_items, [:board_feed_id, :external_id])
    create index(:board_feed_items, [:board_id, :published_at])
    create index(:board_feed_items, [:board_feed_id, :fetched_at])

    create constraint(:board_feed_items, :board_feed_items_title_length,
             check: "char_length(title) BETWEEN 1 AND 300"
           )
  end
end
