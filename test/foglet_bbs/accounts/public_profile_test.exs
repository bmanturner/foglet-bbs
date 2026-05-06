defmodule Foglet.Accounts.PublicProfileTest do
  use FogletBbs.DataCase, async: false

  import FogletBbs.BoardsFixtures, only: [board_fixture: 1, category_fixture: 0, user_fixture: 0]

  alias Ecto.Adapters.SQL.Sandbox
  alias Foglet.Accounts.PublicProfile
  alias Foglet.Sessions.PresenceSummary
  alias FogletBbs.Repo

  defmodule OfflineSessions do
    def lookup_session(_user_id), do: {:error, :not_found}
  end

  defp allow_board_server!(board_id) do
    [{pid, _}] = Registry.lookup(Foglet.BoardRegistry, board_id)
    Sandbox.allow(Repo, self(), pid)
    pid
  end

  defp board_with_server do
    category = category_fixture()
    board = board_fixture(category)
    allow_board_server!(board.id)
    board
  end

  defp thread_with_root(board, author) do
    {:ok, %{thread: thread, post: root}} =
      Foglet.Threads.create_thread(board.id, author.id, %{title: "Profile karma", body: "Root"})

    {thread, root}
  end

  test "from_user/2 whitelists public profile fields and excludes private/operator fields" do
    user = %{
      id: "u1",
      handle: "alice",
      handle_color: "#ff8800",
      role: :sysop,
      tagline: "Terminal local",
      location: "The Grid",
      post_count: 42,
      karma: 11,
      inserted_at: ~U[2026-04-01 00:00:00Z],
      last_seen_at: ~U[2026-04-02 00:00:00Z],
      real_name: "Private Name",
      email: "alice@example.test",
      password_hash: "secret",
      confirmed_at: ~U[2026-04-01 00:00:00Z]
    }

    profile = PublicProfile.from_user(user, sessions: OfflineSessions)

    assert %PublicProfile{
             user_id: "u1",
             handle: "alice",
             handle_color: "#ff8800",
             role: :sysop,
             tagline: "Terminal local",
             location: "The Grid",
             post_count: 42,
             karma: 11,
             presence: %PresenceSummary{activity: :offline, online?: false}
           } = profile

    refute Map.has_key?(profile, :real_name)
    refute Map.has_key?(profile, :email)
    refute Map.has_key?(profile, :password_hash)
    refute Map.has_key?(profile, :confirmed_at)
  end

  test "load/2 counts all upvote rows across multiple posts authored by the viewed user" do
    board = board_with_server()
    author = user_fixture()
    voter_1 = user_fixture()
    voter_2 = user_fixture()
    outsider = user_fixture()

    {thread, root} = thread_with_root(board, author)
    {:ok, reply} = Foglet.Posts.create_reply(thread.id, board.id, author.id, %{body: "Reply"})

    {:ok, outsider_post} =
      Foglet.Posts.create_reply(thread.id, board.id, outsider.id, %{body: "Other"})

    assert {:ok, %{upvote_count: 1}} = Foglet.Posts.toggle_upvote(voter_1.id, root.id)
    assert {:ok, %{upvote_count: 2}} = Foglet.Posts.toggle_upvote(voter_2.id, root.id)
    assert {:ok, %{upvote_count: 1}} = Foglet.Posts.toggle_upvote(voter_1.id, reply.id)
    assert {:ok, %{upvote_count: 1}} = Foglet.Posts.toggle_upvote(voter_1.id, outsider_post.id)

    assert {:ok, %PublicProfile{karma: 3}} =
             PublicProfile.load(author.id, sessions: OfflineSessions)
  end

  test "load/2 returns zero karma for a user with posts but no upvotes" do
    board = board_with_server()
    author = user_fixture()

    thread_with_root(board, author)

    assert {:ok, %PublicProfile{karma: 0}} =
             PublicProfile.load(author.id, sessions: OfflineSessions)
  end

  test "load/2 returns zero karma for a user with no posts" do
    user = user_fixture()

    assert {:ok, %PublicProfile{karma: 0}} =
             PublicProfile.load(user.id, sessions: OfflineSessions)
  end
end
