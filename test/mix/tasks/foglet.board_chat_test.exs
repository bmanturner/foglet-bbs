defmodule Mix.Tasks.Foglet.BoardChatTest do
  use FogletBbs.DataCase, async: false

  import ExUnit.CaptureIO

  alias Foglet.Boards.Board
  alias FogletBbs.AccountsFixtures
  alias FogletBbs.BoardsFixtures
  alias FogletBbs.Repo

  setup do
    Mix.shell(Mix.Shell.IO)
    :ok
  end

  defp sysop_fixture(handle) do
    AccountsFixtures.user_fixture(%{handle: handle})
    |> Ecto.Changeset.change(role: :sysop)
    |> Repo.update!()
  end

  defp reload(%Board{id: id}), do: Repo.get!(Board, id)

  describe "show" do
    test "prints chat settings for a known board" do
      category = BoardsFixtures.category_fixture()

      _board =
        BoardsFixtures.board_fixture(category, %{
          slug: "general",
          chat_enabled: true,
          chat_storage_mode: :ephemeral,
          chat_message_ttl_seconds: 3600
        })

      output =
        capture_io(fn ->
          Mix.Tasks.Foglet.BoardChat.run(["show", "--board", "general"])
        end)

      assert output =~ "general"
      assert output =~ "chat_enabled:             true"
      assert output =~ "chat_storage_mode:        ephemeral"
      assert output =~ "chat_message_ttl_seconds: 3600"
    end

    test "prints settings for an archived board with [archived] tag" do
      category = BoardsFixtures.category_fixture()
      board = BoardsFixtures.board_fixture(category, %{slug: "old"})
      Repo.update!(Ecto.Changeset.change(board, archived: true))

      output =
        capture_io(fn ->
          Mix.Tasks.Foglet.BoardChat.run(["show", "--board", "old"])
        end)

      assert output =~ "old [archived]"
    end

    test "unknown board exits non-zero" do
      output =
        capture_io(:stderr, fn ->
          assert catch_exit(Mix.Tasks.Foglet.BoardChat.run(["show", "--board", "nope"])) ==
                   {:shutdown, 1}
        end)

      assert output =~ "Unknown board"
    end
  end

  describe "enable / disable" do
    test "enables chat for a board" do
      sysop = sysop_fixture("opsysop1")
      category = BoardsFixtures.category_fixture()
      board = BoardsFixtures.board_fixture(category, %{slug: "lounge", chat_enabled: false})

      output =
        capture_io(fn ->
          Mix.Tasks.Foglet.BoardChat.run([
            "enable",
            "--board",
            "lounge",
            "--actor",
            sysop.handle
          ])
        end)

      assert output =~ "Chat enabled for lounge"
      assert reload(board).chat_enabled == true
    end

    test "disables chat for a board that has it on" do
      sysop = sysop_fixture("opsysop2")
      category = BoardsFixtures.category_fixture()

      board =
        BoardsFixtures.board_fixture(category, %{slug: "noisy", chat_enabled: true})

      output =
        capture_io(fn ->
          Mix.Tasks.Foglet.BoardChat.run([
            "disable",
            "--board",
            "noisy",
            "--actor",
            sysop.handle
          ])
        end)

      assert output =~ "Chat disabled for noisy"
      assert reload(board).chat_enabled == false
    end

    test "enabling already-enabled chat reports unchanged and does not call update" do
      sysop = sysop_fixture("opsysop3")
      category = BoardsFixtures.category_fixture()
      _board = BoardsFixtures.board_fixture(category, %{slug: "warm", chat_enabled: true})

      output =
        capture_io(fn ->
          Mix.Tasks.Foglet.BoardChat.run([
            "enable",
            "--board",
            "warm",
            "--actor",
            sysop.handle
          ])
        end)

      assert output =~ "No change"
      assert output =~ "warm already has chat enabled"
    end

    test "non-sysop actor exits forbidden" do
      regular = AccountsFixtures.user_fixture(%{handle: "notasysop"})
      category = BoardsFixtures.category_fixture()
      _board = BoardsFixtures.board_fixture(category, %{slug: "private"})

      output =
        capture_io(:stderr, fn ->
          assert catch_exit(
                   Mix.Tasks.Foglet.BoardChat.run([
                     "enable",
                     "--board",
                     "private",
                     "--actor",
                     regular.handle
                   ])
                 ) == {:shutdown, 1}
        end)

      assert output =~ "Forbidden"
    end

    test "archived board refuses mutation" do
      sysop = sysop_fixture("opsysop4")
      category = BoardsFixtures.category_fixture()
      board = BoardsFixtures.board_fixture(category, %{slug: "stale"})
      Repo.update!(Ecto.Changeset.change(board, archived: true))

      output =
        capture_io(:stderr, fn ->
          assert catch_exit(
                   Mix.Tasks.Foglet.BoardChat.run([
                     "enable",
                     "--board",
                     "stale",
                     "--actor",
                     sysop.handle
                   ])
                 ) == {:shutdown, 1}
        end)

      assert output =~ "archived"
    end

    test "unknown actor exits non-zero" do
      category = BoardsFixtures.category_fixture()
      _board = BoardsFixtures.board_fixture(category, %{slug: "absent-actor"})

      output =
        capture_io(:stderr, fn ->
          assert catch_exit(
                   Mix.Tasks.Foglet.BoardChat.run([
                     "enable",
                     "--board",
                     "absent-actor",
                     "--actor",
                     "ghost"
                   ])
                 ) == {:shutdown, 1}
        end)

      assert output =~ "Unknown actor"
    end
  end

  describe "set-mode" do
    test "switches storage mode to permanent" do
      sysop = sysop_fixture("opsysop5")
      category = BoardsFixtures.category_fixture()

      board =
        BoardsFixtures.board_fixture(category, %{
          slug: "store-perm",
          chat_storage_mode: :ephemeral
        })

      output =
        capture_io(fn ->
          Mix.Tasks.Foglet.BoardChat.run([
            "set-mode",
            "--board",
            "store-perm",
            "--mode",
            "permanent",
            "--actor",
            sysop.handle
          ])
        end)

      assert output =~ "Storage mode set to permanent for store-perm"
      assert reload(board).chat_storage_mode == :permanent
    end

    test "rejects an invalid mode" do
      sysop = sysop_fixture("opsysop6")
      category = BoardsFixtures.category_fixture()
      _board = BoardsFixtures.board_fixture(category, %{slug: "bogus-mode"})

      output =
        capture_io(:stderr, fn ->
          assert catch_exit(
                   Mix.Tasks.Foglet.BoardChat.run([
                     "set-mode",
                     "--board",
                     "bogus-mode",
                     "--mode",
                     "telegram",
                     "--actor",
                     sysop.handle
                   ])
                 ) == {:shutdown, 1}
        end)

      assert output =~ "Invalid --mode"
    end

    test "no-op when mode is already correct" do
      sysop = sysop_fixture("opsysop7")
      category = BoardsFixtures.category_fixture()

      _board =
        BoardsFixtures.board_fixture(category, %{
          slug: "perm-already",
          chat_storage_mode: :permanent
        })

      output =
        capture_io(fn ->
          Mix.Tasks.Foglet.BoardChat.run([
            "set-mode",
            "--board",
            "perm-already",
            "--mode",
            "permanent",
            "--actor",
            sysop.handle
          ])
        end)

      assert output =~ "No change"
      assert output =~ "uses storage mode permanent"
    end
  end

  describe "set-ttl" do
    test "sets a valid ttl" do
      sysop = sysop_fixture("opsysop8")
      category = BoardsFixtures.category_fixture()

      board =
        BoardsFixtures.board_fixture(category, %{
          slug: "ttl-set",
          chat_enabled: true,
          chat_storage_mode: :ephemeral,
          chat_message_ttl_seconds: 7200
        })

      output =
        capture_io(fn ->
          Mix.Tasks.Foglet.BoardChat.run([
            "set-ttl",
            "--board",
            "ttl-set",
            "--seconds",
            "600",
            "--actor",
            sysop.handle
          ])
        end)

      assert output =~ "Ephemeral TTL set to 600s for ttl-set"
      assert reload(board).chat_message_ttl_seconds == 600
    end

    test "rejects ttl below the lower bound" do
      sysop = sysop_fixture("opsysop9")
      category = BoardsFixtures.category_fixture()
      _board = BoardsFixtures.board_fixture(category, %{slug: "ttl-low"})

      output =
        capture_io(:stderr, fn ->
          assert catch_exit(
                   Mix.Tasks.Foglet.BoardChat.run([
                     "set-ttl",
                     "--board",
                     "ttl-low",
                     "--seconds",
                     "30",
                     "--actor",
                     sysop.handle
                   ])
                 ) == {:shutdown, 1}
        end)

      assert output =~ "Invalid --seconds"
    end

    test "rejects ttl above the upper bound" do
      sysop = sysop_fixture("opsysop10")
      category = BoardsFixtures.category_fixture()
      _board = BoardsFixtures.board_fixture(category, %{slug: "ttl-high"})

      output =
        capture_io(:stderr, fn ->
          assert catch_exit(
                   Mix.Tasks.Foglet.BoardChat.run([
                     "set-ttl",
                     "--board",
                     "ttl-high",
                     "--seconds",
                     "100000",
                     "--actor",
                     sysop.handle
                   ])
                 ) == {:shutdown, 1}
        end)

      assert output =~ "Invalid --seconds"
    end
  end

  describe "argument validation" do
    test "missing --board exits non-zero" do
      output =
        capture_io(:stderr, fn ->
          assert catch_exit(Mix.Tasks.Foglet.BoardChat.run(["show"])) == {:shutdown, 1}
        end)

      assert output =~ "Missing required --board"
    end

    test "missing --actor on a mutation exits non-zero" do
      category = BoardsFixtures.category_fixture()
      _board = BoardsFixtures.board_fixture(category, %{slug: "no-actor"})

      output =
        capture_io(:stderr, fn ->
          assert catch_exit(Mix.Tasks.Foglet.BoardChat.run(["enable", "--board", "no-actor"])) ==
                   {:shutdown, 1}
        end)

      assert output =~ "Missing required --actor"
    end

    test "unknown action exits non-zero" do
      output =
        capture_io(:stderr, fn ->
          assert catch_exit(Mix.Tasks.Foglet.BoardChat.run(["wat", "--board", "x"])) ==
                   {:shutdown, 1}
        end)

      assert output =~ "Unknown action"
    end
  end
end
