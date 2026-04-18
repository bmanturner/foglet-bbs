defmodule Foglet.Posts do
  @moduledoc """
  Context for posts and post editing.

  Post creation (create_reply/4) routes through Foglet.Boards.Server for
  message-number allocation. Edit and delete are plain Ecto operations.

  Public API consumed by Phase 3 (SSH/TUI).
  """

  import Ecto.Query, warn: false

  alias Ecto.Multi
  alias Foglet.Posts.{Edit, Post}
  alias FogletBbs.Repo

  # ---------- Post creation (BOARD-03) ----------

  @doc """
  Create a reply in a thread. Routes through Board Server for message-number
  allocation (BOARD-06). Returns {:ok, post} on success.

  `reply_to_id` is optional — pass nil for a plain reply, a post ID for a quoted reply.
  Optional reply-to metadata does not affect post ordering.
  """
  @spec create_reply(String.t(), String.t(), String.t(), map()) ::
          {:ok, Post.t()} | {:error, any()}
  def create_reply(thread_id, board_id, user_id, attrs) do
    Foglet.Boards.Server.create_post(board_id, thread_id, user_id, attrs)
  end

  # ---------- Post queries ----------

  @doc "Get a post by ID. Preloads :user and :reply_to. Raises if not found."
  @spec get_post!(String.t()) :: Post.t()
  def get_post!(id) do
    Repo.get!(Post, id)
    |> Repo.preload([:user, :reply_to])
  end

  @doc "List all non-deleted posts in a thread, in insertion order. Preloads :user."
  @spec list_posts(String.t()) :: [Post.t()]
  def list_posts(thread_id) do
    Repo.all(
      from p in Post,
        where: p.thread_id == ^thread_id and is_nil(p.deleted_at),
        order_by: [asc: :inserted_at],
        preload: [:user]
    )
  end

  # ---------- Post editing (BOARD-04) ----------

  @doc """
  Edit a post body. Inserts a post_edits record with the previous body,
  then updates the post. Uses Ecto.Multi for atomicity.

  Returns {:ok, post} on success, {:error, reason} on failure.
  """
  @spec edit_post(Post.t(), String.t(), map()) :: {:ok, Post.t()} | {:error, any()}
  def edit_post(%Post{} = post, editor_user_id, attrs) do
    previous_body = post.body

    Multi.new()
    |> Multi.insert(:edit_record, fn _ ->
      %Edit{post_id: post.id, edited_by_id: editor_user_id}
      |> Edit.changeset(%{
        previous_body: previous_body,
        edited_at: DateTime.utc_now()
      })
    end)
    |> Multi.update(:post, fn _ ->
      Post.edit_changeset(post, attrs)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{post: updated_post}} -> {:ok, updated_post}
      {:error, _op, reason, _changes} -> {:error, reason}
    end
  end

  @doc "List edit history for a post, newest first. Preloads :edited_by."
  @spec list_edits(String.t()) :: [Edit.t()]
  def list_edits(post_id) do
    Repo.all(
      from e in Edit,
        where: e.post_id == ^post_id,
        order_by: [desc: :edited_at],
        preload: [:edited_by]
    )
  end

  # ---------- Post soft-delete (BOARD-11) ----------

  @doc """
  Soft-delete a post. Sets deleted_at; message number is preserved permanently
  (no gap filling). The post body remains in the DB but should be shown as
  a tombstone ([deleted]) when rendered.

  `reason` is optional — nil for user self-delete, string for mod action.
  """
  @spec delete_post(Post.t(), String.t() | nil) ::
          {:ok, Post.t()} | {:error, Ecto.Changeset.t()}
  def delete_post(%Post{} = post, reason \\ nil) do
    post
    |> Post.delete_changeset(reason)
    |> Repo.update()
  end
end
