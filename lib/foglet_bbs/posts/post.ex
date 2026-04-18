defmodule Foglet.Posts.Post do
  @moduledoc """
  Schema for BBS posts.

  NOTE: `body_tsv` is intentionally omitted from this schema — it is a
  PostgreSQL generated column (GENERATED ALWAYS AS ... STORED) used for
  full-text search. Phase 9 adds it to queries. Adding it here without
  `load_in_query: false` would cause Ecto to attempt INSERTs into the
  generated column, which Postgres rejects.
  """
  use Foglet.Schema

  schema "posts" do
    field :message_number, :integer
    field :body, :string
    # stays NULL in Phase 2; computed on demand via Foglet.Markdown.render/1 (D-03)
    field :body_rendered, :string
    field :deleted_at, :utc_datetime_usec
    field :deletion_reason, :string
    field :upvote_count, :integer, default: 0
    field :edit_count, :integer, default: 0
    field :last_edited_at, :utc_datetime_usec
    # body_tsv intentionally omitted — generated column, Phase 9 search queries

    belongs_to :thread, Foglet.Threads.Thread
    belongs_to :board, Foglet.Boards.Board
    belongs_to :user, Foglet.Accounts.User
    belongs_to :reply_to, Foglet.Posts.Post

    has_many :edits, Foglet.Posts.Edit
    has_many :upvotes, Foglet.Posts.Upvote

    timestamps()
  end

  @doc """
  Changeset for post creation. message_number, thread_id, board_id, user_id are
  set on the struct directly by the Board Server — NOT in attrs (security).
  """
  def creation_changeset(post, attrs) do
    post
    |> cast(attrs, [:body, :reply_to_id])
    |> validate_required([:body])
    |> validate_length(:body, min: 1, max: 65_535)
    |> foreign_key_constraint(:thread_id)
    |> foreign_key_constraint(:board_id)
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:reply_to_id)
    |> unique_constraint([:board_id, :message_number])
  end

  @doc "Changeset for post editing — only body and last_edited_at are mutable by user."
  def edit_changeset(post, attrs) do
    post
    |> cast(attrs, [:body])
    |> validate_required([:body])
    |> validate_length(:body, min: 1, max: 65_535)
    |> put_change(:last_edited_at, DateTime.utc_now())
    |> put_change(:edit_count, post.edit_count + 1)
  end

  @doc "Soft-delete changeset. deletion_reason optional (nil for user self-delete)."
  def delete_changeset(post, reason \\ nil) do
    change(post, %{deleted_at: DateTime.utc_now(), deletion_reason: reason})
  end
end
