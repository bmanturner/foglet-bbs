defmodule FogletBbs.Repo.Migrations.AddRequiredSubscriptionToBoards do
  use Ecto.Migration

  def change do
    alter table(:boards) do
      add :required_subscription, :boolean, null: false, default: false
    end

    create constraint(:boards, :boards_required_subscription_requires_default_subscription,
             check: "required_subscription = false OR default_subscription = true"
           )
  end
end
