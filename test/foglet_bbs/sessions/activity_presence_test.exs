defmodule Foglet.Sessions.ActivityPresenceTest do
  use ExUnit.Case, async: false

  alias Foglet.Sessions.ActivityPresence

  setup do
    user_id = "user-" <> Ecto.UUID.generate()
    other_user_id = "user-" <> Ecto.UUID.generate()

    %{user_id: user_id, other_user_id: other_user_id, board: %{id: "b1", name: "General"}}
  end

  test "tracks and clears the caller activity", %{user_id: user_id, board: board} do
    assert ActivityPresence.get(user_id) == :error

    :ok = ActivityPresence.track(user_id, {:reading_board, board})

    assert ActivityPresence.get(user_id) == {:ok, {:reading_board, board}}

    :ok = ActivityPresence.clear(user_id)
    assert ActivityPresence.get(user_id) == :error
  end

  test "nil users are ignored", %{board: board} do
    assert :ok = ActivityPresence.track(nil, {:browsing_board, board})
    assert :ok = ActivityPresence.clear(nil)
  end

  test "process exit auto-evicts entries", %{user_id: user_id, board: board} do
    pid =
      spawn_link(fn ->
        :ok = ActivityPresence.track(user_id, {:chatting_in_board, board})

        receive do
          :stop -> :ok
        end
      end)

    wait_until(fn -> ActivityPresence.get(user_id) == {:ok, {:chatting_in_board, board}} end)

    ref = Process.monitor(pid)
    send(pid, :stop)
    assert_receive {:DOWN, ^ref, :process, ^pid, _reason}
    wait_until(fn -> ActivityPresence.get(user_id) == :error end)
  end

  test "activity precedence is stable per user", %{user_id: user_id} do
    first_board = %{id: "b2", name: "Zed"}
    second_board = %{id: "b1", name: "General"}

    first_pid = tracker(user_id, {:browsing_board, first_board})
    second_pid = tracker(user_id, {:reading_board, second_board})
    third_pid = tracker(user_id, {:chatting_in_board, first_board})

    wait_until(fn ->
      ActivityPresence.get(user_id) == {:ok, {:chatting_in_board, first_board}}
    end)

    stop_tracker(third_pid)
    wait_until(fn -> ActivityPresence.get(user_id) == {:ok, {:reading_board, second_board}} end)

    stop_tracker(second_pid)
    wait_until(fn -> ActivityPresence.get(user_id) == {:ok, {:browsing_board, first_board}} end)

    stop_tracker(first_pid)
  end

  defp tracker(user_id, activity) do
    parent = self()

    pid =
      spawn_link(fn ->
        :ok = ActivityPresence.track(user_id, activity)
        send(parent, {:tracked, self()})

        receive do
          :stop -> :ok
        end
      end)

    assert_receive {:tracked, ^pid}
    pid
  end

  defp stop_tracker(pid) do
    ref = Process.monitor(pid)
    send(pid, :stop)
    assert_receive {:DOWN, ^ref, :process, ^pid, _reason}
  end

  defp wait_until(fun, attempts \\ 25)

  defp wait_until(fun, attempts) when attempts > 0 do
    if fun.() do
      :ok
    else
      Process.sleep(10)
      wait_until(fun, attempts - 1)
    end
  end

  defp wait_until(fun, 0), do: assert(fun.())
end
