defmodule Foglet.Boards do
  @moduledoc """
  Context for categories, boards, subscriptions, and read pointers.

  Public API consumed by:
    * Phase 2: Foglet.Boards.Server (via internal calls)
    * Phase 2: FogletBbs.Application.start/2 (boot_board_servers/0)
    * Phase 2: Foglet.Accounts.create_user/1 (subscribe_to_defaults/1 — D-06)
    * Phase 3: SSH/TUI (list_boards, subscribe, read pointer management)
  """

  require Logger

  import Ecto.Query, warn: false

  alias Foglet.Boards.{Board, Category, ReadPointer, Subscription}
  alias Foglet.Boards.Supervisor, as: BoardSupervisor
  alias FogletBbs.Repo

  # ---------- Authorization scope helper (D-08) ----------

  @doc """
  Returns the authorization scope for a board — the board itself.
  Consumed by callers that invoke `Bodyguard.permit(Foglet.Authorization, action, actor, Foglet.Boards.scope_for(board))`.
  """
  @spec scope_for(Board.t()) :: {:board, Ecto.UUID.t()}
  def scope_for(%Board{id: id}), do: {:board, id}

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

  @doc """
  Create a category. Actor must be authorized for `:create_category` at `:site` scope.
  Returns `{:error, :forbidden}` if the actor is not permitted (D-15, SYSO-03).

  This actor-first arity-2 form is additive to `create_category/1` (D-10), which
  remains for seeds and internal trusted callers.
  """
  @spec create_category(Foglet.Accounts.User.t() | nil, map()) ::
          {:ok, Category.t()} | {:error, Ecto.Changeset.t()} | {:error, :forbidden}
  def create_category(actor, attrs) do
    with :ok <- Bodyguard.permit(Foglet.Authorization, :create_category, actor, :site) do
      %Category{}
      |> Category.changeset(attrs)
      |> Repo.insert()
    end
  end

  @doc """
  Update a category's attributes. Actor must be authorized for `:update_category` at `:site` scope.
  Returns `{:error, :forbidden}` if the actor is not permitted (SYSO-03).
  """
  @spec update_category(Foglet.Accounts.User.t() | nil, Category.t(), map()) ::
          {:ok, Category.t()} | {:error, Ecto.Changeset.t()} | {:error, :forbidden}
  def update_category(actor, %Category{} = category, attrs) do
    with :ok <- Bodyguard.permit(Foglet.Authorization, :update_category, actor, :site) do
      category
      |> Category.changeset(attrs)
      |> Repo.update()
    end
  end

  @doc """
  Archive a category. Actor must be authorized for `:archive_category` at `:site` scope.
  Flips `archived` to true via `Category.archive_changeset/1` (defensive: only archived is cast).
  Returns `{:error, :forbidden}` if the actor is not permitted (SYSO-03).
  """
  @spec archive_category(Foglet.Accounts.User.t() | nil, Category.t()) ::
          {:ok, Category.t()} | {:error, Ecto.Changeset.t()} | {:error, :forbidden}
  def archive_category(actor, %Category{} = category) do
    with :ok <- Bodyguard.permit(Foglet.Authorization, :archive_category, actor, :site) do
      category
      |> Category.archive_changeset()
      |> Repo.update()
    end
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
  Create a board in a category. Actor must be authorized for `:create_board` at `:site` scope.
  Starts a Board Server for the new board immediately (D-04).

  Returns `{:error, :forbidden}` if the actor is not permitted (D-15).
  """
  @spec create_board(Foglet.Accounts.User.t() | nil, String.t(), map()) ::
          {:ok, Board.t()}
          | {:error, Ecto.Changeset.t()}
          | {:error, :forbidden}
          | {:error, :board_server_unavailable}
  def create_board(actor, category_id, attrs) do
    with :ok <- Bodyguard.permit(Foglet.Authorization, :create_board, actor, :site) do
      result =
        %Board{category_id: category_id}
        |> Board.changeset(attrs)
        |> Repo.insert()

      case result do
        {:ok, board} ->
          case start_board_server(board.id) do
            {:ok, _pid} ->
              {:ok, board}

            {:error, {:already_started, _pid}} ->
              {:ok, board}

            {:error, reason} ->
              Logger.error(
                "Failed to start Board Server for #{board.slug} (#{board.id}): #{inspect(reason)}. " <>
                  "Rolling back the board insert so the caller can retry."
              )

              _ = Repo.delete(board)
              {:error, :board_server_unavailable}
          end

        error ->
          error
      end
    end
  end

  defp start_board_server(board_id) do
    BoardSupervisor.start_board(board_id)
  catch
    :exit, reason -> {:error, reason}
  end

  @doc """
  Update a board's attributes. Actor must be authorized for `:update_board` at `:site` scope.
  Returns `{:error, :forbidden}` if the actor is not permitted.
  """
  @spec update_board(Foglet.Accounts.User.t() | nil, Board.t(), map()) ::
          {:ok, Board.t()} | {:error, Ecto.Changeset.t()} | {:error, :forbidden}
  def update_board(actor, %Board{} = board, attrs) do
    with :ok <- Bodyguard.permit(Foglet.Authorization, :update_board, actor, :site) do
      board
      |> Board.changeset(attrs)
      |> Repo.update()
    end
  end

  @doc """
  Archive a board. Actor must be authorized for `:archive_board` at `:site` scope.
  Flips `archived` to true via `Board.archive_changeset/1` (defensive: only archived is cast).
  Returns `{:error, :forbidden}` if the actor is not permitted.
  """
  @spec archive_board(Foglet.Accounts.User.t() | nil, Board.t()) ::
          {:ok, Board.t()} | {:error, Ecto.Changeset.t()} | {:error, :forbidden}
  def archive_board(actor, %Board{} = board) do
    with :ok <- Bodyguard.permit(Foglet.Authorization, :archive_board, actor, :site) do
      board
      |> Board.archive_changeset()
      |> Repo.update()
    end
  end

  @doc "Get a board by ID. Raises if not found."
  @spec get_board!(String.t()) :: Board.t()
  def get_board!(id), do: Repo.get!(Board, id)

  @doc "Get a board by slug. Raises if not found."
  @spec get_board_by_slug!(String.t()) :: Board.t()
  def get_board_by_slug!(slug), do: Repo.get_by!(Board, slug: slug)

  @doc "Get a board by slug. Returns nil if not found."
  @spec get_board_by_slug(String.t()) :: Board.t() | nil
  def get_board_by_slug(slug) when is_binary(slug), do: Repo.get_by(Board, slug: slug)

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

  @type directory_board :: %{
          board: Board.t(),
          subscribed?: boolean(),
          required_subscription?: boolean(),
          unread_count: non_neg_integer() | nil
        }

  @type directory_category :: %{
          category: Category.t(),
          boards: [directory_board()]
        }

  @doc """
  Return active boards in active categories grouped for the user-facing board directory.

  Subscribed board entries include unread counts; unsubscribed entries keep
  `unread_count` nil so callers do not imply unread state for boards the user
  has not joined.
  """
  @spec board_directory_for(Foglet.Accounts.User.t() | nil) :: [directory_category()]
  def board_directory_for(nil), do: []

  def board_directory_for(actor) do
    user_id = user_id(actor)
    subscribed_board_ids = subscribed_board_ids(user_id)
    unread_counts = unread_counts(user_id)

    list_boards()
    |> Enum.chunk_by(& &1.category.id)
    |> Enum.map(fn boards ->
      category = hd(boards).category

      %{
        category: category,
        boards:
          Enum.map(boards, fn board ->
            subscribed? = MapSet.member?(subscribed_board_ids, board.id)

            %{
              board: board,
              subscribed?: subscribed?,
              required_subscription?: board.required_subscription,
              unread_count: if(subscribed?, do: Map.get(unread_counts, board.id, 0), else: nil)
            }
          end)
      }
    end)
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
      result =
        %Subscription{user_id: user_id, board_id: board_id}
        |> Subscription.changeset(%{subscribed_at: DateTime.utc_now()})
        |> Repo.insert(on_conflict: :nothing, conflict_target: [:user_id, :board_id])

      case result do
        {:ok, _} ->
          :ok

        {:error, cs} ->
          Logger.error(
            "subscribe_to_defaults: failed to subscribe #{user_id} to #{board_id}: #{inspect(cs.errors)}"
          )
      end
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

  @doc """
  Subscribe a user to an active board through the context rule boundary.

  Accepts a user struct or user id string. Archived boards and boards in
  archived categories are rejected before attempting the insert.
  """
  @spec subscribe_user_to_board(Foglet.Accounts.User.t() | String.t(), String.t()) ::
          {:ok, :subscribed}
          | {:error, :not_found}
          | {:error, :board_archived}
          | {:error, Ecto.Changeset.t()}
  def subscribe_user_to_board(actor, board_id) do
    with {:ok, _board} <- fetch_active_board(board_id),
         {:ok, _subscription} <- subscribe(user_id(actor), board_id) do
      {:ok, :subscribed}
    end
  end

  @doc """
  Unsubscribe a user from an active board unless the board requires subscription.

  Missing subscription rows are treated as an idempotent successful unsubscribe;
  users are allowed to end with zero board subscriptions.
  """
  @spec unsubscribe_user_from_board(Foglet.Accounts.User.t() | String.t(), String.t()) ::
          {:ok, :unsubscribed}
          | {:error, :not_found}
          | {:error, :board_archived}
          | {:error, :required_subscription}
  def unsubscribe_user_from_board(actor, board_id) do
    with {:ok, board} <- fetch_active_board(board_id),
         :ok <- reject_required_subscription(board) do
      Repo.delete_all(
        from s in Subscription,
          where: s.user_id == ^user_id(actor) and s.board_id == ^board_id
      )

      {:ok, :unsubscribed}
    end
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

  @doc """
  List Board structs for every board a user is subscribed to, with :category
  preloaded and :unread_count populated. Ordered by category.display_order
  then board.display_order. Returns [] for a nil user (guest).
  """
  @spec list_subscribed_boards(Foglet.Accounts.User.t() | nil) :: [Board.t()]
  def list_subscribed_boards(nil), do: []

  def list_subscribed_boards(%{id: user_id}) do
    boards =
      Repo.all(
        from b in Board,
          join: s in Subscription,
          on: s.board_id == b.id and s.user_id == ^user_id,
          join: c in assoc(b, :category),
          where: b.archived == false and c.archived == false,
          order_by: [asc: c.display_order, asc: b.display_order],
          preload: [category: c]
      )

    counts = unread_counts(user_id)
    Enum.map(boards, fn b -> %{b | unread_count: Map.get(counts, b.id, 0)} end)
  end

  defp user_id(%{id: id}), do: id
  defp user_id(id) when is_binary(id), do: id

  defp subscribed_board_ids(user_id) do
    Repo.all(from s in Subscription, where: s.user_id == ^user_id, select: s.board_id)
    |> MapSet.new()
  end

  defp fetch_active_board(board_id) do
    case Repo.get(Board, board_id) |> Repo.preload(:category) do
      nil -> {:error, :not_found}
      %Board{archived: true} -> {:error, :board_archived}
      %Board{category: %Category{archived: true}} -> {:error, :board_archived}
      %Board{} = board -> {:ok, board}
    end
  end

  defp reject_required_subscription(%Board{required_subscription: true}) do
    {:error, :required_subscription}
  end

  defp reject_required_subscription(%Board{}), do: :ok

  # ---------- Read Pointers (BOARD-08) ----------

  @doc """
  Advance (or create) a board read pointer (LIST-01 monotonic).

  The `last_read_message_number` only ever increases — the on_conflict
  upsert uses a `GREATEST(existing, incoming)` fragment so that reading
  an older thread after a newer one does NOT regress the pointer.
  `last_read_at` is updated to `now` unconditionally because it
  represents "most recent activity", not the pointer's identity.

  Safe to call multiple times with the same or lower message_number —
  the pointer stays at the max value seen so far.
  """
  @spec advance_board_read_pointer(String.t(), String.t(), integer()) ::
          {:ok, ReadPointer.t()} | {:error, Ecto.Changeset.t()}
  def advance_board_read_pointer(user_id, board_id, message_number)
      when is_integer(message_number) and message_number >= 0 do
    now = DateTime.utc_now()

    on_conflict_query =
      from(rp in ReadPointer,
        update: [
          set: [
            last_read_message_number:
              fragment(
                "GREATEST(?, ?)",
                rp.last_read_message_number,
                ^message_number
              ),
            last_read_at: ^now
          ]
        ]
      )

    %ReadPointer{user_id: user_id, board_id: board_id}
    |> ReadPointer.changeset(%{
      last_read_message_number: message_number,
      last_read_at: now
    })
    |> Repo.insert(
      on_conflict: on_conflict_query,
      conflict_target: [:user_id, :board_id],
      returning: true
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
