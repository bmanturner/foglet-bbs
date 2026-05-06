defmodule FogletBbs.Repo.Migrations.AddHandleColorToUsers do
  use Ecto.Migration

  @default_handle_color "#FFFFFF"

  def up do
    alter table(:users) do
      add :handle_color, :string, default: @default_handle_color
    end

    backfill_handle_color()

    create constraint(:users, :users_handle_color_hex_format,
             check: "handle_color IS NULL OR handle_color ~ '^#[0-9A-Fa-f]{6}$'"
           )
  end

  def down do
    drop constraint(:users, :users_handle_color_hex_format)

    alter table(:users) do
      remove :handle_color
    end
  end

  def backfill_handle_color do
    execute(backfill_handle_color_sql())
  end

  def backfill_handle_color_sql do
    """
    UPDATE users
    SET handle_color = '#{@default_handle_color}'
    WHERE handle_color IS NULL
    """
  end
end
