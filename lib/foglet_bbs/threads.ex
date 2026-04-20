defmodule Foglet.Threads do
  @moduledoc """
  Context for threads and thread read pointers.

  Thread creation routes through Foglet.Boards.Server (for message-number
  allocation). Other thread operations (lock, sticky, move, read pointers)
  are plain Ecto operations.

  Public API consumed by Phase 3 (SSH/TUI).
  """

  import Ecto.Query, warn: false

  alias Ecto.Multi
  alias Foglet.Posts.Post
  alias Foglet.Threads.{ReadPointer, Thread}
  alias FogletBbs.Repo

  # ---------- Thread creation (BOARD-02) ----------

  @doc """
  Create a thread with a root post. Delegates to Board Server for atomic
  message-number allocation and thread+post insertion.
  Returns {:ok, %{thread: thread, post: post}} on success.
  """
  @spec create_thread(String.t(), String.t(), map()) ::
          {:ok, %{thread: Thread.t(), post: Post.t()}} | {:error, any()}
  def create_thread(board_id, user_id, attrs) do
    Foglet.Boards.Server.create_thread(board_id, user_id, attrs)
  end

  # ---------- Thread queries ----------

  @doc "Get a thread by ID. Preloads :board, :created_by, :first_post. Raises if not found."
  @spec get_thread!(String.t()) :: Thread.t()
  def get_thread!(id) do
    Repo.get!(Thread, id)
    |> Repo.preload([:board, :created_by, :first_post])
  end

  @doc "List all non-deleted threads in a board, stickies first then by last_post_at desc."
  @spec list_threads(String.t()) :: [Thread.t()]
  def list_threads(board_id) do
    Repo.all(
      from t in Thread,
        where: t.board_id == ^board_id and is_nil(t.deleted_at),
        order_by: [desc: t.sticky, desc: t.last_post_at],
        preload: [:created_by]
    )
  end

  @doc """
  List all non-deleted threads in a board, annotated with `:has_unread` for
  the given user (LIST-03).

  Returns a list of maps (not `Thread.t()` structs) — each map merges the
  thread's fields with a boolean `:has_unread` virtual field computed
  from `thread_read_pointers`. A thread is `has_unread: true` when its
  `last_post_at` is later than the user's `last_read_at` for that thread
  (NULL last_read_at is treated as the Unix epoch, so never-opened
  threads with activity are unread). Empty threads (`last_post_at IS
  NULL`) are always `has_unread: false`.

  Order matches `list_threads/1`: stickies first, then newest activity.
  Preloads `:created_by` so callers can render the creator handle
  without a follow-up N+1 query.

  When `user_id` is `nil`, delegates to `list_threads/1` and annotates
  every row with `has_unread: false` — the "no user context" case used
  by admin paths and tests that don't care about read-state.
  """
  @spec list_threads(String.t(), String.t() | nil) :: [map()]
  def list_threads(board_id, nil) do
    board_id
    |> list_threads()
    |> Enum.map(&annotate_no_user/1)
  end

  def list_threads(board_id, user_id) when is_binary(user_id) do
    query =
      from t in Thread,
        left_join: trp in ReadPointer,
        on: trp.thread_id == t.id and trp.user_id == ^user_id,
        where: t.board_id == ^board_id and is_nil(t.deleted_at),
        order_by: [desc: t.sticky, desc: t.last_post_at],
        select: %{
          id: t.id,
          title: t.title,
          board_id: t.board_id,
          sticky: t.sticky,
          locked: t.locked,
          post_count: t.post_count,
          first_post_id: t.first_post_id,
          last_post_at: t.last_post_at,
          deleted_at: t.deleted_at,
          inserted_at: t.inserted_at,
          created_by_id: t.created_by_id,
          has_unread:
            not is_nil(t.last_post_at) and
              t.last_post_at > coalesce(trp.last_read_at, fragment("to_timestamp(0)"))
        }

    query
    |> Repo.all()
    |> preload_created_by()
  end

  defp preload_created_by(rows) do
    # Batch preload created_by for all threads in one query
    created_by_ids = rows |> Enum.map(& &1.created_by_id) |> Enum.filter(& &1) |> Enum.uniq()

    users =
      if created_by_ids == [] do
        %{}
      else
        Repo.all(from u in Foglet.Accounts.User, where: u.id in ^created_by_ids, select: {u.id, u})
        |> Map.new()
      end

    Enum.map(rows, fn row ->
      Map.put(row, :created_by, Map.get(users, row.created_by_id))
    end)
  end

  defp annotate_no_user(%Thread{} = t) do
    t
    |> Map.from_struct()
    |> Map.put(:has_unread, false)
  end

  # ---------- Mod/sysop operations (BOARD-12) ----------

  @doc "Lock a thread (mod/sysop). Returns {:ok, thread} or {:error, changeset}."
  @spec lock_thread(Thread.t()) :: {:ok, Thread.t()} | {:error, Ecto.Changeset.t()}
  def lock_thread(%Thread{} = thread) do
    thread |> Thread.lock_changeset(true) |> Repo.update()
  end

  @doc "Unlock a thread (mod/sysop)."
  @spec unlock_thread(Thread.t()) :: {:ok, Thread.t()} | {:error, Ecto.Changeset.t()}
  def unlock_thread(%Thread{} = thread) do
    thread |> Thread.lock_changeset(false) |> Repo.update()
  end

  @doc "Sticky a thread (mod/sysop)."
  @spec sticky_thread(Thread.t()) :: {:ok, Thread.t()} | {:error, Ecto.Changeset.t()}
  def sticky_thread(%Thread{} = thread) do
    thread |> Thread.sticky_changeset(true) |> Repo.update()
  end

  @doc "Unsticky a thread (mod/sysop)."
  @spec unsticky_thread(Thread.t()) :: {:ok, Thread.t()} | {:error, Ecto.Changeset.t()}
  def unsticky_thread(%Thread{} = thread) do
    thread |> Thread.sticky_changeset(false) |> Repo.update()
  end

  @doc """
  Move a thread to another board (mod/sysop — BOARD-12).

  Updates thread.board_id AND all posts in the thread (posts.board_id
  denormalization). Uses Ecto.Multi for atomicity.

  NOTE: Moved posts retain their original message numbers. These numbers may not
  be contiguous with the destination board's existing message numbers — this is
  intentional. The unique constraint (board_id, message_number) prevents
  conflicts at the DB level; sysops should be aware of this limitation.
  """
  @spec move_thread(Thread.t(), String.t()) :: {:ok, Thread.t()} | {:error, any()}
  def move_thread(%Thread{} = thread, new_board_id) do
    Multi.new()
    |> Multi.update(:thread, Ecto.Changeset.change(thread, %{board_id: new_board_id}))
    |> Multi.update_all(
      :posts,
      from(p in Post, where: p.thread_id == ^thread.id),
      set: [board_id: new_board_id]
    )
    |> Repo.transaction()
    |> case do
      {:ok, %{thread: updated_thread}} -> {:ok, updated_thread}
      {:error, _op, reason, _changes} -> {:error, reason}
    end
  end

  @doc "Soft-delete a thread."
  @spec delete_thread(Thread.t()) :: {:ok, Thread.t()} | {:error, Ecto.Changeset.t()}
  def delete_thread(%Thread{} = thread) do
    thread |> Thread.delete_changeset() |> Repo.update()
  end

  # ---------- Read pointers (BOARD-09) ----------

  @doc """
  Advance (or create) a thread read pointer.
  Upserts on (user_id, thread_id) — safe to call multiple times.
  """
  @spec advance_thread_read_pointer(String.t(), String.t(), String.t()) ::
          {:ok, ReadPointer.t()} | {:error, Ecto.Changeset.t()}
  def advance_thread_read_pointer(user_id, thread_id, last_read_post_id) do
    now = DateTime.utc_now()

    %ReadPointer{user_id: user_id, thread_id: thread_id}
    |> ReadPointer.changeset(%{last_read_post_id: last_read_post_id, last_read_at: now})
    |> Repo.insert(
      on_conflict: [set: [last_read_post_id: last_read_post_id, last_read_at: now]],
      conflict_target: [:user_id, :thread_id]
    )
  end

  @doc "Get the thread read pointer for a user and thread. Returns nil if not found."
  @spec get_thread_read_pointer(String.t(), String.t()) :: ReadPointer.t() | nil
  def get_thread_read_pointer(user_id, thread_id) do
    Repo.get_by(ReadPointer, user_id: user_id, thread_id: thread_id)
  end
end
