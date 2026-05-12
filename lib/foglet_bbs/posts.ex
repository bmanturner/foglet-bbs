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
  alias Foglet.Notifications
  alias Foglet.Notifications.Mentions
  alias Foglet.PostingPolicy
  alias Foglet.Posts.{Edit, Post, ReaderWindow, Upvote}
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
      # belongs to a different board, (c) thread is soft-deleted,
      # (d) `thread` is not a `%Thread{}` —
      # into a single `:posting_not_allowed` error so callers without
      # post-creation permission cannot probe thread existence.
      not match?(%Thread{board_id: ^board_id, deleted_at: nil}, thread) ->
        {:error, :posting_not_allowed}

      thread.locked and not PostingPolicy.can_bypass_thread_lock?(user, board_id) ->
        {:error, :thread_locked}

      true ->
        with {:ok, post} <- Boards.Server.create_post(board_id, thread_id, user_id, attrs) do
          emit_post_event_notifications(post, thread, attrs)
          {:ok, post}
        end
    end
  end

  defp emit_post_event_notifications(%Post{} = post, %Thread{} = thread, attrs) do
    mentioned_users =
      attrs
      |> post_body()
      |> Mentions.extract_handles()
      |> active_mentioned_users(post.user_id)

    mentioned_ids = MapSet.new(mentioned_users, & &1.id)

    mentioned_users
    |> Enum.each(&create_post_event_notification(:mention, &1.id, post))

    reply_recipient_id = reply_recipient_id(post)

    if reply_recipient_id && not MapSet.member?(mentioned_ids, reply_recipient_id) do
      create_post_event_notification(:reply, reply_recipient_id, post)
    end

    notified_ids =
      mentioned_ids
      |> maybe_put(reply_recipient_id)

    if thread.created_by_id != post.user_id and
         not MapSet.member?(notified_ids, thread.created_by_id) do
      create_post_event_notification(:thread_update, thread.created_by_id, post)
    end
  end

  defp post_body(attrs), do: Map.get(attrs, :body, Map.get(attrs, "body", ""))

  defp active_mentioned_users([], _actor_id), do: []

  defp active_mentioned_users(handles, actor_id) do
    normalized_handles = Enum.map(handles, &String.downcase/1)

    User
    |> where([user], user.status == :active)
    |> where([user], is_nil(user.deleted_at))
    |> where([user], user.id != ^actor_id)
    |> where([user], fragment("lower(?)", user.handle) in ^normalized_handles)
    |> Repo.all()
  end

  defp reply_recipient_id(%Post{reply_to_id: nil}), do: nil

  defp reply_recipient_id(%Post{} = reply) do
    case Repo.get(Post, reply.reply_to_id) do
      %Post{deleted_at: nil, user_id: recipient_id}
      when not is_nil(recipient_id) and recipient_id != reply.user_id ->
        recipient_id

      _parent_missing_deleted_or_self ->
        nil
    end
  end

  defp maybe_put(set, nil), do: set
  defp maybe_put(set, value), do: MapSet.put(set, value)

  defp create_post_event_notification(kind, recipient_id, %Post{} = post) do
    case Notifications.create_notification(%{
           user_id: recipient_id,
           actor_id: post.user_id,
           kind: kind,
           dedupe_key: post_recipient_dedupe_key(post.id, recipient_id),
           payload: post_event_payload(kind, post)
         }) do
      {:ok, _notification} ->
        :ok

      {:error, reason} ->
        Logger.warning("#{kind} notification emission skipped: #{inspect(reason)}")
    end
  end

  defp post_event_payload(_kind, %Post{} = post),
    do: %{
      board_id: post.board_id,
      thread_id: post.thread_id,
      post_id: post.id,
      snippet: post.body
    }

  defp post_recipient_dedupe_key(post_id, recipient_id),
    do: "post:#{post_id}:user:#{recipient_id}"

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

  @doc "Fetch a post only when its board is visible to `actor`."
  @spec fetch_readable_post(Foglet.Accounts.User.t() | nil, String.t()) ::
          {:ok, Post.t()} | {:error, :not_found | :board_archived}
  def fetch_readable_post(actor, id) do
    with %Post{} = post <- Repo.get(Post, id) |> Repo.preload([:user, :reply_to]),
         {:ok, _board} <- Boards.fetch_readable_board(actor, post.board_id) do
      {:ok, post}
    else
      nil -> {:error, :not_found}
      error -> error
    end
  end

  @doc """
  Actor-aware upvote boundary for reader surfaces.

  The actor must be an active, non-deleted user and the target post must be
  readable through the same board-visibility gate used for reply-context fetches.
  Own-post attempts remain silent no-ops via `toggle_upvote/2`.
  """
  @spec toggle_readable_upvote(Foglet.Accounts.User.t() | nil, String.t()) ::
          {:ok, Post.t()} | {:error, term()}
  def toggle_readable_upvote(
        %User{status: :active, deleted_at: nil, id: user_id} = actor,
        post_id
      ) do
    with {:ok, %Post{id: readable_post_id}} <- fetch_readable_post(actor, post_id) do
      toggle_upvote(user_id, readable_post_id)
    end
  end

  def toggle_readable_upvote(_actor, _post_id), do: {:error, :forbidden}

  @doc """
  Toggles `user_id`'s upvote on `post_id` and returns the refreshed post.

  Own-post attempts are silent no-ops. The post row is locked while the upvote
  row is inserted/deleted and the denormalized `posts.upvote_count` is
  reconciled to the actual upvote row count, so rapid repeat toggles and
  concurrent sessions cannot create duplicate rows or drifting counts.
  """
  @spec toggle_upvote(String.t(), String.t()) :: {:ok, Post.t()} | {:error, term()}
  def toggle_upvote(user_id, post_id) do
    with {:ok, user_uuid} <- Ecto.UUID.cast(user_id),
         {:ok, post_uuid} <- Ecto.UUID.cast(post_id) do
      Repo.transaction(fn ->
        post = locked_post!(post_uuid)

        if post.user_id == user_uuid do
          Repo.preload(post, [:user, :reply_to])
        else
          toggle_upvote_row!(user_uuid, post_uuid)
          reconcile_post_upvote_count!(post_uuid)
        end
      end)
    else
      :error -> {:error, :not_found}
    end
  end

  defp locked_post!(post_id) do
    query = from p in Post, where: p.id == ^post_id, lock: "FOR UPDATE"

    case Repo.one(query) do
      %Post{} = post -> post
      nil -> Repo.rollback(:not_found)
    end
  end

  defp toggle_upvote_row!(user_id, post_id) do
    case Repo.get_by(Upvote, user_id: user_id, post_id: post_id) do
      %Upvote{} = upvote ->
        Repo.delete!(upvote)

      nil ->
        %Upvote{user_id: user_id, post_id: post_id}
        |> Upvote.changeset(%{})
        |> Repo.insert!()
    end
  end

  defp reconcile_post_upvote_count!(post_id) do
    count =
      Upvote
      |> where([u], u.post_id == ^post_id)
      |> Repo.aggregate(:count, :id)

    Post
    |> where([p], p.id == ^post_id)
    |> Repo.update_all(set: [upvote_count: count])

    get_post!(post_id)
  end

  @doc """
  Returns a reader window only when `actor` may read the thread's board.

  This actor-aware wrapper is the domain boundary direct-navigation callers
  should use; the legacy `list_reader_window/2` remains trusted/internal so
  authenticated member flows do not lose access to members-only boards.
  """
  @spec list_reader_window_for(Foglet.Accounts.User.t() | nil, String.t(), keyword()) ::
          {:ok, ReaderWindow.t()} | {:error, :not_found | :board_archived}
  def list_reader_window_for(actor, thread_id, opts \\ []) do
    with {:ok, _thread} <- Foglet.Threads.fetch_readable_thread(actor, thread_id) do
      {:ok, list_reader_window(thread_id, opts)}
    end
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
        #
        # IN-04: mirror BL-01 for the nil-cursor case. Without a positive
        # cursor we cannot meaningfully report `has_next?`: there is no
        # "current window" to page forward from. The `:previous` direction
        # with `before_message_number: nil` collapses to "the tail of the
        # thread"; reporting `has_next?: true` for that result misleads
        # callers that map it to a "Next" affordance.
        has_next? =
          posts != [] and is_integer(cursor) and cursor > 0 and
            reader_has_next?(thread_id, posts, cursor)

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
