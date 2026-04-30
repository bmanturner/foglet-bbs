defmodule Foglet.Posts do
  @moduledoc """
  Context for posts and post editing.

  Post creation (create_reply/4) routes through Foglet.Boards.Server for
  message-number allocation. Edit and delete are plain Ecto operations.

  Public API consumed by Phase 3 (SSH/TUI).
  """

  import Ecto.Query, warn: false

  require Logger

  alias Foglet.Accounts.User
  alias Foglet.Boards
  alias Foglet.Boards.Board
  alias Foglet.PostingPolicy
  alias Foglet.Posts.{Edit, Post, ReaderWindow}
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

      # IN-02: this clause intentionally folds three failure modes —
      # (a) thread does not exist (`safe_get` returned nil), (b) thread
      # belongs to a different board, (c) `thread` is not a `%Thread{}` —
      # into a single `:posting_not_allowed` error so callers without
      # post-creation permission cannot probe thread existence.
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

  @doc """
  Returns a bounded, tombstone-capable reader window for a thread.

  Cursor semantics are based on per-board `message_number` scoped by
  `thread_id`, and returned posts are always ordered ascending for reader
  display. This intentionally does not filter soft-deleted rows.
  """
  @spec list_reader_window(String.t(), keyword()) :: ReaderWindow.t()
  def list_reader_window(thread_id, opts \\ []) do
    limit = normalize_reader_limit(Keyword.get(opts, :limit, 50))
    direction = normalize_reader_direction(Keyword.get(opts, :direction, :initial))

    case direction do
      :initial ->
        rows = reader_rows(thread_id, order: :asc, limit: limit + 1)
        {posts, extra} = Enum.split(rows, limit)
        reader_window(posts, direction, false, extra != [])

      :next ->
        cursor = Keyword.get(opts, :after_message_number, 0)
        rows = reader_rows(thread_id, after_message_number: cursor, order: :asc, limit: limit + 1)
        {posts, extra} = Enum.split(rows, limit)

        reader_window(
          posts,
          direction,
          reader_has_previous?(thread_id, posts, cursor),
          extra != []
        )

      :previous ->
        cursor = Keyword.get(opts, :before_message_number, nil)

        rows =
          reader_rows(thread_id, before_message_number: cursor, order: :desc, limit: limit + 1)

        {window_rows, extra} = Enum.split(rows, limit)
        posts = Enum.reverse(window_rows)
        # BL-01: when no previous posts exist relative to `cursor`, there is
        # by definition nothing to page forward into either — pass `false`
        # rather than letting `reader_has_next?` infer `true` from the
        # mere presence of an integer cursor.
        has_next? = posts != [] and reader_has_next?(thread_id, posts, cursor)
        reader_window(posts, direction, extra != [], has_next?)

      :last ->
        rows = reader_rows(thread_id, order: :desc, limit: limit + 1)
        {window_rows, extra} = Enum.split(rows, limit)
        posts = Enum.reverse(window_rows)
        reader_window(posts, direction, extra != [], false)

      :around ->
        around_message_number = Keyword.get(opts, :around_message_number, nil)

        {posts, has_previous?, has_next?} =
          reader_rows_around(thread_id, around_message_number, limit)

        reader_window(posts, direction, has_previous?, has_next?)
    end
  end

  defp normalize_reader_limit(limit) when is_integer(limit) and limit > 0, do: limit
  defp normalize_reader_limit(_limit), do: 50

  defp normalize_reader_direction(direction)
       when direction in [:initial, :next, :previous, :last, :around],
       do: direction

  # WR-04 (iteration 2): mirror the WR-06 fix in `reader_rows_around/3`. A
  # buggy caller (e.g. a typo like `:before` or a string `"next"`) would
  # otherwise silently degrade to the `:initial` window with no diagnostic.
  # Surface the coercion via Logger.warning while keeping the defensive
  # default — `:direction` is an external-API-shaped option (documented in
  # the @spec keyword list shape) so a future caller can easily get it
  # wrong, and we want a breadcrumb when that happens.
  defp normalize_reader_direction(direction) do
    Logger.warning(
      "Foglet.Posts.list_reader_window/2 received unknown direction; " <>
        "coercing to :initial. direction=#{inspect(direction)}"
    )

    :initial
  end

  defp reader_rows(thread_id, opts) do
    order = Keyword.fetch!(opts, :order)
    limit = Keyword.fetch!(opts, :limit)

    Post
    |> where([p], p.thread_id == ^thread_id)
    |> maybe_after_message_number(Keyword.get(opts, :after_message_number))
    |> maybe_before_message_number(Keyword.get(opts, :before_message_number))
    |> order_by_message_number(order)
    |> limit(^limit)
    |> preload([:user])
    |> Repo.all()
  end

  defp reader_rows_around(thread_id, nil, limit) do
    rows = reader_rows(thread_id, order: :asc, limit: limit + 1)
    {posts, extra} = Enum.split(rows, limit)
    {posts, false, extra != []}
  end

  defp reader_rows_around(thread_id, around_message_number, limit)
       when is_integer(around_message_number) do
    before_limit = div(limit - 1, 2)
    after_limit = limit - before_limit

    previous_rows =
      reader_rows(
        thread_id,
        before_message_number: around_message_number,
        order: :desc,
        limit: before_limit + 1
      )

    {previous_window_rows, previous_extra} = Enum.split(previous_rows, before_limit)

    next_rows =
      reader_rows(
        thread_id,
        after_message_number: around_message_number - 1,
        order: :asc,
        limit: after_limit + 1
      )

    {next_window_rows, next_extra} = Enum.split(next_rows, after_limit)

    {Enum.reverse(previous_window_rows) ++ next_window_rows, previous_extra != [],
     next_extra != []}
  end

  # WR-06: defensive fallback for non-int / non-nil `around_message_number`.
  # Callers always pass `int | nil`; if a buggy caller passes anything else
  # (e.g. a stringified number), surface it via a Logger.warning rather than
  # silently coercing to the initial-window query.
  defp reader_rows_around(thread_id, around_message_number, limit) do
    Logger.warning(
      "Foglet.Posts.reader_rows_around/3 received non-integer around_message_number; " <>
        "coercing to initial window. thread_id=#{inspect(thread_id)} " <>
        "around_message_number=#{inspect(around_message_number)}"
    )

    reader_rows_around(thread_id, nil, limit)
  end

  defp maybe_after_message_number(query, nil), do: query

  defp maybe_after_message_number(query, message_number) when is_integer(message_number) do
    where(query, [p], p.message_number > ^message_number)
  end

  defp maybe_after_message_number(query, _message_number), do: query

  defp maybe_before_message_number(query, nil), do: query

  defp maybe_before_message_number(query, message_number) when is_integer(message_number) do
    where(query, [p], p.message_number < ^message_number)
  end

  defp maybe_before_message_number(query, _message_number), do: query

  defp order_by_message_number(query, :desc), do: order_by(query, [p], desc: p.message_number)
  defp order_by_message_number(query, _asc), do: order_by(query, [p], asc: p.message_number)

  defp reader_window(posts, direction, has_previous?, has_next?) do
    %ReaderWindow{
      posts: posts,
      first_message_number: posts |> List.first() |> message_number(),
      last_message_number: posts |> List.last() |> message_number(),
      has_previous?: has_previous?,
      has_next?: has_next?,
      direction: direction
    }
  end

  defp reader_has_previous?(_thread_id, [_ | _posts], _fallback_cursor), do: true

  defp reader_has_previous?(_thread_id, [], cursor) when is_integer(cursor) and cursor > 0,
    do: true

  defp reader_has_previous?(_thread_id, _posts, _cursor), do: false

  defp reader_has_next?(_thread_id, [_ | _posts], _fallback_cursor), do: true

  # BL-01: require cursor > 0 (mirrors reader_has_previous?/3 — a cursor of
  # 0 with no posts means there is no adjacent next window).
  defp reader_has_next?(_thread_id, [], cursor) when is_integer(cursor) and cursor > 0,
    do: true

  defp reader_has_next?(_thread_id, _posts, _cursor), do: false

  defp message_number(nil), do: nil
  defp message_number(%Post{message_number: message_number}), do: message_number

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
  Soft-delete a post as the given actor (mod/sysop).

  Gates via `Bodyguard.permit/4` before delegating to the trusted single-arity
  variant. Returns `{:error, :forbidden}` when the actor is not authorized.
  Prefer this arity for general callers that have an actor in scope.

  `reason` is optional — nil for user self-delete, string for mod action.
  """
  @spec delete_post(User.t() | nil, Post.t(), String.t() | nil) ::
          {:ok, Post.t()} | {:error, Ecto.Changeset.t()} | {:error, :forbidden}
  def delete_post(actor, %Post{} = post, reason) do
    with :ok <- Bodyguard.permit(Foglet.Authorization, :delete_post, actor, scope_for(post)) do
      delete_post(post, reason)
    end
  end

  # Trusted internal variant; callers MUST authorize. Prefer the actor-aware arity above for general callers.
  @doc """
  Soft-delete a post. Sets deleted_at; message number is preserved permanently
  (no gap filling). The post body remains in the DB but should be shown as
  a tombstone ([deleted]) when rendered.

  `reason` is optional — nil for user self-delete, string for mod action.
  """
  @spec delete_post(Post.t(), String.t() | nil) ::
          {:ok, Post.t()} | {:error, Ecto.Changeset.t()}
  def delete_post(%Post{} = post, reason) do
    post
    |> Post.delete_changeset(reason)
    |> Repo.update()
  end

  @spec delete_post(Post.t()) :: {:ok, Post.t()} | {:error, Ecto.Changeset.t()}
  def delete_post(%Post{} = post), do: delete_post(post, nil)
end
