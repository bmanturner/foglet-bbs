defmodule Foglet.Boards do
  @moduledoc """
  Context for categories, boards, subscriptions, and read pointers.

  Public API consumed by:
    * Phase 2: Foglet.Boards.Server (via internal calls)
    * Phase 2: FogletBbs.Application.start/2 (boot_board_servers/0)
    * Phase 2: Foglet.Accounts.create_user/1 (subscribe_to_defaults/1 — D-06)
    * Phase 3: SSH/TUI (list_boards, subscribe, read pointer management)
  """

  import Ecto.Query, warn: false

  alias Foglet.Boards.{Board, Category, ReadPointer, Subscription}
  alias Foglet.Boards.Supervisor, as: BoardSupervisor
  alias FogletBbs.Repo

  # ---------- Application boot ----------

  @doc """
  Start a Board Server for every non-archived board.
  Called from FogletBbs.Application.start/2 after the supervision tree is up.
  Replaces the stub in Plan 02.
  """
  @spec boot_board_servers() :: :ok
  def boot_board_servers do
    active_board_ids = Repo.all(from b in Board, where: b.archived == false, select: b.id)
    Enum.each(active_board_ids, &BoardSupervisor.start_board/1)
    :ok
  end

  # ---------- Categories ----------

  @doc "Create a category (sysop pathway — BOARD-01)."
  @spec create_category(map()) :: {:ok, Category.t()} | {:error, Ecto.Changeset.t()}
  def create_category(attrs) do
    %Category{}
    |> Category.changeset(attrs)
    |> Repo.insert()
  end

  @doc "Get a category by ID. Raises if not found."
  @spec get_category!(String.t()) :: Category.t()
  def get_category!(id), do: Repo.get!(Category, id)

  @doc "List all non-archived categories, ordered by display_order."
  @spec list_categories() :: [Category.t()]
  def list_categories do
    Repo.all(from c in Category, where: c.archived == false, order_by: [asc: :display_order])
  end

  # ---------- Boards ----------

  @doc """
  Create a board in a category (sysop pathway — BOARD-01).
  Starts a Board Server for the new board immediately (D-04).
  """
  @spec create_board(String.t(), map()) :: {:ok, Board.t()} | {:error, Ecto.Changeset.t()}
  def create_board(category_id, attrs) do
    result =
      %Board{category_id: category_id}
      |> Board.changeset(attrs)
      |> Repo.insert()

    case result do
      {:ok, board} ->
        BoardSupervisor.start_board(board.id)
        {:ok, board}

      error ->
        error
    end
  end

  @doc "Get a board by ID. Raises if not found."
  @spec get_board!(String.t()) :: Board.t()
  def get_board!(id), do: Repo.get!(Board, id)

  @doc "Get a board by slug. Raises if not found."
  @spec get_board_by_slug!(String.t()) :: Board.t()
  def get_board_by_slug!(slug), do: Repo.get_by!(Board, slug: slug)

  @doc """
  List all non-archived boards in non-archived categories, ordered by
  category.display_order then board.display_order. Preloads :category.
  """
  @spec list_boards() :: [Board.t()]
  def list_boards do
    Repo.all(
      from b in Board,
        where: b.archived == false,
        join: c in assoc(b, :category),
        where: c.archived == false,
        order_by: [asc: c.display_order, asc: b.display_order],
        preload: [:category]
    )
  end

  # ---------- Subscriptions (BOARD-07) ----------

  @doc """
  Subscribe user to all boards with default_subscription: true.
  Called from Foglet.Accounts.create_user/1 after successful user insert (D-06).
  Idempotent — duplicate subscriptions are silently ignored via on_conflict: :nothing.
  """
  @spec subscribe_to_defaults(String.t()) :: :ok
  def subscribe_to_defaults(user_id) do
    default_board_ids =
      Repo.all(from b in Board, where: b.default_subscription == true, select: b.id)

    Enum.each(default_board_ids, fn board_id ->
      %Subscription{user_id: user_id, board_id: board_id}
      |> Subscription.changeset(%{subscribed_at: DateTime.utc_now()})
      |> Repo.insert(on_conflict: :nothing, conflict_target: [:user_id, :board_id])
    end)

    :ok
  end

  @doc "Subscribe a user to a specific board. Idempotent."
  @spec subscribe(String.t(), String.t()) ::
          {:ok, Subscription.t()} | {:error, Ecto.Changeset.t()}
  def subscribe(user_id, board_id) do
    %Subscription{user_id: user_id, board_id: board_id}
    |> Subscription.changeset(%{subscribed_at: DateTime.utc_now()})
    |> Repo.insert(on_conflict: :nothing, conflict_target: [:user_id, :board_id])
  end

  @doc "List all subscriptions for a user. Preloads :board."
  @spec list_subscriptions(String.t()) :: [Subscription.t()]
  def list_subscriptions(user_id) do
    Repo.all(
      from s in Subscription,
        where: s.user_id == ^user_id,
        preload: [:board]
    )
  end

  # ---------- Read Pointers (BOARD-08) ----------

  @doc """
  Advance (or create) a board read pointer.
  Upserts on (user_id, board_id) — safe to call multiple times.
  """
  @spec advance_board_read_pointer(String.t(), String.t(), integer()) ::
          {:ok, ReadPointer.t()} | {:error, Ecto.Changeset.t()}
  def advance_board_read_pointer(user_id, board_id, message_number) do
    now = DateTime.utc_now()

    %ReadPointer{user_id: user_id, board_id: board_id}
    |> ReadPointer.changeset(%{
      last_read_message_number: message_number,
      last_read_at: now
    })
    |> Repo.insert(
      on_conflict: [set: [last_read_message_number: message_number, last_read_at: now]],
      conflict_target: [:user_id, :board_id]
    )
  end

  @doc "Get the board read pointer for a user and board. Returns nil if not found."
  @spec get_board_read_pointer(String.t(), String.t()) :: ReadPointer.t() | nil
  def get_board_read_pointer(user_id, board_id) do
    Repo.get_by(ReadPointer, user_id: user_id, board_id: board_id)
  end

  # ---------- Unread Counts (BOARD-10) ----------

  @doc """
  Count unread posts for a user in a single board.
  Returns integer count of non-deleted posts with message_number > last_read_message_number.
  """
  @spec unread_count(String.t(), String.t()) :: non_neg_integer()
  def unread_count(user_id, board_id) do
    last_read =
      case Repo.get_by(ReadPointer, user_id: user_id, board_id: board_id) do
        nil -> 0
        ptr -> ptr.last_read_message_number
      end

    Repo.aggregate(
      from(p in Foglet.Posts.Post,
        where:
          p.board_id == ^board_id and
            p.message_number > ^last_read and
            is_nil(p.deleted_at)
      ),
      :count,
      :id
    )
  end

  @doc """
  Batch unread counts for all boards a user is subscribed to.
  Returns a map of %{board_id => count}.
  """
  @spec unread_counts(String.t()) :: %{String.t() => non_neg_integer()}
  def unread_counts(user_id) do
    Repo.all(
      from s in Subscription,
        where: s.user_id == ^user_id,
        left_join: rp in ReadPointer,
        on: rp.user_id == s.user_id and rp.board_id == s.board_id,
        left_join: p in Foglet.Posts.Post,
        on:
          p.board_id == s.board_id and
            p.message_number > coalesce(rp.last_read_message_number, 0) and
            is_nil(p.deleted_at),
        group_by: s.board_id,
        select: {s.board_id, count(p.id)}
    )
    |> Map.new()
  end
end
