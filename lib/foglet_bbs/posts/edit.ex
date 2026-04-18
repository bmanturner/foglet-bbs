defmodule Foglet.Posts.Edit do
  @moduledoc "Schema for post edit history — insert-only records of previous post bodies."
  use Foglet.Schema

  schema "post_edits" do
    field :previous_body, :string
    field :reason, :string
    field :edited_at, :utc_datetime_usec

    belongs_to :post, Foglet.Posts.Post
    belongs_to :edited_by, Foglet.Accounts.User

    timestamps(updated_at: false)
  end

  @doc "Changeset for recording edit history. post_id and edited_by_id set on struct."
  def changeset(edit, attrs) do
    edit
    |> cast(attrs, [:previous_body, :reason, :edited_at])
    |> validate_required([:previous_body])
    |> put_change(:edited_at, Map.get(attrs, :edited_at, DateTime.utc_now()))
    |> foreign_key_constraint(:post_id)
    |> foreign_key_constraint(:edited_by_id)
  end
end
