defmodule Foglet.BoardsTest do
  use FogletBbs.DataCase, async: false
  import FogletBbs.BoardsFixtures

  import Ecto.Query, warn: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Foglet.Accounts.User
  alias Foglet.Boards.{Board, Category, ReadPointer, Subscription}
  alias Foglet.Threads.Thread
  alias FogletBbs.Repo

  # Locate a directory entry by board.id rather than destructuring the full
  # directory shape. Survives fixture growth without test churn.
  defp find_board_entry(directory, board_id) do
    directory
    |> Enum.flat_map(& &1.boards)
    |> Enum.find(fn %{board: %{id: id}} -> id == board_id end)
    |> case do
      nil ->
        flunk(
          "no entry found for board_id=#{inspect(board_id)} in directory=#{inspect(directory)}"
        )

      entry ->
        entry
    end
  end

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

  describe "Category.archive_changeset/1 (02-02 Task 1)" do
    test "returns a changeset that sets archived: true" do
      category = category_fixture()

      cs = Category.archive_changeset(category)
      assert cs.valid?
      assert Ecto.Changeset.get_change(cs, :archived) == true
    end

    test "does not allow other fields to be mutated through archive_changeset" do
      category = category_fixture()

      cs = Category.archive_changeset(category)
      assert is_nil(Ecto.Changeset.get_change(cs, :name))
      assert is_nil(Ecto.Changeset.get_change(cs, :display_order))
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

  describe "Board.changeset/2 required subscription policy (SUBS-03)" do
    test "accepts required subscriptions when default subscriptions are enabled" do
      category = category_fixture()

      changeset =
        Board.changeset(%Board{category_id: category.id}, %{
          slug: "required-default",
          name: "Required Default",
          default_subscription: true,
          required_subscription: true
        })

      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :required_subscription) == true
    end

    test "rejects required subscriptions without default subscriptions" do
      category = category_fixture()

      changeset =
        Board.changeset(%Board{category_id: category.id}, %{
          slug: "required-non-default",
          name: "Required Non Default",
          default_subscription: false,
          required_subscription: true
        })

      refute changeset.valid?

      assert "requires default_subscription to be true" in errors_on(changeset).required_subscription
    end

    test "database constraint rejects required subscriptions without default subscriptions" do
      category = category_fixture()

      assert {:error, changeset} =
               %Board{category_id: category.id}
               |> Board.changeset(%{
                 slug: "required-db",
                 name: "Required DB",
                 default_subscription: true,
                 required_subscription: true
               })
               |> Ecto.Changeset.put_change(:default_subscription, false)
               |> Repo.insert()

      assert "requires default_subscription to be true" in errors_on(changeset).required_subscription
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

    test "sysop requiring a board subscribes existing non-deleted users" do
      category = category_fixture()

      board =
        board_fixture(category, %{default_subscription: false, required_subscription: false})

      user = user_fixture()
      other_user = user_fixture()

      assert [] = Foglet.Boards.list_subscriptions(user.id)
      assert [] = Foglet.Boards.list_subscriptions(other_user.id)

      assert {:ok, updated} =
               Foglet.Boards.update_board(sysop_actor(), board, %{
                 default_subscription: true,
                 required_subscription: true
               })

      assert updated.required_subscription == true

      assert [%Subscription{board_id: board_id}] = Foglet.Boards.list_subscriptions(user.id)
      assert board_id == board.id

      assert [%Subscription{board_id: board_id}] = Foglet.Boards.list_subscriptions(other_user.id)
      assert board_id == board.id
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

  describe "create_category/2 (SYSO-03, actor-first)" do
    test "sysop creates category" do
      assert {:ok, %Category{name: "Tech", display_order: 3}} =
               Foglet.Boards.create_category(sysop_actor(), %{name: "Tech", display_order: 3})
    end

    test "mod is forbidden" do
      assert {:error, :forbidden} =
               Foglet.Boards.create_category(mod_actor(), %{name: "Tech"})

      assert Repo.aggregate(Category, :count) == 0
    end

    test "nil actor is forbidden" do
      assert {:error, :forbidden} = Foglet.Boards.create_category(nil, %{name: "Tech"})
      assert Repo.aggregate(Category, :count) == 0
    end

    test "regular user is forbidden" do
      user = user_fixture()

      assert {:error, :forbidden} = Foglet.Boards.create_category(user, %{name: "Tech"})
      assert Repo.aggregate(Category, :count) == 0
    end

    test "invalid attrs return changeset error" do
      assert {:error, %Ecto.Changeset{valid?: false}} =
               Foglet.Boards.create_category(sysop_actor(), %{})
    end
  end

  describe "update_category/3 (SYSO-03)" do
    test "sysop updates category" do
      category = category_fixture()

      assert {:ok, %Category{name: "Renamed"} = updated} =
               Foglet.Boards.update_category(sysop_actor(), category, %{name: "Renamed"})

      assert updated.id == category.id
    end

    test "mod is forbidden" do
      category = category_fixture()
      original_name = category.name

      assert {:error, :forbidden} =
               Foglet.Boards.update_category(mod_actor(), category, %{name: "X"})

      assert Repo.get!(Category, category.id).name == original_name
    end

    test "regular user is forbidden" do
      category = category_fixture()
      user = user_fixture()

      assert {:error, :forbidden} =
               Foglet.Boards.update_category(user, category, %{name: "X"})
    end

    test "invalid attrs return changeset error" do
      category = category_fixture()

      assert {:error, %Ecto.Changeset{valid?: false}} =
               Foglet.Boards.update_category(sysop_actor(), category, %{name: ""})
    end
  end

  describe "archive_category/2 (SYSO-03)" do
    test "sysop archives category — archived becomes true" do
      category = category_fixture()

      assert {:ok, %Category{archived: true}} =
               Foglet.Boards.archive_category(sysop_actor(), category)
    end

    test "mod is forbidden" do
      category = category_fixture()

      assert {:error, :forbidden} = Foglet.Boards.archive_category(mod_actor(), category)

      assert Repo.get!(Category, category.id).archived == false
    end

    test "regular user is forbidden" do
      category = category_fixture()
      user = user_fixture()

      assert {:error, :forbidden} = Foglet.Boards.archive_category(user, category)
      assert Repo.get!(Category, category.id).archived == false
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

  describe "board_directory_for/1 (SUBS-01)" do
    @describetag :board_directory

    test "returns active subscribed and unsubscribed boards grouped by category order" do
      category_b = category_fixture(%{name: "Beta", display_order: 2})
      category_a = category_fixture(%{name: "Alpha", display_order: 1})

      subscribed_board =
        board_fixture(category_a, %{
          slug: "subscribed-directory",
          name: "Subscribed Directory",
          display_order: 2,
          required_subscription: false
        })

      unsubscribed_board =
        board_fixture(category_a, %{
          slug: "unsubscribed-directory",
          name: "Unsubscribed Directory",
          display_order: 1
        })

      other_category_board =
        board_fixture(category_b, %{
          slug: "other-category-directory",
          name: "Other Category Directory",
          display_order: 1
        })

      archived_board = board_fixture(category_a, %{slug: "archived-directory", archived: true})
      archived_category = category_fixture(%{name: "Archived", display_order: 0, archived: true})
      hidden_board = board_fixture(archived_category, %{slug: "hidden-directory"})
      user = user_fixture()
      subscribed_board_id = subscribed_board.id
      unsubscribed_board_id = unsubscribed_board.id
      other_category_board_id = other_category_board.id

      assert {:ok, :subscribed} =
               Foglet.Boards.subscribe_user_to_board(user, subscribed_board.id)

      directory = Foglet.Boards.board_directory_for(user)

      assert Enum.map(directory, & &1.category.id) == [category_a.id, category_b.id]

      assert [
               %{
                 subscribed?: false,
                 unread_count: nil,
                 board: %{id: ^unsubscribed_board_id}
               },
               %{
                 subscribed?: true,
                 required_subscription?: false,
                 unread_count: 0,
                 board: %{id: ^subscribed_board_id}
               }
             ] = hd(directory).boards

      assert [%{subscribed?: false, board: %{id: ^other_category_board_id}}] =
               List.last(directory).boards

      refute Enum.any?(directory, fn category ->
               Enum.any?(category.boards, &(&1.board.id in [archived_board.id, hidden_board.id]))
             end)
    end

    test "returns an empty directory for nil users" do
      assert Foglet.Boards.board_directory_for(nil) == []
    end

    test "returns max thread last_post_at across non-deleted threads (BOARDS-03)" do
      category = category_fixture(%{name: "Cat A", display_order: 1})
      board = board_fixture(category, %{slug: "cat-a-board", name: "Board A"})
      user = user_fixture()
      author = user_fixture()

      now = DateTime.utc_now() |> DateTime.truncate(:microsecond)
      t_old = DateTime.add(now, -3600, :second)
      t_mid = DateTime.add(now, -1800, :second)
      t_new = DateTime.add(now, -60, :second)

      thread1 = thread_fixture(board, author, %{}) |> Repo.preload(:posts)
      thread2 = thread_fixture(board, author, %{}) |> Repo.preload(:posts)
      thread3 = thread_fixture(board, author, %{}) |> Repo.preload(:posts)

      Repo.update_all(
        from(t in Thread, where: t.id == ^thread1.id),
        set: [last_post_at: t_old]
      )

      Repo.update_all(
        from(t in Thread, where: t.id == ^thread2.id),
        set: [last_post_at: t_mid]
      )

      Repo.update_all(
        from(t in Thread, where: t.id == ^thread3.id),
        set: [last_post_at: t_new]
      )

      directory = Foglet.Boards.board_directory_for(user)

      entry = find_board_entry(directory, board.id)
      assert DateTime.compare(entry.last_post_at, t_new) == :eq
    end

    test "returns nil last_post_at when board has no non-deleted threads (BOARDS-03)" do
      category = category_fixture(%{name: "Cat B", display_order: 1})
      board = board_fixture(category, %{slug: "empty-board", name: "Empty"})
      user = user_fixture()

      directory = Foglet.Boards.board_directory_for(user)

      entry = find_board_entry(directory, board.id)
      assert entry.last_post_at == nil
    end

    test "excludes soft-deleted threads from last_post_at max (BOARDS-03)" do
      category = category_fixture(%{name: "Cat C", display_order: 1})
      board = board_fixture(category, %{slug: "cat-c-board", name: "Board C"})
      user = user_fixture()
      author = user_fixture()

      now = DateTime.utc_now() |> DateTime.truncate(:microsecond)
      t_kept = DateTime.add(now, -1800, :second)
      t_deleted_later = DateTime.add(now, -60, :second)

      kept = thread_fixture(board, author, %{}) |> Repo.preload(:posts)
      deleted = thread_fixture(board, author, %{}) |> Repo.preload(:posts)

      Repo.update_all(
        from(t in Thread, where: t.id == ^kept.id),
        set: [last_post_at: t_kept]
      )

      Repo.update_all(
        from(t in Thread, where: t.id == ^deleted.id),
        set: [last_post_at: t_deleted_later, deleted_at: now]
      )

      directory = Foglet.Boards.board_directory_for(user)

      entry = find_board_entry(directory, board.id)
      assert DateTime.compare(entry.last_post_at, t_kept) == :eq
    end

    test "last_post_at is identical for subscribed and unsubscribed actors on same board (BOARDS-03)" do
      category = category_fixture(%{name: "Cat D", display_order: 1})
      board = board_fixture(category, %{slug: "cat-d-board", name: "Board D"})
      author = user_fixture()
      subscribed_user = user_fixture()
      unsubscribed_user = user_fixture()

      now = DateTime.utc_now() |> DateTime.truncate(:microsecond)
      t = DateTime.add(now, -300, :second)

      thread = thread_fixture(board, author, %{}) |> Repo.preload(:posts)

      Repo.update_all(
        from(t in Thread, where: t.id == ^thread.id),
        set: [last_post_at: t]
      )

      assert {:ok, :subscribed} = Foglet.Boards.subscribe_user_to_board(subscribed_user, board.id)

      sub_entry = find_board_entry(Foglet.Boards.board_directory_for(subscribed_user), board.id)

      unsub_entry =
        find_board_entry(Foglet.Boards.board_directory_for(unsubscribed_user), board.id)

      assert sub_entry.subscribed? == true
      assert unsub_entry.subscribed? == false
      assert sub_entry.last_post_at == unsub_entry.last_post_at
      assert DateTime.compare(sub_entry.last_post_at, t) == :eq
    end
  end

  describe "subscribe_user_to_board/2 and unsubscribe_user_from_board/2 (SUBS-02, SUBS-03)" do
    test "subscribe is idempotent for active boards" do
      category = category_fixture()
      board = board_fixture(category)
      user = user_fixture()

      assert {:ok, :subscribed} = Foglet.Boards.subscribe_user_to_board(user, board.id)
      assert {:ok, :subscribed} = Foglet.Boards.subscribe_user_to_board(user.id, board.id)

      assert Repo.aggregate(
               from(s in Subscription, where: s.user_id == ^user.id and s.board_id == ^board.id),
               :count,
               :id
             ) == 1
    end

    test "subscribe rejects unknown and archived boards" do
      category = category_fixture()
      archived_board = board_fixture(category, %{archived: true})
      archived_category = category_fixture(%{archived: true})
      hidden_board = board_fixture(archived_category)
      user = user_fixture()

      assert {:error, :not_found} =
               Foglet.Boards.subscribe_user_to_board(user, Ecto.UUID.generate())

      assert {:error, :board_archived} =
               Foglet.Boards.subscribe_user_to_board(user, archived_board.id)

      assert {:error, :board_archived} =
               Foglet.Boards.subscribe_user_to_board(user, hidden_board.id)
    end

    test "unsubscribe deletes allowed rows and permits zero remaining subscriptions" do
      category = category_fixture()
      board = board_fixture(category)
      user = user_fixture()

      assert {:ok, :subscribed} = Foglet.Boards.subscribe_user_to_board(user, board.id)
      assert {:ok, :unsubscribed} = Foglet.Boards.unsubscribe_user_from_board(user.id, board.id)

      assert Repo.aggregate(
               from(s in Subscription, where: s.user_id == ^user.id),
               :count,
               :id
             ) == 0
    end

    test "unsubscribe from a required board is blocked and leaves the row intact" do
      category = category_fixture()

      required_board =
        board_fixture(category, %{
          default_subscription: true,
          required_subscription: true
        })

      user = user_fixture()

      assert {:ok, :subscribed} = Foglet.Boards.subscribe_user_to_board(user, required_board.id)

      assert {:error, :required_subscription} =
               Foglet.Boards.unsubscribe_user_from_board(user, required_board.id)

      assert Repo.get_by(Subscription, user_id: user.id, board_id: required_board.id)
    end

    test "unsubscribe rejects unknown and archived boards" do
      category = category_fixture()
      archived_board = board_fixture(category, %{archived: true})
      archived_category = category_fixture(%{archived: true})
      hidden_board = board_fixture(archived_category)
      user = user_fixture()

      assert {:error, :not_found} =
               Foglet.Boards.unsubscribe_user_from_board(user, Ecto.UUID.generate())

      assert {:error, :board_archived} =
               Foglet.Boards.unsubscribe_user_from_board(user, archived_board.id)

      assert {:error, :board_archived} =
               Foglet.Boards.unsubscribe_user_from_board(user, hidden_board.id)
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
