defmodule Foglet.Posts.Upvote do
  @moduledoc "Schema for post upvotes — tracks which users upvoted which posts."
  use Foglet.Schema

  schema "upvotes" do
    belongs_to :user, Foglet.Accounts.User
    belongs_to :post, Foglet.Posts.Post

    timestamps(updated_at: false)
  end

  @doc "Changeset for upvote creation. user_id and post_id set on struct."
  def changeset(upvote, attrs) do
    upvote
    |> cast(attrs, [])
    |> unique_constraint([:user_id, :post_id])
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:post_id)
  end
end
