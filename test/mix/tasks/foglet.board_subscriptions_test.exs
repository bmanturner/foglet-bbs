defmodule Mix.Tasks.Foglet.BoardSubscriptionsTest do
  use FogletBbs.DataCase, async: false

  import ExUnit.CaptureIO

  alias Foglet.Boards
  alias FogletBbs.AccountsFixtures
  alias FogletBbs.BoardsFixtures

  setup do
    Mix.shell(Mix.Shell.IO)
    :ok
  end

  describe "mix foglet.board_subscriptions (SUBS-04)" do
    test "lists active board subscription statuses for a user handle" do
      user = AccountsFixtures.user_fixture(%{handle: "sublist"})
      category = BoardsFixtures.category_fixture(%{name: "General"})
      subscribed = BoardsFixtures.board_fixture(category, %{slug: "joined"})
      unsubscribed = BoardsFixtures.board_fixture(category, %{slug: "open"})

      required =
        BoardsFixtures.board_fixture(category, %{
          slug: "required",
          default_subscription: true,
          required_subscription: true
        })

      {:ok, :subscribed} = Boards.subscribe_user_to_board(user, subscribed.id)
      {:ok, :subscribed} = Boards.subscribe_user_to_board(user, required.id)

      output =
        capture_io(fn ->
          Mix.Tasks.Foglet.BoardSubscriptions.run(["list", "--user", "sublist"])
        end)

      assert output =~ "General"
      assert output =~ "joined [subscribed]"
      assert output =~ "open [unsubscribed]"
      assert output =~ "required [required]"
      refute output =~ unsubscribed.id
    end

    test "subscribes a user selected by email to an active board" do
      user = AccountsFixtures.user_fixture(%{handle: "subemail", email: "subemail@example.com"})
      category = BoardsFixtures.category_fixture()
      board = BoardsFixtures.board_fixture(category, %{slug: "email-board"})

      output =
        capture_io(fn ->
          Mix.Tasks.Foglet.BoardSubscriptions.run([
            "subscribe",
            "--user",
            "subemail@example.com",
            "--board",
            "email-board"
          ])
        end)

      assert output =~ "Subscribed subemail to email-board"
      assert Enum.any?(Boards.list_subscriptions(user.id), &(&1.board_id == board.id))
    end

    test "unsubscribes an allowed board through the context API" do
      user = AccountsFixtures.user_fixture(%{handle: "unsubuser"})
      category = BoardsFixtures.category_fixture()
      board = BoardsFixtures.board_fixture(category, %{slug: "leave-me"})
      {:ok, :subscribed} = Boards.subscribe_user_to_board(user, board.id)

      output =
        capture_io(fn ->
          Mix.Tasks.Foglet.BoardSubscriptions.run([
            "unsubscribe",
            "--user",
            "unsubuser",
            "--board",
            "leave-me"
          ])
        end)

      assert output =~ "Unsubscribed unsubuser from leave-me"
      refute Enum.any?(Boards.list_subscriptions(user.id), &(&1.board_id == board.id))
    end

    test "refuses required-board unsubscribe with explicit output" do
      user = AccountsFixtures.user_fixture(%{handle: "requireduser"})
      category = BoardsFixtures.category_fixture()

      board =
        BoardsFixtures.board_fixture(category, %{
          slug: "stay-required",
          default_subscription: true,
          required_subscription: true
        })

      {:ok, :subscribed} = Boards.subscribe_user_to_board(user, board.id)

      output =
        capture_io(:stderr, fn ->
          assert catch_exit(
                   Mix.Tasks.Foglet.BoardSubscriptions.run([
                     "unsubscribe",
                     "--user",
                     "requireduser",
                     "--board",
                     "stay-required"
                   ])
                 ) == {:shutdown, 1}
        end)

      assert output =~ "required subscription"
      assert Enum.any?(Boards.list_subscriptions(user.id), &(&1.board_id == board.id))
    end

    test "unknown user exits non-zero with explicit output" do
      output =
        capture_io(:stderr, fn ->
          assert catch_exit(Mix.Tasks.Foglet.BoardSubscriptions.run(["list", "--user", "nobody"])) ==
                   {:shutdown, 1}
        end)

      assert output =~ "Unknown user"
    end

    test "unknown board exits non-zero with explicit output" do
      _user = AccountsFixtures.user_fixture(%{handle: "unknownboarduser"})

      output =
        capture_io(:stderr, fn ->
          assert catch_exit(
                   Mix.Tasks.Foglet.BoardSubscriptions.run([
                     "subscribe",
                     "--user",
                     "unknownboarduser",
                     "--board",
                     "missing"
                   ])
                 ) == {:shutdown, 1}
        end)

      assert output =~ "Unknown board"
    end

    test "archived board exits non-zero with explicit output" do
      _user = AccountsFixtures.user_fixture(%{handle: "archiveduser"})
      category = BoardsFixtures.category_fixture()
      _board = BoardsFixtures.board_fixture(category, %{slug: "old-board", archived: true})

      output =
        capture_io(:stderr, fn ->
          assert catch_exit(
                   Mix.Tasks.Foglet.BoardSubscriptions.run([
                     "subscribe",
                     "--user",
                     "archiveduser",
                     "--board",
                     "old-board"
                   ])
                 ) == {:shutdown, 1}
        end)

      assert output =~ "archived"
    end

    test "does not directly mutate subscriptions in the task source" do
      source = File.read!("lib/mix/tasks/foglet.board_subscriptions.ex")

      refute source =~ "Repo."
      refute source =~ "Subscription.changeset"
      assert source =~ "Boards.subscribe_user_to_board"
      assert source =~ "Boards.unsubscribe_user_from_board"
    end
  end
end
