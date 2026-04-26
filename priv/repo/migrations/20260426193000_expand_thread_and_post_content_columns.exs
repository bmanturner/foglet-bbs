defmodule FogletBbs.Repo.Migrations.ExpandThreadAndPostContentColumns do
  use Ecto.Migration

  def up do
    alter table(:threads) do
      modify :title, :string, size: 300, null: false
    end

    execute "DROP INDEX IF EXISTS posts_body_tsv_gin_idx"
    execute "ALTER TABLE posts DROP COLUMN body_tsv"

    alter table(:posts) do
      modify :body, :text, null: false
      modify :body_rendered, :text
    end

    execute """
    ALTER TABLE posts ADD COLUMN body_tsv tsvector
    GENERATED ALWAYS AS (to_tsvector('english', coalesce(body, ''))) STORED
    """

    execute "CREATE INDEX posts_body_tsv_gin_idx ON posts USING GIN (body_tsv)"

    alter table(:post_edits) do
      modify :previous_body, :text, null: false
    end
  end

  def down do
    alter table(:post_edits) do
      modify :previous_body, :string, null: false
    end

    execute "DROP INDEX IF EXISTS posts_body_tsv_gin_idx"
    execute "ALTER TABLE posts DROP COLUMN body_tsv"

    alter table(:posts) do
      modify :body, :string, null: false
      modify :body_rendered, :string
    end

    execute """
    ALTER TABLE posts ADD COLUMN body_tsv tsvector
    GENERATED ALWAYS AS (to_tsvector('english', coalesce(body, ''))) STORED
    """

    execute "CREATE INDEX posts_body_tsv_gin_idx ON posts USING GIN (body_tsv)"

    alter table(:threads) do
      modify :title, :string, null: false
    end
  end
end
