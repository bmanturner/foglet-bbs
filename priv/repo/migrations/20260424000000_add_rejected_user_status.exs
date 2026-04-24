defmodule FogletBbs.Repo.Migrations.AddRejectedUserStatus do
  use Ecto.Migration

  def up do
    drop constraint(:users, :status_must_be_valid)

    create constraint(:users, :status_must_be_valid,
             check: "status IN ('active', 'pending', 'rejected', 'suspended')"
           )
  end

  def down do
    execute "UPDATE users SET status = 'pending' WHERE status = 'rejected'"

    drop constraint(:users, :status_must_be_valid)

    create constraint(:users, :status_must_be_valid,
             check: "status IN ('active', 'pending', 'suspended')"
           )
  end
end
