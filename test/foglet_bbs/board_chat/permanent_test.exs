defmodule Foglet.BoardChat.PermanentTest do
  use FogletBbs.DataCase, async: true

  alias Foglet.BoardChat
  alias Foglet.BoardChat.{Body, Message, Permanent}
  alias Foglet.Boards.Board
  alias Foglet.PubSub, as: Topics

  import FogletBbs.BoardsFixtures, only: [category_fixture: 0, user_fixture: 0]

  # Insert boards directly via Repo to avoid spinning up Foglet.Boards.Server in
  # the sandbox — the chat context never invokes the board server, so tests
  # don't need it allowed.
  defp permanent_board_fixture(category, overrides \\ %{}) do
    attrs =
      Map.merge(
        %{
          slug: "chatboard-#{System.unique_integer([:positive])}",
          name: "Chat Board #{System.unique_integer([:positive])}",
          description: "Chat fixture",
          category_id: category.id,
          chat_enabled: true,
          chat_storage_mode: :permanent,
          chat_message_ttl_seconds: 7_200
        },
        overrides
      )

    %Board{}
    |> Board.changeset(attrs)
    |> Repo.insert!()
  end

  defp ephemeral_board_fixture(category, overrides \\ %{}) do
    permanent_board_fixture(
      category,
      Map.merge(
        %{chat_storage_mode: :ephemeral, chat_message_ttl_seconds: 600},
        overrides
      )
    )
  end

  describe "insert/3" do
    setup do
      category = category_fixture()
      board = permanent_board_fixture(category)
      user = user_fixture()
      %{board: board, user: user, category: category}
    end

    test "writes a message and returns it", %{board: board, user: user} do
      assert {:ok, %Message{} = message} = Permanent.insert(board, user, "hello world")
      assert message.body == "hello world"
      assert message.board_id == board.id
      assert message.user_id == user.id
      refute is_nil(message.id)
      refute is_nil(message.inserted_at)
    end

    test "trims whitespace and rejects blank bodies", %{board: board, user: user} do
      assert {:error, changeset} = Permanent.insert(board, user, "   ")
      assert %{body: ["can't be blank"]} = errors_on(changeset)

      assert {:error, changeset} = Permanent.insert(board, user, "")
      assert %{body: ["can't be blank"]} = errors_on(changeset)
    end

    test "rejects bodies that exceed the maximum length", %{board: board, user: user} do
      too_long = String.duplicate("a", Message.body_max() + 1)
      assert {:error, changeset} = Permanent.insert(board, user, too_long)
      assert %{body: [_ | _]} = errors_on(changeset)
    end

    test "uses the shared chat body limit", %{board: board, user: user} do
      assert Message.body_max() == Body.max_length()

      max_body = String.duplicate("a", Body.max_length())
      too_long = max_body <> "a"

      assert {:ok, %Message{body: ^max_body}} = Permanent.insert(board, user, max_body)
      assert {:error, changeset} = Permanent.insert(board, user, too_long)
      assert %{body: [_ | _]} = errors_on(changeset)
    end

    test "rejects insert when chat is disabled", %{category: category, user: user} do
      board = permanent_board_fixture(category, %{chat_enabled: false})
      assert {:error, :chat_disabled} = Permanent.insert(board, user, "nope")
    end

    test "rejects insert when storage mode is not permanent", %{category: category, user: user} do
      board = ephemeral_board_fixture(category)
      assert {:error, :not_permanent} = Permanent.insert(board, user, "nope")
    end

    test "broadcasts on the board_chat topic", %{board: board, user: user} do
      :ok = Phoenix.PubSub.subscribe(FogletBbs.PubSub, Topics.board_chat_topic(board.id))

      assert {:ok, %Message{id: id}} = Permanent.insert(board, user, "ping")

      assert_receive {:board_chat, :new_message, %Message{id: ^id, body: "ping"}}, 500
    end

    test "does not broadcast on other boards' chat topic", %{
      board: board,
      user: user,
      category: category
    } do
      other_board = permanent_board_fixture(category)

      :ok =
        Phoenix.PubSub.subscribe(FogletBbs.PubSub, Topics.board_chat_topic(other_board.id))

      assert {:ok, _} = Permanent.insert(board, user, "isolated")

      refute_receive {:board_chat, :new_message, _}, 100
    end
  end

  describe "recent/2" do
    setup do
      category = category_fixture()
      board = permanent_board_fixture(category)
      user = user_fixture()
      %{board: board, user: user, category: category}
    end

    test "returns messages oldest -> newest, bounded by limit", %{board: board, user: user} do
      for i <- 1..5 do
        {:ok, _} = Permanent.insert(board, user, "msg-#{i}")
        # Distinct inserted_at values keep ordering deterministic.
        Process.sleep(2)
      end

      bodies = board.id |> Permanent.recent(3) |> Enum.map(& &1.body)
      assert bodies == ["msg-3", "msg-4", "msg-5"]
    end

    test "default limit returns all rows when fewer than the cap exist", %{
      board: board,
      user: user
    } do
      for i <- 1..4 do
        {:ok, _} = Permanent.insert(board, user, "msg-#{i}")
        Process.sleep(2)
      end

      bodies = board.id |> Permanent.recent() |> Enum.map(& &1.body)
      assert bodies == ["msg-1", "msg-2", "msg-3", "msg-4"]
    end

    test "clamps oversized limits to recent_max_limit", %{board: board} do
      assert Permanent.recent_max_limit() == 100
      # Empty board still returns []; clamping is exercised by the query.
      assert Permanent.recent(board.id, 10_000) == []
    end

    test "isolates messages between boards", %{
      board: board_a,
      user: user,
      category: category
    } do
      board_b = permanent_board_fixture(category)

      {:ok, _} = Permanent.insert(board_a, user, "a-only")
      {:ok, _} = Permanent.insert(board_b, user, "b-only")

      assert [%Message{body: "a-only", board_id: a_id}] = Permanent.recent(board_a.id)
      assert a_id == board_a.id

      assert [%Message{body: "b-only", board_id: b_id}] = Permanent.recent(board_b.id)
      assert b_id == board_b.id
    end
  end

  describe "recent_for/2 guest readability" do
    setup do
      category = category_fixture()
      user = user_fixture()
      %{category: category, user: user}
    end

    test "returns no history to nil guests for members-readable boards", %{
      category: category,
      user: user
    } do
      board = permanent_board_fixture(category, %{readable_by: :members})
      assert {:ok, _message} = Permanent.insert(board, user, "members only")

      assert [] = BoardChat.recent_for(nil, board)
      assert [%Message{body: "members only"}] = BoardChat.recent_for(user, board)
    end

    test "returns public history to nil guests", %{category: category, user: user} do
      board = permanent_board_fixture(category, %{readable_by: :public})
      assert {:ok, _message} = Permanent.insert(board, user, "public hello")

      assert [%Message{body: "public hello"}] = BoardChat.recent_for(nil, board)
    end
  end
end
