defmodule Foglet.ThreadsTest do
  use FogletBbs.DataCase, async: false
  import FogletBbs.BoardsFixtures

  import Ecto.Query, warn: false

  alias Ecto.Adapters.SQL.Sandbox
  alias FogletBbs.Repo

  # Board Server is started by Foglet.Boards.create_board/2 via BoardSupervisor.
  # Look up the PID from the Registry and allow sandbox access.
  defp allow_board_server!(board_id) do
    [{pid, _}] = Registry.lookup(Foglet.BoardRegistry, board_id)
    Sandbox.allow(Repo, self(), pid)
    pid
  end

  defp setup_board_with_server do
    category = category_fixture()
    board = board_fixture(category)
    pid = allow_board_server!(board.id)
    {board, pid}
  end

  defp setup_board_with_server(attrs) do
    category = category_fixture()
    board = board_fixture(category, attrs)
    pid = allow_board_server!(board.id)
    {board, pid}
  end

  defp update_user_status!(user, status) do
    user
    |> Foglet.Accounts.User.status_changeset(%{status: status})
    |> Repo.update!()
  end

  defp user_with_role!(role) do
    user_fixture()
    |> Foglet.Accounts.User.role_changeset(%{role: role})
    |> Repo.update!()
  end

  defp delete_user!(user) do
    user
    |> Foglet.Accounts.User.deletion_changeset()
    |> Repo.update!()
  end

  defp posting_attrs(title \\ "Policy test") do
    %{title: title, body: "Policy body"}
  end

  describe "create_thread/3 (BOARD-02)" do
    test "creates thread with first_post_id set and root post in DB" do
      {board, _pid} = setup_board_with_server()
      user = user_fixture()

      assert {:ok, %{thread: thread, post: post}} =
               Foglet.Threads.create_thread(board.id, user.id, %{
                 title: "Hello World",
                 body: "First post!"
               })

      assert thread.first_post_id == post.id
      assert post.board_id == board.id
      assert post.user_id == user.id
    end

    test "thread.post_count is 1 after creation" do
      {board, _pid} = setup_board_with_server()
      user = user_fixture()

      {:ok, %{thread: thread}} =
        Foglet.Threads.create_thread(board.id, user.id, %{title: "T", body: "b"})

      # Reload to get fresh counters
      reloaded = Repo.get!(Foglet.Threads.Thread, thread.id)
      assert reloaded.post_count == 1
    end

    test "root post has message_number allocated by Board Server" do
      {board, _pid} = setup_board_with_server()
      user = user_fixture()

      {:ok, %{post: post}} =
        Foglet.Threads.create_thread(board.id, user.id, %{title: "T", body: "b"})

      assert post.message_number == 1
    end
  end

  describe "create_thread/3 posting policy (POST-01)" do
    test ":members board allows active users, mods, and sysops" do
      {board, _pid} = setup_board_with_server(%{postable_by: :members})

      for role <- [:user, :mod, :sysop] do
        user = user_with_role!(role)

        assert {:ok, %{thread: thread, post: post}} =
                 Foglet.Threads.create_thread(board.id, user.id, posting_attrs("#{role} thread"))

        assert thread.created_by_id == user.id
        assert post.user_id == user.id
      end
    end

    test ":mods_only board rejects users and allows mods and sysops" do
      {board, _pid} = setup_board_with_server(%{postable_by: :mods_only})
      user = user_with_role!(:user)

      assert {:error, :posting_not_allowed} =
               Foglet.Threads.create_thread(board.id, user.id, posting_attrs())

      for role <- [:mod, :sysop] do
        poster = user_with_role!(role)

        assert {:ok, %{thread: thread, post: post}} =
                 Foglet.Threads.create_thread(
                   board.id,
                   poster.id,
                   posting_attrs("#{role} thread")
                 )

        assert thread.created_by_id == poster.id
        assert post.user_id == poster.id
      end
    end

    test ":sysop_only board rejects users and mods and allows sysops" do
      {board, _pid} = setup_board_with_server(%{postable_by: :sysop_only})

      for role <- [:user, :mod] do
        user = user_with_role!(role)

        assert {:error, :posting_not_allowed} =
                 Foglet.Threads.create_thread(board.id, user.id, posting_attrs("#{role} thread"))
      end

      sysop = user_with_role!(:sysop)

      assert {:ok, %{thread: thread, post: post}} =
               Foglet.Threads.create_thread(board.id, sysop.id, posting_attrs("sysop thread"))

      assert thread.created_by_id == sysop.id
      assert post.user_id == sysop.id
    end

    test "rejects pending, suspended, deleted, missing, and unknown users" do
      {board, _pid} = setup_board_with_server(%{postable_by: :members})
      pending = user_fixture() |> update_user_status!(:pending)
      suspended = user_fixture() |> update_user_status!(:suspended)
      deleted = user_fixture() |> delete_user!()

      disallowed_user_ids = [
        pending.id,
        suspended.id,
        deleted.id,
        nil,
        Ecto.UUID.generate()
      ]

      for user_id <- disallowed_user_ids do
        assert {:error, :posting_not_allowed} =
                 Foglet.Threads.create_thread(board.id, user_id, posting_attrs("denied thread"))
      end
    end

    test "rejected creates do not persist rows or advance board message numbers" do
      {board, pid} = setup_board_with_server(%{postable_by: :sysop_only})
      user = user_with_role!(:user)

      before_thread_count = Repo.aggregate(Foglet.Threads.Thread, :count, :id)
      before_post_count = Repo.aggregate(Foglet.Posts.Post, :count, :id)
      before_board = Repo.get!(Foglet.Boards.Board, board.id)
      before_next_number = :sys.get_state(pid).next_number

      assert before_board.next_message_number == before_next_number

      assert {:error, :posting_not_allowed} =
               Foglet.Threads.create_thread(board.id, user.id, posting_attrs("denied thread"))

      after_board = Repo.get!(Foglet.Boards.Board, board.id)

      assert Repo.aggregate(Foglet.Threads.Thread, :count, :id) == before_thread_count
      assert Repo.aggregate(Foglet.Posts.Post, :count, :id) == before_post_count
      assert after_board.next_message_number == before_board.next_message_number
      assert :sys.get_state(pid).next_number == before_next_number
    end
  end

  describe "advance_thread_read_pointer/3 (BOARD-09)" do
    test "inserts thread read pointer on first read" do
      {board, _pid} = setup_board_with_server()
      user = user_fixture()

      {:ok, %{thread: thread, post: post}} =
        Foglet.Threads.create_thread(board.id, user.id, %{title: "T", body: "b"})

      assert {:ok, ptr} =
               Foglet.Threads.advance_thread_read_pointer(user.id, thread.id, post.id)

      assert ptr.last_read_post_id == post.id
      assert ptr.thread_id == thread.id
    end

    test "updates last_read_post_id on subsequent reads (upsert)" do
      {board, _pid} = setup_board_with_server()
      user = user_fixture()
      poster = user_fixture()

      {:ok, %{thread: thread, post: p1}} =
        Foglet.Threads.create_thread(board.id, poster.id, %{title: "T", body: "b"})

      {:ok, p2} =
        Foglet.Posts.create_reply(thread.id, board.id, poster.id, %{body: "reply"})

      {:ok, _} = Foglet.Threads.advance_thread_read_pointer(user.id, thread.id, p1.id)
      {:ok, updated} = Foglet.Threads.advance_thread_read_pointer(user.id, thread.id, p2.id)

      assert updated.last_read_post_id == p2.id

      # Only one pointer row
      count =
        Repo.aggregate(
          from(ptr in Foglet.Threads.ReadPointer,
            where: ptr.user_id == ^user.id and ptr.thread_id == ^thread.id
          ),
          :count,
          :id
        )

      assert count == 1
    end
  end

  describe "lock_thread/1, sticky_thread/1 (BOARD-12)" do
    test "lock_thread/1 sets locked: true" do
      {board, _pid} = setup_board_with_server()
      user = user_fixture()

      {:ok, %{thread: thread}} =
        Foglet.Threads.create_thread(board.id, user.id, %{title: "T", body: "b"})

      assert {:ok, locked} = Foglet.Threads.lock_thread(thread)
      assert locked.locked == true
    end

    test "sticky_thread/1 sets sticky: true" do
      {board, _pid} = setup_board_with_server()
      user = user_fixture()

      {:ok, %{thread: thread}} =
        Foglet.Threads.create_thread(board.id, user.id, %{title: "T", body: "b"})

      assert {:ok, stickied} = Foglet.Threads.sticky_thread(thread)
      assert stickied.sticky == true
    end
  end

  describe "move_thread/2 (BOARD-12)" do
    test "updates thread.board_id and all thread posts' board_id" do
      category = category_fixture()
      board_a = board_fixture(category)
      board_b = board_fixture(category)
      user = user_fixture()

      allow_board_server!(board_a.id)
      allow_board_server!(board_b.id)

      {:ok, %{thread: thread, post: p1}} =
        Foglet.Threads.create_thread(board_a.id, user.id, %{title: "T", body: "b"})

      {:ok, p2} = Foglet.Posts.create_reply(thread.id, board_a.id, user.id, %{body: "reply"})

      assert {:ok, moved_thread} = Foglet.Threads.move_thread(thread, board_b.id)
      assert moved_thread.board_id == board_b.id

      # All posts updated
      reloaded_p1 = Repo.get!(Foglet.Posts.Post, p1.id)
      reloaded_p2 = Repo.get!(Foglet.Posts.Post, p2.id)
      assert reloaded_p1.board_id == board_b.id
      assert reloaded_p2.board_id == board_b.id
    end
  end

  describe "list_threads/2 — unread annotation (LIST-03)" do
    test "returns empty list for a board with no threads" do
      {board, _pid} = setup_board_with_server()
      user = user_fixture()

      assert [] = Foglet.Threads.list_threads(board.id, user.id)
    end

    test "new user (no read pointers) sees all threads as has_unread: true" do
      {board, _pid} = setup_board_with_server()
      poster = user_fixture()
      reader = user_fixture()

      {:ok, %{thread: t1}} =
        Foglet.Threads.create_thread(board.id, poster.id, %{title: "A", body: "b"})

      {:ok, %{thread: t2}} =
        Foglet.Threads.create_thread(board.id, poster.id, %{title: "B", body: "b"})

      results = Foglet.Threads.list_threads(board.id, reader.id)

      assert length(results) == 2

      result_map = Map.new(results, fn t -> {t.id, t.has_unread} end)
      assert Map.get(result_map, t1.id) == true
      assert Map.get(result_map, t2.id) == true
    end

    test "thread read before its last post is has_unread: true" do
      {board, _pid} = setup_board_with_server()
      poster = user_fixture()
      reader = user_fixture()

      {:ok, %{thread: thread, post: p1}} =
        Foglet.Threads.create_thread(board.id, poster.id, %{title: "T", body: "root"})

      {:ok, _} = Foglet.Threads.advance_thread_read_pointer(reader.id, thread.id, p1.id)

      past = DateTime.add(DateTime.utc_now(), -3600, :second)

      from(rp in Foglet.Threads.ReadPointer,
        where: rp.user_id == ^reader.id and rp.thread_id == ^thread.id
      )
      |> Repo.update_all(set: [last_read_at: past])

      {:ok, _p2} =
        Foglet.Posts.create_reply(thread.id, board.id, poster.id, %{body: "later"})

      [%{has_unread: has_unread}] = Foglet.Threads.list_threads(board.id, reader.id)
      assert has_unread == true
    end

    test "thread read up-to-date is has_unread: false" do
      {board, _pid} = setup_board_with_server()
      poster = user_fixture()
      reader = user_fixture()

      {:ok, %{thread: thread, post: p1}} =
        Foglet.Threads.create_thread(board.id, poster.id, %{title: "T", body: "root"})

      future = DateTime.add(DateTime.utc_now(), 3600, :second)

      {:ok, _} = Foglet.Threads.advance_thread_read_pointer(reader.id, thread.id, p1.id)

      from(rp in Foglet.Threads.ReadPointer,
        where: rp.user_id == ^reader.id and rp.thread_id == ^thread.id
      )
      |> Repo.update_all(set: [last_read_at: future])

      [%{has_unread: has_unread}] = Foglet.Threads.list_threads(board.id, reader.id)
      assert has_unread == false
    end

    test "preserves order: stickies first, then newest last_post_at" do
      {board, _pid} = setup_board_with_server()
      poster = user_fixture()
      reader = user_fixture()

      {:ok, %{thread: t_old}} =
        Foglet.Threads.create_thread(board.id, poster.id, %{title: "old", body: "b"})

      {:ok, %{thread: t_sticky}} =
        Foglet.Threads.create_thread(board.id, poster.id, %{title: "sticky", body: "b"})

      {:ok, %{thread: t_new}} =
        Foglet.Threads.create_thread(board.id, poster.id, %{title: "new", body: "b"})

      {:ok, _} = Foglet.Threads.sticky_thread(Foglet.Threads.get_thread!(t_sticky.id))

      past = DateTime.add(DateTime.utc_now(), -3600, :second)

      from(t in Foglet.Threads.Thread, where: t.id == ^t_old.id)
      |> Repo.update_all(set: [last_post_at: past])

      results = Foglet.Threads.list_threads(board.id, reader.id)
      ids = Enum.map(results, & &1.id)

      assert ids == [t_sticky.id, t_new.id, t_old.id]
    end

    test "preloads :created_by so callers can read handle without N+1" do
      {board, _pid} = setup_board_with_server()
      poster = user_fixture(%{handle: "mallory"})
      reader = user_fixture()

      {:ok, _} =
        Foglet.Threads.create_thread(board.id, poster.id, %{title: "T", body: "b"})

      [t | _] = Foglet.Threads.list_threads(board.id, reader.id)

      assert %Foglet.Threads.ThreadEntry{} = t
      assert %Foglet.Accounts.User{handle: "mallory"} = t.created_by
    end

    test "list_threads/2 rows always include created_by.handle for rendering contract" do
      {board, _pid} = setup_board_with_server()
      poster_a = user_fixture(%{handle: "alpha"})
      poster_b = user_fixture(%{handle: "beta"})
      reader = user_fixture()

      {:ok, _} =
        Foglet.Threads.create_thread(board.id, poster_a.id, %{title: "A", body: "b"})

      {:ok, _} =
        Foglet.Threads.create_thread(board.id, poster_b.id, %{title: "B", body: "b"})

      rows = Foglet.Threads.list_threads(board.id, reader.id)
      assert length(rows) == 2

      assert Enum.all?(rows, fn row ->
               is_map(row.created_by) and
                 is_binary(row.created_by.handle) and
                 row.created_by.handle != ""
             end)
    end

    test "list_threads/2 with nil user_id delegates to list_threads/1 with has_unread: false" do
      {board, _pid} = setup_board_with_server()
      poster = user_fixture()

      {:ok, _} =
        Foglet.Threads.create_thread(board.id, poster.id, %{title: "A", body: "b"})

      [t] = Foglet.Threads.list_threads(board.id, nil)
      assert t.has_unread == false
      assert t.title == "A"
    end

    test "excludes soft-deleted threads" do
      {board, _pid} = setup_board_with_server()
      poster = user_fixture()
      reader = user_fixture()

      {:ok, %{thread: alive}} =
        Foglet.Threads.create_thread(board.id, poster.id, %{title: "alive", body: "b"})

      {:ok, %{thread: dead}} =
        Foglet.Threads.create_thread(board.id, poster.id, %{title: "dead", body: "b"})

      {:ok, _} = Foglet.Threads.delete_thread(Foglet.Threads.get_thread!(dead.id))

      results = Foglet.Threads.list_threads(board.id, reader.id)
      ids = Enum.map(results, & &1.id)

      assert alive.id in ids
      refute dead.id in ids
    end

    test "empty thread (last_post_at nil) is has_unread: false" do
      {board, _pid} = setup_board_with_server()
      poster = user_fixture()
      reader = user_fixture()

      {:ok, %{thread: thread}} =
        Foglet.Threads.create_thread(board.id, poster.id, %{title: "T", body: "b"})

      from(t in Foglet.Threads.Thread, where: t.id == ^thread.id)
      |> Repo.update_all(set: [last_post_at: nil])

      [%{has_unread: has_unread}] = Foglet.Threads.list_threads(board.id, reader.id)
      assert has_unread == false
    end
  end

  describe "scope_for/1 (D-08)" do
    test "returns {:board, board_id} for a Thread struct" do
      thread = %Foglet.Threads.Thread{
        id: "00000000-0000-0000-0000-000000000001",
        board_id: "11111111-1111-1111-1111-111111111111"
      }

      assert Foglet.Threads.scope_for(thread) == {:board, "11111111-1111-1111-1111-111111111111"}
    end

    test "works with a persisted thread" do
      {board, _pid} = setup_board_with_server()
      user = user_fixture()
      thread = thread_fixture(board, user)

      assert Foglet.Threads.scope_for(thread) == {:board, board.id}
    end
  end
end
