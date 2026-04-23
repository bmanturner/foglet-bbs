defmodule Foglet.BoardsTest do
  use FogletBbs.DataCase, async: false
  import FogletBbs.BoardsFixtures

  import Ecto.Query, warn: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Foglet.Accounts.User
  alias Foglet.Boards.{ReadPointer, Subscription}
  alias FogletBbs.Repo

  # Board Server is started by Foglet.Boards.create_board/3 via BoardSupervisor.
  # Look up the PID from the Registry and allow sandbox access.
  defp allow_board_server!(board_id) do
    [{pid, _}] = Registry.lookup(Foglet.BoardRegistry, board_id)
    Sandbox.allow(Repo, self(), pid)
    pid
  end

  # Plain-struct actors (not inserted; policy only matches on role/status/deleted_at).
  defp sysop_actor, do: %User{role: :sysop, status: :active, deleted_at: nil}
  defp mod_actor, do: %User{role: :mod, status: :active, deleted_at: nil}

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

  describe "Board.archive_changeset/1 (Task 1)" do
    test "returns a changeset that sets archived: true" do
      category = category_fixture()
      board = board_fixture(category)

      cs = Foglet.Boards.Board.archive_changeset(board)
      assert cs.valid?
      assert Ecto.Changeset.get_change(cs, :archived) == true
    end

    test "does not allow other fields to be mutated through archive_changeset" do
      category = category_fixture()
      board = board_fixture(category)

      # archive_changeset ignores all attrs beyond archived
      cs = Foglet.Boards.Board.archive_changeset(board)
      assert is_nil(Ecto.Changeset.get_change(cs, :name))
      assert is_nil(Ecto.Changeset.get_change(cs, :slug))
    end
  end

  describe "Boards.scope_for/1 (Task 1)" do
    test "returns {:board, id} for a board struct" do
      category = category_fixture()
      board = board_fixture(category)

      assert Foglet.Boards.scope_for(board) == {:board, board.id}
    end
  end

  describe "create_board/3 (BOARD-01)" do
    test "creates a board in a category" do
      category = category_fixture()

      assert {:ok, board} =
               Foglet.Boards.create_board(sysop_actor(), category.id, %{
                 slug: "tech",
                 name: "Tech"
               })

      assert board.slug == "tech"
      assert board.category_id == category.id
      assert board.next_message_number == 1
    end

    test "rejects board with duplicate slug" do
      category = category_fixture()

      {:ok, _} =
        Foglet.Boards.create_board(sysop_actor(), category.id, %{slug: "dup", name: "First"})

      assert {:error, changeset} =
               Foglet.Boards.create_board(sysop_actor(), category.id, %{
                 slug: "dup",
                 name: "Second"
               })

      assert "has already been taken" in errors_on(changeset).slug
    end

    test "rejects board with invalid slug format (uppercase)" do
      category = category_fixture()

      assert {:error, changeset} =
               Foglet.Boards.create_board(sysop_actor(), category.id, %{
                 slug: "Tech-Board",
                 name: "Tech"
               })

      assert errors_on(changeset).slug != []
    end
  end

  describe "create_board/3 authorization (D-27)" do
    test "returns {:error, :forbidden} for a regular user" do
      category = category_fixture()
      user = user_fixture()

      assert {:error, :forbidden} =
               Foglet.Boards.create_board(user, category.id, %{slug: "test", name: "Test"})

      assert Repo.aggregate(Foglet.Boards.Board, :count) == 0
    end

    test "returns {:error, :forbidden} for nil actor (guest)" do
      category = category_fixture()

      assert {:error, :forbidden} =
               Foglet.Boards.create_board(nil, category.id, %{slug: "test", name: "Test"})

      assert Repo.aggregate(Foglet.Boards.Board, :count) == 0
    end

    test "returns {:error, :forbidden} for a mod (sysop-only action)" do
      category = category_fixture()

      assert {:error, :forbidden} =
               Foglet.Boards.create_board(mod_actor(), category.id, %{slug: "test", name: "Test"})

      assert Repo.aggregate(Foglet.Boards.Board, :count) == 0
    end
  end

  describe "update_board/3" do
    test "sysop can update a board's name" do
      category = category_fixture()
      board = board_fixture(category)

      assert {:ok, updated} = Foglet.Boards.update_board(sysop_actor(), board, %{name: "Renamed"})
      assert updated.name == "Renamed"
      assert updated.id == board.id
    end

    test "returns {:error, :forbidden} for a regular user" do
      category = category_fixture()
      board = board_fixture(category)
      user = user_fixture()

      assert {:error, :forbidden} =
               Foglet.Boards.update_board(user, board, %{name: "Renamed"})

      reloaded = Repo.get!(Foglet.Boards.Board, board.id)
      assert reloaded.name == board.name
    end

    test "returns {:error, :forbidden} for a mod" do
      category = category_fixture()
      board = board_fixture(category)

      assert {:error, :forbidden} =
               Foglet.Boards.update_board(mod_actor(), board, %{name: "Renamed"})
    end

    test "does not mutate the board row when forbidden" do
      category = category_fixture()
      board = board_fixture(category)
      user = user_fixture()

      assert {:error, :forbidden} =
               Foglet.Boards.update_board(user, board, %{name: "Renamed"})

      reloaded = Repo.get!(Foglet.Boards.Board, board.id)
      assert reloaded.name == board.name
    end
  end

  describe "archive_board/2" do
    test "sysop archives a board — archived becomes true" do
      category = category_fixture()
      board = board_fixture(category)

      assert {:ok, archived} = Foglet.Boards.archive_board(sysop_actor(), board)
      assert archived.archived == true
    end

    test "returns {:error, :forbidden} for a regular user" do
      category = category_fixture()
      board = board_fixture(category)
      user = user_fixture()

      assert {:error, :forbidden} = Foglet.Boards.archive_board(user, board)

      reloaded = Repo.get!(Foglet.Boards.Board, board.id)
      assert reloaded.archived == false
    end

    test "returns {:error, :forbidden} for a mod" do
      category = category_fixture()
      board = board_fixture(category)

      assert {:error, :forbidden} = Foglet.Boards.archive_board(mod_actor(), board)
    end

    test "does not flip archived when forbidden" do
      category = category_fixture()
      board = board_fixture(category)
      user = user_fixture()

      assert {:error, :forbidden} = Foglet.Boards.archive_board(user, board)

      reloaded = Repo.get!(Foglet.Boards.Board, board.id)
      assert reloaded.archived == false
    end
  end

  describe "subscribe_to_defaults/1 (BOARD-07)" do
    test "inserts subscription rows for all boards with default_subscription: true" do
      category = category_fixture()

      {:ok, default_board} =
        Foglet.Boards.create_board(sysop_actor(), category.id, %{
          slug: "default-board",
          name: "Default",
          default_subscription: true
        })

      {:ok, _non_default} =
        Foglet.Boards.create_board(sysop_actor(), category.id, %{
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
        Foglet.Boards.create_board(sysop_actor(), category.id, %{
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

    test "does NOT regress when advanced with a lower message_number (LIST-01)" do
      category = category_fixture()
      board = board_fixture(category)
      user = user_fixture()

      # Advance to 7 first
      {:ok, first} = Foglet.Boards.advance_board_read_pointer(user.id, board.id, 7)
      assert first.last_read_message_number == 7

      # Advance to 3 (lower) — must NOT regress the pointer
      {:ok, second} = Foglet.Boards.advance_board_read_pointer(user.id, board.id, 3)

      assert second.last_read_message_number == 7,
             "Expected pointer to remain at 7 after advancing with 3, got #{second.last_read_message_number}"

      # Reload from DB to confirm the stored row is also 7
      reloaded = Foglet.Boards.get_board_read_pointer(user.id, board.id)
      assert reloaded.last_read_message_number == 7
    end

    test "stays at max across a mixed advance sequence (LIST-01 monotonicity)" do
      category = category_fixture()
      board = board_fixture(category)
      user = user_fixture()

      # Advance sequence: 2, 5, 1, 4, 7, 3 — max is 7
      Enum.each([2, 5, 1, 4, 7, 3], fn n ->
        assert {:ok, _} = Foglet.Boards.advance_board_read_pointer(user.id, board.id, n)
      end)

      reloaded = Foglet.Boards.get_board_read_pointer(user.id, board.id)
      assert reloaded.last_read_message_number == 7
    end

    test "advancing with same message_number is a no-op (still returns :ok)" do
      category = category_fixture()
      board = board_fixture(category)
      user = user_fixture()

      {:ok, _} = Foglet.Boards.advance_board_read_pointer(user.id, board.id, 5)
      assert {:ok, same} = Foglet.Boards.advance_board_read_pointer(user.id, board.id, 5)
      assert same.last_read_message_number == 5
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
