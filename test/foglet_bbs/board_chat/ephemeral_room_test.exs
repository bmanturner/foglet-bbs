defmodule Foglet.BoardChat.Ephemeral.RoomTest do
  use ExUnit.Case, async: false

  alias Foglet.BoardChat.Ephemeral.Room

  setup do
    board_id = "board-" <> Ecto.UUID.generate()
    user_id = "user-" <> Ecto.UUID.generate()
    other_user_id = "user-" <> Ecto.UUID.generate()

    %{board_id: board_id, user_id: user_id, other_user_id: other_user_id}
  end

  defp start_room!(board_id, opts) do
    opts =
      opts
      |> Keyword.put_new(:board_id, board_id)
      |> Keyword.put_new(:ttl_seconds, 60)
      |> Keyword.put_new(:tick_interval_ms, 1_000_000)
      |> Keyword.put_new(:idle_grace_ms, 10 * 60 * 1000)

    {:ok, pid} = Room.start_link(opts)
    on_exit_stop(pid)
    pid
  end

  defp on_exit_stop(pid) do
    ExUnit.Callbacks.on_exit(fn ->
      if Process.alive?(pid), do: GenServer.stop(pid, :normal, 1000)
    end)
  end

  describe "post/3 + recent/1" do
    test "appends messages and returns them oldest-first", %{
      board_id: board_id,
      user_id: user_id
    } do
      start_room!(board_id, [])

      {:ok, m1} = Room.post(board_id, user_id, "first")
      {:ok, m2} = Room.post(board_id, user_id, "second")

      assert [^m1, ^m2] = Room.recent(board_id)
    end

    test "broadcasts on the board chat topic", %{board_id: board_id, user_id: user_id} do
      start_room!(board_id, [])

      Phoenix.PubSub.subscribe(FogletBbs.PubSub, Foglet.PubSub.board_chat_topic(board_id))
      {:ok, msg} = Room.post(board_id, user_id, "hi")

      assert_receive {:board_chat, :new_message, ^msg}, 500
    end

    test "soft cap drops oldest entries", %{board_id: board_id, user_id: user_id} do
      start_room!(board_id, soft_cap: 3, recent_limit: 100)

      {:ok, _} = Room.post(board_id, user_id, "a")
      {:ok, _} = Room.post(board_id, user_id, "b")
      {:ok, _} = Room.post(board_id, user_id, "c")
      {:ok, _} = Room.post(board_id, user_id, "d")

      bodies = Room.recent(board_id) |> Enum.map(& &1.body)
      assert bodies == ["b", "c", "d"]
    end

    test "recent_limit caps the returned tail", %{board_id: board_id, user_id: user_id} do
      start_room!(board_id, soft_cap: 100, recent_limit: 2)

      for i <- 1..5, do: Room.post(board_id, user_id, "msg-#{i}")

      bodies = Room.recent(board_id) |> Enum.map(& &1.body)
      assert bodies == ["msg-4", "msg-5"]
    end
  end

  describe "TTL expiry" do
    test "expired messages disappear from recent", %{board_id: board_id, user_id: user_id} do
      now_ref = :counters.new(1, [])
      :counters.put(now_ref, 1, 1_000)

      start_room!(board_id,
        ttl_seconds: 30,
        now_fn: fn -> :counters.get(now_ref, 1) end
      )

      {:ok, _} = Room.post(board_id, user_id, "old")

      :counters.put(now_ref, 1, 1_000 + 31)
      {:ok, fresh} = Room.post(board_id, user_id, "new")

      msgs = Room.recent(board_id)
      assert msgs == [fresh]
    end

    test "purge tick removes expired entries even without a read", %{
      board_id: board_id,
      user_id: user_id
    } do
      now_ref = :counters.new(1, [])
      :counters.put(now_ref, 1, 1_000)

      start_room!(board_id,
        ttl_seconds: 10,
        now_fn: fn -> :counters.get(now_ref, 1) end
      )

      {:ok, _} = Room.post(board_id, user_id, "expires")

      :counters.put(now_ref, 1, 1_000 + 11)
      :ok = Room.purge_now(board_id)
      assert Room.buffer_size(board_id) == 0
    end
  end

  describe "board isolation" do
    test "two boards do not share state", %{user_id: user_id} do
      board_a = "board-" <> Ecto.UUID.generate()
      board_b = "board-" <> Ecto.UUID.generate()

      start_room!(board_a, [])
      start_room!(board_b, [])

      {:ok, _} = Room.post(board_a, user_id, "for-a")

      assert Room.recent(board_a) |> Enum.map(& &1.body) == ["for-a"]
      assert Room.recent(board_b) == []
    end
  end

  describe "server-restart wipes state" do
    test "stopping and restarting the Room yields an empty buffer", %{
      board_id: board_id,
      user_id: user_id
    } do
      pid = start_room!(board_id, [])
      {:ok, _} = Room.post(board_id, user_id, "ephemeral")
      assert length(Room.recent(board_id)) == 1

      ref = Process.monitor(pid)
      GenServer.stop(pid, :normal, 1000)
      assert_receive {:DOWN, ^ref, :process, ^pid, _}, 500

      start_room!(board_id, [])
      assert Room.recent(board_id) == []
    end
  end

  describe "idle-shutdown" do
    test "stops itself after idle_grace_ms with no traffic", %{board_id: board_id} do
      mono_ref = :counters.new(1, [])
      :counters.put(mono_ref, 1, 0)

      {:ok, pid} =
        Room.start_link(
          board_id: board_id,
          ttl_seconds: 60,
          idle_grace_ms: 100,
          tick_interval_ms: 20,
          monotonic_fn: fn -> :counters.get(mono_ref, 1) end
        )

      ref = Process.monitor(pid)

      :counters.put(mono_ref, 1, 1_000)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 500
    end

    test "post/3 resets the idle clock", %{board_id: board_id, user_id: user_id} do
      mono_ref = :counters.new(1, [])
      :counters.put(mono_ref, 1, 0)

      {:ok, pid} =
        Room.start_link(
          board_id: board_id,
          ttl_seconds: 60,
          idle_grace_ms: 100,
          tick_interval_ms: 20,
          monotonic_fn: fn -> :counters.get(mono_ref, 1) end
        )

      on_exit_stop(pid)

      # Advance the clock close to the idle threshold then post — the post
      # should reset last_traffic_at and keep the room alive.
      :counters.put(mono_ref, 1, 80)
      {:ok, _} = Room.post(board_id, user_id, "still here")

      :counters.put(mono_ref, 1, 150)
      :ok = Room.purge_now(board_id)
      assert Process.alive?(pid)
    end
  end
end
