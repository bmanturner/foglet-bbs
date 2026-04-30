defmodule Foglet.Threads.Thread do
  @moduledoc "Schema for BBS threads — titled discussions within a board."
  use Foglet.Schema

  schema "threads" do
    field :title, :string
    field :locked, :boolean, default: false
    field :sticky, :boolean, default: false
    field :deleted_at, :utc_datetime_usec
    field :post_count, :integer, default: 1
    field :last_post_at, :utc_datetime_usec

    belongs_to :board, Foglet.Boards.Board
    belongs_to :created_by, Foglet.Accounts.User
    belongs_to :first_post, Foglet.Posts.Post

    has_many :posts, Foglet.Posts.Post

    timestamps()
  end

  @doc "Changeset for thread creation. board_id and created_by_id set on struct before calling."
  def creation_changeset(thread, attrs) do
    thread
    |> cast(attrs, [:title])
    |> validate_required([:title])
    |> validate_length(:title, min: 1, max: 300)
    |> foreign_key_constraint(:board_id)
    |> foreign_key_constraint(:created_by_id)
  end

  @doc "Used by Board Server to update thread counters after a post is inserted."
  def bump_counters(thread, %Foglet.Posts.Post{inserted_at: inserted_at}) do
    change(thread, %{
      post_count: thread.post_count + 1,
      last_post_at: inserted_at
    })
  end

  @doc "Set first_post_id and last_post_at after root post creation."
  def set_first_post(thread, %Foglet.Posts.Post{id: post_id, inserted_at: inserted_at}) do
    change(thread, %{first_post_id: post_id, last_post_at: inserted_at})
  end

  @doc "Mod/sysop: lock or unlock a thread."
  def lock_changeset(thread, locked) do
    change(thread, %{locked: locked})
  end

  @doc "Mod/sysop: sticky or unsticky a thread."
  def sticky_changeset(thread, sticky) do
    change(thread, %{sticky: sticky})
  end

  @doc "Soft-delete a thread."
  def delete_changeset(thread) do
    change(thread, %{deleted_at: DateTime.utc_now()})
  end
end
