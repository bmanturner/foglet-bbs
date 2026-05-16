defmodule Foglet.BoardFeedsTest do
  use FogletBbs.DataCase, async: false

  import FogletBbs.BoardsFixtures

  alias Foglet.BoardFeeds
  alias Foglet.BoardFeeds.FetchResult
  alias FogletBbs.Repo

  defp board! do
    category = category_fixture()
    board_fixture(category)
  end

  defp actor!(role) do
    FogletBbs.AccountsFixtures.user_fixture()
    |> Ecto.Changeset.change(role: role)
    |> Repo.update!()
  end

  defp rss_body do
    """
    <?xml version="1.0"?>
    <rss version="2.0"><channel><title>Example RSS</title>
      <item><guid>one</guid><title>Hello <b>RSS</b>\e[31m</title><link>https://example.com/one</link><description><![CDATA[<p>Summary &amp; notes</p>\u001b[2J]]></description><pubDate>Wed, 13 May 2026 10:00:00 GMT</pubDate><author>writer</author></item>
      <item><guid>one</guid><title>Duplicate</title><link>https://example.com/dup</link></item>
    </channel></rss>
    """
  end

  defp atom_body do
    """
    <feed xmlns="http://www.w3.org/2005/Atom"><title>Atom Feed</title>
      <entry><id>tag:example,2026:1</id><title>Atom Item</title><link href="https://example.com/a"/><summary>Atom summary</summary><updated>2026-05-13T10:00:00Z</updated><author><name>Ada</name></author></entry>
    </feed>
    """
  end

  test "authorized sysop validates and creates RSS feeds with sanitized cached items and dedupe" do
    board = board!()
    actor = actor!(:sysop)

    fetcher = fn "https://example.com/feed.xml" ->
      {:ok, %FetchResult{url: "https://example.com/feed.xml", body: rss_body()}}
    end

    assert {:ok, feed} =
             BoardFeeds.create_feed(
               actor,
               board.id,
               %{url: "https://example.com/feed.xml", cache_ttl_seconds: 900},
               fetcher: fetcher
             )

    assert feed.title == "Example RSS"

    items = BoardFeeds.list_cached_items(actor, board.id)
    assert length(items) == 1
    [item] = items
    assert item.title == "Hello RSS"
    assert item.summary == "Summary & notes"
    refute item.title =~ "\e"
    refute item.summary =~ "<p>"
  end

  test "parses Atom feeds" do
    board = board!()
    actor = actor!(:sysop)

    fetcher = fn _ ->
      {:ok, %FetchResult{url: "https://example.com/atom.xml", body: atom_body()}}
    end

    assert {:ok, _feed} =
             BoardFeeds.create_feed(actor, board.id, %{url: "https://example.com/atom.xml"},
               fetcher: fetcher
             )

    assert [%{title: "Atom Item", author: "Ada"}] = BoardFeeds.list_cached_items(actor, board.id)
  end

  test "rejects invalid feed bodies and unsafe URLs" do
    board = board!()
    actor = actor!(:sysop)

    assert {:error, :unsafe_url} =
             BoardFeeds.create_feed(actor, board.id, %{url: "file:///etc/passwd"})

    assert {:error, :unsafe_url} =
             BoardFeeds.create_feed(actor, board.id, %{url: "http://127.0.0.1/feed"})

    fetcher = fn _ ->
      {:ok, %FetchResult{url: "https://example.com/not-feed", body: "<html>nope</html>"}}
    end

    assert {:error, :invalid_feed} =
             BoardFeeds.create_feed(actor, board.id, %{url: "https://example.com/not-feed"},
               fetcher: fetcher
             )
  end

  test "rejects fetches that resolve through a private redirect target" do
    board = board!()
    actor = actor!(:sysop)

    redirecting_fetcher = fn "https://example.com/feed" ->
      {:ok, %FetchResult{url: "http://127.0.0.1/private-feed", body: rss_body()}}
    end

    assert {:error, :unsafe_url} =
             BoardFeeds.create_feed(actor, board.id, %{url: "https://example.com/feed"},
               fetcher: redirecting_fetcher
             )
  end

  test "ttl skips unexpired refreshes and refreshes expired feeds" do
    board = board!()
    actor = actor!(:sysop)
    calls = :counters.new(1, [])

    fetcher = fn _ ->
      :counters.add(calls, 1, 1)
      {:ok, %FetchResult{url: "https://example.com/feed", body: rss_body()}}
    end

    assert {:ok, feed} =
             BoardFeeds.create_feed(
               actor,
               board.id,
               %{url: "https://example.com/feed", cache_ttl_seconds: 3600},
               fetcher: fetcher
             )

    assert {:ok, :fresh} = BoardFeeds.refresh_feed(actor, feed.id, fetcher: fetcher)
    assert :counters.get(calls, 1) == 1
    expired = DateTime.add(DateTime.utc_now(), -7200, :second)
    feed |> Ecto.Changeset.change(last_fetched_at: expired) |> Repo.update!()
    assert {:ok, :refreshed} = BoardFeeds.refresh_feed(actor, feed.id, fetcher: fetcher)
    assert :counters.get(calls, 1) == 2
  end

  test "failed expired refresh keeps stale cached items and records error" do
    board = board!()
    actor = actor!(:sysop)

    ok_fetcher = fn _ ->
      {:ok, %FetchResult{url: "https://example.com/feed", body: rss_body()}}
    end

    assert {:ok, feed} =
             BoardFeeds.create_feed(actor, board.id, %{url: "https://example.com/feed"},
               fetcher: ok_fetcher
             )

    feed
    |> Ecto.Changeset.change(last_fetched_at: DateTime.add(DateTime.utc_now(), -7200, :second))
    |> Repo.update!()

    bad_fetcher = fn _ -> {:error, :timeout} end
    assert {:error, :timeout} = BoardFeeds.refresh_feed(actor, feed.id, fetcher: bad_fetcher)
    assert [_] = BoardFeeds.list_cached_items(actor, board.id)
    assert Repo.reload!(feed).last_error =~ "timeout"
  end

  test "permission denied for regular users managing feeds" do
    board = board!()

    assert {:error, :forbidden} =
             BoardFeeds.create_feed(actor!(:user), board.id, %{url: "https://example.com/feed"})
  end

  test "reader feed lists follow board readability including guests and inactive users" do
    category = category_fixture()
    public_board = board_fixture(category, %{readable_by: :public})
    members_board = board_fixture(category, %{readable_by: :members})
    actor = actor!(:sysop)

    fetcher = fn _ ->
      {:ok, %FetchResult{url: "https://example.com/feed", body: rss_body()}}
    end

    assert {:ok, _feed} =
             BoardFeeds.create_feed(actor, public_board.id, %{url: "https://example.com/feed"},
               fetcher: fetcher
             )

    assert {:ok, _feed} =
             BoardFeeds.create_feed(actor, members_board.id, %{url: "https://example.com/feed"},
               fetcher: fetcher
             )

    assert [_] = BoardFeeds.list_feeds(nil, public_board.id)
    assert [_] = BoardFeeds.list_cached_items(nil, public_board.id)
    assert [] = BoardFeeds.list_feeds(nil, members_board.id)
    assert [] = BoardFeeds.list_cached_items(nil, members_board.id)

    inactive_user =
      actor!(:user)
      |> Ecto.Changeset.change(status: :suspended)
      |> Repo.update!()

    assert [] = BoardFeeds.list_feeds(inactive_user, members_board.id)
    assert [] = BoardFeeds.list_cached_items(inactive_user, members_board.id)
  end
end
