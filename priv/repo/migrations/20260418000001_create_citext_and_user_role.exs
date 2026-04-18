defmodule FogletBbs.Repo.Migrations.CreateCitextAndUserRole do
  use Ecto.Migration

  def up do
    execute("CREATE EXTENSION IF NOT EXISTS citext")
    execute("CREATE TYPE user_role AS ENUM ('user', 'mod', 'sysop')")
  end

  def down do
    execute("DROP TYPE user_role")
    # Don't drop citext on down — other migrations may have run on the same DB;
    # leaving the extension installed is harmless.
  end
end
