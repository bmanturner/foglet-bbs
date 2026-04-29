defmodule Foglet.Boards.Subscription do
  @moduledoc """
  Schema for board subscriptions.

  In the domain contract this table is the BoardMembership persistence row:
  every member has a board-local role and may also be subscribed for navigation.
  """
  use Foglet.Schema

  @roles [:reader, :poster, :moderator, :owner]

  schema "board_subscriptions" do
    field :subscribed_at, :utc_datetime_usec
    field :role, Ecto.Enum, values: @roles, default: :reader

    belongs_to :user, Foglet.Accounts.User
    belongs_to :board, Foglet.Boards.Board

    timestamps(updated_at: false)
  end

  @doc "Changeset for subscription creation. user_id and board_id set on struct before calling."
  def changeset(subscription, attrs) do
    subscription
    |> cast(attrs, [:subscribed_at, :role])
    |> put_change(:subscribed_at, Map.get(attrs, :subscribed_at, DateTime.utc_now()))
    |> validate_required([:role])
    |> validate_inclusion(:role, @roles)
    |> unique_constraint([:user_id, :board_id])
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:board_id)
  end

  def roles, do: @roles
end
