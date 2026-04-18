defmodule Foglet.BoardsTest do
  use FogletBbs.DataCase, async: false
  import FogletBbs.BoardsFixtures

  import Ecto.Query, warn: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Foglet.Boards.{ReadPointer, Subscription}
  alias FogletBbs.Repo

  # Board Server is started by Foglet.Boards.create_board/2 via BoardSupervisor.
  # Look up the PID from the Registry and allow sandbox access.
  defp allow_board_server!(board_id) do
    [{pid, _}] = Registry.lookup(Foglet.BoardRegistry, board_id)
    Sandbox.allow(Repo, self(), pid)
    pid
  end

  describe "create_category/1 (BOARD-01)" do
    test "creates a category with valid attrs" do
      assert {:ok, category} = Foglet.Boards.create_category(%{name: "Tech", display_order: 1})
      assert category.name == "Tech"
      assert category.display_order == 1
      assert category.archived == false
    end

    test "rejects category with blank name" do
      assert {:error, changeset} = Foglet.Boards.create_category(%{name: ""})
      assert "can't be blank" in errors_on(changeset).name
    end
  end

  describe "create_board/2 (BOARD-01)" do
    test "creates a board in a category" do
      category = category_fixture()
      assert {:ok, board} = Foglet.Boards.create_board(category.id, %{slug: "tech", name: "Tech"})
      assert board.slug == "tech"
      assert board.category_id == category.id
      assert board.next_message_number == 1
    end

    test "rejects board with duplicate slug" do
      category = category_fixture()
      {:ok, _} = Foglet.Boards.create_board(category.id, %{slug: "dup", name: "First"})

      assert {:error, changeset} =
               Foglet.Boards.create_board(category.id, %{slug: "dup", name: "Second"})

      assert "has already been taken" in errors_on(changeset).slug
    end

    test "rejects board with invalid slug format (uppercase)" do
      category = category_fixture()

      assert {:error, changeset} =
               Foglet.Boards.create_board(category.id, %{slug: "Tech-Board", name: "Tech"})

      assert errors_on(changeset).slug != []
    end
  end

  describe "subscribe_to_defaults/1 (BOARD-07)" do
    test "inserts subscription rows for all boards with default_subscription: true" do
      category = category_fixture()

      {:ok, default_board} =
        Foglet.Boards.create_board(category.id, %{
          slug: "default-board",
          name: "Default",
          default_subscription: true
        })

      {:ok, _non_default} =
        Foglet.Boards.create_board(category.id, %{
          slug: "non-default-board",
          name: "Non-default",
          default_subscription: false
        })

      user = user_fixture()

      # register_user calls subscribe_to_defaults — verify subscription exists
      subs = Repo.all(from s in Subscription, where: s.user_id == ^user.id)
      board_ids = Enum.map(subs, & &1.board_id)
      assert default_board.id in board_ids
    end

    test "is idempotent — calling twice does not create duplicates" do
      category = category_fixture()

      {:ok, board} =
        Foglet.Boards.create_board(category.id, %{
          slug: "idem-board",
          name: "Idem",
          default_subscription: true
        })

      user = user_fixture()

      # Call directly a second time
      assert :ok = Foglet.Boards.subscribe_to_defaults(user.id)

      count =
        Repo.aggregate(
          from(s in Subscription,
            where: s.user_id == ^user.id and s.board_id == ^board.id
          ),
          :count,
          :id
        )

      assert count == 1
    end
  end

  describe "advance_board_read_pointer/3 (BOARD-08)" do
    test "inserts a read pointer on first call" do
      category = category_fixture()
      board = board_fixture(category)
      user = user_fixture()

      assert {:ok, ptr} = Foglet.Boards.advance_board_read_pointer(user.id, board.id, 5)
      assert ptr.last_read_message_number == 5
    end

    test "updates existing pointer on subsequent call (upsert)" do
      category = category_fixture()
      board = board_fixture(category)
      user = user_fixture()

      {:ok, _} = Foglet.Boards.advance_board_read_pointer(user.id, board.id, 3)
      {:ok, updated} = Foglet.Boards.advance_board_read_pointer(user.id, board.id, 7)

      assert updated.last_read_message_number == 7

      # Only one row in DB
      count =
        Repo.aggregate(
          from(p in ReadPointer, where: p.user_id == ^user.id and p.board_id == ^board.id),
          :count,
          :id
        )

      assert count == 1
    end
  end

  describe "unread_counts/1 (BOARD-10)" do
    test "returns map of board_id => unread post count" do
      category = category_fixture()

      board =
        board_fixture(category, %{
          slug: "unread-board-#{System.unique_integer([:positive])}",
          default_subscription: true
        })

      user = user_fixture()

      # No posts yet — unread count is 0
      counts = Foglet.Boards.unread_counts(user.id)
      assert Map.get(counts, board.id, 0) == 0
    end

    test "unread count reflects posts beyond last read message number" do
      category = category_fixture()
      board = board_fixture(category)
      user = user_fixture()
      poster = user_fixture()

      # Board Server already started by create_board — allow sandbox access
      allow_board_server!(board.id)

      Foglet.Boards.subscribe(user.id, board.id)

      {:ok, %{post: p1}} =
        Foglet.Threads.create_thread(board.id, poster.id, %{title: "T1", body: "b"})

      {:ok, _p2} = Foglet.Posts.create_reply(p1.thread_id, board.id, poster.id, %{body: "reply"})

      {:ok, _p3} =
        Foglet.Posts.create_reply(p1.thread_id, board.id, poster.id, %{body: "reply 2"})

      # User has read up to p1 (message_number 1)
      Foglet.Boards.advance_board_read_pointer(user.id, board.id, p1.message_number)

      counts = Foglet.Boards.unread_counts(user.id)
      # p2 and p3 are unread
      assert Map.get(counts, board.id) == 2
    end

    test "soft-deleted posts are not counted as unread" do
      category = category_fixture()
      board = board_fixture(category)
      user = user_fixture()
      poster = user_fixture()

      allow_board_server!(board.id)
      Foglet.Boards.subscribe(user.id, board.id)

      {:ok, %{post: p1}} =
        Foglet.Threads.create_thread(board.id, poster.id, %{title: "T1", body: "b"})

      {:ok, p2} =
        Foglet.Posts.create_reply(p1.thread_id, board.id, poster.id, %{
          body: "will be deleted"
        })

      # Soft-delete p2
      {:ok, _} = Foglet.Posts.delete_post(p2)

      counts = Foglet.Boards.unread_counts(user.id)
      # Only p1 is unread (p2 is deleted)
      assert Map.get(counts, board.id) == 1
    end
  end
end
