defmodule Foglet.SiteCountersTest do
  use FogletBbs.DataCase, async: false

  alias Foglet.SiteCounters

  describe "total BBS calls" do
    test "get_call_count/0 initializes an absent counter as zero" do
      assert SiteCounters.get_call_count() == 0
    end

    test "increment_call_count/0 persists and returns the incremented total" do
      assert SiteCounters.increment_call_count() == 1
      assert SiteCounters.increment_call_count() == 2
      assert SiteCounters.get_call_count() == 2
    end

    test "increment_call_count/0 is atomic under concurrent callers" do
      increments = 40

      results =
        1..increments
        |> Task.async_stream(
          fn _ -> SiteCounters.increment_call_count() end,
          max_concurrency: increments,
          timeout: 5_000
        )
        |> Enum.map(fn {:ok, count} -> count end)

      assert Enum.sort(results) == Enum.to_list(1..increments)
      assert SiteCounters.get_call_count() == increments
    end
  end
end
