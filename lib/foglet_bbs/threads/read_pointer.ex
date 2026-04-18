defmodule Foglet.Threads.ReadPointer do
  @moduledoc "Schema for thread read pointers — tracks last-read post per user per thread."
  use Foglet.Schema

  schema "thread_read_pointers" do
    field :last_read_at, :utc_datetime_usec

    belongs_to :user, Foglet.Accounts.User
    belongs_to :thread, Foglet.Threads.Thread
    belongs_to :last_read_post, Foglet.Posts.Post

    timestamps(updated_at: false)
  end

  @doc "Changeset for upsert. user_id and thread_id set on struct before calling."
  def changeset(pointer, attrs) do
    pointer
    |> cast(attrs, [:last_read_at, :last_read_post_id])
    |> put_change(:last_read_at, Map.get(attrs, :last_read_at, DateTime.utc_now()))
    |> unique_constraint([:user_id, :thread_id])
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:thread_id)
    |> foreign_key_constraint(:last_read_post_id)
  end
end
