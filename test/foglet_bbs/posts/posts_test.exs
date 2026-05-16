defmodule Foglet.PostsTest do
  use FogletBbs.DataCase, async: false
  import FogletBbs.BoardsFixtures

  import Ecto.Query

  alias Ecto.Adapters.SQL.Sandbox
  alias Foglet.Notifications.Notification
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

  defp setup_thread_with_posts(count) when count >= 1 do
    board = setup_board_with_server()
    user = user_fixture()
    {thread, root} = setup_thread(board, user)

    replies =
      for index <- 2..count do
        {:ok, reply} =
          Foglet.Posts.create_reply(thread.id, board.id, user.id, %{
            body: "Reply #{index}"
          })

        reply
      end

    {board, user, thread, [root | replies]}
  end

  defp active_user_fixture(attrs \\ %{}) do
    user = user_fixture()

    user
    |> Ecto.Changeset.change(Map.merge(%{status: :active}, attrs))
    |> Repo.update!()
  end

  defp notifications_for(user) do
    Notification
    |> where([notification], notification.user_id == ^user.id)
    |> order_by([notification], asc: notification.inserted_at, asc: notification.id)
    |> Repo.all()
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

  describe "create_reply/4 mention notifications" do
    test "emits one mention notification per active non-actor recipient" do
      board = setup_board_with_server()
      actor = user_fixture(%{handle: "poster"})
      alice = user_fixture(%{handle: "Alice"})
      bob = user_fixture(%{handle: "bob_2"})
      {thread, _root} = setup_thread(board, actor)

      assert {:ok, post} =
               Foglet.Posts.create_reply(thread.id, board.id, actor.id, %{
                 body: "Ping @alice and @BOB_2 and again @Alice"
               })

      notifications = mention_notifications_for_post(post.id)
      assert Enum.map(notifications, & &1.user_id) |> Enum.sort() == Enum.sort([alice.id, bob.id])
      assert Enum.all?(notifications, &(&1.kind == :mention))
      assert Enum.all?(notifications, &(&1.actor_id == actor.id))
      assert Enum.all?(notifications, &(&1.payload["thread_id"] == thread.id))
      assert Enum.all?(notifications, &(&1.payload["board_id"] == board.id))
    end

    test "ignores unknown, suspended, deleted, and self mentions without failing post creation" do
      board = setup_board_with_server()
      actor = user_fixture(%{handle: "self"})
      active = user_fixture(%{handle: "active"})
      suspended = active_user_fixture(%{handle: "suspended", status: :suspended})
      deleted = user_fixture(%{handle: "deleted"})
      {:ok, _deleted} = Foglet.Accounts.delete_user(deleted)
      {thread, _root} = setup_thread(board, actor)

      assert {:ok, post} =
               Foglet.Posts.create_reply(thread.id, board.id, actor.id, %{
                 body: "@active @suspended @deleted @self @nobody"
               })

      notifications = mention_notifications_for_post(post.id)
      assert Enum.map(notifications, & &1.user_id) == [active.id]
      refute Enum.any?(notifications, &(&1.user_id in [suspended.id, deleted.id, actor.id]))
    end

    test "uses mention dedupe so repeated emission and future reply duplicate paths keep one mention" do
      board = setup_board_with_server()
      actor = user_fixture(%{handle: "poster"})
      recipient = user_fixture(%{handle: "recipient"})
      {thread, _root} = setup_thread(board, actor)

      assert {:ok, post} =
               Foglet.Posts.create_reply(thread.id, board.id, actor.id, %{body: "hi @recipient"})

      dedupe_key = "post:#{post.id}:user:#{recipient.id}"

      assert {:ok, existing} =
               Foglet.Notifications.create_notification(%{
                 user_id: recipient.id,
                 actor_id: actor.id,
                 kind: :reply,
                 dedupe_key: dedupe_key,
                 payload: %{
                   board_id: board.id,
                   thread_id: thread.id,
                   post_id: post.id,
                   snippet: "reply duplicate"
                 }
               })

      [notification] = mention_notifications_for_post(post.id)
      assert notification.id == existing.id
      assert notification.kind == :mention
      assert notification.dedupe_key == dedupe_key
    end
  end

  defp mention_notifications_for_post(post_id) do
    Repo.all(
      from n in Notification,
        where: n.payload["post_id"] == ^post_id,
        order_by: [asc: n.inserted_at, asc: n.id]
    )
  end

  describe "create_reply/4 reply notifications" do
    test "replying to another user's post creates one unread reply notification" do
      board = setup_board_with_server()
      author = active_user_fixture()
      replier = active_user_fixture()
      {thread, root} = setup_thread(board, author)

      assert {:ok, reply} =
               Foglet.Posts.create_reply(thread.id, board.id, replier.id, %{
                 body: "  hello\n\nfrom the other side  ",
                 reply_to_id: root.id
               })

      assert [notification] = Repo.all(Notification)
      assert notification.kind == :reply
      assert notification.user_id == author.id
      assert notification.actor_id == replier.id
      assert is_nil(notification.read_at)
      assert notification.dedupe_key == "post:#{reply.id}:user:#{author.id}"

      assert notification.payload == %{
               "board_id" => board.id,
               "thread_id" => thread.id,
               "post_id" => reply.id,
               "snippet" => "hello from the other side"
             }
    end

    test "replying to your own post does not create a notification" do
      board = setup_board_with_server()
      author = active_user_fixture()
      {thread, root} = setup_thread(board, author)

      assert {:ok, _reply} =
               Foglet.Posts.create_reply(thread.id, board.id, author.id, %{
                 body: "self follow-up",
                 reply_to_id: root.id
               })

      assert Repo.aggregate(Notification, :count) == 0
    end

    test "deleted parents do not create reply notifications" do
      board = setup_board_with_server()
      author = active_user_fixture()
      replier = active_user_fixture()
      other = active_user_fixture()
      {thread, root} = setup_thread(board, author)

      {:ok, other_post} =
        Foglet.Posts.create_reply(thread.id, board.id, other.id, %{body: "other"})

      Repo.delete_all(Notification)

      assert {:ok, deleted_root} = Foglet.Posts.delete_post(root)

      assert {:ok, reply_to_deleted} =
               Foglet.Posts.create_reply(thread.id, board.id, replier.id, %{
                 body: "reply to deleted",
                 reply_to_id: deleted_root.id
               })

      assert [notification] = Repo.all(Notification)
      assert notification.kind == :thread_update
      assert notification.user_id == author.id

      assert notification.payload == %{
               "board_id" => board.id,
               "thread_id" => thread.id,
               "post_id" => reply_to_deleted.id,
               "snippet" => "reply to deleted"
             }

      refute notification.user_id == other_post.user_id
      assert Repo.aggregate(from(n in Notification, where: n.kind == :reply), :count) == 0
    end

    test "missing parent references fail without notifications or counter drift" do
      {board, pid} = setup_board_with_server_and_pid()
      author = active_user_fixture()
      replier = active_user_fixture()
      {thread, _root} = setup_thread(board, author)

      before_posts = Repo.aggregate(Foglet.Posts.Post, :count)
      before_thread = Repo.get!(Foglet.Threads.Thread, thread.id)
      before_replier = Repo.get!(Foglet.Accounts.User, replier.id)
      before_board = Repo.get!(Foglet.Boards.Board, board.id)
      before_next_number = :sys.get_state(pid).next_number

      assert {:error, %Ecto.Changeset{}} =
               Foglet.Posts.create_reply(thread.id, board.id, replier.id, %{
                 body: "reply to missing parent",
                 reply_to_id: Ecto.UUID.generate()
               })

      after_thread = Repo.get!(Foglet.Threads.Thread, thread.id)
      after_replier = Repo.get!(Foglet.Accounts.User, replier.id)
      after_board = Repo.get!(Foglet.Boards.Board, board.id)

      assert Repo.aggregate(Notification, :count) == 0
      assert Repo.aggregate(Foglet.Posts.Post, :count) == before_posts
      assert after_thread.post_count == before_thread.post_count
      assert after_thread.last_post_at == before_thread.last_post_at
      assert after_replier.post_count == before_replier.post_count
      assert after_board.next_message_number == before_board.next_message_number
      assert :sys.get_state(pid).next_number == before_next_number
    end

    test "missing and deleted actors are rejected before notification emission" do
      {board, pid} = setup_board_with_server_and_pid()
      author = active_user_fixture()
      deleted_actor = active_user_fixture(%{deleted_at: DateTime.utc_now()})
      {thread, root} = setup_thread(board, author)

      before_posts = Repo.aggregate(Foglet.Posts.Post, :count)
      before_thread = Repo.get!(Foglet.Threads.Thread, thread.id)
      before_deleted_actor = Repo.get!(Foglet.Accounts.User, deleted_actor.id)
      before_board = Repo.get!(Foglet.Boards.Board, board.id)
      before_next_number = :sys.get_state(pid).next_number

      for actor_id <- [Ecto.UUID.generate(), deleted_actor.id] do
        assert {:error, :posting_not_allowed} =
                 Foglet.Posts.create_reply(thread.id, board.id, actor_id, %{
                   body: "unsafe actor reply",
                   reply_to_id: root.id
                 })
      end

      after_thread = Repo.get!(Foglet.Threads.Thread, thread.id)
      after_deleted_actor = Repo.get!(Foglet.Accounts.User, deleted_actor.id)
      after_board = Repo.get!(Foglet.Boards.Board, board.id)

      assert Repo.aggregate(Notification, :count) == 0
      assert Repo.aggregate(Foglet.Posts.Post, :count) == before_posts
      assert after_thread.post_count == before_thread.post_count
      assert after_thread.last_post_at == before_thread.last_post_at
      assert after_deleted_actor.post_count == before_deleted_actor.post_count
      assert after_board.next_message_number == before_board.next_message_number
      assert :sys.get_state(pid).next_number == before_next_number
    end

    test "dedupes duplicate reply notification attempts for one created post" do
      board = setup_board_with_server()
      author = active_user_fixture()
      replier = active_user_fixture()
      {thread, root} = setup_thread(board, author)

      assert {:ok, reply} =
               Foglet.Posts.create_reply(thread.id, board.id, replier.id, %{
                 body: "dedupe me",
                 reply_to_id: root.id
               })

      assert {:ok, duplicate} =
               Foglet.Notifications.create_notification(%{
                 user_id: author.id,
                 actor_id: replier.id,
                 kind: :reply,
                 dedupe_key: "post:#{reply.id}:user:#{author.id}",
                 payload: %{
                   board_id: board.id,
                   thread_id: thread.id,
                   post_id: reply.id,
                   snippet: "dedupe me"
                 }
               })

      assert [notification] = Repo.all(Notification)
      assert duplicate.id == notification.id
    end
  end

  describe "create_reply/4 post-event notification hierarchy" do
    test "mention wins over reply for the same recipient and post" do
      board = setup_board_with_server()
      recipient = active_user_fixture(%{handle: "recipient"})
      actor = active_user_fixture(%{handle: "actor"})
      {thread, root} = setup_thread(board, recipient)

      assert {:ok, reply} =
               Foglet.Posts.create_reply(thread.id, board.id, actor.id, %{
                 body: "replying to @recipient",
                 reply_to_id: root.id
               })

      assert [%Notification{} = notification] = Repo.all(Notification)
      assert notification.kind == :mention
      assert notification.user_id == recipient.id
      assert notification.dedupe_key == "post:#{reply.id}:user:#{recipient.id}"
      assert notification.payload["post_id"] == reply.id
    end

    test "mention wins over thread creator fallback for the same recipient and post" do
      board = setup_board_with_server()
      creator = active_user_fixture(%{handle: "creator"})
      actor = active_user_fixture(%{handle: "actor"})
      {thread, _root} = setup_thread(board, creator)

      assert {:ok, reply} =
               Foglet.Posts.create_reply(thread.id, board.id, actor.id, %{body: "ping @creator"})

      assert [%Notification{} = notification] = Repo.all(Notification)
      assert notification.kind == :mention
      assert notification.user_id == creator.id
      assert notification.dedupe_key == "post:#{reply.id}:user:#{creator.id}"
    end

    test "reply wins over thread creator fallback for the same recipient and post" do
      board = setup_board_with_server()
      creator = active_user_fixture(%{handle: "creator"})
      actor = active_user_fixture(%{handle: "actor"})
      {thread, root} = setup_thread(board, creator)

      assert {:ok, reply} =
               Foglet.Posts.create_reply(thread.id, board.id, actor.id, %{
                 body: "quoted reply",
                 reply_to_id: root.id
               })

      assert [%Notification{} = notification] = Repo.all(Notification)
      assert notification.kind == :reply
      assert notification.user_id == creator.id
      assert notification.dedupe_key == "post:#{reply.id}:user:#{creator.id}"
    end

    test "mention wins when mention, reply, and thread creator all overlap" do
      board = setup_board_with_server()
      creator = active_user_fixture(%{handle: "creator"})
      actor = active_user_fixture(%{handle: "actor"})
      {thread, root} = setup_thread(board, creator)

      assert {:ok, reply} =
               Foglet.Posts.create_reply(thread.id, board.id, actor.id, %{
                 body: "quoted reply for @creator",
                 reply_to_id: root.id
               })

      assert [%Notification{} = notification] = Repo.all(Notification)
      assert notification.kind == :mention
      assert notification.user_id == creator.id
      assert notification.dedupe_key == "post:#{reply.id}:user:#{creator.id}"
    end

    test "thread creator fallback emits when there is no mention or reply overlap" do
      board = setup_board_with_server()
      creator = active_user_fixture(%{handle: "creator"})
      actor = active_user_fixture(%{handle: "actor"})
      {thread, _root} = setup_thread(board, creator)

      assert {:ok, reply} =
               Foglet.Posts.create_reply(thread.id, board.id, actor.id, %{body: "new update"})

      assert [%Notification{} = notification] = Repo.all(Notification)
      assert notification.kind == :thread_update
      assert notification.user_id == creator.id
      assert notification.actor_id == actor.id
      assert notification.dedupe_key == "post:#{reply.id}:user:#{creator.id}"

      assert notification.payload == %{
               "board_id" => board.id,
               "thread_id" => thread.id,
               "post_id" => reply.id,
               "snippet" => "new update"
             }
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

  describe "toggle_upvote/2" do
    test "inserts an upvote and increments the denormalized count" do
      board = setup_board_with_server()
      author = active_user_fixture()
      voter = active_user_fixture()
      {thread, _root} = setup_thread(board, author)
      {:ok, post} = Foglet.Posts.create_reply(thread.id, board.id, author.id, %{body: "Good"})

      assert {:ok, toggled} = Foglet.Posts.toggle_upvote(voter.id, post.id)

      assert toggled.id == post.id
      assert toggled.upvote_count == 1
      assert Repo.get!(Foglet.Posts.Post, post.id).upvote_count == 1
      assert Repo.get_by(Foglet.Posts.Upvote, user_id: voter.id, post_id: post.id)
    end

    test "second toggle by the same user deletes the upvote and decrements count" do
      board = setup_board_with_server()
      author = active_user_fixture()
      voter = active_user_fixture()
      {thread, _root} = setup_thread(board, author)
      {:ok, post} = Foglet.Posts.create_reply(thread.id, board.id, author.id, %{body: "Good"})

      assert {:ok, %{upvote_count: 1}} = Foglet.Posts.toggle_upvote(voter.id, post.id)
      assert {:ok, toggled} = Foglet.Posts.toggle_upvote(voter.id, post.id)

      assert toggled.upvote_count == 0
      assert Repo.get!(Foglet.Posts.Post, post.id).upvote_count == 0
      refute Repo.get_by(Foglet.Posts.Upvote, user_id: voter.id, post_id: post.id)
    end

    test "own-post toggle silently no-ops without row or count changes" do
      board = setup_board_with_server()
      author = active_user_fixture()
      {thread, _root} = setup_thread(board, author)
      {:ok, post} = Foglet.Posts.create_reply(thread.id, board.id, author.id, %{body: "Mine"})

      assert {:ok, toggled} = Foglet.Posts.toggle_upvote(author.id, post.id)

      assert toggled.id == post.id
      assert toggled.upvote_count == 0
      assert Repo.get!(Foglet.Posts.Post, post.id).upvote_count == 0
      refute Repo.get_by(Foglet.Posts.Upvote, user_id: author.id, post_id: post.id)
    end

    test "repeat toggles keep count equal to actual upvote rows" do
      board = setup_board_with_server()
      author = active_user_fixture()
      voter = active_user_fixture()
      other_voter = active_user_fixture()
      {thread, _root} = setup_thread(board, author)
      {:ok, post} = Foglet.Posts.create_reply(thread.id, board.id, author.id, %{body: "Good"})

      assert {:ok, %{upvote_count: 1}} = Foglet.Posts.toggle_upvote(voter.id, post.id)
      assert {:ok, %{upvote_count: 0}} = Foglet.Posts.toggle_upvote(voter.id, post.id)
      assert {:ok, %{upvote_count: 1}} = Foglet.Posts.toggle_upvote(voter.id, post.id)
      assert {:ok, %{upvote_count: 2}} = Foglet.Posts.toggle_upvote(other_voter.id, post.id)

      row_count =
        Foglet.Posts.Upvote
        |> Ecto.Query.where([u], u.post_id == ^post.id)
        |> Repo.aggregate(:count, :id)

      assert row_count == 2
      assert Repo.get!(Foglet.Posts.Post, post.id).upvote_count == row_count
    end

    test "actor-aware toggle rejects guests without mutating public posts" do
      board = setup_board_with_server()
      author = active_user_fixture()
      {thread, _root} = setup_thread(board, author)
      {:ok, post} = Foglet.Posts.create_reply(thread.id, board.id, author.id, %{body: "Good"})

      assert {:error, :forbidden} = Foglet.Posts.toggle_readable_upvote(nil, post.id)
      assert Repo.get!(Foglet.Posts.Post, post.id).upvote_count == 0
      refute Repo.get_by(Foglet.Posts.Upvote, post_id: post.id)
    end

    test "actor-aware toggle applies the existing own-post silent no-op" do
      board = setup_board_with_server()
      author = active_user_fixture()
      {thread, _root} = setup_thread(board, author)
      {:ok, post} = Foglet.Posts.create_reply(thread.id, board.id, author.id, %{body: "Mine"})

      assert {:ok, refreshed} = Foglet.Posts.toggle_readable_upvote(author, post.id)
      assert refreshed.id == post.id
      assert refreshed.upvote_count == 0
      refute Repo.get_by(Foglet.Posts.Upvote, user_id: author.id, post_id: post.id)
    end

    test "actor-aware toggle enforces readable-board visibility" do
      board = setup_board_with_server(%{readable_by: :members})
      author = active_user_fixture()
      voter = active_user_fixture()
      {thread, _root} = setup_thread(board, author)
      {:ok, post} = Foglet.Posts.create_reply(thread.id, board.id, author.id, %{body: "Private"})

      assert {:ok, %{upvote_count: 1}} = Foglet.Posts.toggle_readable_upvote(voter, post.id)
      assert {:error, :forbidden} = Foglet.Posts.toggle_readable_upvote(nil, post.id)
      assert Repo.get!(Foglet.Posts.Post, post.id).upvote_count == 1
    end
  end

  describe "thread creator notifications" do
    test "notifies a thread creator when another user posts in their thread" do
      board = setup_board_with_server()
      creator = active_user_fixture(%{handle: "creator"})
      poster = active_user_fixture(%{handle: "poster"})
      {thread, _root} = setup_thread(board, creator)

      assert {:ok, post} =
               Foglet.Posts.create_reply(thread.id, board.id, poster.id, %{
                 body: "  thread update\n\nsummary  "
               })

      assert [notification] = notifications_for(creator)
      assert notification.kind == :thread_update
      assert notification.actor_id == poster.id
      assert notification.read_at == nil
      assert notification.dedupe_key == "post:#{post.id}:user:#{creator.id}"
      assert notification.payload["board_id"] == board.id
      assert notification.payload["thread_id"] == thread.id
      assert notification.payload["post_id"] == post.id
      assert notification.payload["snippet"] == "thread update summary"
    end

    test "does not notify the creator for their own post" do
      board = setup_board_with_server()
      creator = active_user_fixture()
      {thread, _root} = setup_thread(board, creator)

      assert {:ok, _post} =
               Foglet.Posts.create_reply(thread.id, board.id, creator.id, %{body: "self update"})

      assert notifications_for(creator) == []
    end

    test "prefers reply notification when the new post replies to the creator" do
      board = setup_board_with_server()
      creator = active_user_fixture()
      poster = active_user_fixture()
      {thread, root} = setup_thread(board, creator)

      assert {:ok, post} =
               Foglet.Posts.create_reply(thread.id, board.id, poster.id, %{
                 body: "quoted reply",
                 reply_to_id: root.id
               })

      assert [notification] = notifications_for(creator)
      assert notification.kind == :reply
      assert notification.dedupe_key == "post:#{post.id}:user:#{creator.id}"
      assert notification.payload["post_id"] == post.id
    end

    test "prefers mention notification when the new post mentions the creator" do
      board = setup_board_with_server()
      creator = active_user_fixture(%{handle: "threadmaker"})
      poster = active_user_fixture()
      {thread, _root} = setup_thread(board, creator)

      assert {:ok, post} =
               Foglet.Posts.create_reply(thread.id, board.id, poster.id, %{
                 body: "hi @threadmaker, see this"
               })

      assert [notification] = notifications_for(creator)
      assert notification.kind == :mention
      assert notification.dedupe_key == "post:#{post.id}:user:#{creator.id}"
      assert notification.payload["post_id"] == post.id
    end

    test "missing and deleted threads are rejected before board-server mutation" do
      board = setup_board_with_server()
      creator = active_user_fixture()
      poster = active_user_fixture()
      missing_thread_id = Ecto.UUID.generate()

      assert {:error, :posting_not_allowed} =
               Foglet.Posts.create_reply(missing_thread_id, board.id, poster.id, %{body: "orphan"})

      {thread, _root} = setup_thread(board, creator)
      {:ok, _deleted_thread} = Foglet.Threads.delete_thread(thread)
      before_board = Repo.get!(Foglet.Boards.Board, board.id)
      before_posts = Repo.aggregate(Foglet.Posts.Post, :count)

      assert {:error, :posting_not_allowed} =
               Foglet.Posts.create_reply(thread.id, board.id, poster.id, %{body: "deleted thread"})

      assert Repo.get!(Foglet.Boards.Board, board.id).next_message_number ==
               before_board.next_message_number

      assert Repo.aggregate(Foglet.Posts.Post, :count) == before_posts
    end
  end

  describe "guest readability gates" do
    test "actor-aware reader window denies nil guests members-readable board posts" do
      category = category_fixture()
      board = board_fixture(category, %{readable_by: :members})
      allow_board_server!(board.id)
      poster = user_fixture()

      assert {:ok, %{thread: thread, post: post}} =
               Foglet.Threads.create_thread(board.id, poster.id, %{
                 title: "Members",
                 body: "Hidden"
               })

      assert {:error, :not_found} = Foglet.Posts.fetch_readable_post(nil, post.id)
      assert {:error, :not_found} = Foglet.Posts.list_reader_window_for(nil, thread.id)
      assert {:ok, fetched} = Foglet.Posts.fetch_readable_post(poster, post.id)
      assert fetched.id == post.id
      assert {:ok, window} = Foglet.Posts.list_reader_window_for(poster, thread.id)
      assert Enum.map(window.posts, fn row -> row.id end) == [post.id]
    end

    test "actor-aware reader window allows nil guests public board posts" do
      category = category_fixture()
      board = board_fixture(category, %{readable_by: :public})
      allow_board_server!(board.id)
      poster = user_fixture()

      assert {:ok, %{thread: thread, post: post}} =
               Foglet.Threads.create_thread(board.id, poster.id, %{
                 title: "Public",
                 body: "Visible"
               })

      assert {:ok, fetched} = Foglet.Posts.fetch_readable_post(nil, post.id)
      assert fetched.id == post.id
      assert {:ok, window} = Foglet.Posts.list_reader_window_for(nil, thread.id)
      assert Enum.map(window.posts, fn row -> row.id end) == [post.id]
    end
  end

  describe "list_reader_window/2" do
    test "returns a bounded initial window with ascending message numbers and next metadata" do
      {_board, user, thread, _posts} = setup_thread_with_posts(5)

      window = Foglet.Posts.list_reader_window(thread.id, limit: 2)

      assert Enum.map(window.posts, & &1.message_number) == [1, 2]
      assert Enum.all?(window.posts, &(&1.user.id == user.id))
      assert window.first_message_number == 1
      assert window.last_message_number == 2
      refute window.has_previous?
      assert window.has_next?
      assert window.direction == :initial
    end

    test "moves forward and backward with message-number cursors" do
      {_board, _user, thread, _posts} = setup_thread_with_posts(5)

      first_window = Foglet.Posts.list_reader_window(thread.id, limit: 2)

      next_window =
        Foglet.Posts.list_reader_window(thread.id,
          direction: :next,
          after_message_number: first_window.last_message_number,
          limit: 2
        )

      assert Enum.map(next_window.posts, & &1.message_number) == [3, 4]
      assert next_window.first_message_number == 3
      assert next_window.last_message_number == 4
      assert next_window.has_previous?
      assert next_window.has_next?

      previous_window =
        Foglet.Posts.list_reader_window(thread.id,
          direction: :previous,
          before_message_number: next_window.first_message_number,
          limit: 2
        )

      assert Enum.map(previous_window.posts, & &1.message_number) == [1, 2]
      assert previous_window.first_message_number == 1
      assert previous_window.last_message_number == 2
      refute previous_window.has_previous?
      assert previous_window.has_next?
    end

    test "returns the newest bounded window in ascending order" do
      {_board, _user, thread, _posts} = setup_thread_with_posts(5)

      last_window =
        Foglet.Posts.list_reader_window(thread.id,
          direction: :last,
          limit: 2
        )

      assert Enum.map(last_window.posts, & &1.message_number) == [4, 5]
      assert last_window.first_message_number == 4
      assert last_window.last_message_number == 5
      assert last_window.has_previous?
      refute last_window.has_next?
      assert last_window.direction == :last
    end

    test "includes soft-deleted posts in reader windows" do
      {_board, user, thread, posts} = setup_thread_with_posts(5)
      deleted_post = Enum.find(posts, &(&1.message_number == 3))

      # delete_post(deleted_post) then list_reader_window(...) must preserve tombstones.
      {:ok, _deleted} = Foglet.Posts.delete_post(deleted_post)

      window =
        Foglet.Posts.list_reader_window(thread.id,
          direction: :next,
          after_message_number: 1,
          limit: 3
        )

      assert Enum.map(window.posts, & &1.message_number) == [2, 3, 4]

      listed_deleted_post = Enum.find(window.posts, &(&1.id == deleted_post.id))
      assert listed_deleted_post.deleted_at != nil
      assert listed_deleted_post.user.id == user.id
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

    # Phase 47 R1 (D-23): the legacy unbounded list-posts tombstone-semantics
    # tests were deleted along with the unbounded reader API itself. Phase 44
    # D-13/D-14 already locks tombstone behavior coverage through
    # `list_reader_window/2` — see the reader window posts test.
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

  describe "search_readable_posts/2" do
    test "returns bounded readable post payloads for active actors" do
      board = setup_board_with_server(%{slug: "search-public"})
      author = active_user_fixture(%{handle: "search_author"})
      {thread, root} = setup_thread(board, author)

      {:ok, match} =
        Foglet.Posts.create_reply(thread.id, board.id, author.id, %{
          body: "needles are easier to find with full text search"
        })

      {:ok, other} =
        Foglet.Posts.create_reply(thread.id, board.id, author.id, %{
          body: "another needles row for pagination"
        })

      results = Foglet.Posts.search_readable_posts(author, query: "needles", limit: 1)

      assert [
               %{
                 board: result_board,
                 thread: result_thread,
                 post: result_post,
                 author: result_author
               }
             ] =
               results

      assert result_board.id == board.id
      assert result_thread.id == thread.id
      assert result_author.id == author.id
      assert result_post.id in [match.id, other.id]
      assert hd(results).around_message_number == result_post.message_number
      assert hd(results).snippet =~ "needles"

      all_results = Foglet.Posts.search_readable_posts(author, query: "needles", limit: 10)
      assert Enum.map(all_results, & &1.post.id) |> Enum.sort() == Enum.sort([match.id, other.id])
      refute Enum.any?(all_results, &(&1.post.id == root.id))
    end

    test "filters unreadable member boards from guests at query level" do
      public_board = setup_board_with_server(%{slug: "public-search", readable_by: :public})
      private_board = setup_board_with_server(%{slug: "private-search", readable_by: :members})
      author = active_user_fixture()

      {public_thread, _public_root} = setup_thread(public_board, author)
      {private_thread, _private_root} = setup_thread(private_board, author)

      {:ok, public_post} =
        Foglet.Posts.create_reply(public_thread.id, public_board.id, author.id, %{
          body: "shared lantern keyword"
        })

      {:ok, private_post} =
        Foglet.Posts.create_reply(private_thread.id, private_board.id, author.id, %{
          body: "private lantern keyword"
        })

      guest_results = Foglet.Posts.search_readable_posts(nil, query: "lantern", limit: 10)
      assert Enum.map(guest_results, & &1.post.id) == [public_post.id]
      refute Enum.any?(guest_results, &(&1.post.id == private_post.id))

      member_results = Foglet.Posts.search_readable_posts(author, query: "lantern", limit: 10)

      assert Enum.map(member_results, & &1.post.id) |> Enum.sort() ==
               Enum.sort([public_post.id, private_post.id])
    end

    test "excludes archived boards, deleted threads, and deleted post bodies" do
      active_board = setup_board_with_server(%{slug: "active-search"})
      archived_board = setup_board_with_server(%{slug: "archived-search"})
      author = active_user_fixture()
      sysop = active_user_fixture(%{role: :sysop})

      {active_thread, _root} = setup_thread(active_board, author)
      {deleted_thread, _deleted_root} = setup_thread(active_board, author)
      {archived_thread, _archived_root} = setup_thread(archived_board, author)

      {:ok, visible} =
        Foglet.Posts.create_reply(active_thread.id, active_board.id, author.id, %{
          body: "visible cicada keyword"
        })

      {:ok, deleted_post} =
        Foglet.Posts.create_reply(active_thread.id, active_board.id, author.id, %{
          body: "deleted cicada secret"
        })

      {:ok, hidden_by_thread} =
        Foglet.Posts.create_reply(deleted_thread.id, active_board.id, author.id, %{
          body: "thread cicada hidden"
        })

      {:ok, hidden_by_archive} =
        Foglet.Posts.create_reply(archived_thread.id, archived_board.id, author.id, %{
          body: "archived cicada hidden"
        })

      {:ok, _deleted_post} = Foglet.Posts.delete_post(deleted_post)
      {:ok, _deleted_thread} = Foglet.Threads.delete_thread(deleted_thread)
      {:ok, _archived_board} = Foglet.Boards.archive_board(sysop, archived_board)

      results = Foglet.Posts.search_readable_posts(sysop, query: "cicada", limit: 10)
      assert Enum.map(results, & &1.post.id) == [visible.id]

      refute Enum.any?(
               results,
               &(&1.post.id in [deleted_post.id, hidden_by_thread.id, hidden_by_archive.id])
             )
    end

    test "supports board, author, title, date, and offset filters" do
      board = setup_board_with_server(%{slug: "filter-search"})
      other_board = setup_board_with_server(%{slug: "other-filter-search"})
      author = active_user_fixture(%{handle: "filter_author"})
      other_author = active_user_fixture(%{handle: "other_filter_author"})

      {thread, _root} = setup_thread(board, author)

      {:ok, updated_thread} =
        thread
        |> Ecto.Changeset.change(title: "Signal Thread")
        |> Repo.update()

      {other_thread, _other_root} = setup_thread(other_board, other_author)

      {:ok, matching_post} =
        Foglet.Posts.create_reply(updated_thread.id, board.id, author.id, %{
          body: "signal filtertoken"
        })

      {:ok, _wrong_board} =
        Foglet.Posts.create_reply(other_thread.id, other_board.id, author.id, %{
          body: "signal filtertoken"
        })

      {:ok, _wrong_author} =
        Foglet.Posts.create_reply(updated_thread.id, board.id, other_author.id, %{
          body: "signal filtertoken"
        })

      after_time = DateTime.add(matching_post.inserted_at, -1, :second)
      before_time = DateTime.add(matching_post.inserted_at, 1, :second)

      assert [%{post: %{id: post_id}}] =
               Foglet.Posts.search_readable_posts(author,
                 query: "filtertoken",
                 board_slug: "FILTER-SEARCH",
                 author_handle: "FILTER_AUTHOR",
                 thread_title: "signal",
                 inserted_after: after_time,
                 inserted_before: before_time,
                 limit: 10
               )

      assert post_id == matching_post.id

      assert [] =
               Foglet.Posts.search_readable_posts(author,
                 query: "filtertoken",
                 board_slug: "filter-search",
                 author_handle: "filter_author",
                 thread_title: "signal",
                 inserted_after: DateTime.add(matching_post.inserted_at, 1, :second)
               )

      assert [] =
               Foglet.Posts.search_readable_posts(author,
                 query: "filtertoken",
                 board_slug: "filter-search",
                 author_handle: "filter_author",
                 thread_title: "signal",
                 limit: 1,
                 offset: 1
               )
    end
  end

  describe "fetch_readable_post_by_board_slug_and_message_number/3" do
    test "returns route payload by board slug and stable message number" do
      board = setup_board_with_server(%{slug: "direct-search"})
      author = active_user_fixture()
      {thread, _root} = setup_thread(board, author)

      {:ok, post} =
        Foglet.Posts.create_reply(thread.id, board.id, author.id, %{body: "jump target"})

      assert {:ok, payload} =
               Foglet.Posts.fetch_readable_post_by_board_slug_and_message_number(
                 author,
                 "DIRECT-SEARCH",
                 post.message_number
               )

      assert payload.board.id == board.id
      assert payload.thread.id == thread.id
      assert payload.post.id == post.id
      assert payload.around_message_number == post.message_number
    end

    test "does not leak private, missing, archived, malformed, or deleted-thread targets" do
      private_board = setup_board_with_server(%{slug: "direct-private", readable_by: :members})
      archived_board = setup_board_with_server(%{slug: "direct-archived"})
      author = active_user_fixture()
      sysop = active_user_fixture(%{role: :sysop})

      {private_thread, _private_root} = setup_thread(private_board, author)
      {archived_thread, _archived_root} = setup_thread(archived_board, author)
      {deleted_thread, _deleted_root} = setup_thread(private_board, author)

      {:ok, private_post} =
        Foglet.Posts.create_reply(private_thread.id, private_board.id, author.id, %{
          body: "private jump"
        })

      {:ok, archived_post} =
        Foglet.Posts.create_reply(archived_thread.id, archived_board.id, author.id, %{
          body: "archived jump"
        })

      {:ok, deleted_thread_post} =
        Foglet.Posts.create_reply(deleted_thread.id, private_board.id, author.id, %{
          body: "deleted thread jump"
        })

      {:ok, _deleted_thread} = Foglet.Threads.delete_thread(deleted_thread)
      {:ok, _archived_board} = Foglet.Boards.archive_board(sysop, archived_board)

      assert {:error, :not_found} =
               Foglet.Posts.fetch_readable_post_by_board_slug_and_message_number(
                 nil,
                 "direct-private",
                 private_post.message_number
               )

      assert {:error, :not_found} =
               Foglet.Posts.fetch_readable_post_by_board_slug_and_message_number(
                 author,
                 "direct-archived",
                 archived_post.message_number
               )

      assert {:error, :not_found} =
               Foglet.Posts.fetch_readable_post_by_board_slug_and_message_number(
                 author,
                 "direct-private",
                 deleted_thread_post.message_number
               )

      assert {:error, :not_found} =
               Foglet.Posts.fetch_readable_post_by_board_slug_and_message_number(
                 author,
                 "direct-private",
                 999_999
               )

      assert {:error, :not_found} =
               Foglet.Posts.fetch_readable_post_by_board_slug_and_message_number(
                 author,
                 "direct-private",
                 0
               )
    end

    test "allows tombstone direct lookup without exposing deleted body through search" do
      board = setup_board_with_server(%{slug: "direct-tombstone"})
      author = active_user_fixture()
      {thread, _root} = setup_thread(board, author)

      {:ok, post} =
        Foglet.Posts.create_reply(thread.id, board.id, author.id, %{body: "tombstone secretword"})

      {:ok, _deleted_post} = Foglet.Posts.delete_post(post)

      assert {:ok, payload} =
               Foglet.Posts.fetch_readable_post_by_board_slug_and_message_number(
                 nil,
                 "direct-tombstone",
                 post.message_number
               )

      assert payload.post.id == post.id
      assert payload.post.deleted_at
      assert [] = Foglet.Posts.search_readable_posts(nil, query: "secretword", limit: 10)
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
