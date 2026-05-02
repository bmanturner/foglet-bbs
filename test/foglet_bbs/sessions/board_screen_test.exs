defmodule Foglet.Sessions.BoardScreenTest do
  use ExUnit.Case, async: false

  alias Foglet.PubSub, as: Topics
  alias Foglet.Sessions.BoardScreen

  setup do
    # The application starts a singleton BoardScreen. Clear any state from
    # previous tests so per-board assertions are isolated.
    board_id = "board-" <> Ecto.UUID.generate()
    other_board_id = "board-" <> Ecto.UUID.generate()
    user_id = "user-" <> Ecto.UUID.generate()
    other_user_id = "user-" <> Ecto.UUID.generate()

    on_exit(fn ->
      # Best-effort cleanup; processes spawned in tests are linked to the
      # test pid and will be torn down.
      :ok
    end)

    %{
      board_id: board_id,
      other_board_id: other_board_id,
      user_id: user_id,
      other_user_id: other_user_id
    }
  end

  describe "track/3 + count/1 + list/1" do
    test "tracks a user once per board and returns count + list", %{
      board_id: board_id,
      user_id: user_id
    } do
      :ok = BoardScreen.track(board_id, user_id, :threads)

      assert BoardScreen.count(board_id) == 1
      assert BoardScreen.list(board_id) == [%{user_id: user_id, tab: :threads}]

      :ok = BoardScreen.untrack(board_id, user_id)
    end

    test "tab switching does not double-count", %{board_id: board_id, user_id: user_id} do
      :ok = BoardScreen.track(board_id, user_id, :threads)
      :ok = BoardScreen.update_tab(board_id, user_id, :chat)

      assert BoardScreen.count(board_id) == 1
      assert BoardScreen.list(board_id) == [%{user_id: user_id, tab: :chat}]

      :ok = BoardScreen.untrack(board_id, user_id)
    end

    test "presence is board-scoped (no cross-board leakage)", %{
      board_id: board_id,
      other_board_id: other_board_id,
      user_id: user_id
    } do
      :ok = BoardScreen.track(board_id, user_id, :chat)

      assert BoardScreen.count(board_id) == 1
      assert BoardScreen.count(other_board_id) == 0
      assert BoardScreen.list(other_board_id) == []

      :ok = BoardScreen.untrack(board_id, user_id)
    end

    test "two users on same board count as two", %{
      board_id: board_id,
      user_id: user_id,
      other_user_id: other_user_id
    } do
      task = run_tracker(board_id, other_user_id, :threads)

      :ok = BoardScreen.track(board_id, user_id, :chat)

      assert BoardScreen.count(board_id) == 2

      assert Enum.sort(Enum.map(BoardScreen.list(board_id), & &1.user_id)) ==
               Enum.sort([user_id, other_user_id])

      :ok = BoardScreen.untrack(board_id, user_id)
      stop_tracker(task)
    end
  end

  describe "untrack/2 and process exit" do
    test "untrack removes the user", %{board_id: board_id, user_id: user_id} do
      :ok = BoardScreen.track(board_id, user_id, :chat)
      :ok = BoardScreen.untrack(board_id, user_id)

      assert BoardScreen.count(board_id) == 0
      assert BoardScreen.list(board_id) == []
    end

    test "caller pid exit auto-evicts the entry", %{board_id: board_id, user_id: user_id} do
      task = run_tracker(board_id, user_id, :threads)
      assert BoardScreen.count(board_id) == 1

      stop_tracker(task)

      # Allow the BoardScreen GenServer to handle :DOWN.
      Process.sleep(20)
      assert BoardScreen.count(board_id) == 0
    end
  end

  describe "PubSub broadcasts" do
    test "join, tab_changed, and leave broadcast on board_screen topic", %{
      board_id: board_id,
      user_id: user_id
    } do
      :ok = Phoenix.PubSub.subscribe(FogletBbs.PubSub, Topics.board_screen_topic(board_id))

      :ok = BoardScreen.track(board_id, user_id, :threads)

      assert_receive {:board_screen, :join,
                      %{board_id: ^board_id, user_id: ^user_id, tab: :threads}}

      :ok = BoardScreen.update_tab(board_id, user_id, :chat)

      assert_receive {:board_screen, :tab_changed,
                      %{board_id: ^board_id, user_id: ^user_id, tab: :chat}}

      :ok = BoardScreen.untrack(board_id, user_id)
      assert_receive {:board_screen, :leave, %{board_id: ^board_id, user_id: ^user_id}}
    end
  end

  describe "Foglet.PubSub topic helpers" do
    test "board_chat_topic/1 + board_screen_topic/1 produce expected strings" do
      assert Topics.board_chat_topic("abc") == "board_chat:abc"
      assert Topics.board_screen_topic("abc") == "board_screen:abc"
    end

    test "topics distinguish boards" do
      refute Topics.board_chat_topic("a") == Topics.board_chat_topic("b")
      refute Topics.board_screen_topic("a") == Topics.board_screen_topic("b")
      refute Topics.board_chat_topic("a") == Topics.board_screen_topic("a")
    end
  end

  # --- helpers ---

  defp run_tracker(board_id, user_id, tab) do
    parent = self()

    pid =
      spawn_link(fn ->
        :ok = BoardScreen.track(board_id, user_id, tab)
        send(parent, {:tracked, self()})

        receive do
          :stop -> :ok
        end
      end)

    receive do
      {:tracked, ^pid} -> :ok
    after
      1_000 -> flunk("tracker did not register in time")
    end

    pid
  end

  defp stop_tracker(pid) do
    ref = Process.monitor(pid)
    send(pid, :stop)

    receive do
      {:DOWN, ^ref, :process, ^pid, _} -> :ok
    after
      1_000 -> :ok
    end
  end
end
