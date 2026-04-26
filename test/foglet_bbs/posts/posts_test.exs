defmodule Foglet.PostsTest do
  use FogletBbs.DataCase, async: false
  import FogletBbs.BoardsFixtures

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
    allow_board_server!(board.id)
    board
  end

  defp setup_board_with_server(attrs) do
    category = category_fixture()
    board = board_fixture(category, attrs)
    allow_board_server!(board.id)
    board
  end

  defp setup_board_with_server_and_pid(attrs \\ %{}) do
    category = category_fixture()
    board = board_fixture(category, attrs)
    pid = allow_board_server!(board.id)
    {board, pid}
  end

  defp setup_thread(board, user) do
    {:ok, %{thread: thread, post: root}} =
      Foglet.Threads.create_thread(board.id, user.id, %{title: "T", body: "root"})

    {thread, root}
  end

  defp active_user_fixture(attrs \\ %{}) do
    user = user_fixture()

    user
    |> Ecto.Changeset.change(Map.merge(%{status: :active}, attrs))
    |> Repo.update!()
  end

  describe "create_reply/4 (BOARD-03)" do
    test "creates a post with message_number from Board Server" do
      board = setup_board_with_server()
      user = user_fixture()
      {thread, root} = setup_thread(board, user)

      assert {:ok, reply} =
               Foglet.Posts.create_reply(thread.id, board.id, user.id, %{body: "A reply"})

      assert reply.message_number == root.message_number + 1
      assert reply.thread_id == thread.id
      assert reply.board_id == board.id
      assert reply.user_id == user.id
    end

    test "increments thread.post_count and sets thread.last_post_at" do
      board = setup_board_with_server()
      user = user_fixture()
      {thread, _root} = setup_thread(board, user)

      # Reload thread state before reply
      before = Repo.get!(Foglet.Threads.Thread, thread.id)
      assert before.post_count == 1

      {:ok, _reply} =
        Foglet.Posts.create_reply(thread.id, board.id, user.id, %{body: "Reply"})

      after_reply = Repo.get!(Foglet.Threads.Thread, thread.id)
      assert after_reply.post_count == 2
      assert after_reply.last_post_at != nil
    end

    test "increments user.post_count" do
      board = setup_board_with_server()
      user = user_fixture()
      {thread, _root} = setup_thread(board, user)

      # root post already bumped post_count to 1
      before_user = Repo.get!(Foglet.Accounts.User, user.id)
      assert before_user.post_count == 1

      {:ok, _reply} =
        Foglet.Posts.create_reply(thread.id, board.id, user.id, %{body: "Reply"})

      after_user = Repo.get!(Foglet.Accounts.User, user.id)
      assert after_user.post_count == 2
    end

    test "reply_to_id is optional and does not affect ordering" do
      board = setup_board_with_server()
      user = user_fixture()
      {thread, root} = setup_thread(board, user)

      assert {:ok, reply} =
               Foglet.Posts.create_reply(thread.id, board.id, user.id, %{
                 body: "Quoting you",
                 reply_to_id: root.id
               })

      assert reply.reply_to_id == root.id
      # message_number still sequentially assigned
      assert reply.message_number == root.message_number + 1
    end
  end

  describe "create_reply/4 posting policy and locks (POST-02, POST-03)" do
    test "matches the board postable_by role matrix for replies" do
      cases = [
        {:members, :user, :ok},
        {:members, :mod, :ok},
        {:members, :sysop, :ok},
        {:mods_only, :user, :posting_not_allowed},
        {:mods_only, :mod, :ok},
        {:mods_only, :sysop, :ok},
        {:sysop_only, :user, :posting_not_allowed},
        {:sysop_only, :mod, :posting_not_allowed},
        {:sysop_only, :sysop, :ok}
      ]

      for {postable_by, role, expected} <- cases do
        board = setup_board_with_server(%{postable_by: postable_by})
        author = active_user_fixture(%{role: :sysop})
        replier = active_user_fixture(%{role: role})
        {thread, _root} = setup_thread(board, author)

        result = Foglet.Posts.create_reply(thread.id, board.id, replier.id, %{body: "Reply"})

        case expected do
          :ok -> assert {:ok, _reply} = result
          reason -> assert {:error, ^reason} = result
        end
      end
    end

    test "rejects locked thread replies unless actor can bypass the lock" do
      board = setup_board_with_server()
      author = active_user_fixture()
      {thread, _root} = setup_thread(board, author)
      {:ok, locked_thread} = Foglet.Threads.lock_thread(thread)

      user = active_user_fixture()
      mod = active_user_fixture(%{role: :mod})
      sysop = active_user_fixture(%{role: :sysop})

      assert {:error, :thread_locked} =
               Foglet.Posts.create_reply(locked_thread.id, board.id, user.id, %{body: "Nope"})

      assert {:ok, _reply} =
               Foglet.Posts.create_reply(locked_thread.id, board.id, mod.id, %{body: "Mod reply"})

      assert {:ok, _reply} =
               Foglet.Posts.create_reply(locked_thread.id, board.id, sysop.id, %{
                 body: "Sysop reply"
               })
    end

    test "lock bypass does not override board posting policy" do
      board = setup_board_with_server(%{postable_by: :sysop_only})
      author = active_user_fixture(%{role: :sysop})
      {thread, _root} = setup_thread(board, author)
      {:ok, locked_thread} = Foglet.Threads.lock_thread(thread)

      mod = active_user_fixture(%{role: :mod})

      assert {:error, :posting_not_allowed} =
               Foglet.Posts.create_reply(locked_thread.id, board.id, mod.id, %{body: "Nope"})
    end

    test "rejected replies do not mutate post, thread, user, or board counters" do
      {board, pid} = setup_board_with_server_and_pid(%{postable_by: :sysop_only})
      author = active_user_fixture(%{role: :sysop})
      replier = active_user_fixture(%{role: :user})
      {thread, _root} = setup_thread(board, author)

      before_posts = Repo.aggregate(Foglet.Posts.Post, :count)
      before_thread = Repo.get!(Foglet.Threads.Thread, thread.id)
      before_user = Repo.get!(Foglet.Accounts.User, replier.id)
      before_board = Repo.get!(Foglet.Boards.Board, board.id)
      before_next_number = :sys.get_state(pid).next_number

      assert {:error, :posting_not_allowed} =
               Foglet.Posts.create_reply(thread.id, board.id, replier.id, %{body: "Nope"})

      after_thread = Repo.get!(Foglet.Threads.Thread, thread.id)
      after_user = Repo.get!(Foglet.Accounts.User, replier.id)
      after_board = Repo.get!(Foglet.Boards.Board, board.id)

      assert Repo.aggregate(Foglet.Posts.Post, :count) == before_posts
      assert after_thread.post_count == before_thread.post_count
      assert after_thread.last_post_at == before_thread.last_post_at
      assert after_user.post_count == before_user.post_count
      assert after_board.next_message_number == before_board.next_message_number
      assert :sys.get_state(pid).next_number == before_next_number
    end

    test "malformed IDs and thread board mismatches are rejected without side effects" do
      {board, pid} = setup_board_with_server_and_pid()
      other_board = setup_board_with_server()
      author = active_user_fixture()
      replier = active_user_fixture()
      {thread, _root} = setup_thread(board, author)

      cases = [
        {"not-a-uuid", board.id, replier.id},
        {thread.id, "not-a-uuid", replier.id},
        {thread.id, board.id, "not-a-uuid"},
        {thread.id, other_board.id, replier.id}
      ]

      for {thread_id, board_id, user_id} <- cases do
        before_posts = Repo.aggregate(Foglet.Posts.Post, :count)
        before_thread = Repo.get!(Foglet.Threads.Thread, thread.id)
        before_user = Repo.get!(Foglet.Accounts.User, replier.id)
        before_board = Repo.get!(Foglet.Boards.Board, board.id)
        before_next_number = :sys.get_state(pid).next_number

        assert {:error, :posting_not_allowed} =
                 Foglet.Posts.create_reply(thread_id, board_id, user_id, %{body: "Nope"})

        after_thread = Repo.get!(Foglet.Threads.Thread, thread.id)
        after_user = Repo.get!(Foglet.Accounts.User, replier.id)
        after_board = Repo.get!(Foglet.Boards.Board, board.id)

        assert Repo.aggregate(Foglet.Posts.Post, :count) == before_posts
        assert after_thread.post_count == before_thread.post_count
        assert after_thread.last_post_at == before_thread.last_post_at
        assert after_user.post_count == before_user.post_count
        assert after_board.next_message_number == before_board.next_message_number
        assert :sys.get_state(pid).next_number == before_next_number
      end
    end
  end

  describe "edit_post/3 (BOARD-04)" do
    test "updates post.body and increments edit_count" do
      board = setup_board_with_server()
      user = user_fixture()
      {thread, _root} = setup_thread(board, user)

      {:ok, post} = Foglet.Posts.create_reply(thread.id, board.id, user.id, %{body: "Original"})
      assert post.edit_count == 0

      assert {:ok, edited} = Foglet.Posts.edit_post(post, user.id, %{body: "Updated"})
      assert edited.body == "Updated"
      assert edited.edit_count == 1
    end

    test "creates a post_edits row with previous_body before update" do
      board = setup_board_with_server()
      user = user_fixture()
      {thread, _root} = setup_thread(board, user)

      {:ok, post} = Foglet.Posts.create_reply(thread.id, board.id, user.id, %{body: "Original"})
      {:ok, _edited} = Foglet.Posts.edit_post(post, user.id, %{body: "Updated"})

      edits = Foglet.Posts.list_edits(post.id)
      assert length(edits) == 1
      assert hd(edits).previous_body == "Original"
    end

    test "edit history contains all previous versions in order" do
      board = setup_board_with_server()
      user = user_fixture()
      {thread, _root} = setup_thread(board, user)

      {:ok, post} = Foglet.Posts.create_reply(thread.id, board.id, user.id, %{body: "v1"})
      {:ok, post_v2} = Foglet.Posts.edit_post(post, user.id, %{body: "v2"})
      {:ok, _post_v3} = Foglet.Posts.edit_post(post_v2, user.id, %{body: "v3"})

      edits = Foglet.Posts.list_edits(post.id)
      assert length(edits) == 2

      # Newest first
      bodies = Enum.map(edits, & &1.previous_body)
      assert "v2" in bodies
      assert "v1" in bodies
    end
  end

  describe "delete_post/2 (BOARD-11)" do
    test "sets deleted_at; message_number is preserved (no gap filling)" do
      board = setup_board_with_server()
      user = user_fixture()
      {thread, _root} = setup_thread(board, user)

      {:ok, post} = Foglet.Posts.create_reply(thread.id, board.id, user.id, %{body: "Delete me"})
      original_message_number = post.message_number

      {:ok, deleted} = Foglet.Posts.delete_post(post)

      assert deleted.deleted_at != nil
      assert deleted.message_number == original_message_number
    end

    test "soft-deleted posts remain visible to list_posts/1 queries" do
      board = setup_board_with_server()
      user = user_fixture()
      {thread, root} = setup_thread(board, user)

      {:ok, post} = Foglet.Posts.create_reply(thread.id, board.id, user.id, %{body: "Visible"})

      {:ok, deleted_post} =
        Foglet.Posts.create_reply(thread.id, board.id, user.id, %{body: "Gone"})

      {:ok, _} = Foglet.Posts.delete_post(deleted_post)

      visible = Foglet.Posts.list_posts(thread.id)
      ids = Enum.map(visible, & &1.id)

      assert root.id in ids
      assert post.id in ids
      assert deleted_post.id in ids

      listed_deleted_post = Enum.find(visible, &(&1.id == deleted_post.id))
      assert listed_deleted_post.deleted_at != nil
      assert listed_deleted_post.user.id == user.id
    end
  end

  describe "delete_post/3 actor-aware gate" do
    test "sysop can soft-delete a post" do
      board = setup_board_with_server()
      user = user_fixture()
      sysop = active_user_fixture(%{role: :sysop})
      {thread, _root} = setup_thread(board, user)

      {:ok, post} = Foglet.Posts.create_reply(thread.id, board.id, user.id, %{body: "Gone"})

      assert {:ok, deleted} = Foglet.Posts.delete_post(sysop, post, "mod action")
      assert deleted.deleted_at != nil
    end

    test "unauthorized actor is forbidden" do
      board = setup_board_with_server()
      user = user_fixture()
      regular = active_user_fixture()
      {thread, _root} = setup_thread(board, user)

      {:ok, post} = Foglet.Posts.create_reply(thread.id, board.id, user.id, %{body: "Gone"})

      assert {:error, :forbidden} = Foglet.Posts.delete_post(regular, post, nil)
    end
  end

  describe "scope_for/1 (D-08)" do
    test "returns {:board, board_id} for a Post struct" do
      post = %Foglet.Posts.Post{
        id: "00000000-0000-0000-0000-000000000001",
        board_id: "11111111-1111-1111-1111-111111111111"
      }

      assert Foglet.Posts.scope_for(post) == {:board, "11111111-1111-1111-1111-111111111111"}
    end

    test "works with a persisted post" do
      board = setup_board_with_server()
      user = user_fixture()
      {thread, _root} = setup_thread(board, user)
      {:ok, post} = Foglet.Posts.create_reply(thread.id, board.id, user.id, %{body: "A post"})

      assert Foglet.Posts.scope_for(post) == {:board, board.id}
    end
  end
end
