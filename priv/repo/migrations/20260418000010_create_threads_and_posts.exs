defmodule FogletBbs.Repo.Migrations.CreateThreadsAndPosts do
  use Ecto.Migration

  def up do
    # Step 1: Create threads WITHOUT first_post_id (circular FK not yet resolvable)
    create table(:threads, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :title, :string, null: false
      add :locked, :boolean, null: false, default: false
      add :sticky, :boolean, null: false, default: false
      add :deleted_at, :utc_datetime_usec
      add :post_count, :integer, null: false, default: 1
      add :last_post_at, :utc_datetime_usec
      add :board_id, references(:boards, type: :binary_id, on_delete: :delete_all), null: false
      add :created_by_id, references(:users, type: :binary_id, on_delete: :nilify_all), null: false
      # first_post_id added AFTER posts table is created (see ALTER TABLE below)
      timestamps(type: :utc_datetime_usec)
    end

    create index(:threads, [:board_id, :sticky, :last_post_at],
      name: :threads_board_id_sticky_last_post_at_idx
    )

    create index(:threads, [:board_id],
      where: "deleted_at IS NULL",
      name: :threads_board_id_active_idx
    )

    # Step 2: Create posts with FK to threads
    create table(:posts, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :message_number, :integer, null: false
      add :body, :string, null: false
      add :body_rendered, :string
      add :deleted_at, :utc_datetime_usec
      add :deletion_reason, :string
      add :upvote_count, :integer, null: false, default: 0
      add :edit_count, :integer, null: false, default: 0
      add :last_edited_at, :utc_datetime_usec
      add :thread_id, references(:threads, type: :binary_id, on_delete: :delete_all), null: false
      add :board_id, references(:boards, type: :binary_id, on_delete: :delete_all), null: false
      add :user_id, references(:users, type: :binary_id, on_delete: :nilify_all), null: false
      add :reply_to_id, references(:posts, type: :binary_id, on_delete: :nilify_all)
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:posts, [:board_id, :message_number])
    create index(:posts, [:thread_id, :inserted_at])

    create index(:posts, [:user_id, :inserted_at],
      where: "deleted_at IS NULL",
      name: :posts_user_id_inserted_at_active_idx
    )

    # Add full-text search generated column (Phase 9 will query it)
    execute """
    ALTER TABLE posts ADD COLUMN body_tsv tsvector
    GENERATED ALWAYS AS (to_tsvector('english', coalesce(body, ''))) STORED;
    """

    execute "CREATE INDEX posts_body_tsv_gin_idx ON posts USING GIN (body_tsv);"

    # Step 3: Add first_post_id FK to threads now that posts table exists
    alter table(:threads) do
      add :first_post_id, references(:posts, type: :binary_id, on_delete: :nilify_all)
    end
  end

  def down do
    # Remove first_post_id FK before dropping posts
    alter table(:threads) do
      remove :first_post_id
    end

    drop table(:posts)
    drop table(:threads)
  end
end
