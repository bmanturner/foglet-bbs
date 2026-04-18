defmodule Foglet.Boards.Subscription do
  @moduledoc "Schema for board subscriptions — tracks which users subscribe to which boards."
  use Foglet.Schema

  schema "board_subscriptions" do
    field :subscribed_at, :utc_datetime_usec

    belongs_to :user, Foglet.Accounts.User
    belongs_to :board, Foglet.Boards.Board

    timestamps(updated_at: false)
  end

  @doc "Changeset for subscription creation. user_id and board_id set on struct before calling."
  def changeset(subscription, attrs) do
    subscription
    |> cast(attrs, [:subscribed_at])
    |> put_change(:subscribed_at, Map.get(attrs, :subscribed_at, DateTime.utc_now()))
    |> unique_constraint([:user_id, :board_id])
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:board_id)
  end
end
