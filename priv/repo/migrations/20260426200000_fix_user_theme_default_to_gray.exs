defmodule FogletBbs.Repo.Migrations.FixUserThemeDefaultToGray do
  use Ecto.Migration

  def up do
    execute("UPDATE users SET theme = 'gray' WHERE theme = 'default'")
    execute("ALTER TABLE users ALTER COLUMN theme SET DEFAULT 'gray'")
  end

  def down do
    execute("ALTER TABLE users ALTER COLUMN theme SET DEFAULT 'default'")
  end
end
