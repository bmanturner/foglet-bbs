defmodule Foglet.BoardChat.EphemeralTest do
  use ExUnit.Case, async: false

  alias Foglet.Accounts.User
  alias Foglet.BoardChat
  alias Foglet.BoardChat.Ephemeral
  alias Foglet.BoardChat.Ephemeral.Room
  alias Foglet.BoardChat.Ephemeral.Supervisor, as: EphemeralSupervisor
  alias Foglet.Boards.Board

  defp build_board(attrs \\ %{}) do
    %Board{
      id: Ecto.UUID.generate(),
      slug: "general",
      name: "General",
      chat_enabled: true,
      chat_storage_mode: :ephemeral,
      chat_message_ttl_seconds: 60
    }
    |> struct!(attrs)
  end

  describe "Supervisor.ensure_room/2" do
    test "lazily starts a Room and is idempotent" do
      board = build_board()
      {:ok, pid} = EphemeralSupervisor.ensure_room(board.id, ttl_seconds: 60)
      assert is_pid(pid)
      assert Process.alive?(pid)
      {:ok, ^pid} = EphemeralSupervisor.ensure_room(board.id, ttl_seconds: 60)
      EphemeralSupervisor.stop_room(board.id)
    end
  end

  describe "Ephemeral.post/recent" do
    test "round-trips a message through the facade" do
      board = build_board()
      user_id = Ecto.UUID.generate()

      {:ok, msg} = Ephemeral.post(board, user_id, "hello")
      assert [^msg] = Ephemeral.recent(board)

      EphemeralSupervisor.stop_room(board.id)
    end

    test "uses the Board's TTL when starting the Room" do
      now_ref = :counters.new(1, [])
      :counters.put(now_ref, 1, 1_000)

      board = build_board(%{chat_message_ttl_seconds: 5})
      user_id = Ecto.UUID.generate()

      {:ok, _} =
        Ephemeral.post(board, user_id, "expires", now_fn: fn -> :counters.get(now_ref, 1) end)

      :counters.put(now_ref, 1, 1_010)

      assert Ephemeral.recent(board) == []
      EphemeralSupervisor.stop_room(board.id)
    end

    test "rejects boards with chat_enabled = false" do
      board = build_board(%{chat_enabled: false})
      user_id = Ecto.UUID.generate()

      assert {:error, :chat_disabled} = Ephemeral.post(board, user_id, "nope")
      assert Ephemeral.recent(board) == []
    end

    test "rejects boards configured for permanent storage" do
      board = build_board(%{chat_storage_mode: :permanent})
      user_id = Ecto.UUID.generate()

      assert {:error, :not_ephemeral} = Ephemeral.post(board, user_id, "wrong backend")
    end
  end

  describe "Foglet.BoardChat dispatch (ephemeral path)" do
    test "ephemeral storage mode routes through the in-memory backend" do
      board = build_board()
      user = %User{id: Ecto.UUID.generate()}

      {:ok, msg} = BoardChat.post(board, user, "via facade")
      assert [^msg] = BoardChat.recent(board)
      assert msg.user_id == user.id
      assert msg.board_id == board.id

      assert is_pid(Room.whereis(board.id)),
             "ephemeral Room should be running for board #{board.id}"

      EphemeralSupervisor.stop_room(board.id)
    end
  end
end
