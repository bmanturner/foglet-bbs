defmodule Foglet.TUI.MinuteClockTest do
  use ExUnit.Case, async: false

  alias Foglet.TUI.MinuteClock

  test "delay_until_next_minute aligns to the next wall-clock minute" do
    assert MinuteClock.delay_until_next_minute(~U[2026-05-04 22:14:00.000000Z]) == 60_000
    assert MinuteClock.delay_until_next_minute(~U[2026-05-04 22:14:00.001000Z]) == 59_999
    assert MinuteClock.delay_until_next_minute(~U[2026-05-04 22:14:59.000000Z]) == 1_000
    assert MinuteClock.delay_until_next_minute(~U[2026-05-04 22:14:59.999000Z]) == 1
  end

  test "broadcast_tick emits the central TUI clock PubSub message" do
    Phoenix.PubSub.subscribe(FogletBbs.PubSub, MinuteClock.topic())

    now = ~U[2026-05-04 22:15:00Z]
    assert :ok = MinuteClock.broadcast_tick(now)
    assert_receive {:tui_clock, :minute_tick, ^now}
  end

  test "scheduled tick uses the next minute-boundary delay without sleeping" do
    parent = self()

    now_fun = fn -> ~U[2026-05-04 22:14:59.250000Z] end

    timer_fun = fn pid, message, delay ->
      send(parent, {:scheduled, pid, message, delay})
      make_ref()
    end

    {:ok, pid} =
      start_supervised({MinuteClock, name: nil, now_fun: now_fun, timer_fun: timer_fun})

    assert_receive {:scheduled, ^pid, :tick, 750}
  end
end
