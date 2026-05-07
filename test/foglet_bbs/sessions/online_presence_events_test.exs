defmodule Foglet.Sessions.OnlinePresenceEventsTest do
  use FogletBbs.DataCase, async: false

  alias Foglet.Sessions.ActivityPresence
  alias Foglet.Sessions.BoardScreen
  alias Foglet.Sessions.DoorPresence
  alias Foglet.Sessions.Supervisor, as: SessionsSupervisor

  setup do
    Phoenix.PubSub.subscribe(FogletBbs.PubSub, Foglet.PubSub.online_presence_topic())

    %{
      user_id: Ecto.UUID.generate(),
      board: %{id: "board-" <> Ecto.UUID.generate(), name: "General"}
    }
  end

  test "authenticated session lifecycle broadcasts connect, disconnect, replacement, and guest promotion",
       %{
         user_id: user_id
       } do
    {:ok, first_pid} =
      SessionsSupervisor.start_session(user_id: user_id, handle: "alice", role: :user)

    assert_receive {:online_presence, :session_connected, %{user_id: ^user_id}}

    {:ok, second_pid} =
      SessionsSupervisor.start_session(user_id: user_id, handle: "alice2", role: :user)

    assert_receive {:online_presence, :session_disconnected, %{user_id: ^user_id}}
    assert_receive {:online_presence, :session_replaced, %{user_id: ^user_id}}
    assert_receive {:online_presence, :session_connected, %{user_id: ^user_id}}

    assert first_pid != second_pid
    assert :ok = SessionsSupervisor.terminate_session(user_id)
    assert_receive {:online_presence, :session_disconnected, %{user_id: ^user_id}}

    guest_user_id = Ecto.UUID.generate()
    {:ok, guest_pid} = SessionsSupervisor.start_guest_session()
    refute_receive {:online_presence, :session_connected, %{user_id: nil}}, 25

    user = %Foglet.Accounts.User{id: guest_user_id, handle: "guest-promoted", role: :user}
    assert :ok = SessionsSupervisor.promote_guest_session(guest_pid, user)
    assert_receive {:online_presence, :session_promoted, %{user_id: ^guest_user_id}}

    if Process.alive?(guest_pid), do: SessionsSupervisor.terminate_session(guest_user_id)
  end

  test "activity presence track, clear, and DOWN cleanup broadcast activity changes", %{
    user_id: user_id,
    board: board
  } do
    assert :ok = ActivityPresence.track(user_id, {:browsing_board, board})

    assert_receive {:online_presence, :activity_changed,
                    %{source: :activity_presence, user_id: ^user_id}}

    assert :ok = ActivityPresence.clear(user_id)

    assert_receive {:online_presence, :activity_changed,
                    %{source: :activity_presence, user_id: ^user_id}}

    tracker = spawn_activity_tracker(user_id, {:chatting_in_board, board})

    assert_receive {:online_presence, :activity_changed,
                    %{source: :activity_presence, user_id: ^user_id}}

    stop_process(tracker)

    assert_receive {:online_presence, :activity_changed,
                    %{source: :activity_presence, user_id: ^user_id}}
  end

  test "board screen tab and leave transitions broadcast global presence changes", %{
    user_id: user_id,
    board: board
  } do
    board_id = board.id

    assert :ok = BoardScreen.track(board_id, user_id, :threads)

    assert_receive {:online_presence, :activity_changed,
                    %{
                      source: :board_screen,
                      user_id: ^user_id,
                      board_id: ^board_id,
                      tab: :threads
                    }}

    assert :ok = BoardScreen.update_tab(board_id, user_id, :chat)

    assert_receive {:online_presence, :activity_changed,
                    %{source: :board_screen, user_id: ^user_id, board_id: ^board_id, tab: :chat}}

    assert :ok = BoardScreen.untrack(board_id, user_id)

    assert_receive {:online_presence, :activity_changed,
                    %{source: :board_screen, user_id: ^user_id, board_id: ^board_id}}
  end

  test "door presence track, untrack, and DOWN cleanup broadcast activity changes", %{
    user_id: user_id
  } do
    runner = spawn_waiter()

    assert :ok = DoorPresence.track(user_id, %{id: "lord", name: "LORD"}, runner)

    assert_receive {:online_presence, :activity_changed,
                    %{source: :door_presence, user_id: ^user_id}}

    assert :ok = DoorPresence.untrack(user_id)

    assert_receive {:online_presence, :activity_changed,
                    %{source: :door_presence, user_id: ^user_id}}

    runner2 = spawn_waiter()
    assert :ok = DoorPresence.track(user_id, %{id: "tw", name: "Trade Wars"}, runner2)

    assert_receive {:online_presence, :activity_changed,
                    %{source: :door_presence, user_id: ^user_id}}

    stop_process(runner2)

    assert_receive {:online_presence, :activity_changed,
                    %{source: :door_presence, user_id: ^user_id}}

    stop_process(runner)
  end

  test "guest activity updates are ignored and never broadcast", %{board: board} do
    assert :ok = ActivityPresence.track(nil, {:browsing_board, board})
    assert :ok = BoardScreen.track(board.id, nil, :threads)
    runner = spawn_waiter()
    assert :ok = DoorPresence.track(nil, %{id: "lord", name: "LORD"}, runner)

    refute_receive {:online_presence, _event, %{user_id: nil}}, 25

    stop_process(runner)
  end

  defp spawn_activity_tracker(user_id, activity) do
    parent = self()

    pid =
      spawn_link(fn ->
        :ok = ActivityPresence.track(user_id, activity)
        send(parent, {:activity_tracked, self()})

        receive do
          :stop -> :ok
        end
      end)

    assert_receive {:activity_tracked, ^pid}
    pid
  end

  defp spawn_waiter do
    spawn_link(fn ->
      receive do
        :stop -> :ok
      end
    end)
  end

  defp stop_process(pid) when is_pid(pid) do
    ref = Process.monitor(pid)
    send(pid, :stop)
    assert_receive {:DOWN, ^ref, :process, ^pid, _reason}, 1_000
  end
end
