defmodule Foglet.Posts do
  @moduledoc """
  Context for posts and post editing.

  Post creation (create_reply/4) routes through Foglet.Boards.Server for
  message-number allocation. Edit and delete are plain Ecto operations.

  Public API consumed by Phase 3 (SSH/TUI).
  """

  import Ecto.Query, warn: false

  alias Foglet.Accounts.User
  alias Foglet.Boards
  alias Foglet.Boards.Board
  alias Foglet.PostingPolicy
  alias Foglet.Posts.{Edit, Post}
  alias Foglet.Threads.Thread
  alias FogletBbs.Repo

  # ---------- Authorization scope helper (D-08) ----------

  @doc """
  Returns the authorization scope for a post — the board it belongs to.
  Consumed by callers of `Bodyguard.permit(Foglet.Authorization, action, actor, scope)`
  when the action targets a specific post (e.g., `:delete_post`, `:edit_post_as_mod`).

  The post operator call sites are deferred to Phase 8 per D-20; the helper is
  introduced now to complete the Phase 1 seam.
  """
  @spec scope_for(Post.t()) :: {:board, Ecto.UUID.t()}
  def scope_for(%Post{board_id: board_id}), do: {:board, board_id}

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
    user = safe_get(User, user_id)
    board = safe_get(Board, board_id)
    thread = safe_get(Thread, thread_id)

    cond do
      not PostingPolicy.can_post?(user, board) ->
        {:error, :posting_not_allowed}

      not match?(%Thread{board_id: ^board_id}, thread) ->
        {:error, :posting_not_allowed}

      thread.locked and not PostingPolicy.can_bypass_thread_lock?(user, board_id) ->
        {:error, :thread_locked}

      true ->
        Boards.Server.create_post(board_id, thread_id, user_id, attrs)
    end
  end

  defp safe_get(schema, id) when is_binary(id) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} -> Repo.get(schema, uuid)
      :error -> nil
    end
  end

  defp safe_get(_schema, _id), do: nil

  # ---------- Post queries ----------

  @doc "Get a post by ID. Preloads :user and :reply_to. Raises if not found."
  @spec get_post!(String.t()) :: Post.t()
  def get_post!(id) do
    Repo.get!(Post, id)
    |> Repo.preload([:user, :reply_to])
  end

  @doc "List all posts in a thread, in insertion order. Preloads :user."
  @spec list_posts(String.t()) :: [Post.t()]
  def list_posts(thread_id) do
    Repo.all(
      from p in Post,
        where: p.thread_id == ^thread_id,
        order_by: [asc: :inserted_at],
        preload: [:user]
    )
  end

  # ---------- Post editing (BOARD-04) ----------

  @doc """
  Edit a post body. Inserts a post_edits record with the previous body,
  then updates the post. Wrapped in a transaction for atomicity.

  Returns {:ok, post} on success, {:error, reason} on failure.
  """
  @spec edit_post(Post.t(), String.t(), map()) :: {:ok, Post.t()} | {:error, any()}
  def edit_post(%Post{} = post, editor_user_id, attrs) do
    Repo.transact(fn ->
      edit_cs =
        Edit.changeset(
          %Edit{post_id: post.id, edited_by_id: editor_user_id},
          %{previous_body: post.body, edited_at: DateTime.utc_now()}
        )

      with {:ok, _edit} <- Repo.insert(edit_cs) do
        post |> Post.edit_changeset(attrs) |> Repo.update()
      end
    end)
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
