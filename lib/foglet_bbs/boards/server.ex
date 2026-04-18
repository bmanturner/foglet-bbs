defmodule Foglet.Boards.Server do
  @moduledoc """
  Per-board GenServer that serializes message-number allocation.

  One Server process per active board. Registered via `Foglet.BoardRegistry`
  so callers can look up the server by board_id without knowing the PID.

  ## Message number allocation

  Each Board Server holds the next available message number in its state.
  When a post is inserted (thread creation or reply), the Server:

    1. Runs an `Ecto.Multi` that atomically:
       - Increments `boards.next_message_number` (persisted source of truth)
       - Inserts the post with the allocated number
       - Bumps thread counters (post_count, last_post_at)
       - Increments user.post_count
    2. On success: advances the in-memory counter and replies `{:ok, post}`
    3. On failure: leaves counter unchanged and replies `{:error, reason}`

  ## Crash recovery (D-05)

  On init, the Server queries `MAX(message_number)` from the posts table
  and resumes from `MAX + 1`. This makes the Server self-healing even if
  the persisted `boards.next_message_number` column is out of sync after
  a mid-flight crash.
  """

  use GenServer

  import Ecto.Query, warn: false

  alias Ecto.Multi
  alias Foglet.Accounts.User
  alias Foglet.Boards.Board
  alias Foglet.Posts.Post
  alias Foglet.Threads.Thread
  alias FogletBbs.Repo

  # ---------- Public API ----------

  @doc "Start a Board Server for the given board_id. Registers via Foglet.BoardRegistry."
  def start_link(opts) do
    board_id = Keyword.fetch!(opts, :board_id)
    GenServer.start_link(__MODULE__, board_id, name: via_tuple(board_id))
  end

  @doc "Allocate a message number and insert a post. Called from Foglet.Posts context."
  @spec create_post(String.t(), String.t(), String.t(), map()) ::
          {:ok, Post.t()} | {:error, any()}
  def create_post(board_id, thread_id, user_id, attrs) do
    GenServer.call(via_tuple(board_id), {:create_post, thread_id, user_id, attrs})
  end

  @doc """
  Create a thread: inserts thread (first_post_id: nil), root post, then updates
  thread with first_post_id. All in one Ecto.Multi.
  """
  @spec create_thread(String.t(), String.t(), map()) ::
          {:ok, %{thread: Thread.t(), post: Post.t()}} | {:error, any()}
  def create_thread(board_id, user_id, attrs) do
    GenServer.call(via_tuple(board_id), {:create_thread, user_id, attrs})
  end

  # ---------- GenServer callbacks ----------

  @impl true
  def init(board_id) do
    # D-05: load current max message_number from DB on (re)start for safety
    current_max =
      Repo.one(
        from p in Post,
          where: p.board_id == ^board_id,
          select: coalesce(max(p.message_number), 0)
      ) || 0

    {:ok, %{board_id: board_id, next_number: current_max + 1}}
  end

  @impl true
  def handle_call({:create_post, thread_id, user_id, attrs}, _from, state) do
    %{board_id: board_id, next_number: n} = state

    result = run_post_insert_multi(board_id, thread_id, user_id, attrs, n)

    case result do
      {:ok, %{post: post}} ->
        {:reply, {:ok, post}, %{state | next_number: n + 1}}

      {:error, _op, reason, _changes} ->
        # Counter NOT advanced — next attempt reuses the same number
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:create_thread, user_id, attrs}, _from, state) do
    %{board_id: board_id, next_number: n} = state

    result = run_thread_create_multi(board_id, user_id, attrs, n)

    case result do
      {:ok, %{thread_update: thread, post: post}} ->
        {:reply, {:ok, %{thread: thread, post: post}}, %{state | next_number: n + 1}}

      {:error, _op, reason, _changes} ->
        {:reply, {:error, reason}, state}
    end
  end

  # ---------- Private helpers ----------

  defp via_tuple(board_id) do
    {:via, Registry, {Foglet.BoardRegistry, board_id}}
  end

  defp run_post_insert_multi(board_id, thread_id, user_id, attrs, message_number) do
    Multi.new()
    |> Multi.run(:bump_board_counter, fn repo, _ ->
      {1, _} =
        repo.update_all(
          from(b in Board, where: b.id == ^board_id),
          inc: [next_message_number: 1]
        )

      {:ok, message_number}
    end)
    |> Multi.insert(:post, fn _ ->
      %Post{
        message_number: message_number,
        board_id: board_id,
        thread_id: thread_id,
        user_id: user_id
      }
      |> Post.creation_changeset(attrs)
    end)
    |> Multi.run(:bump_thread_counters, fn repo, %{post: _post} ->
      thread = repo.get!(Thread, thread_id)

      case thread |> Thread.bump_counters() |> repo.update() do
        {:ok, updated} -> {:ok, updated}
        error -> error
      end
    end)
    |> Multi.run(:bump_user_post_count, fn repo, _ ->
      {1, _} =
        repo.update_all(
          from(u in User, where: u.id == ^user_id),
          inc: [post_count: 1]
        )

      {:ok, :bumped}
    end)
    |> Repo.transaction()
  end

  defp run_thread_create_multi(board_id, user_id, attrs, message_number) do
    title = Map.get(attrs, :title, Map.get(attrs, "title", ""))
    body = Map.get(attrs, :body, Map.get(attrs, "body", ""))

    Multi.new()
    |> Multi.run(:bump_board_counter, fn repo, _ ->
      {1, _} =
        repo.update_all(
          from(b in Board, where: b.id == ^board_id),
          inc: [next_message_number: 1]
        )

      {:ok, message_number}
    end)
    |> Multi.insert(:thread, fn _ ->
      %Thread{board_id: board_id, created_by_id: user_id}
      |> Thread.creation_changeset(%{title: title})
    end)
    |> Multi.insert(:post, fn %{thread: thread} ->
      %Post{
        message_number: message_number,
        board_id: board_id,
        thread_id: thread.id,
        user_id: user_id
      }
      |> Post.creation_changeset(%{body: body})
    end)
    |> Multi.update(:thread_update, fn %{thread: thread, post: post} ->
      Thread.set_first_post(thread, post.id)
    end)
    |> Multi.run(:bump_user_post_count, fn repo, _ ->
      {1, _} =
        repo.update_all(
          from(u in User, where: u.id == ^user_id),
          inc: [post_count: 1]
        )

      {:ok, :bumped}
    end)
    |> Repo.transaction()
  end
end
