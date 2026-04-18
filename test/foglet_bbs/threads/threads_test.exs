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
end
