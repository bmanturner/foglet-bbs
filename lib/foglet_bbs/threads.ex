defmodule Foglet.Threads do
  @moduledoc """
  Context for threads and thread read pointers.

  Thread creation routes through Foglet.Boards.Server (for message-number
  allocation). Other thread operations (lock, sticky, move, read pointers)
  are plain Ecto operations.

  Public API consumed by Phase 3 (SSH/TUI).
  """

  import Ecto.Query, warn: false

  alias Foglet.QueryHelpers

  alias Foglet.Accounts.User
  alias Foglet.Boards
  alias Foglet.Boards.Board
  alias Foglet.PostingPolicy
  alias Foglet.Posts.Post
  alias Foglet.Threads.{ReadPointer, Thread, ThreadEntry}
  alias FogletBbs.Repo

  # ---------- Bounded list defaults (Phase 47 — R3/R4) ----------

  # Default page size for `list_threads/{1,2,3}`. Centralised so the
  # SQL `LIMIT` and the public `default_page_size/0` accessor cannot
  # drift. Query bodies reference `@page_size` only — never the literal.
  @page_size 50

  # WR-07: hard ceiling on `:limit` — even an explicitly-passed positive
  # integer is clamped to this maximum so a future caller cannot
  # re-introduce the unbounded scan that Phase 47 R3/R4 removed.
  @max_page_size 500

  @doc "Default page size for `list_threads/{1,2,3}` (Phase 47 — R4)."
  # No @spec: the success typing is the literal `50`; widening to
  # `pos_integer()` triggers Dialyzer :contract_supertype.
  def default_page_size, do: @page_size

  # ---------- Authorization scope helper (D-08) ----------

  @doc """
  Returns the authorization scope for a thread — the board it belongs to.
  Consumed by callers of `Bodyguard.permit(Foglet.Authorization, action, actor, scope)`
  when the action targets a specific thread (e.g., `:lock_thread`, `:move_thread`).

  The thread/post operator call sites are deferred to Phase 8 per D-20; the helper is
  introduced now to complete the Phase 1 seam.
  """
  @spec scope_for(Thread.t()) :: {:board, Ecto.UUID.t()}
  def scope_for(%Thread{board_id: board_id}), do: {:board, board_id}

  # ---------- Thread creation (BOARD-02) ----------

  @doc """
  Create a thread with a root post. Delegates to Board Server for atomic
  message-number allocation and thread+post insertion.
  Returns {:ok, %{thread: thread, post: post}} on success.
  """
  @spec create_thread(String.t(), String.t(), map()) ::
          {:ok, %{thread: Thread.t(), post: Post.t()}} | {:error, any()}
  def create_thread(board_id, user_id, attrs) do
    user = safe_get(User, user_id)
    board = safe_get(Board, board_id)

    if PostingPolicy.can_post?(user, board) do
      Boards.Server.create_thread(board_id, user_id, attrs)
    else
      {:error, :posting_not_allowed}
    end
  end

  defp safe_get(schema, id) when is_binary(id) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} -> Repo.get(schema, uuid)
      :error -> nil
    end
  end

  defp safe_get(_schema, _id), do: nil

  # ---------- Thread queries ----------

  @doc "Get a thread by ID. Preloads :board, :created_by, :first_post. Raises if not found."
  @spec get_thread!(String.t()) :: Thread.t()
  def get_thread!(id) do
    Repo.get!(Thread, id)
    |> Repo.preload([:board, :created_by, :first_post])
  end

  @doc "Fetch a thread only when its board is visible to `actor`."
  @spec fetch_readable_thread(Foglet.Accounts.User.t() | nil, String.t()) ::
          {:ok, Thread.t()} | {:error, :not_found | :board_archived}
  def fetch_readable_thread(actor, id) do
    with %Thread{} = thread <-
           Repo.get(Thread, id) |> Repo.preload([:board, :created_by, :first_post]),
         {:ok, _board} <- Boards.fetch_readable_board(actor, thread.board_id) do
      {:ok, thread}
    else
      nil -> {:error, :not_found}
      error -> error
    end
  end

  @doc """
  List all non-deleted threads in a board, stickies first then by
  `last_post_at` desc.

  Bounded by `@page_size` (Phase 47 — R3). Delegates to `list_threads/3`
  with `opts: []`.
  """
  @spec list_threads(String.t()) :: [Thread.t()]
  def list_threads(board_id), do: list_threads(board_id, nil, [])

  @doc """
  List all non-deleted threads in a board, annotated with `:has_unread` for
  the given user (LIST-03).

  Bounded by `@page_size` (Phase 47 — R3). Delegates to `list_threads/3`
  with `opts: []`.
  """
  @spec list_threads(String.t(), String.t() | nil) :: [ThreadEntry.t()]
  def list_threads(board_id, user_id_or_nil), do: list_threads(board_id, user_id_or_nil, [])

  @doc """
  List non-deleted threads in a board, bounded to at most `@page_size` rows
  (Phase 47 — R3, R4). For binary `user_id` arguments each row is annotated
  with `:has_unread` against `thread_read_pointers`; for `nil` callers each
  row is annotated with `has_unread: false`.

  Order: `[desc: sticky, desc: last_post_at]` — stickies first, then newest
  activity within each tier.

  ## Options

    * `:limit` — positive integer overriding the default `@page_size` of
      `#{@page_size}`. Clamped to a hard ceiling of `@max_page_size`
      (`#{@max_page_size}`) so an erroneous caller cannot re-introduce
      an unbounded scan (WR-07). Non-positive or non-integer values fall
      back to `@page_size` (defensive default — D-06).

  ### Reserved keys (not yet implemented — D-06)

    * `:after`  — cursor for next page (future cursor-based pagination)
    * `:before` — cursor for prev page (future cursor-based pagination)

  Phase 47 only consumes `:limit`. Reserved keys are accepted by the
  function signature (because `opts` is a free-form keyword list) but are
  intentionally NOT validated, parsed, or rejected. Adding stub validators
  would introduce untested code paths and conflict with SPEC R3's "Phase 47
  only uses default options at call sites."
  """
  @spec list_threads(String.t(), String.t() | nil, keyword()) :: [ThreadEntry.t()]
  def list_threads(board_id, nil, opts) do
    case Boards.fetch_readable_board(nil, board_id) do
      {:ok, _board} ->
        limit = normalize_limit(Keyword.get(opts, :limit, @page_size))

        from(t in Thread,
          where: t.board_id == ^board_id,
          order_by: [desc: t.sticky, desc: t.last_post_at],
          limit: ^limit,
          preload: [:created_by]
        )
        |> QueryHelpers.not_deleted()
        |> Repo.all()
        |> Enum.map(&annotate_no_user/1)

      {:error, _reason} ->
        []
    end
  end

  def list_threads(board_id, user_id, opts) when is_binary(user_id) do
    board_id
    |> list_threads_query(user_id, opts)
    |> Repo.all()
    |> Enum.map(&struct(ThreadEntry, &1))
    |> preload_created_by()
  end

  @doc """
  Build the bounded `list_threads` Ecto query without executing it.

  Exposed so tests can inspect the generated SQL via
  `Ecto.Adapters.SQL.to_sql/3` to verify a `LIMIT` clause is applied at
  the SQL layer (R3 acceptance). Not intended for general callers —
  use `list_threads/3` instead.
  """
  @doc since: "Phase 47"
  @spec list_threads_query(String.t(), String.t() | nil, keyword()) :: Ecto.Query.t()
  def list_threads_query(board_id, nil, opts) do
    limit = normalize_limit(Keyword.get(opts, :limit, @page_size))

    from(t in Thread,
      join: b in Board,
      on: b.id == t.board_id,
      join: c in assoc(b, :category),
      where:
        t.board_id == ^board_id and b.readable_by == :public and b.archived == false and
          c.archived == false,
      order_by: [desc: t.sticky, desc: t.last_post_at],
      limit: ^limit
    )
    |> QueryHelpers.not_deleted()
  end

  def list_threads_query(board_id, user_id, opts) when is_binary(user_id) do
    limit = normalize_limit(Keyword.get(opts, :limit, @page_size))

    query =
      from t in Thread,
        left_join: trp in ReadPointer,
        on: trp.thread_id == t.id and trp.user_id == ^user_id,
        where: t.board_id == ^board_id,
        order_by: [desc: t.sticky, desc: t.last_post_at],
        limit: ^limit,
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

    QueryHelpers.not_deleted(query)
  end

  defp normalize_limit(limit) when is_integer(limit) and limit > 0,
    do: min(limit, @max_page_size)

  defp normalize_limit(_limit), do: @page_size

  defp preload_created_by(rows) do
    # Batch preload created_by for all threads in one query
    created_by_ids = rows |> Enum.map(& &1.created_by_id) |> Enum.filter(& &1) |> Enum.uniq()

    users =
      if created_by_ids == [] do
        %{}
      else
        Repo.all(
          from u in Foglet.Accounts.User, where: u.id in ^created_by_ids, select: {u.id, u}
        )
        |> Map.new()
      end

    Enum.map(rows, fn row ->
      %{row | created_by: Map.get(users, row.created_by_id)}
    end)
  end

  defp annotate_no_user(%Thread{} = t) do
    %ThreadEntry{
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
      has_unread: false,
      created_by: t.created_by
    }
  end

  # ---------- Mod/sysop operations (BOARD-12) ----------

  @doc """
  Lock a thread as the given actor (mod/sysop).

  Gates via `Bodyguard.permit/4` before delegating to the trusted single-arity
  variant. Returns `{:error, :forbidden}` when the actor is not authorized.
  Prefer this arity for general callers that have an actor in scope.
  """
  @spec lock_thread(User.t() | nil, Thread.t()) ::
          {:ok, Thread.t()} | {:error, Ecto.Changeset.t()} | {:error, :forbidden}
  def lock_thread(actor, %Thread{} = thread) do
    with :ok <- Bodyguard.permit(Foglet.Authorization, :lock_thread, actor, scope_for(thread)) do
      lock_thread(thread)
    end
  end

  # Trusted internal variant; callers MUST authorize. Prefer the actor-aware arity above for general callers.
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
  Move a thread to another board as the given actor (mod/sysop — BOARD-12).

  Gates via `Bodyguard.permit/4` before delegating to the trusted two-arity
  variant. Returns `{:error, :forbidden}` when the actor is not authorized.
  Prefer this arity for general callers that have an actor in scope.
  """
  @spec move_thread(User.t() | nil, Thread.t(), String.t()) ::
          {:ok, Thread.t()} | {:error, any()} | {:error, :forbidden}
  def move_thread(actor, %Thread{} = thread, new_board_id) do
    with :ok <- Bodyguard.permit(Foglet.Authorization, :move_thread, actor, scope_for(thread)) do
      move_thread(thread, new_board_id)
    end
  end

  # Trusted internal variant; callers MUST authorize. Prefer the actor-aware arity above for general callers.
  @doc """
  Move a thread to another board (mod/sysop — BOARD-12).

  Updates thread.board_id AND all posts in the thread (posts.board_id
  denormalization). Wrapped in a transaction for atomicity.

  NOTE: Moved posts retain their original message numbers. These numbers may not
  be contiguous with the destination board's existing message numbers — this is
  intentional. The unique constraint (board_id, message_number) prevents
  conflicts at the DB level; sysops should be aware of this limitation.
  """
  @spec move_thread(Thread.t(), String.t()) :: {:ok, Thread.t()} | {:error, any()}
  def move_thread(%Thread{} = thread, new_board_id) do
    Repo.transact(fn ->
      with {:ok, updated_thread} <-
             thread
             |> Ecto.Changeset.change(%{board_id: new_board_id})
             |> Repo.update() do
        # Pattern-match the return tuple to surface any unexpected return
        # shape from update_all (a non-`{integer, nil}` shape would mean Ecto
        # changed its contract, and we want to fail loudly rather than
        # silently swallow it).
        {_count, nil} =
          Repo.update_all(
            from(p in Post, where: p.thread_id == ^thread.id),
            set: [board_id: new_board_id]
          )

        {:ok, updated_thread}
      end
    end)
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
  Existing pointers only move forward by post `message_number`.
  """
  @spec advance_thread_read_pointer(String.t(), String.t(), String.t()) ::
          {:ok, ReadPointer.t()} | {:error, Ecto.Changeset.t()}
  def advance_thread_read_pointer(user_id, thread_id, last_read_post_id) do
    new_post = Repo.get_by!(Post, id: last_read_post_id, thread_id: thread_id)
    new_read_at = new_post.inserted_at

    on_conflict_query =
      from(rp in ReadPointer,
        update: [
          set: [
            last_read_post_id:
              fragment(
                """
                CASE
                WHEN ? > COALESCE((SELECT message_number FROM posts WHERE id = ?), 0)
                THEN ?
                ELSE ?
                END
                """,
                ^new_post.message_number,
                rp.last_read_post_id,
                type(^last_read_post_id, :binary_id),
                rp.last_read_post_id
              ),
            last_read_at:
              fragment(
                """
                CASE
                WHEN ? > COALESCE((SELECT message_number FROM posts WHERE id = ?), 0)
                THEN ?
                ELSE ?
                END
                """,
                ^new_post.message_number,
                rp.last_read_post_id,
                type(^new_read_at, :utc_datetime_usec),
                rp.last_read_at
              )
          ]
        ]
      )

    %ReadPointer{user_id: user_id, thread_id: thread_id}
    |> ReadPointer.changeset(%{last_read_post_id: last_read_post_id, last_read_at: new_read_at})
    |> Repo.insert(
      on_conflict: on_conflict_query,
      conflict_target: [:user_id, :thread_id],
      returning: true
    )
  end

  @doc "Get the thread read pointer for a user and thread. Returns nil if not found."
  @spec get_thread_read_pointer(String.t(), String.t()) :: ReadPointer.t() | nil
  def get_thread_read_pointer(user_id, thread_id) do
    Repo.get_by(ReadPointer, user_id: user_id, thread_id: thread_id)
  end
end
