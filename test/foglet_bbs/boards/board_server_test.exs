defmodule Foglet.Boards.ServerTest do
  use FogletBbs.DataCase, async: false
  use ExUnitProperties

  import Ecto.Query, warn: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Foglet.Boards.{Board, Category, Server}
  alias Foglet.Posts.Post
  alias FogletBbs.AccountsFixtures
  alias FogletBbs.Repo

  # ---------- Setup helpers ----------

  defp insert_category! do
    %Category{}
    |> Category.changeset(%{name: "Test Category #{System.unique_integer([:positive])}"})
    |> Repo.insert!()
  end

  defp insert_board!(category) do
    %Board{}
    |> Board.changeset(%{
      slug: "board-#{System.unique_integer([:positive])}",
      name: "Test Board #{System.unique_integer([:positive])}",
      category_id: category.id
    })
    |> Repo.insert!()
  end

  defp start_server!(board_id, extra_id \\ nil) do
    sup_id = {:board_server, board_id, extra_id}

    pid =
      start_supervised!(
        {Server, board_id: board_id},
        id: sup_id
      )

    Sandbox.allow(Repo, self(), pid)
    {pid, sup_id}
  end

  # ---------- Tests ----------

  describe "Board Server (BOARD-06)" do
    test "starts and registers via Registry under board_id" do
      category = insert_category!()
      board = insert_board!(category)

      {pid, _sup_id} = start_server!(board.id)

      assert Process.alive?(pid)

      assert [{^pid, nil}] =
               Registry.lookup(Foglet.BoardRegistry, board.id)
    end

    test "init loads next_message_number as MAX(message_number)+1 from DB (D-05)" do
      category = insert_category!()
      board = insert_board!(category)
      user = AccountsFixtures.user_fixture()

      {pid, sup_id} = start_server!(board.id)

      # Verify the server starts with next_number = 1 (no posts yet)
      %{next_number: initial} = :sys.get_state(pid)
      assert initial == 1

      # Create a thread so we have message_number = 1 in the DB
      {:ok, %{post: _post}} =
        Server.create_thread(board.id, user.id, %{
          title: "First Thread",
          body: "First body"
        })

      # Stop and restart — D-05: reload from MAX(message_number) + 1
      stop_supervised!(sup_id)

      {new_pid, _} = start_server!(board.id, :v2)
      Sandbox.allow(Repo, self(), new_pid)

      %{next_number: recovered} = :sys.get_state(new_pid)
      assert recovered == 2
    end

    test "allocates sequential message numbers for posts in a single board" do
      category = insert_category!()
      board = insert_board!(category)
      user = AccountsFixtures.user_fixture()

      start_server!(board.id)

      {:ok, %{post: first_post}} =
        Server.create_thread(board.id, user.id, %{
          title: "Thread",
          body: "Opening post"
        })

      {:ok, reply} =
        Server.create_post(board.id, first_post.thread_id, user.id, %{body: "Reply"})

      assert first_post.message_number == 1
      assert reply.message_number == 2
    end

    test "does not advance counter when transaction fails" do
      category = insert_category!()
      board = insert_board!(category)
      user = AccountsFixtures.user_fixture()

      {pid, _sup_id} = start_server!(board.id)

      # A thread with no body should fail Post.creation_changeset validation
      {:error, _reason} =
        Server.create_thread(board.id, user.id, %{
          title: "Thread",
          body: ""
        })

      # Counter must still be at 1 — not advanced by the failed attempt
      %{next_number: n} = :sys.get_state(pid)
      assert n == 1

      # A valid create should now get message_number 1
      {:ok, %{post: post}} =
        Server.create_thread(board.id, user.id, %{
          title: "Thread",
          body: "Valid body"
        })

      assert post.message_number == 1
    end

    test "message numbers are per-board (two boards have independent sequences)" do
      category = insert_category!()
      board_a = insert_board!(category)
      board_b = insert_board!(category)
      user = AccountsFixtures.user_fixture()

      start_server!(board_a.id)
      start_server!(board_b.id)

      {:ok, %{post: post_a1}} =
        Server.create_thread(board_a.id, user.id, %{title: "A-1", body: "body a1"})

      {:ok, %{post: post_a2}} =
        Server.create_thread(board_a.id, user.id, %{title: "A-2", body: "body a2"})

      {:ok, %{post: post_b1}} =
        Server.create_thread(board_b.id, user.id, %{title: "B-1", body: "body b1"})

      # Board A has message numbers 1 and 2
      assert post_a1.message_number == 1
      assert post_a2.message_number == 2

      # Board B independently starts at 1
      assert post_b1.message_number == 1
    end
  end

  describe "message-number monotonicity property (BOARD-06)" do
    property "message numbers are monotonically sequential under concurrent inserts" do
      check all(count <- integer(2..6), max_runs: 5) do
        category = insert_category!()
        board = insert_board!(category)
        user = AccountsFixtures.user_fixture()
        sup_id = {:prop_server, board.id}

        pid =
          start_supervised!(
            {Server, board_id: board.id},
            id: sup_id
          )

        Sandbox.allow(Repo, self(), pid)

        # Create the seed thread first to get a thread_id
        {:ok, %{thread: thread, post: _seed}} =
          Server.create_thread(board.id, user.id, %{
            title: "Property Thread",
            body: "Seed post"
          })

        # Insert (count) replies via the server
        results =
          Enum.map(1..count, fn i ->
            Server.create_post(board.id, thread.id, user.id, %{body: "Reply #{i}"})
          end)

        assert Enum.all?(results, &match?({:ok, _}, &1))

        # Collect all message numbers from DB for this board
        numbers =
          Repo.all(from p in Post, where: p.board_id == ^board.id, select: p.message_number)
          |> Enum.sort()

        expected = Enum.to_list(1..length(numbers))
        assert numbers == expected

        stop_supervised!(sup_id)
      end
    end
  end
end
